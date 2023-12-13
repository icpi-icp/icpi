import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import P "mo:base/Prelude";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Bool "mo:base/Bool";
import Nat "mo:base/Nat";
import Timer "mo:base/Timer";
import Result "mo:base/Result";
import Prim "mo:⛔";

import Types "types/Types";
import ICRC2Types "types/ICRC2Types";
import TextUtils "common/TextUtils";
import ArrayUtils "common/ArrayUtils";

actor class Ledger(
  init : {
    initial_mints : [{
      account : {
        owner : Principal;
        subaccount : ?Blob;
      };
      amount : Nat;
    }];
    minting_account : { owner : Principal; subaccount : ?Blob };
    token_name : Text;
    token_symbol : Text;
    decimals : Nat8;
    transfer_fee : Nat;
  }
) = this {

  public type Account = ICRC2Types.Account;
  public type Subaccount = ICRC2Types.Subaccount;
  public type Tokens = ICRC2Types.Tokens;
  public type Memo = ICRC2Types.Memo;
  public type Timestamp = ICRC2Types.Timestamp;
  public type Duration = ICRC2Types.Duration;
  public type TxIndex = ICRC2Types.TxIndex;
  public type TxLog = ICRC2Types.TxLog;
  public type Value = ICRC2Types.Value;

  public type TxKind = ICRC2Types.TxKind;
  public type Transaction = ICRC2Types.Transaction;
  public type Transfer = ICRC2Types.Transfer;
  public type TransferError = ICRC2Types.TransferError;
  public type TransferResult = ICRC2Types.TransferResult;
  public type TransferFromArgs = ICRC2Types.TransferFromArgs;
  public type TransferFromError = ICRC2Types.TransferFromError;
  public type TransferFromResult = ICRC2Types.TransferFromResult;
  public type ApproveArgs = ICRC2Types.ApproveArgs;
  public type ApproveError = ICRC2Types.ApproveError;
  public type ApproveResult = ICRC2Types.ApproveResult;
  public type AllowanceArgs = ICRC2Types.AllowanceArgs;

  public type UserBalance = Types.UserBalance;
  public type UserBalanceResponse = Types.UserBalanceResponse;
  public type ActiveStartRequest = Types.ActiveStartRequest;
  public type MintConfigResponse = Types.MintConfigResponse;
  public type MintStatisticsResponse = Types.MintStatisticsResponse;
  public type GetAccountIdentifierTransactionsArgs = Types.GetAccountIdentifierTransactionsArgs;
  public type GetAccountIdentifierTransactionsResult = Types.GetAccountIdentifierTransactionsResult;
  public type GetBlocksArgs = Types.GetBlocksArgs;
  public type QueryBlocksResponse = Types.QueryBlocksResponse;
  public type QueryEncodedBlocksResponse = Types.QueryEncodedBlocksResponse;
  public type GetAccountTransactionsArgs = Types.GetAccountTransactionsArgs;
  public type TransactionWithId = Types.TransactionWithId;

  let permittedDriftNanos : Duration = 60_000_000_000;
  let transactionWindowNanos : Duration = 24 * 60 * 60 * 1_000_000_000;
  let defaultSubaccount : Subaccount = Blob.fromArrayMut(
    Array.init(
      32,
      0 : Nat8,
    )
  );

  //Dynamically configurable parameters {"op":"mint","token":"icpi"}
  // private stable var mint_memo : Text = "data:,{\"p\":\"icpi20\",\"op\":\"mint\",\"tick\":\"icpi\",\"amt\":\"100000000\"}";
  private stable var mint_memo : Text = "{op:mint,token:icpi}";
  private stable var mint_amount : Nat = 100000000;
  private stable var max_mint_amount : Nat = 100000000;
  private stable var start_block_time : Nat64 = 0;
  private stable var end_block_time : Nat64 = 0;
  private stable var last_block_time : Nat64 = 0;

  //Results of automatic calculation of the contract
  private stable var distribute_timer_id : Timer.TimerId = 0;
  private stable var settle_timer_id : Timer.TimerId = 0;
  private stable var get_last_block_time_id : Timer.TimerId = 0;
  private stable var total_number_of_mint : Nat64 = 0;
  private stable var end_of_settle : Bool = false;
  private stable var end_of_distribute : Bool = false;
  private stable var balance_stat : [(Text, UserBalance)] = [];
  private var balance_map : HashMap.HashMap<Text, UserBalance> = HashMap.fromIter(balance_stat.vals(), 0, Text.equal, Text.hash);
  private stable var register_stat : [(Text, Principal)] = [];
  private var register_map : HashMap.HashMap<Text, Principal> = HashMap.fromIter(register_stat.vals(), 0, Text.equal, Text.hash);

  private var tmp_balance_map = HashMap.HashMap<Text, UserBalance>(100, Text.equal, Text.hash);

  public shared ({ caller }) func activity_start(request : ActiveStartRequest) : async Bool {
    assert (init.minting_account.owner == caller);
    mint_memo := Option.get(request.memo, mint_memo);
    mint_amount := Option.get(request.amount, mint_amount);
    max_mint_amount := Option.get(request.max_amount, max_mint_amount);
    start_block_time := Option.get(request.start_block_time, start_block_time);
    end_block_time := Option.get(request.end_block_time, end_block_time);
    //Start the timing task
    start_timing();
    return true;
  };

  func start_timing() {
    distribute_timer_id := Timer.recurringTimer(#seconds(60), distribute);
    settle_timer_id := Timer.recurringTimer(#seconds(300), settle);
    get_last_block_time_id := Timer.recurringTimer(#seconds(60), get_last_block_time);
  };

  public shared ({ caller }) func set_mint_memo(memo : Text) : async Bool {
    assert (init.minting_account.owner == caller);
    mint_memo := memo;
    return true;
  };
  public shared ({ caller }) func set_mint_amount(amount : Nat) : async Bool {
    assert (init.minting_account.owner == caller);
    mint_amount := amount;
    return true;
  };
  public shared ({ caller }) func set_end_block(block : Nat64) : async Bool {
    assert (init.minting_account.owner == caller);
    end_block_time := block;
    return true;
  };

  public query func query_mint_config() : async MintConfigResponse {
    return {
      memo = mint_memo;
      amount = mint_amount;
      start_block_time = start_block_time;
      end_block_time = end_block_time;
    };
  };
  public query func query_mint_statistics() : async MintStatisticsResponse {
    return {
      valid_addresses = balance_map.size();
      valid_transactions = total_number_of_mint;
      end_of_distribute = end_of_distribute;
      end_of_settle = end_of_settle;
    };
  };
  public query func query_user_valid_balance(principal : Principal) : async Nat {
    let account_id = TextUtils.toAddress(principal);
    switch (balance_map.get(account_id)) {
      case (?balance) {
        return balance.mint_amount;
      };
      case (_) {
        return 0;
      };
    };
  };
  public query func query_users_valid_balance(offset : Nat, limit : Nat) : async Result.Result<Types.Page<UserBalanceResponse>, Text> {
    var buffer : Buffer.Buffer<(UserBalanceResponse)> = Buffer.Buffer<(UserBalanceResponse)>(1);
    for ((account_id, user_balance) in balance_map.entries()) {
      let user_balance_response = {
        account_id = user_balance.account_id;
        principal = user_balance.principal;
        mint_amount = user_balance.mint_amount;
        distributed_amount = user_balance.distributed_amount;
      };
      buffer.add(user_balance_response);
    };
    return #ok({
      totalElements = buffer.size();
      content = ArrayUtils.bufferRange(buffer, offset, limit);
      offset = offset;
      limit = limit;
    });
  };

  public shared ({ caller }) func register() : async Bool {
    let account_id = TextUtils.toAddress(caller);
    register_map.put(account_id, caller);
    switch (balance_map.get(account_id)) {
      case (?balance) {
        balance.principal := ?caller;
      };
      case (_) {

      };
    };
    return true;
  };

  private func distribute() : async () {
    if (end_of_distribute) {
      ignore Timer.cancelTimer(distribute_timer_id);
      ignore Timer.cancelTimer(get_last_block_time_id);
      return;
    };
    if (end_block_time == 0 or (not end_of_settle)) {
      //The activity is not over yet.
      return;
    };
    //It can be distributed
    let memo : Blob = Text.encodeUtf8(init.token_symbol # " Mint");
    let now = Nat64.fromNat(Int.abs(Time.now()));
    for ((account_id, balance) in balance_map.entries()) {
      switch (register_map.get(account_id)) {
        case (?principal) {
          let to = { owner = principal; subaccount = null };
          let tx : Transaction = {
            args = {
              from = init.minting_account;
              to = to;
              amount = balance.mint_amount - balance.distributed_amount;
              fee = null;
              memo = ?memo;
              created_at_time = ?now;
            };
            kind = #Mint;
            fee = 0;
            timestamp = now;
          };
          log.add(tx);
          balance.distributed_amount := balance.mint_amount;
        };
        case (_) {

        };
      };
    };
    end_of_distribute := true;

  };

  private func settle() : async () {
    if (end_of_settle) {
      ignore Timer.cancelTimer(settle_timer_id);
      //The activity is over yet.
      return;
    };
    tmp_balance_map := HashMap.HashMap<Text, UserBalance>(100, Text.equal, Text.hash);
    let indexLedger = actor ("qhbym-qaaaa-aaaaa-aaafq-cai") : actor {
      get_account_identifier_transactions : shared query GetAccountIdentifierTransactionsArgs -> async GetAccountIdentifierTransactionsResult;
      get_account_transactions : shared query GetAccountTransactionsArgs -> async GetAccountIdentifierTransactionsResult;
    };

    var number_of_mints : Nat64 = 0;
    var oldest_tx_id : Nat64 = 0;
    var current_old_tx_id : Nat64 = 0;

    let canister_principal = Principal.fromActor(this);
    let canister_account_id = TextUtils.toAddress(canister_principal);

    //Synchronize transaction data and obtain the final target transaction id
    let args = buildRequestArgs(canister_account_id, null);
    let transactionResult : GetAccountIdentifierTransactionsResult = await indexLedger.get_account_identifier_transactions(args);
    let (ol_tx_id, current_ol_tx_id, total_mint_count) = checkTxIsCompliant(transactionResult, number_of_mints);
    oldest_tx_id := ol_tx_id;
    current_old_tx_id := current_ol_tx_id;
    number_of_mints := total_mint_count;

    //Synchronize all transaction data
    while (current_old_tx_id > oldest_tx_id) {
      let args = buildRequestArgs(canister_account_id, ?current_old_tx_id);
      let transactionResult = await indexLedger.get_account_identifier_transactions(args);
      let (ol_tx_id, current_ol_tx_id, total_mint_count) = checkTxIsCompliant(transactionResult, number_of_mints);
      current_old_tx_id := current_ol_tx_id;
      number_of_mints := total_mint_count;
    };
    total_number_of_mint := number_of_mints;
    balance_map := tmp_balance_map;
    if (end_block_time != 0 and last_block_time > end_block_time) {
      end_of_settle := true;
    };
    return;
  };

  func get_last_block_time() : async () {
    last_block_time := await get_block_time(0, 100);
  };

  func get_block_time(start : Nat64, count : Nat64) : async Nat64 {
    if (count == 0) {
      return 0;
    };
    let ledger = actor ("ryjl3-tyaaa-aaaaa-aaaba-cai") : actor {
      query_blocks : shared query GetBlocksArgs -> async QueryBlocksResponse;
      query_encoded_blocks : shared query GetBlocksArgs -> async QueryEncodedBlocksResponse;
    };

    let getBlocksArgs : GetBlocksArgs = {
      start = start;
      length = 1;
    };
    let block_result = await ledger.query_blocks(getBlocksArgs);

    if (block_result.blocks.size() == 0) {
      if (start == 0) {
        return await get_block_time(block_result.chain_length -5, count -1);
      } else {
        return await get_block_time(start, count -1);
      };
    };
    return block_result.blocks[0].timestamp.timestamp_nanos;
  };

  func buildRequestArgs(accountId : Text, startArg : ?Nat64) : GetAccountIdentifierTransactionsArgs {
    let args : GetAccountIdentifierTransactionsArgs = {
      max_results = 20000;
      start = startArg;
      account_identifier = accountId;
    };
  };

  func checkTxIsCompliant(transactionResult : GetAccountIdentifierTransactionsResult, count : Nat64) : (Nat64, Nat64, Nat64) {
    var total_mint_conut = count;
    var oldest_tx_id : Nat64 = 0;
    var current_old_tx_id : Nat64 = 0;
    switch (transactionResult) {
      case (#Ok(result)) {
        oldest_tx_id := Option.get(result.oldest_tx_id, oldest_tx_id);

        let txs : [TransactionWithId] = result.transactions;

        for (transaction : TransactionWithId in txs.vals()) {
          current_old_tx_id := transaction.id;
          let memo : Nat64 = transaction.transaction.memo;
          let icrc1_memo : ?Blob = transaction.transaction.icrc1_memo;
          switch (icrc1_memo) {
            case (?icrc_memo) {
              if (Option.get(Text.decodeUtf8(icrc_memo), "error") == mint_memo) {
                total_mint_conut += 1;
                switch (transaction.transaction.operation) {
                  case (#Mint(mint_operation)) {};
                  case (#Burn(burn_operation)) {};
                  case (#Approve(approve_operation)) {};
                  case (#Transfer(transfer_operation)) {
                    updateUserBalance(transfer_operation.from);
                  };
                  case (#TransferFrom(transfer_from_operation)) {
                    updateUserBalance(transfer_from_operation.from);
                  };
                };
              };
            };
            case (_) {};
          };
        };
      };
      case (#Err(msg)) {

      };
    };
    return (oldest_tx_id, current_old_tx_id, total_mint_conut);
  };

  func updateUserBalance(user_account_id : Text) {
    switch (tmp_balance_map.get(user_account_id)) {
      case (?balance) {
        if (balance.mint_amount < max_mint_amount) {
          balance.mint_amount += mint_amount;
        };
      };
      case (_) {
        var balance : UserBalance = {
          account_id = user_account_id;
          var principal = register_map.get(user_account_id);
          var mint_amount = mint_amount;
          var distributed_amount = 0;
        };
        tmp_balance_map.put(user_account_id, balance);
      };
    };
  };

  // Checks whether two accounts are semantically equal.
  func accountsEqual(lhs : Account, rhs : Account) : Bool {
    let lhsSubaccount = Option.get(lhs.subaccount, defaultSubaccount);
    let rhsSubaccount = Option.get(rhs.subaccount, defaultSubaccount);

    Principal.equal(lhs.owner, rhs.owner) and Blob.equal(lhsSubaccount, rhsSubaccount);
  };

  // Computes the balance of the specified account.
  func balance(account : Account, log : TxLog) : Nat {
    var sum = 0;
    for (tx in log.vals()) {
      switch (tx.kind) {
        case (#Burn) {
          if (accountsEqual(tx.args.from, account)) { sum -= tx.args.amount };
        };
        case (#Mint) {
          if (accountsEqual(tx.args.to, account)) { sum += tx.args.amount };
        };
        case (#Transfer) {
          if (accountsEqual(tx.args.from, account)) {
            sum -= tx.args.amount + tx.fee;
          };
          if (accountsEqual(tx.args.to, account)) { sum += tx.args.amount };
        };
      };
    };
    sum;
  };

  // Computes the total token supply.
  func totalSupply(log : TxLog) : Tokens {
    var total = 0;
    for (tx in log.vals()) {
      switch (tx.kind) {
        case (#Burn) { total -= tx.args.amount };
        case (#Mint) { total += tx.args.amount };
        case (#Transfer) { total -= tx.fee };
      };
    };
    total;
  };

  // Finds a transaction in the transaction log.
  func findTransfer(transfer : Transfer, log : TxLog) : ?TxIndex {
    var i = 0;
    for (tx in log.vals()) {
      if (tx.args == transfer) { return ?i };
      i += 1;
    };
    null;
  };

  // Checks if the principal is anonymous.
  func isAnonymous(p : Principal) : Bool {
    Blob.equal(Principal.toBlob(p), Blob.fromArray([0x04]));
  };

  // Constructs the transaction log corresponding to the init argument.
  func makeGenesisChain() : TxLog {
    validateSubaccount(init.minting_account.subaccount);

    let now = Nat64.fromNat(Int.abs(Time.now()));
    let log = Buffer.Buffer<Transaction>(100);
    for ({ account; amount } in Array.vals(init.initial_mints)) {
      validateSubaccount(account.subaccount);
      let tx : Transaction = {
        args = {
          from = init.minting_account;
          to = account;
          amount = amount;
          fee = null;
          memo = null;
          created_at_time = ?now;
        };
        kind = #Mint;
        fee = 0;
        timestamp = now;
      };
      log.add(tx);
    };
    log;
  };

  // Traps if the specified blob is not a valid subaccount.
  func validateSubaccount(s : ?Subaccount) {
    let subaccount = Option.get(s, defaultSubaccount);
    assert (subaccount.size() == 32);
  };

  func validateMemo(m : ?Memo) {
    switch (m) {
      case (null) {};
      case (?memo) { assert (memo.size() <= 32) };
    };
  };

  // The list of all transactions.
  var log : TxLog = makeGenesisChain();

  // The stable representation of the transaction log.
  // Used only during upgrades.
  stable var persistedLog : [Transaction] = [];

  public shared ({ caller }) func icrc1_transfer({
    from_subaccount : ?Subaccount;
    to : Account;
    amount : Tokens;
    fee : ?Tokens;
    memo : ?Memo;
    created_at_time : ?Timestamp;
  }) : async TransferResult {
    if (isAnonymous(caller)) {
      throw Error.reject("anonymous user is not allowed to transfer funds");
    };
    let now = Nat64.fromNat(Int.abs(Time.now()));

    let txTime : Timestamp = Option.get(created_at_time, now);

    if ((txTime > now) and (txTime - now > permittedDriftNanos)) {
      return #Err(#CreatedInFuture { ledger_time = now });
    };

    if (
      (
        txTime < now
      ) and (now - txTime > transactionWindowNanos + permittedDriftNanos)
    ) {
      return #Err(#TooOld);
    };

    validateSubaccount(from_subaccount);
    validateSubaccount(to.subaccount);
    validateMemo(memo);

    let from = { owner = caller; subaccount = from_subaccount };

    let args : Transfer = {
      from = from;
      to = to;
      amount = amount;
      memo = memo;
      fee = fee;
      created_at_time = created_at_time;
    };

    if (Option.isSome(created_at_time)) {
      switch (findTransfer(args, log)) {
        case (?height) { return #Err(#Duplicate { duplicate_of = height }) };
        case null {};
      };
    };

    let minter = init.minting_account;

    let (kind, effectiveFee) = if (accountsEqual(from, minter)) {
      if (Option.get(fee, 0) != 0) {
        return #Err(#BadFee { expected_fee = 0 });
      };
      (#Mint, 0);
    } else if (accountsEqual(to, minter)) {
      if (Option.get(fee, 0) != 0) {
        return #Err(#BadFee { expected_fee = 0 });
      };

      if (amount < init.transfer_fee) {
        return #Err(#BadBurn { min_burn_amount = init.transfer_fee });
      };

      let debitBalance = balance(from, log);
      if (debitBalance < amount) {
        return #Err(#InsufficientFunds { balance = debitBalance });
      };

      (#Burn, 0);
    } else {
      let effectiveFee = init.transfer_fee;
      if (Option.get(fee, effectiveFee) != effectiveFee) {
        return #Err(#BadFee { expected_fee = init.transfer_fee });
      };

      let debitBalance = balance(from, log);
      if (debitBalance < amount + effectiveFee) {
        return #Err(#InsufficientFunds { balance = debitBalance });
      };

      (#Transfer, effectiveFee);
    };

    let tx : Transaction = {
      args = args;
      kind = kind;
      fee = effectiveFee;
      timestamp = now;
    };

    let txIndex = log.size();
    log.add(tx);
    #Ok(txIndex);
  };

  public type TransactionView = {
    from : Text;
    to : Text;
    amount : Tokens;
    kind : TxKind;
    fee : Tokens;
    timestamp : Timestamp;
  };

  public query func transaction(_offset : Nat, _limit : Nat) : async {
    totalElements : Nat;
    offset : Nat;
    limit : Nat;
    content : [TransactionView];
  } {
    var buffer : Buffer.Buffer<TransactionView> = Buffer.Buffer<TransactionView>(0);
    let size : Nat = log.size();
    var index : Nat = 0;
    var i : Nat = size;
    while (i > 0) {
      i -= 1;
      let tx : Transaction = log.get(i);
      if (_limit == 0 or (index >= _offset and buffer.size() < _limit)) {
        let txView : TransactionView = {
          from = Principal.toText(tx.args.from.owner);
          to = Principal.toText(tx.args.to.owner);
          amount = tx.args.amount;
          kind = tx.kind;
          fee = tx.fee;
          timestamp = tx.timestamp;
        };
        buffer.add(txView);
      } else if (_limit > 0 and index >= _offset + _limit) {
        i := 0;
      };
      index += 1;
    };
    {
      totalElements = size;
      offset = _offset;
      limit = _limit;
      content = buffer.toArray();
    };
  };

  public query func icrc1_balance_of(account : Account) : async Tokens {
    balance(account, log);
  };

  public query func icrc1_total_supply() : async Tokens {
    totalSupply(log);
  };

  public query func icrc1_minting_account() : async ?Account {
    ?init.minting_account;
  };

  public query func icrc1_name() : async Text {
    init.token_name;
  };

  public query func icrc1_symbol() : async Text {
    init.token_symbol;
  };

  public query func icrc1_decimals() : async Nat8 {
    init.decimals;
  };

  public query func icrc1_fee() : async Nat {
    init.transfer_fee;
  };

  public query func icrc1_metadata() : async [(Text, Value)] {
    [
      ("icrc1:name", #Text(init.token_name)),
      ("icrc1:symbol", #Text(init.token_symbol)),
      ("icrc1:decimals", #Nat(Nat8.toNat(init.decimals))),
      ("icrc1:fee", #Nat(init.transfer_fee)),
    ];
  };

  public query func icrc1_supported_standards() : async [{
    name : Text;
    url : Text;
  }] {
    [{ name = "ICRC-2"; url = "https://github.com/dfinity/ICRC-1" }];
  };

  private stable var allowanceEntries : [(Principal, [(Principal, Nat)])] = [];
  private var allowances = HashMap.HashMap<Principal, HashMap.HashMap<Principal, Nat>>(1, Principal.equal, Principal.hash);

  func unwrap<T>(x : ?T) : T = switch x {
    case null { P.unreachable() };
    case (?x_) { x_ };
  };

  func _allowance(owner : Principal, spender : Principal) : Nat {
    switch (allowances.get(owner)) {
      case (?allowance_owner) {
        switch (allowance_owner.get(spender)) {
          case (?allowance) { return allowance };
          case (_) { return 0 };
        };
      };
      case (_) { return 0 };
    };
  };

  public shared ({ caller }) func icrc2_transfer_from({
    from : Account;
    to : Account;
    amount : Tokens;
    fee : ?Tokens;
    memo : ?Memo;
    created_at_time : ?Timestamp;
  }) : async TransferFromResult {
    if (isAnonymous(caller)) {
      throw Error.reject("anonymous user is not allowed to transfer funds");
    };
    if (isAnonymous(from.owner)) {
      throw Error.reject("anonymous user is not allowed to transfer funds");
    };

    let debitBalance = balance(from, log);
    let _fee = switch (fee) {
      case (?fee) { fee };
      case (_) { 0 };
    };
    if (debitBalance < amount + _fee) {
      return #Err(#InsufficientFunds { balance = debitBalance });
    };
    let allowed : Nat = _allowance(from.owner, caller);
    if (allowed < amount + _fee) {
      return #Err(#InsufficientAllowance { allowance = allowed });
    };

    let now = Nat64.fromNat(Int.abs(Time.now()));

    let txTime : Timestamp = Option.get(created_at_time, now);

    if ((txTime > now) and (txTime - now > permittedDriftNanos)) {
      return #Err(#CreatedInFuture { ledger_time = now });
    };

    if (
      (
        txTime < now
      ) and (now - txTime > transactionWindowNanos + permittedDriftNanos)
    ) {
      return #Err(#TooOld);
    };

    validateSubaccount(from.subaccount);
    validateSubaccount(to.subaccount);
    validateMemo(memo);

    let args : Transfer = {
      from = from;
      to = to;
      amount = amount;
      memo = memo;
      fee = fee;
      created_at_time = created_at_time;
    };

    if (Option.isSome(created_at_time)) {
      switch (findTransfer(args, log)) {
        case (?height) { return #Err(#Duplicate { duplicate_of = height }) };
        case null {};
      };
    };

    let minter = init.minting_account;

    let (kind, effectiveFee) = if (accountsEqual(from, minter)) {
      if (Option.get(fee, 0) != 0) {
        return #Err(#BadFee { expected_fee = 0 });
      };
      (#Mint, 0);
    } else if (accountsEqual(to, minter)) {
      if (Option.get(fee, 0) != 0) {
        return #Err(#BadFee { expected_fee = 0 });
      };

      if (amount < init.transfer_fee) {
        return #Err(#BadBurn { min_burn_amount = init.transfer_fee });
      };

      if (debitBalance < amount) {
        return #Err(#InsufficientFunds { balance = debitBalance });
      };

      (#Burn, 0);
    } else {
      let effectiveFee = init.transfer_fee;
      if (Option.get(fee, effectiveFee) != effectiveFee) {
        return #Err(#BadFee { expected_fee = init.transfer_fee });
      };

      let debitBalance = balance(from, log);
      if (debitBalance < amount + effectiveFee) {
        return #Err(#InsufficientFunds { balance = debitBalance });
      };

      (#Transfer, effectiveFee);
    };

    let allowed_new : Nat = allowed - amount - _fee;
    if (allowed_new != 0) {
      let allowance_from = unwrap(allowances.get(from.owner));
      allowance_from.put(caller, allowed_new);
      allowances.put(from.owner, allowance_from);
    } else {
      if (allowed != 0) {
        let allowance_from = unwrap(allowances.get(from.owner));
        allowance_from.delete(caller);
        if (allowance_from.size() == 0) { allowances.delete(from.owner) } else {
          allowances.put(from.owner, allowance_from);
        };
      };
    };

    let tx : Transaction = {
      args = args;
      kind = kind;
      fee = effectiveFee;
      timestamp = now;
    };

    let txIndex = log.size();
    log.add(tx);
    #Ok(txIndex);
  };

  public shared ({ caller }) func icrc2_approve({
    from_subaccount : ?Subaccount;
    spender : Principal;
    amount : Tokens;
    fee : ?Tokens;
    memo : ?Memo;
    created_at_time : ?Timestamp;
  }) : async ApproveResult {
    if (isAnonymous(caller)) {
      throw Error.reject("anonymous user is not allowed to transfer funds");
    };

    let from = { owner = caller; subaccount = from_subaccount };

    let debitBalance = balance(from, log);
    if (amount == 0 and Option.isSome(allowances.get(caller))) {
      let allowance_caller = unwrap(allowances.get(caller));
      allowance_caller.delete(spender);
      if (allowance_caller.size() == 0) { allowances.delete(caller) } else {
        allowances.put(caller, allowance_caller);
      };
    } else if (amount != 0 and Option.isNull(allowances.get(caller))) {
      var temp = HashMap.HashMap<Principal, Nat>(
        1,
        Principal.equal,
        Principal.hash,
      );
      temp.put(spender, amount);
      allowances.put(caller, temp);
    } else if (amount != 0 and Option.isSome(allowances.get(caller))) {
      let allowance_caller = unwrap(allowances.get(caller));
      allowance_caller.put(spender, amount);
      allowances.put(caller, allowance_caller);
    };
    #Ok(amount);
  };

  public query func icrc2_allowance({
    account : Account;
    spender : Principal;
  }) : async Tokens {
    switch (allowances.get(account.owner)) {
      case (?allowance_who) {
        switch (allowance_who.get(spender)) {
          case (?amount) { amount };
          case (_) { 0 };
        };
      };
      case (_) {
        return 0;
      };
    };
  };

  system func preupgrade() {
    balance_stat := Iter.toArray(balance_map.entries());
    register_stat := Iter.toArray(register_map.entries());
    persistedLog := log.toArray();
    var size : Nat = allowances.size();
    var temp : [var (Principal, [(Principal, Nat)])] = Array.init<(Principal, [(Principal, Nat)])>(
      size,
      (init.minting_account.owner, []),
    );
    size := 0;
    for ((k, v) in allowances.entries()) {
      temp[size] := (k, Iter.toArray(v.entries()));
      size += 1;
    };
    allowanceEntries := Array.freeze(temp);
  };

  system func postupgrade() {
    balance_stat := [];
    register_stat := [];
    log := Buffer.Buffer(persistedLog.size());
    for (tx in Array.vals(persistedLog)) {
      log.add(tx);
    };
    for ((k, v) in allowanceEntries.vals()) {
      let allowed_temp = HashMap.fromIter<Principal, Nat>(
        v.vals(),
        1,
        Principal.equal,
        Principal.hash,
      );
      allowances.put(k, allowed_temp);
    };
    allowanceEntries := [];
  };

};

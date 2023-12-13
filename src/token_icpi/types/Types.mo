import Bool "mo:base/Bool";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";

module {

  public type Page<T> = {
    totalElements : Nat;
    content : [T];
    offset : Nat;
    limit : Nat;
  };

  public type Account = { owner : Principal; subaccount : ?Blob };

  public type GetAccountIdentifierTransactionsArgs = {
    max_results : Nat64;
    start : ?Nat64;
    account_identifier : Text;
  };

  public type GetAccountTransactionsArgs = {
    max_results : Nat;
    start : ?Nat;
    account : Account;
  };

  public type Tokens = { e8s : Nat64 };
  public type TimeStamp = { timestamp_nanos : Nat64 };

  public type Operation = {
    #Approve : {
      fee : Tokens;
      from : Text;
      allowance : Tokens;
      expires_at : ?TimeStamp;
      spender : Text;
    };
    #Burn : { from : Text; amount : Tokens };
    #Mint : { to : Text; amount : Tokens };
    #Transfer : { to : Text; fee : Tokens; from : Text; amount : Tokens };
    #TransferFrom : {
      to : Text;
      fee : Tokens;
      from : Text;
      amount : Tokens;
      spender : Text;
    };
  };

  public type Transaction = {
    memo : Nat64;
    icrc1_memo : ?Blob;
    operation : Operation;
    created_at_time : ?TimeStamp;
  };

  public type TransactionWithId = { id : Nat64; transaction : Transaction };
  public type GetAccountIdentifierTransactionsError = { message : Text };
  public type GetAccountIdentifierTransactionsResponse = {
    balance : Nat64;
    transactions : [TransactionWithId];
    oldest_tx_id : ?Nat64;
  };
  public type GetAccountIdentifierTransactionsResult = {
    #Ok : GetAccountIdentifierTransactionsResponse;
    #Err : GetAccountIdentifierTransactionsError;
  };

  public type GetBlocksArgs = { start : Nat64; length : Nat64 };

  public type CandidOperation = {
    #Approve : {
      fee : Tokens;
      from : Blob;
      allowance_e8s : Int;
      allowance : Tokens;
      expected_allowance : ?Tokens;
      expires_at : ?TimeStamp;
      spender : Blob;
    };
    #Burn : { from : Blob; amount : Tokens; spender : ?Blob };
    #Mint : { to : Blob; amount : Tokens };
    #Transfer : {
      to : Blob;
      fee : Tokens;
      from : Blob;
      amount : Tokens;
      spender : ?Blob;
    };
  };

  public type CandidTransaction = {
    memo : Nat64;
    icrc1_memo : ?Blob;
    operation : ?CandidOperation;
    created_at_time : TimeStamp;
  };
  public type CandidBlock = {
    transaction : CandidTransaction;
    timestamp : TimeStamp;
    parent_hash : ?Blob;
  };

  public type BlockRange = { blocks : [CandidBlock] };
  public type GetBlocksError = {
    #BadFirstBlockIndex : {
      requested_index : Nat64;
      first_valid_index : Nat64;
    };
    #Other : { error_message : Text; error_code : Nat64 };
  };

  public type Result_3 = { #Ok : BlockRange; #Err : GetBlocksError };
  public type Result_4 = { #Ok : [Blob]; #Err : GetBlocksError };

  public type ArchivedBlocksRange = {
    callback : shared query GetBlocksArgs -> async Result_3;
    start : Nat64;
    length : Nat64;
  };

  public type ArchivedEncodedBlocksRange = {
    callback : shared query GetBlocksArgs -> async Result_4;
    start : Nat64;
    length : Nat64;
  };

  public type QueryBlocksResponse = {
    certificate : ?Blob;
    blocks : [CandidBlock];
    chain_length : Nat64;
    first_block_index : Nat64;
    archived_blocks : [ArchivedBlocksRange];
  };
  public type QueryEncodedBlocksResponse = {
    certificate : ?Blob;
    blocks : [Blob];
    chain_length : Nat64;
    first_block_index : Nat64;
    archived_blocks : [ArchivedEncodedBlocksRange];
  };

  public type UserBalance = {
    account_id : Text; //accountId
    var principal : ?Principal;
    var mint_amount : Nat;
    var distributed_amount : Nat;
  };

  public type UserBalanceResponse = {
    account_id : Text; //accountId
    principal : ?Principal;
    mint_amount : Nat;
    distributed_amount : Nat;
  };

  public type ActiveStartRequest = {
    memo : ?Text;
    amount : ?Nat;
    max_amount : ?Nat;
    start_block_time : ?Nat64;
    end_block_time : ?Nat64;
  };

  public type MintConfigResponse = {
    memo : Text;
    amount : Nat;
    start_block_time : Nat64;
    end_block_time : Nat64;
  };

  public type MintStatisticsResponse = {
    valid_addresses : Nat;
    valid_transactions : Nat64;
    end_of_distribute : Bool;
    end_of_settle : Bool;
  };
};

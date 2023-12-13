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

module {
    public type Account = { owner : Principal; subaccount : ?Subaccount };
    public type Subaccount = Blob;
    public type Tokens = Nat;
    public type Memo = Blob;
    public type Timestamp = Nat64;
    public type Duration = Nat64;
    public type TxIndex = Nat;
    public type TxLog = Buffer.Buffer<Transaction>;
    public type TxKind = { #Burn; #Mint; #Transfer };
    public type Value = { #Nat : Nat; #Int : Int; #Blob : Blob; #Text : Text };

    public type Transfer = {
        to : Account;
        from : Account;
        memo : ?Memo;
        amount : Tokens;
        fee : ?Tokens;
        created_at_time : ?Timestamp;
    };

    public type Transaction = {
        args : Transfer;
        kind : TxKind;
        // Effective fee for this transaction.
        fee : Tokens;
        timestamp : Timestamp;
    };

    public type TransferError = {
        #BadFee : { expected_fee : Tokens };
        #BadBurn : { min_burn_amount : Tokens };
        #InsufficientFunds : { balance : Tokens };
        #TooOld;
        #CreatedInFuture : { ledger_time : Timestamp };
        #Duplicate : { duplicate_of : TxIndex };
        #TemporarilyUnavailable;
        #GenericError : { error_code : Nat; message : Text };
    };

    public type TransferResult = {
        #Ok : TxIndex;
        #Err : TransferError;
    };

    public type ApproveArgs = {
        from_subaccount : ?Subaccount;
        spender : Principal;
        amount : Tokens;
        fee : ?Tokens;
        memo : ?Memo;
        created_at_time : ?Timestamp;
    };
    public type ApproveError = {
        #BadFee : { expected_fee : Tokens };
        #InsufficientFunds : { balance : Tokens };
        #TooOld;
        #CreatedInFuture : { ledger_time : Timestamp };
        #Duplicate : { duplicate_of : TxIndex };
        #TemporarilyUnavailable;
        #GenericError : { error_code : Nat; message : Text };
    };
    public type ApproveResult = {
        #Ok : TxIndex;
        #Err : ApproveError;
    };
    public type TransferFromArgs = {
        from : Account;
        to : Account;
        amount : Tokens;
        fee : ?Tokens;
        memo : ?Memo;
        created_at_time : ?Timestamp;
    };
    public type TransferFromError = {
        #BadFee : { expected_fee : Tokens };
        #BadBurn : { min_burn_amount : Tokens };
        #InsufficientFunds : { balance : Tokens };
        #InsufficientAllowance : { allowance : Tokens };
        #TooOld;
        #CreatedInFuture : { ledger_time : Timestamp };
        #Duplicate : { duplicate_of : TxIndex };
        #TemporarilyUnavailable;
        #GenericError : { error_code : Nat; message : Text };
    };
    public type TransferFromResult = {
        #Ok : TxIndex;
        #Err : TransferFromError;
    };
    public type AllowanceArgs = {
        account : Account;
        spender : Principal;
    };
};

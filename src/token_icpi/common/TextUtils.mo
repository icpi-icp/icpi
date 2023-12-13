import Principal "mo:base/Principal";
import Nat8 "mo:base/Nat8";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Char "mo:base/Char";
import List "mo:base/List";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Order "mo:base/Order";
import Text "mo:base/Text";
import Buffer "mo:base/Buffer";
import Prim "mo:⛔";
import CRC32 "CRC32";
import SHA224 "SHA224";

module {
    private let symbols = [
        '0',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
    ];

    private let base : Nat8 = 0x10;

    /**
     * Encodes an array of Nat8 by Base64, return the encoded string.
     */
    public func encode(array : [Nat8]) : Text {
        Array.foldLeft<Nat8, Text>(
            array,
            "",
            func(accum, u8) {
                accum # fromNat8(u8);
            },
        );
    };

    /**
     * Converts an Nat8 number into string.
     */
    public func fromNat8(u8 : Nat8) : Text {
        let c1 = symbols[Nat8.toNat((u8 / base))];
        let c2 = symbols[Nat8.toNat((u8 % base))];
        return Char.toText(c1) # Char.toText(c2);
    };

    public func toAddress(p : Principal) : Text {
        let digest = SHA224.Digest();
        digest.write([10, 97, 99, 99, 111, 117, 110, 116, 45, 105, 100] : [Nat8]); // b"\x0Aaccount-id"
        let blob = Principal.toBlob(p);
        digest.write(Blob.toArray(blob));
        digest.write(Array.freeze<Nat8>(Array.init<Nat8>(32, 0 : Nat8))); // sub account
        let hash_bytes : [Nat8] = digest.sum();
        let crc : [Nat8] = CRC32.crc32(hash_bytes);
        let aid_bytes = addAll<Nat8>(crc, hash_bytes);

        return encode(aid_bytes);
    };

    func addAll<T>(a : [T], b : [T]) : [T] {
        var result : Buffer.Buffer<T> = Buffer.Buffer<T>(0);
        for (t : T in a.vals()) {
            result.add(t);
        };
        for (t : T in b.vals()) {
            result.add(t);
        };
        return result.toArray();
    };




};

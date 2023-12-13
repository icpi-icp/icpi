import Buffer "mo:base/Buffer";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
module {
    public func bufferRange<T>(arr : Buffer.Buffer<T>, offset : Nat, limit : Nat) : [T] {
        let size : Nat = arr.size();
        var newArrayBuffer : Buffer.Buffer<T> = Buffer.Buffer<T>(0);
        if (size == 0) { return newArrayBuffer.toArray() };
        var end : Nat = offset + limit - 1;
        if (end > Nat.sub(size, 1)) {
            end := size - 1;
        };
        if (offset >= 0 and size > offset) {
            for (i in Iter.range(offset, end)) {
                newArrayBuffer.add(arr.get(i));
            };
        };
        return newArrayBuffer.toArray();
    };

    public func arrayRange<T>(arr : [T], offset : Nat, limit : Nat) : [T] {
        let size : Nat = arr.size();
        var newArrayBuffer : Buffer.Buffer<T> = Buffer.Buffer<T>(0);
        if (size == 0) { return newArrayBuffer.toArray() };
        var end : Nat = offset + limit - 1;
        if (end > Nat.sub(size, 1)) {
            end := size - 1;
        };
        if (offset >= 0 and size > offset) {
            for (i in Iter.range(offset, end)) {
                newArrayBuffer.add(arr[i]);
            };
        };
        return newArrayBuffer.toArray();
    };

};

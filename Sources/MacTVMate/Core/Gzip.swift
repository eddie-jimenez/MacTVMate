import Foundation

/// Minimal gzip support via Foundation's raw-deflate decompressor.
enum Gzip {
    static func isGzipped(_ data: Data) -> Bool {
        data.count > 18 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
    }

    static func decompress(_ data: Data) -> Data? {
        guard isGzipped(data) else { return nil }
        let bytes = [UInt8](data)
        let flags = bytes[3]
        var pos = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard pos + 2 <= bytes.count else { return nil }
            pos += 2 + Int(bytes[pos]) + Int(bytes[pos + 1]) << 8
        }
        if flags & 0x08 != 0 { while pos < bytes.count, bytes[pos] != 0 { pos += 1 }; pos += 1 } // FNAME
        if flags & 0x10 != 0 { while pos < bytes.count, bytes[pos] != 0 { pos += 1 }; pos += 1 } // FCOMMENT
        if flags & 0x02 != 0 { pos += 2 } // FHCRC
        guard pos < bytes.count - 8 else { return nil }
        let deflate = Data(bytes[pos..<(bytes.count - 8)]) as NSData
        return try? deflate.decompressed(using: .zlib) as Data
    }
}

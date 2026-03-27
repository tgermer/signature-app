import Foundation

/// Pure Swift ZIP writer (PKZIP, no-compression/STORE method).
/// No external libraries required.
struct ZIPExporter {

    static func create(files: [(name: String, data: Data)]) -> Data {
        var writer = ZIPExporter()
        for (name, data) in files { writer.addEntry(name: name, data: data) }
        return writer.finalize()
    }

    // MARK: - Private

    private var buf = Data()
    private struct Entry { let name: [UInt8]; let offset: UInt32; let size: UInt32; let crc: UInt32 }
    private var entries: [Entry] = []

    private mutating func addEntry(name: String, data: Data) {
        let nameBytes = Array(name.utf8)
        let crc = crc32(data)
        let offset = UInt32(buf.count)

        // Local file header
        u32(0x04034b50)             // signature
        u16(20)                     // version needed (2.0)
        u16(0)                      // flags
        u16(0)                      // compression: STORE
        u16(0); u16(0)              // last mod time, date
        u32(crc)
        u32(UInt32(data.count))     // compressed size
        u32(UInt32(data.count))     // uncompressed size
        u16(UInt16(nameBytes.count))
        u16(0)                      // extra field length
        buf.append(contentsOf: nameBytes)
        buf.append(data)

        entries.append(Entry(name: nameBytes, offset: offset, size: UInt32(data.count), crc: crc))
    }

    private mutating func finalize() -> Data {
        let cdOffset = UInt32(buf.count)
        var cdSize: UInt32 = 0

        for e in entries {
            let start = buf.count
            u32(0x02014b50)             // central dir signature
            u16(20); u16(20)            // version made by, needed
            u16(0); u16(0)              // flags, compression
            u16(0); u16(0)              // mod time, date
            u32(e.crc)
            u32(e.size); u32(e.size)    // compressed, uncompressed
            u16(UInt16(e.name.count))
            u16(0); u16(0)              // extra, comment length
            u16(0)                      // disk number start
            u16(0); u32(0)              // internal attrs, external attrs
            u32(e.offset)
            buf.append(contentsOf: e.name)
            cdSize += UInt32(buf.count - start)
        }

        // End of central directory
        u32(0x06054b50)
        u16(0); u16(0)                          // disk number, cd start disk
        u16(UInt16(entries.count))
        u16(UInt16(entries.count))
        u32(cdSize)
        u32(cdOffset)
        u16(0)                                  // comment length

        return buf
    }

    // MARK: - Helpers

    private mutating func u32(_ v: UInt32) {
        withUnsafeBytes(of: v.littleEndian) { buf.append(contentsOf: $0) }
    }
    private mutating func u16(_ v: UInt16) {
        withUnsafeBytes(of: v.littleEndian) { buf.append(contentsOf: $0) }
    }

    /// Standard CRC-32 (polynomial 0xEDB88320) — no libz dependency.
    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}

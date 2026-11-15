import Foundation
import Compression

/// Streams a .tar.gz (a sysdiagnose is several hundred MB) without loading it: reads 1 MB at a time,
/// inflates with the Compression framework, walks tar headers, and hands over only the entries
/// `want` asks for, each capped at `maxEntryBytes`. Everything else is skipped as it streams past.
public final class TarGzReader {
    public struct Entry: Sendable { public let path: String; public let size: Int }
    public enum ReaderError: Error { case notGzip, inflate, unreadable }

    let url: URL
    let maxEntryBytes: Int

    public init(url: URL, maxEntryBytes: Int = 8 << 20) {
        self.url = url
        self.maxEntryBytes = maxEntryBytes
    }

    /// `want` decides from the path and size whether to keep an entry; `found` gets each kept entry's bytes.
    /// `progress` gets compressed bytes read so far. Returns the number of entries seen.
    @discardableResult
    public func read(want: (Entry) -> Bool, found: (Entry, Data) -> Void, progress: ((Int64) -> Void)? = nil) throws -> Int {
        try withoutActuallyEscaping(want) { want in
            try withoutActuallyEscaping(found) { found in
                try readEscaping(want: want, found: found, progress: progress)
            }
        }
    }

    private func readEscaping(want: @escaping (Entry) -> Bool, found: @escaping (Entry, Data) -> Void, progress: ((Int64) -> Void)?) throws -> Int {
        guard let input = InputStream(url: url) else { throw ReaderError.unreadable }
        input.open()
        defer { input.close() }

        let inflater = try Inflater()
        var tar = TarWalker(maxEntryBytes: maxEntryBytes, want: want, found: found)
        var headerSkipped = false
        var pending = Data()
        var readTotal: Int64 = 0
        let chunk = 1 << 20
        var buffer = [UInt8](repeating: 0, count: chunk)

        while input.hasBytesAvailable {
            let n = input.read(&buffer, maxLength: chunk)
            if n < 0 { throw ReaderError.unreadable }
            if n == 0 { break }
            readTotal += Int64(n)
            progress?(readTotal)
            var data = Data(buffer[0..<n])
            if !headerSkipped {
                pending.append(data)
                guard let offset = try Self.gzipHeaderLength(pending) else { continue }
                data = pending.subdata(in: offset..<pending.count)
                pending = Data()
                headerSkipped = true
            }
            let out = try inflater.process(data, final: false)
            tar.feed(out)
            if tar.finished || inflater.done { break }
        }
        if !inflater.done { tar.feed(try inflater.process(Data(), final: true)) }
        return tar.entriesSeen
    }

    /// Length of the gzip member header (RFC 1952), or nil if more bytes are needed.
    static func gzipHeaderLength(_ d: Data) throws -> Int? {
        let b = [UInt8](d.prefix(4096))
        guard b.count >= 10 else { return nil }
        guard b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { throw ReaderError.notGzip }
        let flags = b[3]
        var i = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard b.count >= i + 2 else { return nil }
            i += 2 + (Int(b[i]) | (Int(b[i + 1]) << 8))
        }
        if flags & 0x08 != 0 { // FNAME
            guard let z = b[i...].firstIndex(of: 0) else { return nil }
            i = z + 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            guard let z = b[i...].firstIndex(of: 0) else { return nil }
            i = z + 1
        }
        if flags & 0x02 != 0 { i += 2 } // FHCRC
        return b.count >= i ? i : nil
    }

    /// Raw-deflate stream via `compression_stream` (COMPRESSION_ZLIB is raw deflate, RFC 1951).
    final class Inflater {
        private var stream: UnsafeMutablePointer<compression_stream>
        private(set) var done = false
        private let outSize = 1 << 20
        private var out: UnsafeMutablePointer<UInt8>

        init() throws {
            stream = .allocate(capacity: 1)
            out = .allocate(capacity: 1 << 20)
            guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { throw ReaderError.inflate }
        }

        deinit {
            compression_stream_destroy(stream)
            stream.deallocate()
            out.deallocate()
        }

        func process(_ input: Data, final: Bool) throws -> Data {
            guard !done else { return Data() }
            var result = Data()
            try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                stream.pointee.src_ptr = raw.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(out)
                stream.pointee.src_size = input.count
                repeat {
                    stream.pointee.dst_ptr = out
                    stream.pointee.dst_size = outSize
                    let status = compression_stream_process(stream, final ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                    let produced = outSize - stream.pointee.dst_size
                    if produced > 0 { result.append(out, count: produced) }
                    switch status {
                    case COMPRESSION_STATUS_END: done = true; return
                    case COMPRESSION_STATUS_OK: break
                    default: throw ReaderError.inflate
                    }
                } while stream.pointee.src_size > 0 || stream.pointee.dst_size == 0
            }
            return result
        }
    }

    /// Incremental tar (ustar / GNU long names / pax path) parser.
    struct TarWalker {
        let maxEntryBytes: Int
        let want: (Entry) -> Bool
        let found: (Entry, Data) -> Void
        var buffer = Data()
        var finished = false
        var entriesSeen = 0
        // Current entry state.
        var remaining = 0
        var padding = 0
        var keeping: Entry?
        var collected = Data()
        var longName: String?
        var collectingLongName = false
        var collectingPax = false

        init(maxEntryBytes: Int, want: @escaping (Entry) -> Bool, found: @escaping (Entry, Data) -> Void) {
            self.maxEntryBytes = maxEntryBytes; self.want = want; self.found = found
        }

        mutating func feed(_ data: Data) {
            buffer.append(data)
            while !finished {
                if remaining > 0 {
                    guard !buffer.isEmpty else { return }
                    let take = min(remaining, buffer.count)
                    let part = buffer.prefix(take)
                    if keeping != nil || collectingLongName || collectingPax {
                        if collected.count < maxEntryBytes { collected.append(part.prefix(maxEntryBytes - collected.count)) }
                    }
                    buffer.removeFirst(take)
                    remaining -= take
                    if remaining == 0 { finishEntry() }
                    continue
                }
                if padding > 0 {
                    guard buffer.count >= padding else { return }
                    buffer.removeFirst(padding)
                    padding = 0
                    continue
                }
                guard buffer.count >= 512 else { return }
                let header = [UInt8](buffer.prefix(512))
                buffer.removeFirst(512)
                if header.allSatisfy({ $0 == 0 }) { finished = true; return }
                startEntry(header)
            }
        }

        mutating func startEntry(_ h: [UInt8]) {
            func str(_ r: Range<Int>) -> String {
                let bytes = h[r].prefix { $0 != 0 }
                return String(decoding: bytes, as: UTF8.self)
            }
            let size = Int(str(124..<136).trimmingCharacters(in: .whitespaces), radix: 8) ?? 0
            let type = h[156]
            var name = str(0..<100)
            let prefix = str(345..<500)
            if str(257..<263).hasPrefix("ustar"), !prefix.isEmpty { name = prefix + "/" + name }
            if let l = longName { name = l; longName = nil }
            remaining = size
            padding = (512 - size % 512) % 512
            collected = Data()
            keeping = nil
            collectingLongName = type == UInt8(ascii: "L")
            collectingPax = type == UInt8(ascii: "x")
            if !collectingLongName && !collectingPax && (type == 0 || type == UInt8(ascii: "0")) {
                entriesSeen += 1
                let e = Entry(path: name, size: size)
                if want(e) { keeping = e }
            }
            if size == 0 { finishEntry() }
        }

        mutating func finishEntry() {
            if collectingLongName {
                longName = String(decoding: collected.prefix { $0 != 0 }, as: UTF8.self)
            } else if collectingPax {
                // Records look like "30 path=some/long/name\n".
                let text = String(decoding: collected, as: UTF8.self)
                for line in text.split(separator: "\n") {
                    if let r = line.range(of: " path=") { longName = String(line[r.upperBound...]) }
                }
            } else if let e = keeping {
                found(e, collected)
            }
            keeping = nil; collectingLongName = false; collectingPax = false
            collected = Data()
        }
    }
}

import Foundation
import Testing
@testable import Pulse

/// The LevelDB reader, which is the one piece of Pulse that parses somebody
/// else's binary format rather than their JSON.
///
/// A real browser profile cannot be committed — it is somebody's storage, and
/// it is thirty megabytes — so the store here is built by hand in the format
/// Chromium writes: a log file of `WriteBatch` records, keys shaped
/// `_<origin>\0<encoded name>`, values carrying their own encoding byte.
@Suite("Chromium localStorage")
struct ChromiumLocalStorageTests {
    // MARK: - Building a store

    /// One log record: four bytes of checksum this reader does not verify, the
    /// payload length, and the fragment type — 1 being "a whole record".
    private static func record(_ payload: [UInt8], type: UInt8 = 1) -> [UInt8] {
        var bytes: [UInt8] = [0, 0, 0, 0]
        bytes.append(UInt8(payload.count & 0xff))
        bytes.append(UInt8((payload.count >> 8) & 0xff))
        bytes.append(type)
        return bytes + payload
    }

    /// A batch: the sequence the first record gets, the number of records, and
    /// then each one as a kind byte and length-prefixed strings.
    private static func batch(sequence: UInt64, _ entries: [(key: [UInt8], value: [UInt8]?)]) -> [UInt8] {
        var bytes: [UInt8] = []
        for shift in 0..<8 { bytes.append(UInt8((sequence >> (8 * UInt64(shift))) & 0xff)) }
        let count = UInt32(entries.count)
        for shift in 0..<4 { bytes.append(UInt8((count >> (8 * UInt32(shift))) & 0xff)) }

        for entry in entries {
            bytes.append(entry.value == nil ? 0 : 1)
            bytes += varint(entry.key.count) + entry.key
            if let value = entry.value { bytes += varint(value.count) + value }
        }
        return bytes
    }

    private static func varint(_ value: Int) -> [UInt8] {
        var remaining = UInt64(value)
        var bytes: [UInt8] = []
        while remaining >= 0x80 {
            bytes.append(UInt8(remaining & 0x7f) | 0x80)
            remaining >>= 7
        }
        bytes.append(UInt8(remaining))
        return bytes
    }

    /// Chromium's own key shape. The `1` is "one byte per character"; a `0`
    /// there would mean UTF-16.
    private static func key(origin: String, name: String) -> [UInt8] {
        Array("_\(origin)".utf8) + [0, 1] + Array(name.utf8)
    }

    private static func value(_ text: String) -> [UInt8] { [1] + Array(text.utf8) }

    private static func store(_ log: [UInt8]) throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "leveldb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(log).write(to: directory.appending(path: "000003.log"))
        return directory
    }

    // MARK: - The log

    @Test("One origin's entries, and nobody else's")
    func readsOneOrigin() throws {
        let log = Self.record(Self.batch(sequence: 1, [
            (Self.key(origin: "https://app.devin.ai", name: "auth1_session"), Self.value("{\"token\":\"auth1_x\"}")),
            (Self.key(origin: "https://elsewhere.test", name: "auth1_session"), Self.value("not ours")),
            (Array("META:https://app.devin.ai".utf8), Self.value("bookkeeping")),
        ]))

        let directory = try Self.store(log)
        defer { try? FileManager.default.removeItem(at: directory) }

        let values = ChromiumLocalStorage.entries(origin: "https://app.devin.ai", in: directory)
        // The `META:` row is the area's own bookkeeping, not a script key, and
        // another site's storage is not this site's.
        #expect(values == ["auth1_session": "{\"token\":\"auth1_x\"}"])
    }

    @Test("The later write wins, and a deletion is a write")
    func sequenceDecides() throws {
        var log = Self.record(Self.batch(sequence: 10, [
            (Self.key(origin: "https://a.test", name: "token"), Self.value("old")),
            (Self.key(origin: "https://a.test", name: "gone"), Self.value("here")),
        ]))
        log += Self.record(Self.batch(sequence: 20, [
            (Self.key(origin: "https://a.test", name: "token"), Self.value("new")),
            // A deletion carries no value and has to beat the write it cancels
            // rather than being ignored as "nothing to read".
            (Self.key(origin: "https://a.test", name: "gone"), nil),
        ]))

        let directory = try Self.store(log)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(ChromiumLocalStorage.entries(origin: "https://a.test", in: directory) == ["token": "new"])
    }

    @Test("A record split across blocks is put back together")
    func fragmentsAreReassembled() throws {
        // Long enough that the record cannot sit inside one 32KB block, which
        // is the case the fragment types exist for.
        let long = String(repeating: "x", count: 40_000)
        let payload = Self.batch(sequence: 1, [
            (Self.key(origin: "https://a.test", name: "big"), Self.value(long)),
        ])

        // Chromium fills to the block boundary and continues in the next one.
        let firstRoom = 32_768 - 7
        var log = Self.record(Array(payload.prefix(firstRoom)), type: 2)
        log += Self.record(Array(payload.dropFirst(firstRoom)), type: 4)

        let directory = try Self.store(log)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(ChromiumLocalStorage.entries(origin: "https://a.test", in: directory)["big"]?.count == 40_000)
    }

    @Test("Padding at the end of a block is not read as a record")
    func paddingIsSkipped() throws {
        var log = Self.record(Self.batch(sequence: 1, [
            (Self.key(origin: "https://a.test", name: "first"), Self.value("1")),
        ]))
        // Fewer than seven bytes left in a block cannot hold a header, so
        // Chromium leaves them zeroed and starts the next block.
        log += [UInt8](repeating: 0, count: 32_768 - log.count)
        log += Self.record(Self.batch(sequence: 2, [
            (Self.key(origin: "https://a.test", name: "second"), Self.value("2")),
        ]))

        let directory = try Self.store(log)
        defer { try? FileManager.default.removeItem(at: directory) }

        let values = ChromiumLocalStorage.entries(origin: "https://a.test", in: directory)
        #expect(values == ["first": "1", "second": "2"])
    }

    // MARK: - How text is stored

    @Test("One byte per character, or UTF-16")
    func bothEncodingsAreRead() {
        #expect(ChromiumLocalStorage.text([1] + Array("plain".utf8)) == "plain")
        #expect(ChromiumLocalStorage.text([0, 0x4B, 0x00, 0x7D, 0x59]) == "K好")

        // An odd number of bytes is not UTF-16, and decoding it anyway drops
        // the last one — a value half-read is worse than one not read.
        #expect(ChromiumLocalStorage.text([0, 0x4B]) == nil)
        #expect(ChromiumLocalStorage.text([]) == nil)
        // A marker this reader does not know is a format that has moved on.
        #expect(ChromiumLocalStorage.text([9, 0x41]) == nil)
    }

    // MARK: - Skipping what cannot match

    @Test("The end of a prefix's range")
    func upperBoundIsTheNextKey() {
        #expect(LevelDB.upperBound([0x61, 0x62]) == [0x61, 0x63])
        // A trailing 0xff has no successor of its own, so the carry moves left.
        #expect(LevelDB.upperBound([0x61, 0xff]) == [0x62])
        // Nothing but 0xff has no upper bound at all: everything sorts below.
        #expect(LevelDB.upperBound([0xff, 0xff]) == nil)
    }

    @Test("Varints stop, even when the bytes do not")
    func varintsAreBounded() {
        var offset = 0
        #expect(LevelDB.varint([0xac, 0x02], &offset) == 300)
        #expect(offset == 2)

        // Without a cap a run of continuation bytes walks the whole file.
        var runaway = 0
        #expect(LevelDB.varint([UInt8](repeating: 0xff, count: 32), &runaway) == nil)
    }

    // MARK: - Snappy

    @Test("A literal, then a copy that overlaps itself")
    func snappyRepeatsARun() {
        // Eight bytes out: one literal 'a', then a copy of seven reaching back
        // one — which is the format's way of saying "repeat that". The source
        // has to include what the copy is still writing.
        let compressed: [UInt8] = [0x08, 0x00, 0x61, 0x0d, 0x01]
        #expect(Snappy.decompress(compressed).map { String(decoding: $0, as: UTF8.self) } == "aaaaaaaa")
    }

    @Test("A literal long enough to need its own length")
    func snappyReadsLongLiterals() {
        let text = String(repeating: "ab", count: 40)
        var compressed = [UInt8(text.utf8.count)]
        // Sixty and above, the tag says how many bytes the length takes rather
        // than carrying it.
        compressed += [60 << 2, UInt8(text.utf8.count - 1)]
        compressed += Array(text.utf8)

        #expect(Snappy.decompress(compressed).map { String(decoding: $0, as: UTF8.self) } == text)
    }

    @Test("A stream that promises more than it delivers is refused")
    func snappyRefusesShortOutput() {
        // Says ten bytes, produces one. Returning the one would hand a caller
        // half a block and let it parse the remains as entries.
        #expect(Snappy.decompress([0x0a, 0x00, 0x61]) == nil)
        // A copy reaching back further than anything written.
        #expect(Snappy.decompress([0x04, 0x0d, 0x01]) == nil)
    }
}

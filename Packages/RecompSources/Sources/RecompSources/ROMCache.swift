import CryptoKit
import Foundation

public struct ImportedROM: Codable, Sendable, Identifiable, Equatable {
    public var id: String { sha256 }
    public let name: String
    public let revision: String?
    public let sha1: String
    public let sha256: String
    public let size: Int64
    public let sourceID: UUID
    public var recognized: Bool { revision != nil }
    // Identity is not launch eligibility. The game runtime is not bundled yet.
    public var launchable: Bool { false }
}

public enum ImportProgress: Sendable {
    case downloading(TransferProgress)
    case verifying
}

public actor ROMCache {
    private let root: URL
    private let revisions: [String: String]
    private var importing = false

    public init(root: URL? = nil) throws {
        self.root = try root ?? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
            .appendingPathComponent("RecompTV/ROMCache", isDirectory: true)
        guard let manifest = Bundle.module.url(forResource: "shipwright-supported-roms", withExtension: "json") else {
            throw LibraryError.message("The Shipwright ROM manifest is missing from this app build.")
        }
        let entries = try JSONDecoder().decode([Revision].self, from: Data(contentsOf: manifest))
        revisions = Dictionary(uniqueKeysWithValues: entries.map { ($0.sha1, $0.name) })
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        // A prior terminated app can leave staging files, but no active transfer exists at init.
        for file in try FileManager.default.contentsOfDirectory(at: self.root, includingPropertiesForKeys: nil)
            where file.pathExtension == "partial" {
            try FileManager.default.removeItem(at: file)
        }
    }

    // Internal test injection permits synthetic accepted bytes without bundling a game ROM.
    init(root: URL, revisions: [String: String]) throws {
        self.root = root; self.revisions = revisions
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func current() throws -> ImportedROM? {
        let index = root.appendingPathComponent("current.json")
        guard FileManager.default.fileExists(atPath: index.path) else { return nil }
        let record = try JSONDecoder().decode(ImportedROM.self, from: Data(contentsOf: index))
        guard record.sha256.count == 64, record.sha256.allSatisfy({ $0.isHexDigit }) else { return nil }
        let file = root.appendingPathComponent(record.sha256 + ".romdata")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let identity = try ROMIdentity.read(file)
        guard identity.sha256 == record.sha256, revisions[identity.sha1] == record.revision,
              record.revision != nil else { return nil }
        return record
    }

    public func acquire(_ entry: LibraryEntry, sourceID: UUID, provider: any LibraryProvider,
                        progress: @escaping @Sendable (ImportProgress) -> Void) async throws -> ImportedROM {
        guard !importing else { throw LibraryError.message("Another ROM import is already running.") }
        importing = true
        defer { importing = false }
        let transfer = root.appendingPathComponent(UUID().uuidString + ".partial")
        let canonical = root.appendingPathComponent(UUID().uuidString + ".partial")
        defer {
            try? FileManager.default.removeItem(at: transfer)
            try? FileManager.default.removeItem(at: canonical)
        }
        try await provider.download(entry, to: transfer) { progress(.downloading($0)) }
        try Task.checkCancellation()
        progress(.verifying)
        let identity = try ROMIdentity.read(transfer, normalizedOutput: canonical)
        let result = ImportedROM(name: entry.name, revision: revisions[identity.sha1], sha1: identity.sha1,
                                 sha256: identity.sha256, size: identity.size, sourceID: sourceID)
        try Task.checkCancellation()
        guard result.recognized else { return result }
        let destination = root.appendingPathComponent(result.sha256 + ".romdata")
        if FileManager.default.fileExists(atPath: destination.path) {
            // Replace a possibly purged/corrupt old copy only after a complete fresh verification.
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: canonical)
        } else { try FileManager.default.moveItem(at: canonical, to: destination) }
        try JSONEncoder().encode(result).write(to: root.appendingPathComponent("current.json"), options: .atomic)
        // This first-game milestone retains one verified ROM. Source files are never modified.
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            where file.pathExtension == "romdata" && file != destination {
            try? FileManager.default.removeItem(at: file)
        }
        return result
    }

    public func clear() throws {
        guard !importing else { throw LibraryError.message("Cancel the import before clearing its cache.") }
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
    }
}

private struct Revision: Decodable { let name: String; let sha1: String }

struct ROMIdentity: Equatable {
    let sha1: String
    let sha256: String
    let size: Int64

    static func read(_ url: URL, normalizedOutput: URL? = nil) throws -> ROMIdentity {
        let before = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .contentModificationDateKey])
        guard before.isRegularFile == true, let length = before.fileSize else {
            throw LibraryError.message("The download is not a regular ROM file.")
        }
        try TransferLimits.validateSize(Int64(length))
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var output: FileHandle?
        if let normalizedOutput {
            guard FileManager.default.createFile(atPath: normalizedOutput.path, contents: nil) else {
                throw LibraryError.message("Could not prepare the ROM cache. Check available storage.")
            }
            output = try FileHandle(forWritingTo: normalizedOutput)
        }
        defer { try? output?.close() }
        let magic = try input.read(upToCount: 4) ?? Data()
        let stride: Int
        switch Array(magic) {
        case [0x80, 0x37, 0x12, 0x40]: stride = 1
        case [0x37, 0x80, 0x40, 0x12]: stride = 2
        case [0x40, 0x12, 0x37, 0x80]: stride = 4
        default: throw LibraryError.message("This is not an uncompressed N64 ROM. Extract any ZIP or 7z archive on your server first.")
        }
        try input.seek(toOffset: 0)
        var sha1 = Insecure.SHA1()
        var sha256 = SHA256()
        var count: Int64 = 0
        while let block = try input.read(upToCount: 1024 * 1024), !block.isEmpty {
            try Task.checkCancellation()
            guard block.count % 4 == 0, Int64(block.count) <= TransferLimits.romBytes - count else {
                throw LibraryError.message("The ROM is truncated or changed during verification.")
            }
            var bytes = [UInt8](block)
            if stride > 1 {
                for index in Swift.stride(from: 0, to: bytes.count, by: stride) {
                    bytes.swapAt(index, index + stride - 1)
                    if stride == 4 { bytes.swapAt(index + 1, index + 2) }
                }
            }
            let canonical = Data(bytes)
            sha1.update(data: canonical); sha256.update(data: canonical)
            try output?.write(contentsOf: canonical)
            count += Int64(block.count)
        }
        let after = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard count == Int64(length), after.fileSize == before.fileSize,
              after.contentModificationDate == before.contentModificationDate else {
            throw LibraryError.message("The ROM changed during verification. Download it again.")
        }
        try output?.synchronize()
        return ROMIdentity(sha1: sha1.finalize().map { String(format: "%02x", $0) }.joined(),
                           sha256: sha256.finalize().map { String(format: "%02x", $0) }.joined(), size: count)
    }
}

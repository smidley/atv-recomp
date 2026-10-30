import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Bounded, purgeable artwork cache. Image parsing and downsampling happen on this
/// actor, away from the UI. A shared download queue avoids flooding a ROM server.
public actor ArtworkCache {
    static let downloadLimit: Int64 = 8 * 1024 * 1024
    private let root: URL
    private let capacity: Int
    private struct Pending {
        let task: Task<Data, any Error>
        var waiters: Set<UUID>
    }
    private var pending = [String: Pending]()
    private var tail: Task<Data, any Error>?

    public init(root: URL? = nil, capacity: Int = 64 * 1024 * 1024) throws {
        self.root = try root ?? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("Nativecade/Artwork", isDirectory: true)
        self.capacity = max(0, capacity)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    public func image(at path: String, artwork: RomMArtwork, sourceID: UUID,
                      provider: (any LibraryProvider)?) async throws -> Data {
        try Task.checkCancellation()
        let identity = sourceID.uuidString + "\n" + artwork.server + "\n" + path
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = root.appendingPathComponent(key + ".png")
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size <= Self.downloadLimit, let data = try? Data(contentsOf: file),
           Self.validImage(data) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return data
        }
        let waiter = UUID()
        if var existing = pending[key] {
            existing.waiters.insert(waiter); pending[key] = existing
            return try await wait(for: existing.task, key: key, waiter: waiter)
        }
        guard let provider else { throw LibraryError.message("Artwork is not cached yet.") }
        let previous = tail
        let task = Task {
            // Waiting for an earlier request also bounds simultaneous image decodes.
            _ = await previous?.result
            try Task.checkCancellation()
            let original = try await provider.imageData(at: path)
            try Task.checkCancellation()
            let image = try Self.thumbnail(original)
            if image.count <= capacity {
                try? image.write(to: file, options: .atomic)
                trim()
            }
            return image
        }
        pending[key] = Pending(task: task, waiters: [waiter]); tail = task
        return try await wait(for: task, key: key, waiter: waiter)
    }

    private func wait(for task: Task<Data, any Error>, key: String, waiter: UUID) async throws -> Data {
        defer { release(key: key, waiter: waiter) }
        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.release(key: key, waiter: waiter) }
        }
        try Task.checkCancellation()
        return result
    }

    private func release(key: String, waiter: UUID) {
        guard var entry = pending[key], entry.waiters.remove(waiter) != nil else { return }
        if entry.waiters.isEmpty {
            entry.task.cancel(); pending[key] = nil
        } else { pending[key] = entry }
    }

    private static func validImage(_ data: Data) -> Bool {
        guard data.count <= downloadLimit,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return width > 0 && height > 0 && width <= 20_000 && height <= 20_000 && width * height <= 40_000_000
    }

    static func thumbnail(_ data: Data) throws -> Data {
        guard validImage(data),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200,
              ] as CFDictionary) else { throw LibraryError.message("RomM did not return a supported image.") }
        let data = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw LibraryError.message("The artwork could not be prepared.")
        }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output), data.length <= downloadLimit else {
            throw LibraryError.message("The artwork could not be prepared.")
        }
        return data as Data
    }

    private func trim() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        let records = files.filter { $0.pathExtension == "png" }.compactMap { file -> (URL, Int, Date)? in
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { return nil }
            return (file, size, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var size = records.reduce(0) { $0 + $1.1 }
        for record in records where size > capacity {
            do { try FileManager.default.removeItem(at: record.0); size -= record.1 } catch { }
        }
    }
}

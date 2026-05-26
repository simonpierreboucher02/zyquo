import Foundation
import CryptoKit

// MARK: - SnapshotRef

/// A reference to a stored file snapshot.
public struct SnapshotRef: Sendable, Codable, Equatable {
    /// SHA-256 hash of the original file content.
    public let sha256: String
    /// Original file path (absolute or workspace-relative).
    public let originalPath: String
    /// Size of the original file in bytes.
    public let size: Int

    public init(sha256: String, originalPath: String, size: Int) {
        self.sha256 = sha256
        self.originalPath = originalPath
        self.size = size
    }
}

// MARK: - SnapshotStore

/// Content-addressed storage for file pre-images.
///
/// Stores file snapshots as gzip-compressed content under `.zyquo/snapshots/<sha256>.gz`.
/// Content-addressed: identical files are stored only once.
///
/// Reference: CLAUDE.md §23.1, §29 Phase 7
public final class SnapshotStore: @unchecked Sendable {
    /// Root directory for snapshots (typically `.zyquo/snapshots/`).
    private let storageDir: URL

    public init(storageDir: URL) {
        self.storageDir = storageDir
    }

    // MARK: - Snapshot

    /// Take a snapshot of a file at the given path.
    ///
    /// - Parameter path: The file URL to snapshot.
    /// - Returns: A `SnapshotRef` that can be used to restore the content later.
    /// - Throws: If the file cannot be read or the snapshot cannot be stored.
    public func snapshot(path: URL) throws -> SnapshotRef {
        let fm = FileManager.default

        guard let data = fm.contents(atPath: path.path) else {
            throw SnapshotError.fileNotFound(path: path.path)
        }

        let hash = computeSHA256(data: data)
        let ref = SnapshotRef(sha256: hash, originalPath: path.path, size: data.count)

        // Only store if not already present (content-addressed)
        if !exists(sha: hash) {
            try store(data: data, sha: hash)
        }

        return ref
    }

    /// Take a snapshot of raw data (for in-memory content).
    ///
    /// - Parameters:
    ///   - data: The raw data to snapshot.
    ///   - originalPath: The logical path this data came from.
    /// - Returns: A `SnapshotRef`.
    public func snapshot(data: Data, originalPath: String) throws -> SnapshotRef {
        let hash = computeSHA256(data: data)
        let ref = SnapshotRef(sha256: hash, originalPath: originalPath, size: data.count)

        if !exists(sha: hash) {
            try store(data: data, sha: hash)
        }

        return ref
    }

    /// Take a snapshot from a string.
    public func snapshot(content: String, originalPath: String) throws -> SnapshotRef {
        guard let data = content.data(using: .utf8) else {
            throw SnapshotError.encodingError
        }
        return try snapshot(data: data, originalPath: originalPath)
    }

    // MARK: - Restore

    /// Restore a snapshot's content.
    ///
    /// - Parameter ref: The snapshot reference to restore.
    /// - Returns: The original file data, or nil if the snapshot is not found.
    public func restore(ref: SnapshotRef) -> Data? {
        return restore(sha: ref.sha256)
    }

    /// Restore content by SHA-256 hash.
    ///
    /// - Parameter sha: The SHA-256 hash to look up.
    /// - Returns: The original data, or nil if not found.
    public func restore(sha: String) -> Data? {
        let path = storagePath(for: sha)
        let fm = FileManager.default

        guard let compressedData = fm.contents(atPath: path.path) else {
            return nil
        }

        return decompress(compressedData)
    }

    /// Restore content as a string.
    public func restoreString(ref: SnapshotRef) -> String? {
        guard let data = restore(ref: ref) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Query

    /// Check if a snapshot with the given SHA exists.
    public func exists(sha: String) -> Bool {
        let path = storagePath(for: sha)
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// List all stored snapshot SHAs.
    public func listAll() -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "gz" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    /// Total storage size in bytes.
    public func totalSize() -> UInt64 {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: UInt64 = 0
        for file in files {
            if let attrs = try? fm.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? UInt64 {
                total += size
            }
        }
        return total
    }

    // MARK: - Internal

    /// Path where a snapshot is stored.
    private func storagePath(for sha: String) -> URL {
        storageDir.appendingPathComponent("\(sha).gz")
    }

    /// Compute SHA-256 of data.
    private func computeSHA256(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Compress data using zlib (gzip-compatible).
    private func compress(_ data: Data) -> Data? {
        // Use NSData's compression (available on macOS 10.11+)
        return try? (data as NSData).compressed(using: .zlib) as Data
    }

    /// Decompress zlib-compressed data.
    private func decompress(_ data: Data) -> Data? {
        return try? (data as NSData).decompressed(using: .zlib) as Data
    }

    /// Store compressed data.
    private func store(data: Data, sha: String) throws {
        let fm = FileManager.default

        // Ensure storage directory exists
        if !fm.fileExists(atPath: storageDir.path) {
            try fm.createDirectory(at: storageDir, withIntermediateDirectories: true)
        }

        guard let compressed = compress(data) else {
            throw SnapshotError.compressionFailed
        }

        let path = storagePath(for: sha)
        try compressed.write(to: path)
    }
}

// MARK: - SnapshotError

public enum SnapshotError: Error, Sendable, CustomStringConvertible {
    case fileNotFound(path: String)
    case compressionFailed
    case decompressionFailed
    case encodingError

    public var description: String {
        switch self {
        case .fileNotFound(let path): return "Snapshot: file not found at \(path)"
        case .compressionFailed: return "Snapshot: compression failed"
        case .decompressionFailed: return "Snapshot: decompression failed"
        case .encodingError: return "Snapshot: failed to encode content as UTF-8"
        }
    }
}

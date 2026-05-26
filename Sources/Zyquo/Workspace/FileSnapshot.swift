import Foundation

public struct FileSnapshot: Sendable, Equatable {
    public let path: String
    public let relativePath: String
    public let size: UInt64
    public let modificationDate: Date
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let isExecutable: Bool

    public init(
        path: String,
        relativePath: String,
        size: UInt64,
        modificationDate: Date,
        isDirectory: Bool,
        isSymlink: Bool = false,
        isExecutable: Bool = false
    ) {
        self.path = path
        self.relativePath = relativePath
        self.size = size
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isExecutable = isExecutable
    }

    public static func from(url: URL, relativeTo root: URL) -> FileSnapshot? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return nil }

        let size = attrs[.size] as? UInt64 ?? 0
        let mdate = attrs[.modificationDate] as? Date ?? Date.distantPast
        let type = attrs[.type] as? FileAttributeType
        let isDir = type == .typeDirectory
        let isSymlink = type == .typeSymbolicLink
        let perms = attrs[.posixPermissions] as? Int ?? 0
        let isExec = !isDir && (perms & 0o111) != 0

        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        let relative = filePath.hasPrefix(rootPath)
            ? String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : filePath

        return FileSnapshot(
            path: filePath,
            relativePath: relative,
            size: size,
            modificationDate: mdate,
            isDirectory: isDir,
            isSymlink: isSymlink,
            isExecutable: isExec
        )
    }
}

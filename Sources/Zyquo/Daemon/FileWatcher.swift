import CoreServices
import Foundation

// MARK: - FSFileChange

/// Represents a single filesystem change detected by the file watcher.
///
/// Named `FSFileChange` to distinguish from `FileChange` in `Diff/ChangeSet`
/// which represents a diff-level file change within a patch.
public struct FSFileChange: Sendable {
    /// The absolute path of the changed file or directory.
    public let path: String
    /// The kind of change that occurred.
    public let kind: FileChangeKind
    /// When the change was detected.
    public let timestamp: Date

    public init(path: String, kind: FileChangeKind, timestamp: Date = Date()) {
        self.path = path
        self.kind = kind
        self.timestamp = timestamp
    }
}

// MARK: - FileChangeKind

/// The type of filesystem change.
public enum FileChangeKind: String, Sendable {
    case created
    case modified
    case deleted
    case renamed
}

// MARK: - FileWatcher

/// Watches a directory tree for filesystem changes using macOS FSEvents.
///
/// Changes are batched with a configurable latency (default 0.5s) and
/// delivered via a callback. The watcher filters out paths matching
/// common skip directories (`.git`, `node_modules`, `.build`, etc.)
/// but does NOT apply .gitignore / .zyquoignore rules itself -- that
/// is the caller's responsibility to allow flexible filtering.
///
/// Thread-safety: the class is marked `@unchecked Sendable` because
/// FSEvents callbacks run on arbitrary threads, but all mutable state
/// is protected by the `lock`.
///
/// Reference: CLAUDE.md V2 Phase 4 - Background Intelligence Runtime
public final class FileWatcher: @unchecked Sendable {

    // MARK: - Properties

    /// The root path being watched.
    public let watchPath: URL

    /// Batching latency in seconds.
    public let latency: TimeInterval

    /// The callback invoked with batched changes.
    private let callback: @Sendable ([FSFileChange]) -> Void

    /// The FSEvents stream reference.
    private var stream: FSEventStreamRef?

    /// Whether the watcher is currently running.
    private var _isRunning: Bool = false

    /// Lock protecting mutable state.
    private let lock = NSLock()

    /// Directories to always skip.
    private static let skipDirs: Set<String> = [
        ".git", ".hg", ".svn", "node_modules", ".build", "build",
        "DerivedData", "Pods", ".venv", "venv", "__pycache__",
        "target", "dist", ".next", ".nuxt", ".output",
    ]

    // MARK: - Init

    /// Create a file watcher.
    ///
    /// - Parameters:
    ///   - path: The root directory to watch recursively.
    ///   - latency: How long to batch changes before delivering (seconds).
    ///   - callback: Called with batched file changes on a background thread.
    public init(
        path: URL,
        latency: TimeInterval = 0.5,
        callback: @Sendable @escaping ([FSFileChange]) -> Void
    ) {
        self.watchPath = path.standardizedFileURL
        self.latency = latency
        self.callback = callback
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Whether the watcher is currently monitoring for changes.
    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }

    /// Start watching for filesystem changes.
    ///
    /// Creates an FSEventStream and schedules it on the current run loop.
    /// If already running, this is a no-op.
    public func start() {
        lock.lock()
        guard !_isRunning else {
            lock.unlock()
            return
        }
        lock.unlock()

        let pathString = watchPath.path as CFString
        let pathsToWatch = [pathString] as CFArray

        // Store self as an unmanaged pointer for the C callback
        let contextPtr = Unmanaged.passRetained(self).toOpaque()

        var context = FSEventStreamContext(
            version: 0,
            info: contextPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagUseCFTypes)
            | UInt32(kFSEventStreamCreateFlagFileEvents)
            | UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            Unmanaged<FileWatcher>.fromOpaque(contextPtr).release()
            return
        }

        self.stream = stream

        let queue = DispatchQueue(label: "dev.zyquo.filewatcher", qos: .utility)
        FSEventStreamSetDispatchQueue(stream, queue)

        FSEventStreamStart(stream)

        lock.lock()
        _isRunning = true
        lock.unlock()
    }

    /// Stop watching for filesystem changes.
    ///
    /// Tears down the FSEventStream and releases resources.
    /// If not running, this is a no-op.
    public func stop() {
        lock.lock()
        let wasRunning = _isRunning
        _isRunning = false
        let currentStream = stream
        stream = nil
        lock.unlock()

        guard wasRunning, let currentStream else { return }

        FSEventStreamStop(currentStream)
        FSEventStreamInvalidate(currentStream)
        FSEventStreamRelease(currentStream)
    }

    // MARK: - Internal

    /// Process raw FSEvents flags into structured FSFileChange values.
    fileprivate func handleEvents(
        paths: [String],
        flags: [FSEventStreamEventFlags]
    ) {
        let now = Date()
        var changes: [FSFileChange] = []

        for (path, flag) in zip(paths, flags) {
            // Skip known directories
            let components = path.components(separatedBy: "/")
            let shouldSkip = components.contains { Self.skipDirs.contains($0) }
            if shouldSkip { continue }

            let kind = Self.classifyEvent(flag)
            changes.append(FSFileChange(path: path, kind: kind, timestamp: now))
        }

        guard !changes.isEmpty else { return }
        callback(changes)
    }

    /// Map FSEvents flags to a FileChangeKind.
    private static func classifyEvent(_ flags: FSEventStreamEventFlags) -> FileChangeKind {
        if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
            return .created
        }
        if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
            return .deleted
        }
        if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
            return .renamed
        }
        // Default to modified for all other changes (content change, metadata, etc.)
        return .modified
    }
}

// MARK: - FSEvents C Callback

/// The C function pointer callback for FSEventStreamCreate.
///
/// Bridges the C callback into the Swift `FileWatcher.handleEvents` method.
private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }

    let watcher = Unmanaged<FileWatcher>.fromOpaque(clientCallBackInfo)
        .takeUnretainedValue()

    // eventPaths is a CFArray of CFString when kFSEventStreamCreateFlagUseCFTypes is set
    guard let cfPaths = unsafeBitCast(eventPaths, to: CFArray?.self) else { return }

    var paths: [String] = []
    var flags: [FSEventStreamEventFlags] = []

    for i in 0..<numEvents {
        if let cfPath = CFArrayGetValueAtIndex(cfPaths, i) {
            let nsPath = unsafeBitCast(cfPath, to: CFString.self) as String
            paths.append(nsPath)
            flags.append(eventFlags[i])
        }
    }

    watcher.handleEvents(paths: paths, flags: flags)
}

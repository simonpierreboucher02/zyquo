import Foundation

// MARK: - ResourceLimiter

/// Actor-based concurrency limiter that prevents unbounded parallelism.
///
/// Provides semaphore-like behavior using Swift structured concurrency.
/// Callers `acquire()` a slot before executing work and `release()` it
/// when done. If all slots are occupied, `acquire()` suspends until a
/// slot becomes available.
///
/// Reference: CLAUDE.md §30 Phase 7
public actor ResourceLimiter {

    /// Maximum number of concurrent tasks allowed.
    public let maxConcurrentTasks: Int

    /// Optional memory cap in megabytes (reserved for future use).
    public let maxMemoryMB: Int?

    /// Number of currently active (acquired) slots.
    public private(set) var active: Int = 0

    /// Queue of continuations waiting for a slot to become available.
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Creates a new resource limiter.
    ///
    /// - Parameters:
    ///   - maxConcurrentTasks: Maximum concurrent slots. Defaults to
    ///     half the active processor count, minimum 2.
    ///   - maxMemoryMB: Optional memory cap (reserved for future use).
    public init(
        maxConcurrentTasks: Int? = nil,
        maxMemoryMB: Int? = nil
    ) {
        let cpuDefault = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        self.maxConcurrentTasks = maxConcurrentTasks ?? cpuDefault
        self.maxMemoryMB = maxMemoryMB
    }

    // MARK: - Slot Management

    /// Acquire a concurrency slot.
    ///
    /// If a slot is available, this returns immediately. Otherwise, the
    /// caller is suspended until a slot is released by another task.
    public func acquire() async {
        if active < maxConcurrentTasks {
            active += 1
            return
        }

        // All slots occupied -- suspend until one is released
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }

        active += 1
    }

    /// Release a concurrency slot.
    ///
    /// If there are suspended waiters, the first one is resumed.
    public func release() {
        active = max(0, active - 1)

        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }

    /// The number of available (unoccupied) slots.
    public var available: Int {
        max(0, maxConcurrentTasks - active)
    }
}

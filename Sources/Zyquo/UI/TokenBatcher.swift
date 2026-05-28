import Foundation

public actor TokenBatcher {
    private var buffer: String = ""
    private var flushTask: Task<Void, Never>?
    private let flushInterval: UInt64  // nanoseconds
    private let writer: @Sendable (String) -> Void

    public init(intervalMs: Int = 16, writer: @escaping @Sendable (String) -> Void) {
        self.flushInterval = UInt64(intervalMs) * 1_000_000
        self.writer = writer
    }

    public func append(_ text: String) {
        buffer += text
        scheduleFlush()
    }

    public func flushNow() {
        guard !buffer.isEmpty else { return }
        let content = buffer
        buffer = ""
        flushTask?.cancel()
        flushTask = nil
        writer(content)
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.flushInterval ?? 16_000_000)
            await self?.flushNow()
        }
    }
}

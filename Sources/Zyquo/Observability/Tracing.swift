import Foundation

public struct TraceSpan: Sendable, Codable {
    public let id: String
    public let parentId: String?
    public let operation: String
    public let startTime: Date
    public let endTime: Date
    public let durationMs: Int
    public let attributes: [String: String]
    public let isError: Bool

    public init(
        id: String = UUID().uuidString,
        parentId: String? = nil,
        operation: String,
        startTime: Date,
        endTime: Date,
        attributes: [String: String] = [:],
        isError: Bool = false
    ) {
        self.id = id
        self.parentId = parentId
        self.operation = operation
        self.startTime = startTime
        self.endTime = endTime
        self.durationMs = Int(endTime.timeIntervalSince(startTime) * 1000)
        self.attributes = attributes
        self.isError = isError
    }
}

public actor TraceCollector {
    public static let shared = TraceCollector()

    private var spans: [String: [TraceSpan]] = [:]

    private init() {}

    public func record(_ span: TraceSpan, sessionId: String) {
        spans[sessionId, default: []].append(span)
    }

    public func spans(for sessionId: String) -> [TraceSpan] {
        spans[sessionId] ?? []
    }

    public func exportJSONL(sessionId: String) throws -> String {
        let sessionSpans = spans[sessionId] ?? []
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys

        return try sessionSpans.map { span in
            let data = try encoder.encode(span)
            return String(data: data, encoding: .utf8) ?? ""
        }.joined(separator: "\n")
    }

    public func flush(sessionId: String, to url: URL) throws {
        let content = try exportJSONL(sessionId: sessionId)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public func clear(sessionId: String) {
        spans.removeValue(forKey: sessionId)
    }

    public func allSessionIds() -> [String] {
        Array(spans.keys)
    }
}

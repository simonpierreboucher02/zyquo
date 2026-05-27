import Foundation
import Logging
import os

public enum ZyquoLogger {
    private static let _logger = OSAllocatedUnfairLock<Logging.Logger?>(initialState: nil)

    public static var shared: Logging.Logger {
        if let existing = _logger.withLock({ $0 }) { return existing }
        let logger = Logging.Logger(label: "dev.zyquo.cli")
        _logger.withLock { $0 = logger }
        return logger
    }

    public static func bootstrap(verbose: Bool, logFile: URL?) {
        LoggingSystem.bootstrap { label in
            var handlers: [any LogHandler] = []

            var consoleHandler = StreamLogHandler.standardError(label: label)
            consoleHandler.logLevel = verbose ? .debug : .warning
            handlers.append(consoleHandler)

            if let logFile {
                if let fileHandler = JSONLFileLogHandler(label: label, path: logFile) {
                    handlers.append(fileHandler)
                }
            }

            return MultiplexLogHandler(handlers)
        }

        _logger.withLock {
            var logger = Logging.Logger(label: "dev.zyquo.cli")
            logger.logLevel = verbose ? .debug : .warning
            $0 = logger
        }
    }
}

struct JSONLFileLogHandler: LogHandler {
    var metadata: Logging.Logger.Metadata = [:]
    var logLevel: Logging.Logger.Level = .info
    let label: String
    private let fileHandle: FileHandle

    init?(label: String, path: URL) {
        self.label = label
        let manager = FileManager.default
        let dir = path.deletingLastPathComponent()
        try? manager.createDirectory(at: dir, withIntermediateDirectories: true)
        if !manager.fileExists(atPath: path.path) {
            manager.createFile(atPath: path.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: path) else { return nil }
        handle.seekToEndOfFile()
        self.fileHandle = handle
    }

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        let merged = self.metadata.merging(event.metadata ?? [:]) { _, new in new }
        let iso8601 = ISO8601DateFormatter().string(from: Date())
        let metaString = merged.isEmpty ? "" : ", \"metadata\": \(metadataJSON(merged))"
        let json = "{\"ts\": \"\(iso8601)\", \"level\": \"\(event.level)\", \"msg\": \"\(redact(String(describing: event.message)))\"\(metaString)}\n"
        if let data = json.data(using: .utf8) {
            fileHandle.write(data)
        }
    }

    private func metadataJSON(_ meta: Logging.Logger.Metadata) -> String {
        let pairs = meta.map { "\"\($0.key)\": \"\(redact(String(describing: $0.value)))\"" }
        return "{\(pairs.joined(separator: ", "))}"
    }

    private func redact(_ text: String) -> String {
        Redaction.redact(text)
    }
}

public enum Redaction {
    private static let patterns: [(NSRegularExpression, String)] = {
        let defs: [(String, String)] = [
            ("(sk-[a-zA-Z0-9_-]{8,})", "[REDACTED_API_KEY]"),
            ("(Bearer\\s+[a-zA-Z0-9._-]{20,})", "[REDACTED_BEARER]"),
            ("([a-zA-Z_]*(?:TOKEN|SECRET|KEY|PASSWORD|CREDENTIAL)[a-zA-Z_]*\\s*=\\s*)\\S+", "$1[REDACTED]"),
        ]
        return defs.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            return (regex, replacement)
        }
    }()

    public static func redact(_ text: String) -> String {
        var result = text
        for (regex, replacement) in patterns {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }
}

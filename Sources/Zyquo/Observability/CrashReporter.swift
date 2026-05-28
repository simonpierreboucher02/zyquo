import Foundation

private func crashExceptionHandler(_ exception: NSException) {
    let report = CrashReporter.buildReport(
        kind: "uncaught_exception",
        message: exception.name.rawValue,
        reason: exception.reason,
        callStack: exception.callStackSymbols
    )
    CrashReporter.writeReport(report)
}

private func crashSignalHandler(_ sig: Int32) {
    let name: String
    switch sig {
    case SIGABRT: name = "SIGABRT"
    case SIGSEGV: name = "SIGSEGV"
    default: name = "SIG\(sig)"
    }
    let report = CrashReporter.buildReport(
        kind: "signal",
        message: name,
        reason: nil,
        callStack: Thread.callStackSymbols
    )
    CrashReporter.writeReport(report)
    _Exit(128 + sig)
}

public enum CrashReporter {
    private static let crashDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("Zyquo")
            .appendingPathComponent("crash")
    }()

    public static func install() {
        NSSetUncaughtExceptionHandler(crashExceptionHandler)
        signal(SIGABRT, crashSignalHandler)
        signal(SIGSEGV, crashSignalHandler)
    }

    public static func reportError(_ error: Error, context: [String: String] = [:]) {
        let report = buildReport(
            kind: "error",
            message: String(describing: type(of: error)),
            reason: error.localizedDescription,
            callStack: Thread.callStackSymbols,
            context: context
        )
        writeReport(report)
    }

    static func buildReport(
        kind: String,
        message: String,
        reason: String?,
        callStack: [String],
        context: [String: String] = [:]
    ) -> [String: Any] {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var report: [String: Any] = [
            "timestamp": timestamp,
            "kind": kind,
            "message": Redaction.redact(message),
            "process": ProcessInfo.processInfo.processName,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
        ]

        if let reason = reason {
            report["reason"] = Redaction.redact(reason)
        }

        let redactedStack = callStack.prefix(50).map { Redaction.redact($0) }
        report["call_stack"] = redactedStack

        if !context.isEmpty {
            report["context"] = context.mapValues { Redaction.redact($0) }
        }

        return report
    }

    static func writeReport(_ report: [String: Any]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: crashDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "crash_\(timestamp).json"
        let path = crashDir.appendingPathComponent(filename)

        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: path)
    }

    public static func recentReports(limit: Int = 10) -> [URL] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: crashDir, includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return aDate > bDate
            }
            .prefix(limit)
            .map { $0 }
    }
}

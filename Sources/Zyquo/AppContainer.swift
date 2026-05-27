import Foundation
import Logging

public final class AppContainer: Sendable {
    public let config: Config
    public let logger: Logger

    public init(flags: CommandFlags = .init()) {
        let workspaceRoot = flags.workspace.map { URL(fileURLWithPath: $0) }
            ?? Self.currentDirectory
        self.workspaceRoot = workspaceRoot

        let workspaceConfigPath = workspaceRoot
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("config.json")

        let logFileURL: URL? = flags.logFile.map { URL(fileURLWithPath: $0) }

        ZyquoLogger.bootstrap(verbose: flags.verbose, logFile: logFileURL)

        self.config = Config(
            flags: flags,
            workspaceConfigPath: FileManager.default.fileExists(atPath: workspaceConfigPath.path)
                ? workspaceConfigPath : nil
        )
        self.logger = ZyquoLogger.shared
    }

    public let workspaceRoot: URL

    private static var currentDirectory: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

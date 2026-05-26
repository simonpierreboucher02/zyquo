import Foundation
import Logging

public final class AppContainer: Sendable {
    public let config: Config
    public let logger: Logger

    public init(flags: CommandFlags = .init()) {
        let workspaceRoot = flags.workspace.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

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

    public var workspaceRoot: URL {
        config.providers.resolvedProvider == "" ? currentDirectory : currentDirectory
    }

    private var currentDirectory: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

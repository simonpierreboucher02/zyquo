import ArgumentParser
import Foundation
import ZyquoCore

struct VersionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Show version, build, and provider info"
    )

    func run() async throws {
        print(ZyquoInfo.versionString)
        print("Platform: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        #if arch(arm64)
        print("Architecture: arm64")
        #elseif arch(x86_64)
        print("Architecture: x86_64")
        #else
        print("Architecture: unknown")
        #endif
    }
}

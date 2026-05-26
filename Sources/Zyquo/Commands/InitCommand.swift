import ArgumentParser
import Foundation

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scaffold .zyquo/ in current workspace"
    )

    @OptionGroup var globals: ZyquoCLI.GlobalOptions

    func run() async throws {
        let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
        let zyquoDir = root.appendingPathComponent(".zyquo")
        let fm = FileManager.default

        if fm.fileExists(atPath: zyquoDir.path) {
            print("  .zyquo/ already exists at \(root.path)")
            return
        }

        let dirs = [
            "memory",
            "memory/sessions",
            "snapshots",
            "patches",
            "plans",
            "logs",
            "index",
        ]

        for dir in dirs {
            try fm.createDirectory(
                at: zyquoDir.appendingPathComponent(dir),
                withIntermediateDirectories: true
            )
        }

        let configJSON = """
        {
          "version": 1,
          "provider": "anthropic",
          "model": "claude-sonnet-4-6",
          "tools": {
            "shell.run": { "enabled": true },
            "git.commit": { "enabled": true },
            "git.push": { "enabled": false }
          }
        }
        """
        try configJSON.write(
            to: zyquoDir.appendingPathComponent("config.json"),
            atomically: true,
            encoding: .utf8
        )

        let trustJSON = """
        {
          "version": 1,
          "grants": []
        }
        """
        try trustJSON.write(
            to: zyquoDir.appendingPathComponent("trust.json"),
            atomically: true,
            encoding: .utf8
        )

        let projectMemory = """
        # Project Memory

        <!-- This file is hand-editable. Zyquo will only propose changes via diffs. -->
        <!-- Add your project conventions, architecture notes, and preferences here. -->

        ## Architecture

        ## Conventions

        ## Test Commands

        ## Notes

        """
        try projectMemory.write(
            to: zyquoDir.appendingPathComponent("memory/project.md"),
            atomically: true,
            encoding: .utf8
        )

        let zyquoignore = """
        .env
        .env.*
        *.pem
        *.key
        *.p12
        *.mobileprovision
        Pods/
        DerivedData/
        .build/
        node_modules/
        .venv/
        target/
        """
        let ignoreURL = root.appendingPathComponent(".zyquoignore")
        if !fm.fileExists(atPath: ignoreURL.path) {
            try zyquoignore.write(to: ignoreURL, atomically: true, encoding: .utf8)
        }

        print("  Initialized .zyquo/ in \(root.path)")
        print()
        print("  Created:")
        print("    .zyquo/config.json      — workspace configuration")
        print("    .zyquo/trust.json        — trust grants")
        print("    .zyquo/memory/project.md — project memory (hand-editable)")
        print("    .zyquoignore             — paths the agent should not touch")
        print()
        print("  Next: run \u{1B}[1mzyquo provider login anthropic\u{1B}[0m to set up your API key.")
    }
}

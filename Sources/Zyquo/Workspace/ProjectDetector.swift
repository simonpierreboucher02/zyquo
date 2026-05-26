import Foundation

public enum Language: String, Sendable, CaseIterable {
    case swift, python, typescript, javascript, rust, go
    case ruby, elixir, java, kotlin, c, cpp, objectiveC, shell
    case html, css, sql, markdown, json, yaml, toml

    public var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .python: return "Python"
        case .typescript: return "TypeScript"
        case .javascript: return "JavaScript"
        case .rust: return "Rust"
        case .go: return "Go"
        case .ruby: return "Ruby"
        case .elixir: return "Elixir"
        case .java: return "Java"
        case .kotlin: return "Kotlin"
        case .c: return "C"
        case .cpp: return "C++"
        case .objectiveC: return "Objective-C"
        case .shell: return "Shell"
        case .html: return "HTML"
        case .css: return "CSS"
        case .sql: return "SQL"
        case .markdown: return "Markdown"
        case .json: return "JSON"
        case .yaml: return "YAML"
        case .toml: return "TOML"
        }
    }

    public var extensions: [String] {
        switch self {
        case .swift: return ["swift"]
        case .python: return ["py", "pyx", "pyi"]
        case .typescript: return ["ts", "tsx", "mts", "cts"]
        case .javascript: return ["js", "jsx", "mjs", "cjs"]
        case .rust: return ["rs"]
        case .go: return ["go"]
        case .ruby: return ["rb", "rake", "gemspec"]
        case .elixir: return ["ex", "exs"]
        case .java: return ["java"]
        case .kotlin: return ["kt", "kts"]
        case .c: return ["c", "h"]
        case .cpp: return ["cpp", "cc", "cxx", "hpp", "hh", "hxx"]
        case .objectiveC: return ["m", "mm"]
        case .shell: return ["sh", "bash", "zsh", "fish"]
        case .html: return ["html", "htm"]
        case .css: return ["css", "scss", "sass", "less"]
        case .sql: return ["sql"]
        case .markdown: return ["md", "markdown"]
        case .json: return ["json", "jsonc"]
        case .yaml: return ["yml", "yaml"]
        case .toml: return ["toml"]
        }
    }

    static let extensionMap: [String: Language] = {
        var map: [String: Language] = [:]
        for lang in Language.allCases {
            for ext in lang.extensions {
                map[ext] = lang
            }
        }
        return map
    }()

    public static func from(extension ext: String) -> Language? {
        extensionMap[ext.lowercased()]
    }
}

public enum Framework: String, Sendable {
    case swiftPM, xcode, tuist
    case node, react, nextjs, vue, angular, express
    case django, flask, fastapi
    case rails
    case phoenix
    case springBoot, android
    case cargo
    case goMod

    public var displayName: String {
        switch self {
        case .swiftPM: return "SwiftPM"
        case .xcode: return "Xcode"
        case .tuist: return "Tuist"
        case .node: return "Node.js"
        case .react: return "React"
        case .nextjs: return "Next.js"
        case .vue: return "Vue"
        case .angular: return "Angular"
        case .express: return "Express"
        case .django: return "Django"
        case .flask: return "Flask"
        case .fastapi: return "FastAPI"
        case .rails: return "Rails"
        case .phoenix: return "Phoenix"
        case .springBoot: return "Spring Boot"
        case .android: return "Android"
        case .cargo: return "Cargo"
        case .goMod: return "Go Modules"
        }
    }
}

public enum PackageManager: String, Sendable {
    case swiftPM, cocoapods, carthage
    case npm, yarn, pnpm, bun
    case pip, poetry, uv, pipenv
    case cargo
    case goMod
    case bundler
    case mix
    case maven, gradle

    public var displayName: String {
        switch self {
        case .swiftPM: return "SwiftPM"
        case .cocoapods: return "CocoaPods"
        case .carthage: return "Carthage"
        case .npm: return "npm"
        case .yarn: return "yarn"
        case .pnpm: return "pnpm"
        case .bun: return "bun"
        case .pip: return "pip"
        case .poetry: return "Poetry"
        case .uv: return "uv"
        case .pipenv: return "Pipenv"
        case .cargo: return "Cargo"
        case .goMod: return "Go Modules"
        case .bundler: return "Bundler"
        case .mix: return "Mix"
        case .maven: return "Maven"
        case .gradle: return "Gradle"
        }
    }
}

public struct ProjectDescriptor: Sendable {
    public let languages: [(Language, Float)]
    public let frameworks: [Framework]
    public let packageManager: PackageManager?
    public let testCommand: String?
    public let buildCommand: String?
    public let runCommand: String?
    public let formatCommand: String?
    public let lintCommand: String?

    public var primaryLanguage: Language? { languages.first?.0 }
}

public struct ProjectDetector: Sendable {
    public init() {}

    public func detect(at root: URL, files: [FileSnapshot]) -> ProjectDescriptor {
        let languages = detectLanguages(files: files)
        let frameworks = detectFrameworks(root: root)
        let packageManager = detectPackageManager(root: root)
        let testCmd = detectTestCommand(root: root, frameworks: frameworks)
        let buildCmd = detectBuildCommand(root: root, frameworks: frameworks)

        return ProjectDescriptor(
            languages: languages,
            frameworks: frameworks,
            packageManager: packageManager,
            testCommand: testCmd,
            buildCommand: buildCmd,
            runCommand: nil,
            formatCommand: nil,
            lintCommand: nil
        )
    }

    private func detectLanguages(files: [FileSnapshot]) -> [(Language, Float)] {
        var counts: [Language: (count: Int, size: UInt64)] = [:]
        for file in files where !file.isDirectory {
            let ext = (file.relativePath as NSString).pathExtension
            guard let lang = Language.from(extension: ext) else { continue }
            let existing = counts[lang] ?? (0, 0)
            counts[lang] = (existing.count + 1, existing.size + file.size)
        }

        let total = counts.values.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }

        return counts.map { (lang, data) in
            let weight = Float(data.count) / Float(total) * 0.7 + Float(data.size) / Float(max(1, counts.values.reduce(0) { $0 + $1.size })) * 0.3
            return (lang, weight)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(5)
        .map { ($0.0, $0.1) }
    }

    private func detectFrameworks(root: URL) -> [Framework] {
        let fm = FileManager.default
        var result: [Framework] = []

        if fm.fileExists(atPath: root.appendingPathComponent("Package.swift").path) { result.append(.swiftPM) }
        if fm.fileExists(atPath: root.appendingPathComponent("Cargo.toml").path) { result.append(.cargo) }
        if fm.fileExists(atPath: root.appendingPathComponent("go.mod").path) { result.append(.goMod) }
        if fm.fileExists(atPath: root.appendingPathComponent("Gemfile").path) { result.append(.rails) }
        if fm.fileExists(atPath: root.appendingPathComponent("mix.exs").path) { result.append(.phoenix) }

        if fm.fileExists(atPath: root.appendingPathComponent("package.json").path) {
            result.append(.node)
            if let data = try? Data(contentsOf: root.appendingPathComponent("package.json")),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let deps = json["dependencies"] as? [String: Any] {
                if deps["react"] != nil { result.append(.react) }
                if deps["next"] != nil { result.append(.nextjs) }
                if deps["vue"] != nil { result.append(.vue) }
                if deps["@angular/core"] != nil { result.append(.angular) }
                if deps["express"] != nil { result.append(.express) }
            }
        }

        if fm.fileExists(atPath: root.appendingPathComponent("pyproject.toml").path) ||
           fm.fileExists(atPath: root.appendingPathComponent("requirements.txt").path) {
            if fm.fileExists(atPath: root.appendingPathComponent("manage.py").path) { result.append(.django) }
        }

        let xcodeprojs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?.filter {
            $0.pathExtension == "xcodeproj" || $0.pathExtension == "xcworkspace"
        }
        if let xc = xcodeprojs, !xc.isEmpty { result.append(.xcode) }

        if fm.fileExists(atPath: root.appendingPathComponent("Tuist").path) ||
           fm.fileExists(atPath: root.appendingPathComponent("Project.swift").path) { result.append(.tuist) }

        if fm.fileExists(atPath: root.appendingPathComponent("build.gradle").path) ||
           fm.fileExists(atPath: root.appendingPathComponent("build.gradle.kts").path) { result.append(.springBoot) }

        return result
    }

    private func detectPackageManager(root: URL) -> PackageManager? {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("Package.swift").path) { return .swiftPM }
        if fm.fileExists(atPath: root.appendingPathComponent("Cargo.toml").path) { return .cargo }
        if fm.fileExists(atPath: root.appendingPathComponent("go.mod").path) { return .goMod }
        if fm.fileExists(atPath: root.appendingPathComponent("Gemfile").path) { return .bundler }
        if fm.fileExists(atPath: root.appendingPathComponent("mix.exs").path) { return .mix }
        if fm.fileExists(atPath: root.appendingPathComponent("Podfile").path) { return .cocoapods }
        if fm.fileExists(atPath: root.appendingPathComponent("Cartfile").path) { return .carthage }

        if fm.fileExists(atPath: root.appendingPathComponent("bun.lockb").path) ||
           fm.fileExists(atPath: root.appendingPathComponent("bun.lock").path) { return .bun }
        if fm.fileExists(atPath: root.appendingPathComponent("pnpm-lock.yaml").path) { return .pnpm }
        if fm.fileExists(atPath: root.appendingPathComponent("yarn.lock").path) { return .yarn }
        if fm.fileExists(atPath: root.appendingPathComponent("package-lock.json").path) { return .npm }
        if fm.fileExists(atPath: root.appendingPathComponent("package.json").path) { return .npm }

        if fm.fileExists(atPath: root.appendingPathComponent("uv.lock").path) { return .uv }
        if fm.fileExists(atPath: root.appendingPathComponent("poetry.lock").path) { return .poetry }
        if fm.fileExists(atPath: root.appendingPathComponent("Pipfile").path) { return .pipenv }
        if fm.fileExists(atPath: root.appendingPathComponent("pyproject.toml").path) { return .pip }
        if fm.fileExists(atPath: root.appendingPathComponent("requirements.txt").path) { return .pip }

        if fm.fileExists(atPath: root.appendingPathComponent("build.gradle.kts").path) { return .gradle }
        if fm.fileExists(atPath: root.appendingPathComponent("build.gradle").path) { return .gradle }
        if fm.fileExists(atPath: root.appendingPathComponent("pom.xml").path) { return .maven }

        return nil
    }

    private func detectTestCommand(root: URL, frameworks: [Framework]) -> String? {
        if frameworks.contains(.swiftPM) { return "swift test" }
        if frameworks.contains(.cargo) { return "cargo test" }
        if frameworks.contains(.goMod) { return "go test ./..." }
        if frameworks.contains(.rails) { return "bundle exec rspec" }
        if frameworks.contains(.phoenix) { return "mix test" }
        if frameworks.contains(.django) { return "python manage.py test" }

        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("package.json").path) {
            if let data = try? Data(contentsOf: root.appendingPathComponent("package.json")),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let scripts = json["scripts"] as? [String: Any],
               scripts["test"] != nil {
                return "npm test"
            }
        }

        if fm.fileExists(atPath: root.appendingPathComponent("pytest.ini").path) ||
           fm.fileExists(atPath: root.appendingPathComponent("setup.cfg").path) {
            return "pytest"
        }

        if frameworks.contains(.springBoot) { return "./gradlew test" }
        if frameworks.contains(.xcode) { return "xcodebuild test" }

        return nil
    }

    private func detectBuildCommand(root: URL, frameworks: [Framework]) -> String? {
        if frameworks.contains(.swiftPM) { return "swift build" }
        if frameworks.contains(.cargo) { return "cargo build" }
        if frameworks.contains(.goMod) { return "go build ./..." }
        if frameworks.contains(.node) { return "npm run build" }
        if frameworks.contains(.springBoot) { return "./gradlew build" }
        if frameworks.contains(.xcode) { return "xcodebuild" }
        return nil
    }
}

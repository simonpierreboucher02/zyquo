import Foundation
import Yams

// MARK: - LoadedSkill

/// A skill that has been loaded from disk, including its parsed manifest
/// and the contents of its prompt file.
public struct LoadedSkill: Sendable {
    /// The parsed skill manifest from `skill.yaml`.
    public let manifest: SkillManifest
    /// The contents of the prompt markdown file.
    public let prompt: String
    /// The directory from which this skill was loaded.
    public let sourcePath: URL

    public init(manifest: SkillManifest, prompt: String, sourcePath: URL) {
        self.manifest = manifest
        self.prompt = prompt
        self.sourcePath = sourcePath
    }
}

// MARK: - SkillLoadError

/// Errors that can occur when loading a skill.
public enum SkillLoadError: Error, CustomStringConvertible, Sendable {
    case manifestNotFound(URL)
    case manifestParseError(String)
    case promptNotFound(URL)
    case promptReadError(String)

    public var description: String {
        switch self {
        case .manifestNotFound(let url):
            return "Skill manifest not found at \(url.path)"
        case .manifestParseError(let detail):
            return "Failed to parse skill manifest: \(detail)"
        case .promptNotFound(let url):
            return "Skill prompt file not found at \(url.path)"
        case .promptReadError(let detail):
            return "Failed to read skill prompt: \(detail)"
        }
    }
}

// MARK: - SkillLoader

/// Loads skills from directories containing `skill.yaml` + `prompt.md`.
///
/// Skills are discovered from two search paths:
/// - Project-local: `.zyquo/skills/` in the workspace root
/// - Global: `~/.zyquo/skills/` in the user's home directory
///
/// Each skill lives in its own subdirectory. The loader reads the YAML
/// manifest, parses it into a `SkillManifest`, and loads the prompt
/// markdown file referenced by the manifest.
///
/// Reference: CLAUDE.md §30 Phase 6
public struct SkillLoader: Sendable {
    public init() {}

    // MARK: - Load Single Skill

    /// Load a skill from the given directory.
    ///
    /// The directory must contain a `skill.yaml` file and a prompt file
    /// (typically `prompt.md`) referenced by the manifest.
    ///
    /// - Parameter directory: The skill directory (e.g. `~/.zyquo/skills/fix_swift_build/`)
    /// - Returns: A `LoadedSkill` with the parsed manifest and prompt contents.
    /// - Throws: `SkillLoadError` if manifest or prompt cannot be loaded.
    public func loadSkill(at directory: URL) throws -> LoadedSkill {
        let manifestURL = directory.appendingPathComponent("skill.yaml")

        // 1. Check manifest exists
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw SkillLoadError.manifestNotFound(manifestURL)
        }

        // 2. Read and parse YAML
        let yamlString: String
        do {
            yamlString = try String(contentsOf: manifestURL, encoding: .utf8)
        } catch {
            throw SkillLoadError.manifestParseError(error.localizedDescription)
        }

        let manifest: SkillManifest
        do {
            let decoder = YAMLDecoder()
            manifest = try decoder.decode(SkillManifest.self, from: yamlString)
        } catch {
            throw SkillLoadError.manifestParseError(error.localizedDescription)
        }

        // 3. Resolve and read prompt file
        let promptPath: String
        if manifest.promptFile.hasPrefix("./") {
            promptPath = String(manifest.promptFile.dropFirst(2))
        } else {
            promptPath = manifest.promptFile
        }
        let promptURL = directory.appendingPathComponent(promptPath)

        guard FileManager.default.fileExists(atPath: promptURL.path) else {
            throw SkillLoadError.promptNotFound(promptURL)
        }

        let promptContent: String
        do {
            promptContent = try String(contentsOf: promptURL, encoding: .utf8)
        } catch {
            throw SkillLoadError.promptReadError(error.localizedDescription)
        }

        return LoadedSkill(
            manifest: manifest,
            prompt: promptContent,
            sourcePath: directory
        )
    }

    // MARK: - Discover Skills

    /// Discover all valid skills in the given search paths.
    ///
    /// Each search path is scanned for subdirectories containing a
    /// `skill.yaml` file. Skills that fail to load are silently skipped.
    /// If the same skill ID appears in multiple search paths, the first
    /// occurrence wins (project-local takes precedence over global when
    /// the search paths are ordered accordingly).
    ///
    /// - Parameter searchPaths: Directories to search for skill subdirectories.
    /// - Returns: Array of successfully loaded skills, deduplicated by ID.
    public func discoverSkills(searchPaths: [URL]) -> [LoadedSkill] {
        var seenIds = Set<String>()
        var result: [LoadedSkill] = []

        for searchPath in searchPaths {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: searchPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                // Only consider directories
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir),
                      isDir.boolValue else {
                    continue
                }

                // Try to load the skill
                guard let skill = try? loadSkill(at: entry) else {
                    continue
                }

                // Deduplicate by ID (first occurrence wins)
                if !seenIds.contains(skill.manifest.id) {
                    seenIds.insert(skill.manifest.id)
                    result.append(skill)
                }
            }
        }

        return result
    }

    // MARK: - Default Search Paths

    /// Returns the default skill search paths:
    /// 1. Project-local: `<workspaceRoot>/.zyquo/skills/`
    /// 2. Global: `~/.zyquo/skills/`
    public static func defaultSearchPaths(workspaceRoot: URL) -> [URL] {
        let projectSkills = workspaceRoot
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("skills")
        let globalSkills = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("skills")

        return [projectSkills, globalSkills]
    }
}

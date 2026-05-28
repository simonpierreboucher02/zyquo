import Foundation

// MARK: - CodeDependencyGraph

/// A graph of module-level dependencies extracted from import symbols.
///
/// Distinct from `Agent/DependencyGraph.swift` which models task execution
/// dependencies. This graph models *code* dependencies: which files import
/// which modules, and how modules relate to each other.
///
/// Reference: CLAUDE.md V2 Phase 2 - Semantic Repository Intelligence
public struct CodeDependencyGraph: Sendable, Equatable {
    /// The modules (nodes) in the dependency graph.
    public var modules: [ModuleNode]
    /// The dependency edges between modules.
    public var edges: [DependencyEdge]

    public init(modules: [ModuleNode] = [], edges: [DependencyEdge] = []) {
        self.modules = modules
        self.edges = edges
    }

    /// Build a dependency graph from extracted symbols and file snapshots.
    ///
    /// Strategy:
    /// 1. Each unique file path becomes a module node.
    /// 2. Each `import` symbol creates an edge from the importing file's module
    ///    to the imported module name.
    /// 3. Modules are deduplicated by their identifier.
    ///
    /// - Parameters:
    ///   - symbols: All symbols extracted from the workspace.
    ///   - files: The file snapshots for metadata (language detection).
    /// - Returns: A populated `CodeDependencyGraph`.
    public static func build(
        from symbols: [Symbol],
        files: [FileSnapshot]
    ) -> CodeDependencyGraph {
        // Build a map of file path -> language for quick lookup
        var fileLanguages: [String: Language] = [:]
        for file in files {
            let ext = (file.relativePath as NSString).pathExtension
            if let lang = Language.from(extension: ext) {
                fileLanguages[file.path] = lang
            }
        }

        // Group symbols by file
        var symbolsByFile: [String: [Symbol]] = [:]
        for symbol in symbols {
            symbolsByFile[symbol.filePath, default: []].append(symbol)
        }

        // Create module nodes (one per file that has symbols)
        var moduleMap: [String: ModuleNode] = [:]
        for (filePath, fileSymbols) in symbolsByFile {
            let moduleId = moduleId(for: filePath)
            if moduleMap[moduleId] == nil {
                let language = fileLanguages[filePath] ?? .swift
                moduleMap[moduleId] = ModuleNode(
                    id: moduleId,
                    path: filePath,
                    language: language,
                    symbolCount: fileSymbols.count
                )
            } else if let existing = moduleMap[moduleId] {
                moduleMap[moduleId] = ModuleNode(
                    id: existing.id,
                    path: existing.path,
                    language: existing.language,
                    symbolCount: existing.symbolCount + fileSymbols.count
                )
            }
        }

        // Create edges from import symbols
        var edgeSet: Set<DependencyEdge> = []
        for (filePath, fileSymbols) in symbolsByFile {
            let fromId = moduleId(for: filePath)
            for symbol in fileSymbols where symbol.kind == .import {
                let toId = symbol.name
                // Avoid self-edges
                if toId != fromId {
                    let edge = DependencyEdge(
                        from: fromId,
                        to: toId,
                        kind: .import
                    )
                    edgeSet.insert(edge)

                    // Ensure the imported module has a node even if we didn't index it
                    if moduleMap[toId] == nil {
                        moduleMap[toId] = ModuleNode(
                            id: toId,
                            path: "",
                            language: .swift,
                            symbolCount: 0
                        )
                    }
                }
            }
        }

        return CodeDependencyGraph(
            modules: Array(moduleMap.values).sorted { $0.id < $1.id },
            edges: Array(edgeSet).sorted { "\($0.from)->\($0.to)" < "\($1.from)->\($1.to)" }
        )
    }

    /// The number of modules in the graph.
    public var moduleCount: Int { modules.count }

    /// The number of edges in the graph.
    public var edgeCount: Int { edges.count }

    /// Find all modules that a given module imports.
    ///
    /// - Parameter moduleId: The module identifier.
    /// - Returns: The IDs of modules imported by the given module.
    public func imports(of moduleId: String) -> [String] {
        edges.filter { $0.from == moduleId }.map(\.to)
    }

    /// Find all modules that import a given module.
    ///
    /// - Parameter moduleId: The module identifier.
    /// - Returns: The IDs of modules that import the given module.
    public func importedBy(_ moduleId: String) -> [String] {
        edges.filter { $0.to == moduleId }.map(\.from)
    }

    // MARK: - Helpers

    /// Derive a module identifier from a file path.
    ///
    /// Uses the file name without extension as the module ID.
    /// This is a heuristic; in a real build system, the module name
    /// comes from the build configuration.
    private static func moduleId(for filePath: String) -> String {
        let url = URL(fileURLWithPath: filePath)
        return url.deletingPathExtension().lastPathComponent
    }
}

// MARK: - ModuleNode

/// A node in the code dependency graph representing a source module.
public struct ModuleNode: Sendable, Identifiable, Equatable, Hashable {
    /// Unique identifier for this module (typically the file name without extension).
    public let id: String
    /// The file path of the primary source file for this module.
    public let path: String
    /// The programming language of this module.
    public let language: Language
    /// The number of symbols defined in this module.
    public let symbolCount: Int

    public init(id: String, path: String, language: Language, symbolCount: Int) {
        self.id = id
        self.path = path
        self.language = language
        self.symbolCount = symbolCount
    }
}

// MARK: - DependencyEdge

/// An edge in the code dependency graph.
public struct DependencyEdge: Sendable, Equatable, Hashable {
    /// The source module (the one that imports/uses).
    public let from: String
    /// The target module (the one being imported/used).
    public let to: String
    /// The kind of dependency relationship.
    public let kind: DependencyKind

    public init(from: String, to: String, kind: DependencyKind) {
        self.from = from
        self.to = to
        self.kind = kind
    }
}

/// The kind of a code dependency relationship.
public enum DependencyKind: String, Sendable, Codable, Hashable {
    /// An import/use/require statement.
    case `import`
    /// A function call across modules.
    case call
    /// An inheritance or protocol conformance relationship.
    case inherit
}

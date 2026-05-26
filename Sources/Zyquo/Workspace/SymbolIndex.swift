import Foundation

// MARK: - SymbolReference

/// A reference to a symbol found by scanning source code for usage patterns.
public struct SymbolReference: Sendable, Equatable {
    /// The name of the symbol being referenced.
    public let symbol: String
    /// The file where the reference was found.
    public let filePath: String
    /// The line number (1-based) of the reference.
    public let line: Int
    /// The source line containing the reference.
    public let context: String

    public init(symbol: String, filePath: String, line: Int, context: String) {
        self.symbol = symbol
        self.filePath = filePath
        self.line = line
        self.context = context
    }
}

// MARK: - SymbolIndex

/// An in-memory index of code symbols extracted from a workspace.
///
/// Provides fast lookup by name, kind, fuzzy query, and file path.
/// Also supports basic reference finding by scanning indexed file contents
/// for symbol name occurrences.
///
/// Thread-safe via actor isolation.
///
/// Reference: CLAUDE.md V2 Phase 2 - Semantic Repository Intelligence
public actor SymbolIndex {

    /// All symbols indexed, keyed by file path.
    private var symbolsByFile: [String: [Symbol]] = [:]

    /// All symbols indexed, for fast name lookup.
    private var symbolsByName: [String: [Symbol]] = [:]

    /// Source content cache for reference finding.
    private var sourceCache: [String: String] = [:]

    /// The registry used to obtain extractors per language.
    private let extractorRegistry: SymbolExtractorRegistry

    public init(extractorRegistry: SymbolExtractorRegistry = .shared) {
        self.extractorRegistry = extractorRegistry
    }

    // MARK: - Indexing

    /// Index a single file, extracting symbols and caching source.
    ///
    /// - Parameters:
    ///   - file: The file URL to read and index.
    ///   - language: The programming language of the file.
    public func index(file: URL, language: Language) async {
        guard let extractor = extractorRegistry.extractor(for: language) else { return }
        guard let source = try? String(contentsOf: file, encoding: .utf8) else { return }

        let filePath = file.path
        let symbols = extractor.extractSymbols(from: source, filePath: filePath)

        // Remove old symbols for this file
        removeFile(filePath)

        // Store new symbols
        symbolsByFile[filePath] = symbols
        sourceCache[filePath] = source

        for symbol in symbols {
            symbolsByName[symbol.name, default: []].append(symbol)
        }
    }

    /// Index a file from source text directly (useful for testing).
    ///
    /// - Parameters:
    ///   - source: The source code text.
    ///   - filePath: The logical file path.
    ///   - language: The programming language.
    public func indexSource(_ source: String, filePath: String, language: Language) {
        guard let extractor = extractorRegistry.extractor(for: language) else { return }

        let symbols = extractor.extractSymbols(from: source, filePath: filePath)

        removeFile(filePath)

        symbolsByFile[filePath] = symbols
        sourceCache[filePath] = source

        for symbol in symbols {
            symbolsByName[symbol.name, default: []].append(symbol)
        }
    }

    /// Index all matching files under a root directory.
    ///
    /// Iterates `files`, determines the language from each file's extension,
    /// and indexes files for which an extractor is available.
    ///
    /// - Parameters:
    ///   - root: The workspace root (used to construct full URLs).
    ///   - files: The file snapshots to consider.
    public func indexAll(root: URL, files: [FileSnapshot]) async {
        for file in files where !file.isDirectory {
            let ext = (file.relativePath as NSString).pathExtension
            guard let language = Language.from(extension: ext) else { continue }
            guard extractorRegistry.extractor(for: language) != nil else { continue }

            let fileURL = URL(fileURLWithPath: file.path)
            await index(file: fileURL, language: language)
        }
    }

    // MARK: - Queries

    /// Return all symbols indexed in a specific file.
    ///
    /// - Parameter path: The absolute file path.
    /// - Returns: The symbols found in that file, or empty if not indexed.
    public func symbols(inFile path: String) -> [Symbol] {
        symbolsByFile[path] ?? []
    }

    /// Find symbols by exact name, optionally filtering by kind.
    ///
    /// - Parameters:
    ///   - name: The symbol name to search for (exact match).
    ///   - kind: Optional kind filter.
    /// - Returns: Matching symbols.
    public func find(name: String, kind: SymbolKind? = nil) -> [Symbol] {
        guard let candidates = symbolsByName[name] else { return [] }
        if let kind {
            return candidates.filter { $0.kind == kind }
        }
        return candidates
    }

    /// Fuzzy-search symbols by query string.
    ///
    /// Matches symbol names that contain the query as a substring (case-insensitive).
    /// Results are ranked: exact match first, then prefix match, then substring.
    ///
    /// - Parameter query: The search query.
    /// - Returns: Matching symbols, ranked by relevance.
    public func find(query: String) -> [Symbol] {
        let lowerQuery = query.lowercased()
        var exactMatches: [Symbol] = []
        var prefixMatches: [Symbol] = []
        var containsMatches: [Symbol] = []

        for (name, symbols) in symbolsByName {
            let lowerName = name.lowercased()
            if lowerName == lowerQuery {
                exactMatches.append(contentsOf: symbols)
            } else if lowerName.hasPrefix(lowerQuery) {
                prefixMatches.append(contentsOf: symbols)
            } else if lowerName.contains(lowerQuery) {
                containsMatches.append(contentsOf: symbols)
            }
        }

        return exactMatches + prefixMatches + containsMatches
    }

    /// Find references to a symbol name across all indexed files.
    ///
    /// Scans the cached source content for lines containing the symbol name
    /// as a whole word (bounded by non-word characters). Excludes the symbol's
    /// own definition lines.
    ///
    /// - Parameter symbolName: The name to search for.
    /// - Returns: References found across all indexed files.
    public func references(to symbolName: String) -> [SymbolReference] {
        var refs: [SymbolReference] = []

        // Gather definition locations to exclude
        let definitionLocations = Set(
            (symbolsByName[symbolName] ?? []).map { "\($0.filePath):\($0.line)" }
        )

        for (filePath, source) in sourceCache {
            let lines = source.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let lineNumber = index + 1
                let locationKey = "\(filePath):\(lineNumber)"

                // Skip definition lines
                if definitionLocations.contains(locationKey) { continue }

                // Check for whole-word match
                if containsWholeWord(line, word: symbolName) {
                    refs.append(SymbolReference(
                        symbol: symbolName,
                        filePath: filePath,
                        line: lineNumber,
                        context: line.trimmingCharacters(in: .whitespaces)
                    ))
                }
            }
        }

        return refs
    }

    /// Remove all indexed data for a file.
    ///
    /// - Parameter filePath: The file to remove from the index.
    public func removeFile(_ filePath: String) {
        if let oldSymbols = symbolsByFile[filePath] {
            for symbol in oldSymbols {
                symbolsByName[symbol.name]?.removeAll { $0.filePath == filePath && $0.line == symbol.line }
                if symbolsByName[symbol.name]?.isEmpty == true {
                    symbolsByName.removeValue(forKey: symbol.name)
                }
            }
        }
        symbolsByFile.removeValue(forKey: filePath)
        sourceCache.removeValue(forKey: filePath)
    }

    /// Remove all symbols and cached source from the index.
    public func clear() {
        symbolsByFile.removeAll()
        symbolsByName.removeAll()
        sourceCache.removeAll()
    }

    /// The total number of symbols in the index across all files.
    public var totalSymbols: Int {
        symbolsByFile.values.reduce(0) { $0 + $1.count }
    }

    /// The number of files currently indexed.
    public var indexedFileCount: Int {
        symbolsByFile.count
    }

    /// All unique symbol names in the index.
    public var allSymbolNames: [String] {
        Array(symbolsByName.keys).sorted()
    }

    // MARK: - Helpers

    /// Check if a line contains a word as a whole-word match.
    private func containsWholeWord(_ line: String, word: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
            options: []
        ) else {
            return line.contains(word)
        }
        let range = NSRange(line.startIndex..., in: line)
        return regex.firstMatch(in: line, options: [], range: range) != nil
    }
}

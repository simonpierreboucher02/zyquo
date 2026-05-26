import Foundation

// MARK: - CodeChunk

/// A semantic chunk of source code.
///
/// Chunks are self-contained pieces of code at function, class, or module boundaries.
/// They are suitable for context injection into LLM prompts and for semantic search.
///
/// Reference: CLAUDE.md V2 Phase 2 - Semantic Repository Intelligence
public struct CodeChunk: Sendable, Codable, Equatable {
    /// The file this chunk belongs to.
    public let filePath: String
    /// The start line (1-based) of the chunk in the original file.
    public let startLine: Int
    /// The end line (1-based, inclusive) of the chunk.
    public let endLine: Int
    /// The structural kind of this chunk.
    public let kind: ChunkKind
    /// The name of the symbol this chunk represents (e.g. function or class name).
    public let name: String?
    /// The source text of the chunk.
    public let content: String
    /// Estimated token count (approximately 4 characters per token).
    public let tokenEstimate: Int

    public init(
        filePath: String,
        startLine: Int,
        endLine: Int,
        kind: ChunkKind,
        name: String?,
        content: String,
        tokenEstimate: Int
    ) {
        self.filePath = filePath
        self.startLine = startLine
        self.endLine = endLine
        self.kind = kind
        self.name = name
        self.content = content
        self.tokenEstimate = tokenEstimate
    }
}

/// The structural kind of a code chunk.
public enum ChunkKind: String, Sendable, Codable, CaseIterable {
    /// A function or method chunk.
    case function
    /// A class, struct, enum, protocol, or similar type declaration.
    case class_
    /// A module-level chunk (package, module declaration).
    case module
    /// Top-level code not inside a named scope.
    case topLevel
    /// A generic block (fallback for line-based chunking).
    case block
}

// MARK: - SemanticChunker

/// Splits source code into semantic chunks at function and class boundaries.
///
/// For supported languages, uses the SymbolExtractor to identify declaration
/// boundaries and produces one chunk per top-level symbol (function, class, etc.).
/// Top-level code between declarations is grouped into `topLevel` chunks.
///
/// For unsupported languages, falls back to fixed-size line-based chunking
/// (100 lines per chunk).
///
/// Token estimates use the ~4 characters per token heuristic.
public struct SemanticChunker: Sendable {
    /// The default number of lines per chunk for unknown languages.
    public static let fallbackChunkSize = 100

    /// The characters-per-token ratio for estimation.
    private static let charsPerToken: Double = 4.0

    public init() {}

    /// Chunk source code into semantic pieces.
    ///
    /// - Parameters:
    ///   - source: The full source text.
    ///   - language: The programming language of the source.
    ///   - filePath: The file path (stored on each chunk for reference).
    /// - Returns: An array of code chunks covering the entire source.
    public func chunk(source: String, language: Language, filePath: String) -> [CodeChunk] {
        let registry = SymbolExtractorRegistry.shared
        guard let extractor = registry.extractor(for: language) else {
            return fallbackChunk(source: source, filePath: filePath)
        }

        let symbols = extractor.extractSymbols(from: source, filePath: filePath)
        if symbols.isEmpty {
            return fallbackChunk(source: source, filePath: filePath)
        }

        return semanticChunk(source: source, symbols: symbols, filePath: filePath)
    }

    // MARK: - Semantic Chunking

    /// Produce chunks based on symbol declaration boundaries.
    ///
    /// Strategy:
    /// 1. Identify "boundary" symbols -- top-level declarations that define chunk starts.
    /// 2. Each boundary symbol owns the lines from its declaration to the line before the
    ///    next boundary (or EOF).
    /// 3. Lines before the first boundary become a `topLevel` chunk (e.g. imports).
    private func semanticChunk(
        source: String,
        symbols: [Symbol],
        filePath: String
    ) -> [CodeChunk] {
        let lines = source.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return [] }

        // Identify boundary symbols: top-level declarations that start chunks.
        // These are symbols without a scope (top-level) that are structural
        // (classes, functions, structs, enums, protocols, extensions, modules).
        let boundaryKinds: Set<SymbolKind> = [
            .function, .class, .struct, .enum, .protocol, .interface,
            .extension, .module,
        ]

        let boundaries = symbols
            .filter { $0.scope == nil && boundaryKinds.contains($0.kind) }
            .sorted { $0.line < $1.line }

        if boundaries.isEmpty {
            // No structural boundaries -- everything is top-level
            return [makeChunk(
                lines: lines, startLine: 1, endLine: lines.count,
                kind: .topLevel, name: nil, filePath: filePath
            )]
        }

        var chunks: [CodeChunk] = []

        // Top-level code before the first boundary
        if boundaries[0].line > 1 {
            chunks.append(makeChunk(
                lines: lines, startLine: 1, endLine: boundaries[0].line - 1,
                kind: .topLevel, name: nil, filePath: filePath
            ))
        }

        // Each boundary symbol gets a chunk from its line to the line before the next boundary
        for (i, boundary) in boundaries.enumerated() {
            let startLine = boundary.line
            let endLine: Int
            if i + 1 < boundaries.count {
                endLine = boundaries[i + 1].line - 1
            } else {
                endLine = lines.count
            }

            let kind = chunkKind(from: boundary.kind)
            chunks.append(makeChunk(
                lines: lines, startLine: startLine, endLine: endLine,
                kind: kind, name: boundary.name, filePath: filePath
            ))
        }

        return chunks
    }

    // MARK: - Fallback Chunking

    /// Split source into fixed-size line-based chunks for unknown languages.
    private func fallbackChunk(source: String, filePath: String) -> [CodeChunk] {
        let lines = source.components(separatedBy: .newlines)
        guard !lines.isEmpty else {
            return [CodeChunk(
                filePath: filePath, startLine: 1, endLine: 1,
                kind: .topLevel, name: nil, content: "",
                tokenEstimate: 0
            )]
        }

        var chunks: [CodeChunk] = []
        var startLine = 1

        while startLine <= lines.count {
            let endLine = min(startLine + Self.fallbackChunkSize - 1, lines.count)
            chunks.append(makeChunk(
                lines: lines, startLine: startLine, endLine: endLine,
                kind: .block, name: nil, filePath: filePath
            ))
            startLine = endLine + 1
        }

        return chunks
    }

    // MARK: - Helpers

    /// Build a chunk from a line range.
    private func makeChunk(
        lines: [String],
        startLine: Int,
        endLine: Int,
        kind: ChunkKind,
        name: String?,
        filePath: String
    ) -> CodeChunk {
        let clampedStart = max(1, startLine)
        let clampedEnd = min(lines.count, endLine)
        let content = lines[(clampedStart - 1)...(clampedEnd - 1)].joined(separator: "\n")
        let tokenEstimate = max(1, Int(Double(content.count) / Self.charsPerToken))

        return CodeChunk(
            filePath: filePath,
            startLine: clampedStart,
            endLine: clampedEnd,
            kind: kind,
            name: name,
            content: content,
            tokenEstimate: tokenEstimate
        )
    }

    /// Map a SymbolKind to a ChunkKind.
    private func chunkKind(from symbolKind: SymbolKind) -> ChunkKind {
        switch symbolKind {
        case .function, .method:
            return .function
        case .class, .struct, .enum, .protocol, .interface, .extension:
            return .class_
        case .module:
            return .module
        default:
            return .topLevel
        }
    }
}

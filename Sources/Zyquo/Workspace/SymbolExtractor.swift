import Foundation

// MARK: - Symbol Types

/// A code symbol extracted from source via regex-based analysis.
///
/// Symbols represent named entities in source code: functions, classes, structs,
/// protocols, variables, imports, etc. Each symbol carries its location (file, line,
/// column), optional scope (parent symbol), and the full signature line.
///
/// Reference: CLAUDE.md V2 Phase 2 - Semantic Repository Intelligence
public struct Symbol: Sendable, Codable, Equatable, Hashable {
    public let name: String
    public let kind: SymbolKind
    public let filePath: String
    public let line: Int
    public let column: Int
    public let scope: String?
    public let signature: String?

    public init(
        name: String,
        kind: SymbolKind,
        filePath: String,
        line: Int,
        column: Int,
        scope: String? = nil,
        signature: String? = nil
    ) {
        self.name = name
        self.kind = kind
        self.filePath = filePath
        self.line = line
        self.column = column
        self.scope = scope
        self.signature = signature
    }
}

/// The kind of a code symbol.
public enum SymbolKind: String, Sendable, Codable, CaseIterable, Hashable {
    case function
    case method
    case property
    case variable
    case constant
    case `class`
    case `struct`
    case `enum`
    case `protocol`
    case `interface`
    case `extension`
    case module
    case typeAlias
    case `import`
}

// MARK: - SymbolExtractor Protocol

/// Extracts code symbols from source text using regex-based analysis.
///
/// Each language has its own extractor implementation that understands the
/// language's declaration syntax. Extractors process source line-by-line
/// and do not perform full parsing -- they are fast and approximate.
///
/// Tree-sitter can be swapped in behind this protocol in the future.
public protocol SymbolExtractor: Sendable {
    var language: Language { get }
    func extractSymbols(from source: String, filePath: String) -> [Symbol]
}

// MARK: - Extractor Registry

/// Provides the appropriate SymbolExtractor for a given Language.
public struct SymbolExtractorRegistry: Sendable {
    public static let shared = SymbolExtractorRegistry()

    private init() {}

    public func extractor(for language: Language) -> (any SymbolExtractor)? {
        switch language {
        case .swift: return SwiftSymbolExtractor()
        case .typescript, .javascript: return TypeScriptSymbolExtractor()
        case .python: return PythonSymbolExtractor()
        case .rust: return RustSymbolExtractor()
        case .go: return GoSymbolExtractor()
        case .ruby: return RubySymbolExtractor()
        default: return nil
        }
    }
}

// MARK: - Base Helpers

/// Shared regex matching helpers used by all extractors.
private enum ExtractorHelpers {
    /// Extract the first capture group from a regex match on a line.
    static func firstMatch(
        in line: String,
        pattern: String
    ) -> (name: String, range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let nsRange = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: nsRange) else {
            return nil
        }
        guard match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return (String(line[captureRange]), captureRange)
    }

    /// Find the column (1-based) where a substring starts in a line.
    static func column(of substring: String, in line: String) -> Int {
        guard let range = line.range(of: substring) else { return 1 }
        return line.distance(from: line.startIndex, to: range.lowerBound) + 1
    }
}

// MARK: - Swift Extractor

/// Regex-based symbol extractor for Swift source code.
///
/// Detects: func, class, struct, enum, protocol, extension, var, let, import, typealias.
public struct SwiftSymbolExtractor: SymbolExtractor, Sendable {
    public let language: Language = .swift

    public func extractSymbols(from source: String, filePath: String) -> [Symbol] {
        var symbols: [Symbol] = []
        let lines = source.components(separatedBy: .newlines)
        var scopeStack: [String] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineNumber = index + 1

            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                continue
            }

            // Track scope via braces (simple heuristic)
            let scope = scopeStack.last

            // import
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^import\s+(\w[\w.]*)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .import, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // typealias
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?typealias\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .typeAlias, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // protocol
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?protocol\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .protocol, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                scopeStack.append(m.name)
                continue
            }

            // class
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(?:final\s+)?class\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .class, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                scopeStack.append(m.name)
                continue
            }

            // struct
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?struct\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .struct, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                scopeStack.append(m.name)
                continue
            }

            // enum
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?enum\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .enum, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                scopeStack.append(m.name)
                continue
            }

            // extension
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:public\s+|private\s+|internal\s+|fileprivate\s+)?extension\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .extension, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                scopeStack.append(m.name)
                continue
            }

            // func (free or method)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(?:static\s+|class\s+)?(?:override\s+)?(?:mutating\s+)?func\s+(\w+)"#) {
                let kind: SymbolKind = scope != nil ? .method : .function
                symbols.append(Symbol(
                    name: m.name, kind: kind, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // var (property or variable)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(?:static\s+)?(?:lazy\s+)?var\s+(\w+)"#) {
                let kind: SymbolKind = scope != nil ? .property : .variable
                symbols.append(Symbol(
                    name: m.name, kind: kind, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // let (constant)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(?:static\s+)?let\s+(\w+)"#) {
                let kind: SymbolKind = scope != nil ? .property : .constant
                symbols.append(Symbol(
                    name: m.name, kind: kind, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // Simple brace tracking for scope management
            if trimmed == "}" && !scopeStack.isEmpty {
                scopeStack.removeLast()
            }
        }

        return symbols
    }
}

// MARK: - TypeScript / JavaScript Extractor

/// Regex-based symbol extractor for TypeScript and JavaScript source code.
///
/// Detects: function, class, interface, const, let, var, export, import.
public struct TypeScriptSymbolExtractor: SymbolExtractor, Sendable {
    public let language: Language = .typescript

    public func extractSymbols(from source: String, filePath: String) -> [Symbol] {
        var symbols: [Symbol] = []
        let lines = source.components(separatedBy: .newlines)
        var scopeStack: [String] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineNumber = index + 1

            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                continue
            }

            let scope = scopeStack.last

            // import
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^import\s+.*?(?:from\s+)?['\"]([^'\"]+)['\"]"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .import, filePath: filePath,
                    line: lineNumber, column: 1,
                    scope: scope, signature: trimmed
                ))
                continue
            }
            // import { ... } (capture module name)
            if trimmed.hasPrefix("import ") && !trimmed.contains("from") {
                if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^import\s+(\w+)"#) {
                    symbols.append(Symbol(
                        name: m.name, kind: .import, filePath: filePath,
                        line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                        scope: scope, signature: trimmed
                    ))
                    continue
                }
            }

            // interface
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:export\s+)?interface\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .interface, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                scopeStack.append(m.name)
                continue
            }

            // class
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:export\s+)?(?:abstract\s+)?(?:default\s+)?class\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .class, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                scopeStack.append(m.name)
                continue
            }

            // function (declaration or exported)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:export\s+)?(?:async\s+)?(?:default\s+)?function\s+(\w+)"#) {
                let kind: SymbolKind = scope != nil ? .method : .function
                symbols.append(Symbol(
                    name: m.name, kind: kind, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // const (arrow function or value)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:export\s+)?const\s+(\w+)"#) {
                let kind: SymbolKind = trimmed.contains("=>") || trimmed.contains("function")
                    ? .function : .constant
                symbols.append(Symbol(
                    name: m.name, kind: kind, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // let
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:export\s+)?let\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .variable, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // var
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:export\s+)?var\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .variable, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // type alias
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:export\s+)?type\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .typeAlias, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            if trimmed == "}" && !scopeStack.isEmpty {
                scopeStack.removeLast()
            }
        }

        return symbols
    }
}

// MARK: - Python Extractor

/// Regex-based symbol extractor for Python source code.
///
/// Detects: def, class, import, from...import.
/// Uses indentation to track scope (Python has no braces).
public struct PythonSymbolExtractor: SymbolExtractor, Sendable {
    public let language: Language = .python

    public func extractSymbols(from source: String, filePath: String) -> [Symbol] {
        var symbols: [Symbol] = []
        let lines = source.components(separatedBy: .newlines)
        var classStack: [(name: String, indent: Int)] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineNumber = index + 1
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Pop scope stack based on indentation
            while let top = classStack.last, indent <= top.indent {
                classStack.removeLast()
            }

            let scope = classStack.last?.name

            // from ... import ...
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^from\s+([\w.]+)\s+import"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .import, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // import
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^import\s+([\w.]+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .import, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // class
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^class\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .class, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                classStack.append((m.name, indent))
                continue
            }

            // def (function or method depending on scope)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:async\s+)?def\s+(\w+)"#) {
                let kind: SymbolKind = scope != nil ? .method : .function
                symbols.append(Symbol(
                    name: m.name, kind: kind, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // Top-level variable assignment (simple heuristic: NAME = ...)
            if scope == nil, indent == 0,
               let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^([A-Z_][A-Z_0-9]*)\s*="#) {
                symbols.append(Symbol(
                    name: m.name, kind: .constant, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }
        }

        return symbols
    }
}

// MARK: - Rust Extractor

/// Regex-based symbol extractor for Rust source code.
///
/// Detects: fn, struct, enum, trait, impl, mod, use, const, let, type.
public struct RustSymbolExtractor: SymbolExtractor, Sendable {
    public let language: Language = .rust

    public func extractSymbols(from source: String, filePath: String) -> [Symbol] {
        var symbols: [Symbol] = []
        let lines = source.components(separatedBy: .newlines)
        var scopeStack: [String] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineNumber = index + 1

            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                continue
            }

            let scope = scopeStack.last

            // use (import)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:pub\s+)?use\s+([\w:]+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .import, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // mod
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:pub\s+)?mod\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .module, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                if trimmed.contains("{") {
                    scopeStack.append(m.name)
                }
                continue
            }

            // trait
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:pub\s+)?(?:unsafe\s+)?trait\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .protocol, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                scopeStack.append(m.name)
                continue
            }

            // struct
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:pub(?:\([\w]+\))?\s+)?struct\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .struct, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                if trimmed.contains("{") {
                    scopeStack.append(m.name)
                }
                continue
            }

            // enum
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:pub(?:\([\w]+\))?\s+)?enum\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .enum, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                scopeStack.append(m.name)
                continue
            }

            // impl (treated as extension)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^impl(?:<[^>]*>)?\s+(?:\w+\s+for\s+)?(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .extension, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                scopeStack.append(m.name)
                continue
            }

            // type alias
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:pub\s+)?type\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .typeAlias, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // fn (function or method)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:pub(?:\([\w]+\))?\s+)?(?:async\s+)?(?:unsafe\s+)?(?:const\s+)?fn\s+(\w+)"#) {
                let kind: SymbolKind = scope != nil ? .method : .function
                symbols.append(Symbol(
                    name: m.name, kind: kind, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // const
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:pub\s+)?const\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .constant, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // static / let bindings
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^(?:pub\s+)?static\s+(?:mut\s+)?(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .variable, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            if trimmed == "}" && !scopeStack.isEmpty {
                scopeStack.removeLast()
            }
        }

        return symbols
    }
}

// MARK: - Go Extractor

/// Regex-based symbol extractor for Go source code.
///
/// Detects: func, type...struct, type...interface, var, const, import, package.
public struct GoSymbolExtractor: SymbolExtractor, Sendable {
    public let language: Language = .go

    public func extractSymbols(from source: String, filePath: String) -> [Symbol] {
        var symbols: [Symbol] = []
        let lines = source.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineNumber = index + 1

            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                continue
            }

            // package
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^package\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .module, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    signature: trimmed
                ))
                continue
            }

            // import (single line)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^import\s+"([^"]+)""#) {
                symbols.append(Symbol(
                    name: m.name, kind: .import, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    signature: trimmed
                ))
                continue
            }

            // type ... struct
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^type\s+(\w+)\s+struct\b"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .struct, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    signature: trimmed
                ))
                continue
            }

            // type ... interface
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^type\s+(\w+)\s+interface\b"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .interface, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    signature: trimmed
                ))
                continue
            }

            // type alias
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^type\s+(\w+)\s+\w"#) {
                // Only match if it's not a struct or interface (handled above)
                symbols.append(Symbol(
                    name: m.name, kind: .typeAlias, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    signature: trimmed
                ))
                continue
            }

            // func with receiver (method)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^func\s+\([^)]+\)\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .method, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    signature: trimmed
                ))
                continue
            }

            // func (free function)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^func\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .function, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    signature: trimmed
                ))
                continue
            }

            // var (top-level)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^var\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .variable, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    signature: trimmed
                ))
                continue
            }

            // const
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^const\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .constant, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    signature: trimmed
                ))
                continue
            }
        }

        return symbols
    }
}

// MARK: - Ruby Extractor

/// Regex-based symbol extractor for Ruby source code.
///
/// Detects: def, class, module, attr_accessor/attr_reader/attr_writer.
public struct RubySymbolExtractor: SymbolExtractor, Sendable {
    public let language: Language = .ruby

    public func extractSymbols(from source: String, filePath: String) -> [Symbol] {
        var symbols: [Symbol] = []
        let lines = source.components(separatedBy: .newlines)
        var scopeStack: [String] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineNumber = index + 1

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let scope = scopeStack.last

            // require (import)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^require(?:_relative)?\s+['\"]([^'\"]+)['\"]"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .import, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // module
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^module\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .module, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                scopeStack.append(m.name)
                continue
            }

            // class
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^class\s+(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .class, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                scopeStack.append(m.name)
                continue
            }

            // def (method or function)
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^def\s+(?:self\.)?(\w+[?!]?)"#) {
                let kind: SymbolKind = scope != nil ? .method : .function
                symbols.append(Symbol(
                    name: m.name, kind: kind, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // attr_accessor, attr_reader, attr_writer
            if let m = ExtractorHelpers.firstMatch(in: trimmed, pattern: #"^attr_(?:accessor|reader|writer)\s+:(\w+)"#) {
                symbols.append(Symbol(
                    name: m.name, kind: .property, filePath: filePath,
                    line: lineNumber, column: ExtractorHelpers.column(of: m.name, in: line),
                    scope: scope, signature: trimmed
                ))
                continue
            }

            // end pops scope
            if trimmed == "end" && !scopeStack.isEmpty {
                scopeStack.removeLast()
            }
        }

        return symbols
    }
}

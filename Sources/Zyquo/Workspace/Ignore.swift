import Foundation

public struct IgnoreRules: Sendable {
    private let patterns: [IgnorePattern]

    public init(patterns: [IgnorePattern] = []) {
        self.patterns = patterns
    }

    public static func load(from urls: [URL]) -> IgnoreRules {
        var patterns: [IgnorePattern] = []
        for url in urls {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            patterns.append(contentsOf: parse(content))
        }
        return IgnoreRules(patterns: patterns)
    }

    public func isIgnored(_ relativePath: String) -> Bool {
        var ignored = false
        for pattern in patterns {
            if pattern.matches(relativePath) {
                ignored = !pattern.negated
            }
        }
        return ignored
    }

    static func parse(_ content: String) -> [IgnorePattern] {
        content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { IgnorePattern($0) }
    }
}

public struct IgnorePattern: Sendable {
    let raw: String
    let negated: Bool
    private let glob: String

    init?(_ line: String) {
        var s = line
        if s.hasPrefix("!") {
            self.negated = true
            s = String(s.dropFirst())
        } else {
            self.negated = false
        }
        s = s.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        self.raw = line
        self.glob = s
    }

    func matches(_ path: String) -> Bool {
        let pattern = glob.hasSuffix("/") ? String(glob.dropLast()) : glob
        if pattern.contains("/") && !pattern.hasPrefix("/") {
            return globMatch(path, pattern: pattern) || globMatch(path, pattern: "*/\(pattern)")
        }
        let components = path.components(separatedBy: "/")
        for component in components {
            if globMatch(component, pattern: pattern) { return true }
        }
        return globMatch(path, pattern: pattern)
    }
}

private func globMatch(_ string: String, pattern: String) -> Bool {
    let s = Array(string)
    let p = Array(pattern)
    var si = 0, pi = 0
    var starSi = -1, starPi = -1

    while si < s.count {
        if pi < p.count && (p[pi] == "?" || p[pi] == s[si]) {
            si += 1; pi += 1
        } else if pi < p.count && p[pi] == "*" {
            if pi + 1 < p.count && p[pi + 1] == "*" {
                pi += 2
                if pi < p.count && p[pi] == "/" { pi += 1 }
                return globMatch(String(s[si...]), pattern: String(p[pi...]))
                    || (si + 1 < s.count && globMatch(String(s[(si + 1)...]), pattern: String(p[(pi - (p[pi - 1] == "/" ? 3 : 2))...])))
            }
            starSi = si; starPi = pi; pi += 1
        } else if starPi >= 0 {
            starSi += 1; si = starSi; pi = starPi + 1
        } else {
            return false
        }
    }
    while pi < p.count && p[pi] == "*" { pi += 1 }
    return pi == p.count
}

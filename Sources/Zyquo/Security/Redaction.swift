import Foundation

public enum Redaction {
    private static let patterns: [(NSRegularExpression, String)] = {
        let defs: [(String, String)] = [
            ("(sk-[a-zA-Z0-9_-]{8,})", "[REDACTED_API_KEY]"),
            ("(Bearer\\s+[a-zA-Z0-9._-]{20,})", "[REDACTED_BEARER]"),
            ("([a-zA-Z_]*(?:TOKEN|SECRET|KEY|PASSWORD|CREDENTIAL)[a-zA-Z_]*\\s*=\\s*)\\S+", "$1[REDACTED]"),
        ]
        return defs.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            return (regex, replacement)
        }
    }()

    public static func redact(_ text: String) -> String {
        var result = text
        for (regex, replacement) in patterns {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }
}

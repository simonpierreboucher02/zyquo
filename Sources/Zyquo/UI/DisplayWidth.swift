import Foundation

// MARK: - DisplayWidth

/// Correct terminal display-width measurement. The previous renderer used
/// `String.count`, which over/under-counts for emoji, CJK, and combining marks,
/// causing panels to misalign. This computes the number of terminal columns a
/// string occupies after stripping ANSI escape sequences.
public enum DisplayWidth {

    /// Strip CSI/OSC ANSI escape sequences from a string.
    public static func stripANSI(_ s: String) -> String {
        // CSI sequences: ESC [ ... letter   ;  OSC: ESC ] ... BEL/ST
        var out = String()
        out.reserveCapacity(s.count)
        var scalars = Array(s.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let sc = scalars[i]
            if sc == "\u{1B}" && i + 1 < scalars.count {
                let next = scalars[i + 1]
                if next == "[" {
                    // CSI — consume until a final byte in @-~ (0x40–0x7E)
                    i += 2
                    while i < scalars.count {
                        let v = scalars[i].value
                        i += 1
                        if v >= 0x40 && v <= 0x7E { break }
                    }
                    continue
                } else if next == "]" {
                    // OSC — consume until BEL or ST (ESC \)
                    i += 2
                    while i < scalars.count {
                        if scalars[i] == "\u{07}" { i += 1; break }
                        if scalars[i] == "\u{1B}", i + 1 < scalars.count, scalars[i + 1] == "\\" {
                            i += 2; break
                        }
                        i += 1
                    }
                    continue
                }
            }
            out.unicodeScalars.append(sc)
            i += 1
        }
        return out
    }

    /// Columns occupied by a single Unicode scalar (0, 1, or 2).
    public static func scalarWidth(_ scalar: Unicode.Scalar) -> Int {
        let v = scalar.value
        // Control characters
        if v == 0 { return 0 }
        if v < 32 || (v >= 0x7F && v < 0xA0) { return 0 }
        // Combining / zero-width marks
        if isZeroWidth(v) { return 0 }
        // Wide ranges (CJK, Hangul, full-width forms, most emoji)
        if isWide(v) { return 2 }
        return 1
    }

    /// Display width of a whole string (ANSI-stripped, grapheme-aware-ish).
    public static func width(_ s: String) -> Int {
        let clean = stripANSI(s)
        var total = 0
        for ch in clean {
            // For a grapheme cluster, the width is the max of its scalars'
            // widths (base char dominates; combining marks add 0). Emoji ZWJ
            // sequences render as a single wide cell in modern terminals.
            var w = 0
            var sawWide = false
            for scalar in ch.unicodeScalars {
                let sw = scalarWidth(scalar)
                if sw == 2 { sawWide = true }
                w = max(w, sw)
            }
            total += sawWide ? 2 : w
        }
        return total
    }

    /// Pad a string with trailing spaces to reach `target` display columns.
    public static func pad(_ s: String, to target: Int) -> String {
        let w = width(s)
        guard w < target else { return s }
        return s + String(repeating: " ", count: target - w)
    }

    /// Truncate a string to at most `max` display columns (ANSI-naive: intended
    /// for plain text only).
    public static func truncate(_ s: String, to max: Int) -> String {
        guard width(s) > max else { return s }
        var out = String()
        var w = 0
        for ch in s {
            let cw = width(String(ch))
            if w + cw > max { break }
            out.append(ch)
            w += cw
        }
        return out
    }

    // MARK: - Ranges

    private static func isZeroWidth(_ v: UInt32) -> Bool {
        // Combining diacritical marks + common zero-width controls/joiners.
        (v >= 0x0300 && v <= 0x036F) ||
        (v >= 0x1AB0 && v <= 0x1AFF) ||
        (v >= 0x1DC0 && v <= 0x1DFF) ||
        (v >= 0x20D0 && v <= 0x20FF) ||
        (v >= 0xFE20 && v <= 0xFE2F) ||
        v == 0x200B || v == 0x200C || v == 0x200D || v == 0xFEFF
    }

    private static func isWide(_ v: UInt32) -> Bool {
        (v >= 0x1100 && v <= 0x115F) ||   // Hangul Jamo
        (v >= 0x2E80 && v <= 0x303E) ||   // CJK radicals, Kangxi
        (v >= 0x3041 && v <= 0x33FF) ||   // Hiragana … CJK symbols
        (v >= 0x3400 && v <= 0x4DBF) ||   // CJK Ext A
        (v >= 0x4E00 && v <= 0x9FFF) ||   // CJK Unified
        (v >= 0xA000 && v <= 0xA4CF) ||   // Yi
        (v >= 0xAC00 && v <= 0xD7A3) ||   // Hangul syllables
        (v >= 0xF900 && v <= 0xFAFF) ||   // CJK compatibility
        (v >= 0xFE30 && v <= 0xFE4F) ||   // CJK compat forms
        (v >= 0xFF00 && v <= 0xFF60) ||   // Fullwidth forms
        (v >= 0xFFE0 && v <= 0xFFE6) ||
        (v >= 0x1F300 && v <= 0x1FAFF) || // emoji & symbols
        (v >= 0x1F000 && v <= 0x1F0FF) || // mahjong/dominoes/cards
        (v >= 0x20000 && v <= 0x3FFFD)    // CJK Ext B+
    }
}

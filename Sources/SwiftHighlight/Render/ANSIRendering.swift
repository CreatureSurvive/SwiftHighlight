/// Terminal color support for ``HighlightedCode/ansi(theme:colors:)``.
public enum ANSIColors: Sendable {
    /// 24-bit `38;2;r;g;b` escapes (most modern terminals).
    case trueColor
    /// The xterm 256-color palette, nearest match.
    case xterm256
}

public extension HighlightedCode {
    /// The code with ANSI escape sequences, for printing to a terminal.
    ///
    /// The theme background is not painted; unscoped text uses the terminal's own foreground.
    func ansi(theme: Theme, colors: ANSIColors = .trueColor) -> String {
        var cache: [UInt32: String] = [:]
        var output = ""
        output.reserveCapacity(source.utf8.count * 2)
        let utf8 = source.utf8
        var index = utf8.startIndex
        var offset = 0
        var runs = RunIterator(tokens: tokens, byteCount: utf8.count)
        while let (range, scope) = runs.next() {
            let lower = utf8.index(index, offsetBy: range.lowerBound - offset)
            let upper = utf8.index(lower, offsetBy: range.count)
            index = upper
            offset = range.upperBound
            let text = source[lower..<upper]
            guard scope != 0 else {
                output += text
                continue
            }
            let open: String
            if let cached = cache[scope] {
                open = cached
            } else {
                open = Self.escape(theme.style(for: Scope(id: scope)), colors: colors)
                cache[scope] = open
            }
            if open.isEmpty {
                output += text
                continue
            }
            // Re-open after each line break so pagers that reset per line keep the color.
            var first = true
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                if !first { output += "\n" }
                first = false
                if !line.isEmpty { output += open + line + "\u{1B}[0m" }
            }
        }
        return output
    }

    private static func escape(_ style: ResolvedStyle, colors: ANSIColors) -> String {
        var codes: [String] = []
        if style.bold { codes.append("1") }
        if style.italic { codes.append("3") }
        if style.underline { codes.append("4") }
        if style.strikethrough { codes.append("9") }
        codes.append(colorCode(style.foreground, colors: colors, base: 38))
        if let background = style.background { codes.append(colorCode(background, colors: colors, base: 48)) }
        return "\u{1B}[" + codes.joined(separator: ";") + "m"
    }

    private static func colorCode(_ color: ThemeColor, colors: ANSIColors, base: Int) -> String {
        switch colors {
        case .trueColor:
            return "\(base);2;\(color.red);\(color.green);\(color.blue)"
        case .xterm256:
            return "\(base);5;\(xterm256Index(color))"
        }
    }

    /// Nearest entry of the 6×6×6 cube or the grayscale ramp.
    static func xterm256Index(_ color: ThemeColor) -> Int {
        let levels = [0, 95, 135, 175, 215, 255]
        func nearestLevel(_ value: UInt8) -> Int {
            var best = 0
            for (index, level) in levels.enumerated() where abs(level - Int(value)) < abs(levels[best] - Int(value)) {
                best = index
            }
            return best
        }
        let (r, g, b) = (nearestLevel(color.red), nearestLevel(color.green), nearestLevel(color.blue))
        let cube = 16 + 36 * r + 6 * g + b
        let cubeColor = (levels[r], levels[g], levels[b])
        let average = (Int(color.red) + Int(color.green) + Int(color.blue)) / 3
        let grayIndex = min(23, max(0, (average - 8 + 5) / 10))
        let gray = 8 + grayIndex * 10
        func distance(_ other: (Int, Int, Int)) -> Int {
            let dr = Int(color.red) - other.0, dg = Int(color.green) - other.1, db = Int(color.blue) - other.2
            return dr * dr + dg * dg + db * db
        }
        return distance((gray, gray, gray)) < distance(cubeColor) ? 232 + grayIndex : cube
    }
}

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
        var table = StyleTable<ResolvedStyle>(resolve: theme.resolvedStyle(for:))
        var text = source
        return text.withUTF8 { bytes -> String in
            let runs = StyledRuns(tokens: tokens, bytes: bytes, table: &table, paintsOnlyGlyphs: \.paintsOnlyGlyphs)
            // Style 0 (unscoped) keeps the terminal's own colors.
            let openings = table.styles.enumerated().map {
                $0.offset == 0 ? [] : Array(Self.escape($0.element, colors: colors).utf8)
            }
            let reset = Array("\u{1B}[0m".utf8)
            var output: [UInt8] = []
            output.reserveCapacity(bytes.count * 3)
            for (range, style) in zip(runs.ranges, runs.styles) {
                let open = openings[style]
                if open.isEmpty {
                    output.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[range]))
                    continue
                }
                // Close before each line break and reopen after it, so pagers that reset per
                // line keep the color.
                var lineStart = range.lowerBound
                var index = range.lowerBound
                while index <= range.upperBound {
                    if index == range.upperBound || bytes[index] == 0x0A {
                        if index > lineStart {
                            output += open
                            output.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[lineStart..<index]))
                            output += reset
                        }
                        if index < range.upperBound { output.append(0x0A) }
                        lineStart = index + 1
                    }
                    index += 1
                }
            }
            return String(decoding: output, as: UTF8.self)
        }
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

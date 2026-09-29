// Built-in themes. Palettes follow the published originals; scopes map them onto this package's
// TextMate-style scope names.

public extension Theme {
    /// Every built-in theme.
    static let builtins: [Theme] = [
        .xcodeLight, .xcodeDark, .githubLight, .githubDark, .oneLight, .oneDark, .solarizedLight, .solarizedDark,
        .catppuccinLatte, .catppuccinMocha, .dracula, .monokai, .nord,
    ]

    /// The built-in theme with this name (case-insensitive).
    static func named(_ name: String) -> Theme? {
        builtins.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: Xcode

    static let xcodeLight = Theme(
        name: "Xcode Light", isDark: false, foreground: "#262626", background: "#FFFFFF",
        selection: "#A4CDFF", lineHighlight: "#E8F2FF", lineNumber: "#A6A6A6", cursor: "#000000",
        styles: [
            .comment: Style("#5D6C79"),
            .commentDocumentation: Style("#5D6C79"),
            .string: Style("#C41A16"),
            .escape: Style("#C41A16"),
            .stringRegex: Style("#C41A16"),
            .interpolation: Style("#262626"),
            .number: Style("#1C00CF"),
            .character: Style("#1C00CF"),
            .constant: Style("#9B2393", bold: true),
            .keyword: Style("#9B2393", bold: true),
            .keywordOperator: Style("#9B2393", bold: true),
            .keywordDeclaration: Style("#9B2393", bold: true),
            .modifier: Style("#9B2393", bold: true),
            .attribute: Style("#815F03"),
            .preprocessor: Style("#643820"),
            .type: Style("#0B4F79"),
            .typeBuiltin: Style("#3900A0"),
            .namespace: Style("#0B4F79"),
            .function: Style("#0F68A0"),
            .functionCall: Style("#326D74"),
            .functionBuiltin: Style("#6C36A9"),
            .variableBuiltin: Style("#9B2393", bold: true),
            .property: Style("#326D74"),
            .tag: Style("#9B2393"),
            .tagAttribute: Style("#815F03"),
            .key: Style("#0B4F79"),
            .heading: Style("#262626", bold: true),
            .bold: Style(bold: true),
            .italic: Style(italic: true),
            .inlineCode: Style("#C41A16"),
            .link: Style("#0E0EFF", underline: true),
            .quote: Style("#5D6C79"),
            .listMarker: Style("#9B2393"),
            .inserted: Style("#1A7F37"),
            .deleted: Style("#CF222E"),
            .changed: Style("#9A6700"),
            .diffHeader: Style("#262626", bold: true),
            .diffRange: Style("#6639BA"),
            .invalid: Style("#FFFFFF", background: "#CF222E"),
        ]
    )

    static let xcodeDark = Theme(
        name: "Xcode Dark", isDark: true, foreground: "#DFDFE0", background: "#1F1F24",
        selection: "#515B70", lineHighlight: "#23252B", lineNumber: "#747478", cursor: "#FFFFFF",
        styles: [
            .comment: Style("#7F8C98"),
            .commentDocumentation: Style("#7F8C98"),
            .string: Style("#FF8170"),
            .escape: Style("#FF8170"),
            .stringRegex: Style("#FF8170"),
            .interpolation: Style("#DFDFE0"),
            .number: Style("#D9C97C"),
            .character: Style("#D9C97C"),
            .constant: Style("#FF7AB2", bold: true),
            .keyword: Style("#FF7AB2", bold: true),
            .keywordOperator: Style("#FF7AB2", bold: true),
            .keywordDeclaration: Style("#FF7AB2", bold: true),
            .modifier: Style("#FF7AB2", bold: true),
            .attribute: Style("#FD8F3F"),
            .preprocessor: Style("#FD8F3F"),
            .type: Style("#5DD8FF"),
            .typeBuiltin: Style("#D0A8FF"),
            .namespace: Style("#5DD8FF"),
            .function: Style("#41A1C0"),
            .functionCall: Style("#67B7A4"),
            .functionBuiltin: Style("#A167E6"),
            .variableBuiltin: Style("#FF7AB2", bold: true),
            .property: Style("#67B7A4"),
            .tag: Style("#FF7AB2"),
            .tagAttribute: Style("#FD8F3F"),
            .key: Style("#5DD8FF"),
            .heading: Style("#DFDFE0", bold: true),
            .bold: Style(bold: true),
            .italic: Style(italic: true),
            .inlineCode: Style("#FF8170"),
            .link: Style("#6699FF", underline: true),
            .quote: Style("#7F8C98"),
            .listMarker: Style("#FF7AB2"),
            .inserted: Style("#3FB950"),
            .deleted: Style("#F85149"),
            .changed: Style("#D29922"),
            .diffHeader: Style("#DFDFE0", bold: true),
            .diffRange: Style("#A371F7"),
            .invalid: Style("#FFFFFF", background: "#DA3633"),
        ]
    )

    // MARK: GitHub

    static let githubLight = Theme(
        name: "GitHub Light", isDark: false, foreground: "#1F2328", background: "#FFFFFF",
        selection: "#B6E3FF", lineHighlight: "#F6F8FA", lineNumber: "#8C959F", cursor: "#1F2328",
        styles: [
            .comment: Style("#59636E"),
            .string: Style("#0A3069"),
            .escape: Style("#0A3069", bold: true),
            .stringRegex: Style("#116329"),
            .interpolation: Style("#1F2328"),
            .number: Style("#0550AE"),
            .constant: Style("#0550AE"),
            .constantOther: Style("#0550AE"),
            .keyword: Style("#CF222E"),
            .keywordDeclaration: Style("#CF222E"),
            .modifier: Style("#CF222E"),
            .attribute: Style("#8250DF"),
            .preprocessor: Style("#CF222E"),
            .type: Style("#953800"),
            .typeBuiltin: Style("#0550AE"),
            .namespace: Style("#953800"),
            .function: Style("#8250DF"),
            .functionCall: Style("#8250DF"),
            .variableBuiltin: Style("#0550AE"),
            .parameter: Style("#1F2328"),
            .property: Style("#0550AE"),
            .tag: Style("#116329"),
            .tagAttribute: Style("#0550AE"),
            .key: Style("#0550AE"),
            .heading: Style("#0550AE", bold: true),
            .bold: Style("#1F2328", bold: true),
            .italic: Style("#1F2328", italic: true),
            .inlineCode: Style("#0550AE"),
            .link: Style("#0A3069", underline: true),
            .quote: Style("#116329"),
            .listMarker: Style("#953800"),
            .inserted: Style("#116329", background: "#DAFBE1"),
            .deleted: Style("#82071E", background: "#FFEBE9"),
            .changed: Style("#953800", background: "#FFD8B5"),
            .diffHeader: Style("#0550AE", bold: true),
            .diffRange: Style("#8250DF", bold: true),
            .invalid: Style("#82071E", italic: true),
        ]
    )

    static let githubDark = Theme(
        name: "GitHub Dark", isDark: true, foreground: "#E6EDF3", background: "#0D1117",
        selection: "#264F78", lineHighlight: "#161B22", lineNumber: "#6E7681", cursor: "#E6EDF3",
        styles: [
            .comment: Style("#8B949E"),
            .string: Style("#A5D6FF"),
            .escape: Style("#79C0FF", bold: true),
            .stringRegex: Style("#7EE787"),
            .interpolation: Style("#E6EDF3"),
            .number: Style("#79C0FF"),
            .constant: Style("#79C0FF"),
            .constantOther: Style("#79C0FF"),
            .keyword: Style("#FF7B72"),
            .keywordDeclaration: Style("#FF7B72"),
            .modifier: Style("#FF7B72"),
            .attribute: Style("#D2A8FF"),
            .preprocessor: Style("#FF7B72"),
            .type: Style("#FFA657"),
            .typeBuiltin: Style("#79C0FF"),
            .namespace: Style("#FFA657"),
            .function: Style("#D2A8FF"),
            .functionCall: Style("#D2A8FF"),
            .variableBuiltin: Style("#79C0FF"),
            .parameter: Style("#E6EDF3"),
            .property: Style("#79C0FF"),
            .tag: Style("#7EE787"),
            .tagAttribute: Style("#79C0FF"),
            .key: Style("#79C0FF"),
            .heading: Style("#1F6FEB", bold: true),
            .bold: Style("#E6EDF3", bold: true),
            .italic: Style("#E6EDF3", italic: true),
            .inlineCode: Style("#79C0FF"),
            .link: Style("#A5D6FF", underline: true),
            .quote: Style("#7EE787"),
            .listMarker: Style("#FFA657"),
            .inserted: Style("#AFF5B4", background: "#033A16"),
            .deleted: Style("#FFDCD7", background: "#67060C"),
            .changed: Style("#FFDFB6", background: "#5A1E02"),
            .diffHeader: Style("#79C0FF", bold: true),
            .diffRange: Style("#D2A8FF", bold: true),
            .invalid: Style("#FFA198", italic: true),
        ]
    )

    // MARK: One

    static let oneLight = Theme(
        name: "One Light", isDark: false, foreground: "#383A42", background: "#FAFAFA",
        selection: "#E5E5E6", lineHighlight: "#F0F0F1", lineNumber: "#9D9D9F", cursor: "#526FFF",
        styles: oneStyles(keyword: "#A626A4", string: "#50A14F", number: "#986801", comment: "#A0A1A7",
                          function: "#4078F2", type: "#C18401", variable: "#E45649", cyan: "#0184BC",
                          foreground: "#383A42")
    )

    static let oneDark = Theme(
        name: "One Dark", isDark: true, foreground: "#ABB2BF", background: "#282C34",
        selection: "#3E4451", lineHighlight: "#2C313C", lineNumber: "#636D83", cursor: "#528BFF",
        styles: oneStyles(keyword: "#C678DD", string: "#98C379", number: "#D19A66", comment: "#5C6370",
                          function: "#61AFEF", type: "#E5C07B", variable: "#E06C75", cyan: "#56B6C2",
                          foreground: "#ABB2BF")
    )

    private static func oneStyles(keyword: ThemeColor, string: ThemeColor, number: ThemeColor, comment: ThemeColor,
                                  function: ThemeColor, type: ThemeColor, variable: ThemeColor, cyan: ThemeColor,
                                  foreground: ThemeColor) -> [Scope: Style] {
        [
            .comment: Style(comment, italic: true),
            .string: Style(string),
            .escape: Style(cyan),
            .stringRegex: Style(cyan),
            .interpolation: Style(variable),
            .number: Style(number),
            .constant: Style(number),
            .constantOther: Style(number),
            .keyword: Style(keyword),
            .keywordOperator: Style(keyword),
            .keywordDeclaration: Style(keyword),
            .modifier: Style(keyword),
            .attribute: Style(number),
            .preprocessor: Style(keyword),
            .type: Style(type),
            .typeBuiltin: Style(type),
            .namespace: Style(type),
            .function: Style(function),
            .functionCall: Style(function),
            .functionBuiltin: Style(cyan),
            .variable: Style(variable),
            .variableBuiltin: Style(type),
            .parameter: Style(foreground),
            .property: Style(variable),
            .tag: Style(variable),
            .tagAttribute: Style(number),
            .key: Style(variable),
            .heading: Style(variable, bold: true),
            .bold: Style(number, bold: true),
            .italic: Style(keyword, italic: true),
            .inlineCode: Style(string),
            .link: Style(function, underline: true),
            .quote: Style(comment, italic: true),
            .listMarker: Style(variable),
            .inserted: Style(string),
            .deleted: Style(variable),
            .changed: Style(type),
            .diffHeader: Style(function, bold: true),
            .diffRange: Style(keyword),
            .invalid: Style(variable, underline: true),
        ]
    }

    // MARK: Solarized

    static let solarizedLight = Theme(
        name: "Solarized Light", isDark: false, foreground: "#657B83", background: "#FDF6E3",
        selection: "#EEE8D5", lineHighlight: "#EEE8D5", lineNumber: "#93A1A1", cursor: "#657B83",
        styles: solarizedStyles(emphasis: "#586E75", comment: "#93A1A1")
    )

    static let solarizedDark = Theme(
        name: "Solarized Dark", isDark: true, foreground: "#839496", background: "#002B36",
        selection: "#073642", lineHighlight: "#073642", lineNumber: "#586E75", cursor: "#839496",
        styles: solarizedStyles(emphasis: "#93A1A1", comment: "#586E75")
    )

    private static func solarizedStyles(emphasis: ThemeColor, comment: ThemeColor) -> [Scope: Style] {
        let yellow: ThemeColor = "#B58900", orange: ThemeColor = "#CB4B16", red: ThemeColor = "#DC322F"
        let magenta: ThemeColor = "#D33682", violet: ThemeColor = "#6C71C4", blue: ThemeColor = "#268BD2"
        let cyan: ThemeColor = "#2AA198", green: ThemeColor = "#859900"
        return [
            .comment: Style(comment, italic: true),
            .string: Style(cyan),
            .escape: Style(orange),
            .stringRegex: Style(red),
            .interpolation: Style(orange),
            .number: Style(magenta),
            .constant: Style(yellow),
            .constantOther: Style(violet),
            .keyword: Style(green),
            .keywordDeclaration: Style(green),
            .modifier: Style(yellow),
            .attribute: Style(violet),
            .preprocessor: Style(orange),
            .type: Style(yellow),
            .typeBuiltin: Style(yellow),
            .namespace: Style(yellow),
            .function: Style(blue),
            .functionCall: Style(blue),
            .variable: Style(blue),
            .variableBuiltin: Style(orange),
            .property: Style(blue),
            .tag: Style(blue),
            .tagAttribute: Style(yellow),
            .key: Style(blue),
            .heading: Style(blue, bold: true),
            .bold: Style(emphasis, bold: true),
            .italic: Style(emphasis, italic: true),
            .inlineCode: Style(cyan),
            .link: Style(violet, underline: true),
            .quote: Style(comment, italic: true),
            .listMarker: Style(orange),
            .inserted: Style(green),
            .deleted: Style(red),
            .changed: Style(yellow),
            .diffHeader: Style(blue, bold: true),
            .diffRange: Style(violet),
            .invalid: Style(red, underline: true),
        ]
    }

    // MARK: Catppuccin

    static let catppuccinLatte = Theme(
        name: "Catppuccin Latte", isDark: false, foreground: "#4C4F69", background: "#EFF1F5",
        selection: "#ACB0BE", lineHighlight: "#E6E9EF", lineNumber: "#8C8FA1", cursor: "#DC8A78",
        styles: catppuccinStyles(text: "#4C4F69", overlay: "#7C7F93", mauve: "#8839EF", green: "#40A02B",
                                 peach: "#FE640B", blue: "#1E66F5", yellow: "#DF8E1D", teal: "#179299",
                                 pink: "#EA76CB", red: "#D20F39", maroon: "#E64553", lavender: "#7287FD",
                                 sky: "#04A5E5", sapphire: "#209FB5")
    )

    static let catppuccinMocha = Theme(
        name: "Catppuccin Mocha", isDark: true, foreground: "#CDD6F4", background: "#1E1E2E",
        selection: "#45475A", lineHighlight: "#313244", lineNumber: "#7F849C", cursor: "#F5E0DC",
        styles: catppuccinStyles(text: "#CDD6F4", overlay: "#9399B2", mauve: "#CBA6F7", green: "#A6E3A1",
                                 peach: "#FAB387", blue: "#89B4FA", yellow: "#F9E2AF", teal: "#94E2D5",
                                 pink: "#F5C2E7", red: "#F38BA8", maroon: "#EBA0AC", lavender: "#B4BEFE",
                                 sky: "#89DCEB", sapphire: "#74C7EC")
    )

    private static func catppuccinStyles(text: ThemeColor, overlay: ThemeColor, mauve: ThemeColor, green: ThemeColor,
                                         peach: ThemeColor, blue: ThemeColor, yellow: ThemeColor, teal: ThemeColor,
                                         pink: ThemeColor, red: ThemeColor, maroon: ThemeColor, lavender: ThemeColor,
                                         sky: ThemeColor, sapphire: ThemeColor) -> [Scope: Style] {
        [
            .comment: Style(overlay, italic: true),
            .string: Style(green),
            .escape: Style(pink),
            .stringRegex: Style(pink),
            .interpolation: Style(pink),
            .number: Style(peach),
            .constant: Style(peach),
            .constantOther: Style(peach),
            .keyword: Style(mauve),
            .keywordOperator: Style(sky),
            .keywordDeclaration: Style(mauve),
            .modifier: Style(mauve),
            .attribute: Style(yellow),
            .preprocessor: Style(pink),
            .type: Style(yellow),
            .typeBuiltin: Style(mauve, italic: true),
            .namespace: Style(yellow),
            .function: Style(blue),
            .functionCall: Style(blue),
            .functionBuiltin: Style(peach),
            .variable: Style(text),
            .variableBuiltin: Style(red),
            .parameter: Style(maroon, italic: true),
            .property: Style(lavender),
            .tag: Style(blue),
            .tagAttribute: Style(yellow, italic: true),
            .key: Style(blue),
            .heading: Style(red, bold: true),
            .bold: Style(red, bold: true),
            .italic: Style(red, italic: true),
            .inlineCode: Style(green),
            .link: Style(blue, underline: true),
            .quote: Style(pink),
            .listMarker: Style(teal),
            .inserted: Style(green),
            .deleted: Style(red),
            .changed: Style(peach),
            .diffHeader: Style(blue, bold: true),
            .diffRange: Style(sapphire),
            .invalid: Style(red, underline: true),
        ]
    }

    // MARK: Dark classics

    static let dracula = Theme(
        name: "Dracula", isDark: true, foreground: "#F8F8F2", background: "#282A36",
        selection: "#44475A", lineHighlight: "#44475A", lineNumber: "#6272A4", cursor: "#F8F8F0",
        styles: [
            .comment: Style("#6272A4"),
            .string: Style("#F1FA8C"),
            .escape: Style("#FF79C6"),
            .stringRegex: Style("#FF5555"),
            .interpolation: Style("#FF79C6"),
            .number: Style("#BD93F9"),
            .constant: Style("#BD93F9"),
            .constantOther: Style("#BD93F9"),
            .keyword: Style("#FF79C6"),
            .keywordDeclaration: Style("#8BE9FD", italic: true),
            .modifier: Style("#FF79C6"),
            .attribute: Style("#50FA7B", italic: true),
            .preprocessor: Style("#FF79C6"),
            .type: Style("#8BE9FD", italic: true),
            .typeBuiltin: Style("#8BE9FD", italic: true),
            .namespace: Style("#8BE9FD"),
            .function: Style("#50FA7B"),
            .functionCall: Style("#50FA7B"),
            .variableBuiltin: Style("#BD93F9", italic: true),
            .parameter: Style("#FFB86C", italic: true),
            .property: Style("#F8F8F2"),
            .tag: Style("#FF79C6"),
            .tagAttribute: Style("#50FA7B", italic: true),
            .key: Style("#8BE9FD"),
            .heading: Style("#BD93F9", bold: true),
            .bold: Style("#FFB86C", bold: true),
            .italic: Style("#F1FA8C", italic: true),
            .inlineCode: Style("#50FA7B"),
            .link: Style("#8BE9FD", underline: true),
            .quote: Style("#F1FA8C", italic: true),
            .listMarker: Style("#8BE9FD"),
            .inserted: Style("#50FA7B"),
            .deleted: Style("#FF5555"),
            .changed: Style("#FFB86C"),
            .diffHeader: Style("#6272A4", bold: true),
            .diffRange: Style("#BD93F9"),
            .invalid: Style("#FF5555", underline: true),
        ]
    )

    static let monokai = Theme(
        name: "Monokai", isDark: true, foreground: "#F8F8F2", background: "#272822",
        selection: "#49483E", lineHighlight: "#3E3D32", lineNumber: "#90908A", cursor: "#F8F8F0",
        styles: [
            .comment: Style("#75715E"),
            .string: Style("#E6DB74"),
            .escape: Style("#AE81FF"),
            .stringRegex: Style("#E6DB74"),
            .interpolation: Style("#F92672"),
            .number: Style("#AE81FF"),
            .constant: Style("#AE81FF"),
            .constantOther: Style("#AE81FF"),
            .keyword: Style("#F92672"),
            .keywordDeclaration: Style("#66D9EF", italic: true),
            .modifier: Style("#F92672"),
            .attribute: Style("#A6E22E"),
            .preprocessor: Style("#F92672"),
            .type: Style("#A6E22E"),
            .typeBuiltin: Style("#66D9EF", italic: true),
            .namespace: Style("#A6E22E"),
            .function: Style("#A6E22E"),
            .functionCall: Style("#66D9EF"),
            .variableBuiltin: Style("#FD971F", italic: true),
            .parameter: Style("#FD971F", italic: true),
            .tag: Style("#F92672"),
            .tagAttribute: Style("#A6E22E"),
            .key: Style("#66D9EF"),
            .heading: Style("#A6E22E", bold: true),
            .bold: Style(bold: true),
            .italic: Style(italic: true),
            .inlineCode: Style("#E6DB74"),
            .link: Style("#66D9EF", underline: true),
            .quote: Style("#75715E"),
            .listMarker: Style("#F92672"),
            .inserted: Style("#A6E22E"),
            .deleted: Style("#F92672"),
            .changed: Style("#E6DB74"),
            .diffHeader: Style("#75715E", bold: true),
            .diffRange: Style("#AE81FF"),
            .invalid: Style("#F8F8F0", background: "#F92672"),
        ]
    )

    static let nord = Theme(
        name: "Nord", isDark: true, foreground: "#D8DEE9", background: "#2E3440",
        selection: "#434C5E", lineHighlight: "#3B4252", lineNumber: "#4C566A", cursor: "#D8DEE9",
        styles: [
            .comment: Style("#616E88"),
            .string: Style("#A3BE8C"),
            .escape: Style("#EBCB8B"),
            .stringRegex: Style("#EBCB8B"),
            .interpolation: Style("#81A1C1"),
            .number: Style("#B48EAD"),
            .constant: Style("#81A1C1"),
            .constantOther: Style("#B48EAD"),
            .keyword: Style("#81A1C1"),
            .keywordDeclaration: Style("#81A1C1"),
            .modifier: Style("#81A1C1"),
            .attribute: Style("#D08770"),
            .preprocessor: Style("#5E81AC"),
            .type: Style("#8FBCBB"),
            .typeBuiltin: Style("#81A1C1"),
            .namespace: Style("#8FBCBB"),
            .function: Style("#88C0D0"),
            .functionCall: Style("#88C0D0"),
            .variableBuiltin: Style("#81A1C1"),
            .property: Style("#D8DEE9"),
            .tag: Style("#81A1C1"),
            .tagAttribute: Style("#8FBCBB"),
            .key: Style("#8FBCBB"),
            .heading: Style("#88C0D0", bold: true),
            .bold: Style(bold: true),
            .italic: Style(italic: true),
            .inlineCode: Style("#A3BE8C"),
            .link: Style("#88C0D0", underline: true),
            .quote: Style("#616E88", italic: true),
            .listMarker: Style("#81A1C1"),
            .inserted: Style("#A3BE8C"),
            .deleted: Style("#BF616A"),
            .changed: Style("#EBCB8B"),
            .diffHeader: Style("#88C0D0", bold: true),
            .diffRange: Style("#B48EAD"),
            .invalid: Style("#BF616A", underline: true),
        ]
    )
}

public extension AdaptiveTheme {
    static let xcode = AdaptiveTheme(light: .xcodeLight, dark: .xcodeDark)
    static let github = AdaptiveTheme(light: .githubLight, dark: .githubDark)
    static let one = AdaptiveTheme(light: .oneLight, dark: .oneDark)
    static let solarized = AdaptiveTheme(light: .solarizedLight, dark: .solarizedDark)
    static let catppuccin = AdaptiveTheme(light: .catppuccinLatte, dark: .catppuccinMocha)
}

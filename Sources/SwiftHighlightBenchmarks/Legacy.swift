// OpenSwift's original single-pass highlighter, for comparison only.
enum LegacyHighlighter {
    enum Language: Sendable, Equatable {
        case swift, javascript, typescript, python, json, shell, go, rust, cFamily, java, kotlin
        case ruby, yaml, toml, css, sql, markup, diff, plain

        /// From a fence label (```swift) or a file extension.
        init(_ raw: String?) {
            switch (raw ?? "").lowercased() {
            case "swift": self = .swift
            case "js", "jsx", "mjs", "cjs", "javascript": self = .javascript
            case "ts", "tsx", "mts", "cts", "typescript": self = .typescript
            case "py", "python", "pyw": self = .python
            case "json", "jsonc", "json5", "jsonl": self = .json
            case "sh", "bash", "zsh", "fish", "shell", "console", "shellsession", "env", "dockerfile", "makefile":
                self = .shell
            case "go", "golang": self = .go
            case "rs", "rust": self = .rust
            case "c", "h", "cc", "cpp", "cxx", "hpp", "hh", "m", "mm", "objc", "objective-c", "cs", "csharp", "c++", "zig":
                self = .cFamily
            case "java", "scala", "groovy", "dart": self = .java
            case "kt", "kts", "kotlin": self = .kotlin
            case "rb", "ruby", "rake", "gemspec": self = .ruby
            case "yml", "yaml": self = .yaml
            case "toml", "ini", "cfg", "conf": self = .toml
            case "css", "scss", "sass", "less": self = .css
            case "sql", "psql", "mysql", "sqlite": self = .sql
            case "html", "htm", "xml", "svg", "plist", "xib", "storyboard", "vue", "svelte": self = .markup
            case "diff", "patch": self = .diff
            default: self = .plain
            }
        }

        fileprivate var keywords: Set<String> {
            switch self {
            case .swift:
                return ["func", "let", "var", "if", "else", "guard", "return", "struct", "class", "enum", "protocol",
                        "extension", "import", "self", "Self", "init", "deinit", "for", "in", "while", "repeat", "switch",
                        "case", "default", "break", "continue", "try", "catch", "throw", "throws", "rethrows", "async",
                        "await", "private", "fileprivate", "public", "internal", "open", "static", "some", "any", "nil",
                        "true", "false", "where", "as", "is", "defer", "typealias", "associatedtype", "inout", "mutating",
                        "nonisolated", "actor", "final", "override", "lazy", "weak", "unowned", "super", "do", "get",
                        "set", "willSet", "didSet", "subscript", "operator", "macro", "consuming", "borrowing", "sending"]
            case .javascript, .typescript:
                return ["function", "const", "let", "var", "if", "else", "return", "class", "extends", "import", "export",
                        "from", "default", "for", "of", "in", "while", "do", "switch", "case", "break", "continue", "try",
                        "catch", "finally", "throw", "async", "await", "new", "this", "super", "null", "undefined", "true",
                        "false", "typeof", "instanceof", "delete", "void", "yield", "static", "get", "set", "interface",
                        "type", "enum", "implements", "private", "public", "protected", "readonly", "as", "satisfies",
                        "declare", "namespace", "keyof", "abstract"]
            case .python:
                return ["def", "class", "if", "elif", "else", "return", "import", "from", "as", "for", "while", "try",
                        "except", "finally", "raise", "with", "lambda", "None", "True", "False", "and", "or", "not", "in",
                        "is", "async", "await", "pass", "break", "continue", "yield", "global", "nonlocal", "del",
                        "assert", "self", "match", "case"]
            case .json:
                return ["true", "false", "null"]
            case .shell:
                return ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until", "case", "esac",
                        "function", "return", "export", "local", "readonly", "echo", "cd", "exit", "set", "unset",
                        "source", "sudo", "FROM", "RUN", "COPY", "ADD", "WORKDIR", "ENV", "CMD", "ENTRYPOINT", "EXPOSE",
                        "ARG", "USER", "VOLUME"]
            case .go:
                return ["func", "package", "import", "var", "const", "type", "struct", "interface", "map", "chan", "if",
                        "else", "for", "range", "return", "switch", "case", "default", "break", "continue", "go",
                        "defer", "select", "fallthrough", "goto", "nil", "true", "false", "iota", "make", "new", "len",
                        "cap", "append", "error"]
            case .rust:
                return ["fn", "let", "mut", "const", "static", "struct", "enum", "trait", "impl", "for", "in", "if",
                        "else", "match", "loop", "while", "return", "break", "continue", "use", "mod", "pub", "crate",
                        "self", "Self", "super", "as", "where", "async", "await", "move", "ref", "dyn", "unsafe",
                        "extern", "type", "true", "false", "Some", "None", "Ok", "Err"]
            case .cFamily:
                return ["int", "char", "float", "double", "void", "long", "short", "unsigned", "signed", "struct",
                        "union", "enum", "typedef", "const", "static", "extern", "return", "if", "else", "for", "while",
                        "do", "switch", "case", "default", "break", "continue", "goto", "sizeof", "include", "define",
                        "ifdef", "ifndef", "endif", "class", "public", "private", "protected", "virtual", "template",
                        "typename", "namespace", "using", "new", "delete", "this", "nullptr", "NULL", "true", "false",
                        "auto", "bool", "inline", "override", "self", "nil", "YES", "NO", "interface", "implementation",
                        "end", "property", "var", "string", "async", "await"]
            case .java, .kotlin:
                return ["class", "interface", "enum", "extends", "implements", "public", "private", "protected",
                        "static", "final", "abstract", "void", "int", "long", "double", "float", "boolean", "char",
                        "byte", "short", "new", "return", "if", "else", "for", "while", "do", "switch", "case",
                        "default", "break", "continue", "try", "catch", "finally", "throw", "throws", "import",
                        "package", "this", "super", "null", "true", "false", "fun", "val", "var", "when", "object",
                        "data", "sealed", "override", "suspend", "companion", "is", "as", "in", "out", "lateinit", "by"]
            case .ruby:
                return ["def", "class", "module", "if", "elsif", "else", "unless", "end", "return", "do", "while",
                        "until", "for", "in", "begin", "rescue", "ensure", "raise", "yield", "self", "nil", "true",
                        "false", "and", "or", "not", "require", "require_relative", "attr_accessor", "attr_reader",
                        "include", "extend", "private", "puts", "lambda", "proc"]
            case .yaml, .toml:
                return ["true", "false", "null", "yes", "no", "on", "off"]
            case .css:
                return ["important", "media", "import", "keyframes", "from", "to", "supports", "font-face"]
            case .sql:
                let words = ["select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create",
                             "table", "drop", "alter", "add", "index", "primary", "key", "foreign", "references", "join",
                             "left", "right", "inner", "outer", "on", "and", "or", "not", "null", "is", "in", "as",
                             "order", "by", "group", "having", "limit", "offset", "distinct", "union", "all", "exists",
                             "case", "when", "then", "else", "end", "default", "unique", "begin", "commit", "rollback"]
                return Set(words + words.map { $0.uppercased() })
            case .markup, .diff, .plain:
                return ["if", "else", "return", "function", "class", "import", "true", "false", "null", "nil"]
            }
        }

        fileprivate var lineComments: [String] {
            switch self {
            case .python, .shell, .ruby, .yaml, .toml: return ["#"]
            case .sql: return ["--"]
            case .json, .markup, .diff: return []
            case .css: return []
            case .plain: return ["//", "#"]
            default: return ["//"]
            }
        }

        fileprivate var blockComment: (open: String, close: String)? {
            switch self {
            case .swift, .javascript, .typescript, .go, .rust, .cFamily, .java, .kotlin, .css, .sql:
                return ("/*", "*/")
            case .markup:
                return ("<!--", "-->")
            default:
                return nil
            }
        }

        fileprivate var colorsKeys: Bool {
            self == .json || self == .yaml || self == .toml
        }
    }

    enum TokenKind: Sendable {
        case plain, keyword, string, number, comment, type, function, attribute, added, removed, meta
    }

    struct Token: Sendable, Equatable {
        var text: String
        var kind: TokenKind
    }

    // MARK: - Tokeniser

    static func tokenize(_ line: String, language: Language, inBlockComment: inout Bool) -> [Token] {
        guard !line.isEmpty else { return [] }

        if language == .diff {
            let kind: TokenKind = line.hasPrefix("+") ? .added : line.hasPrefix("-") ? .removed : line.hasPrefix("@@") ? .meta : .plain
            return [Token(text: line, kind: kind)]
        }
        // Minified bundles and long log lines have no structure worth the pass.
        if line.utf8.count > 2_000 {
            return [Token(text: line, kind: .plain)]
        }

        let characters = Array(line)
        var tokens: [Token] = []
        var pending = ""
        var index = 0

        func flush() {
            guard !pending.isEmpty else { return }
            tokens.append(Token(text: pending, kind: .plain))
            pending = ""
        }

        func matches(_ marker: String, at position: Int) -> Bool {
            let marks = Array(marker)
            guard position + marks.count <= characters.count else { return false }
            for offset in 0..<marks.count where characters[position + offset] != marks[offset] {
                return false
            }
            return true
        }

        func nextNonSpace(after position: Int) -> Character? {
            var scan = position
            while scan < characters.count, characters[scan] == " " || characters[scan] == "\t" { scan += 1 }
            return scan < characters.count ? characters[scan] : nil
        }

        while index < characters.count {
            if inBlockComment, let block = language.blockComment {
                var comment = ""
                while index < characters.count {
                    if matches(block.close, at: index) {
                        comment += block.close
                        index += block.close.count
                        inBlockComment = false
                        break
                    }
                    comment.append(characters[index])
                    index += 1
                }
                tokens.append(Token(text: comment, kind: .comment))
                continue
            }

            let character = characters[index]

            if let block = language.blockComment, matches(block.open, at: index) {
                flush()
                inBlockComment = true
                tokens.append(Token(text: block.open, kind: .comment))
                index += block.open.count
                continue
            }

            if let marker = language.lineComments.first(where: { matches($0, at: index) }) {
                // `#` inside a shell word (`a#b`) or a URL fragment is not a comment.
                let previous = index > 0 ? characters[index - 1] : " "
                if marker != "#" || previous == " " || previous == "\t" || index == 0 {
                    flush()
                    tokens.append(Token(text: String(characters[index...]), kind: .comment))
                    return tokens
                }
            }

            if character == "\"" || character == "'" || character == "`" {
                // An apostrophe in prose-like languages is usually not a string opener.
                if character == "'", language == .plain || language == .markup {
                    pending.append(character)
                    index += 1
                    continue
                }
                flush()
                var literal = String(character)
                var scan = index + 1
                while scan < characters.count {
                    let next = characters[scan]
                    literal.append(next)
                    if next == "\\", scan + 1 < characters.count {
                        literal.append(characters[scan + 1])
                        scan += 2
                        continue
                    }
                    scan += 1
                    if next == character { break }
                }
                let isKey = language.colorsKeys && nextNonSpace(after: scan) == ":"
                tokens.append(Token(text: literal, kind: isKey ? .type : .string))
                index = scan
                continue
            }

            if character == "@" || (character == "#" && language == .swift) {
                var scan = index + 1
                var word = String(character)
                while scan < characters.count, characters[scan].isLetter || characters[scan].isNumber || characters[scan] == "_" {
                    word.append(characters[scan])
                    scan += 1
                }
                if word.count > 1 {
                    flush()
                    tokens.append(Token(text: word, kind: .attribute))
                    index = scan
                    continue
                }
            }

            if character.isLetter || character == "_" || character == "$" {
                flush()
                var word = ""
                var scan = index
                while scan < characters.count,
                      characters[scan].isLetter || characters[scan].isNumber || characters[scan] == "_" || characters[scan] == "$"
                        || (language == .css && characters[scan] == "-") {
                    word.append(characters[scan])
                    scan += 1
                }
                let kind: TokenKind
                if language.keywords.contains(word) {
                    kind = .keyword
                } else if language.colorsKeys, nextNonSpace(after: scan) == ":" || nextNonSpace(after: scan) == "=" {
                    kind = .type
                } else if scan < characters.count, characters[scan] == "(" {
                    kind = .function
                } else if let first = word.first, first.isUppercase, word.count > 1 {
                    kind = .type
                } else {
                    kind = .plain
                }
                tokens.append(Token(text: word, kind: kind))
                index = scan
                continue
            }

            if character.isNumber {
                let previous = index > 0 ? characters[index - 1] : " "
                if !(previous.isLetter || previous == "_") {
                    flush()
                    var number = ""
                    var scan = index
                    while scan < characters.count,
                          characters[scan].isHexDigit || characters[scan] == "." || characters[scan] == "x"
                            || characters[scan] == "_" || characters[scan] == "o" || characters[scan] == "b" {
                        number.append(characters[scan])
                        scan += 1
                    }
                    tokens.append(Token(text: number, kind: .number))
                    index = scan
                    continue
                }
            }

            pending.append(character)
            index += 1
        }

        flush()
        return tokens
    }
}


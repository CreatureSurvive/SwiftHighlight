@testable import SwiftHighlight
import Testing

@Suite("Built-in languages")
struct LanguageTests {
    @Test(arguments: BuiltinGrammars.all)
    func compiles(_ grammar: Grammar) throws {
        let language = try Language(grammar)
        #expect(language.id == grammar.id)
        // The registry must hand out the same definition.
        #expect(LanguageRegistry.shared.language(named: grammar.id)?.grammar == grammar)
    }

    @Test func idsAndAliasesAreUnique() {
        var seen: [String: String] = [:]
        for grammar in BuiltinGrammars.all {
            for name in [grammar.id] + grammar.aliases {
                let key = name.lowercased()
                #expect(seen[key] == nil, "\(key) claimed by \(seen[key] ?? "") and \(grammar.id)")
                seen[key] = grammar.id
            }
        }
    }

    /// One sample per language: (language, code, [text: scope]) — each text's first token must
    /// have exactly that scope.
    static let samples: [(String, String, [String: String])] = [
        ("c", """
        #include <stdio.h>
        /* block */ int main(void) { // line
            size_t n = 0x1F; char c = '\\n';
            printf("%d\\n", MAX_SIZE);
            return 0;
        }
        """, ["#include": "meta.preprocessor", "<stdio.h>": "string", "/* block */": "comment.block",
              "int": "storage.type", "size_t": "support.type", "0x1F": "constant.numeric", "'\\n'": "constant.character",
              "printf": "support.function", "\"%d": "string", "\\n": "constant.character.escape",
              "MAX_SIZE": "constant.other", "return": "keyword.control", "// line": "comment.line"]),
        ("cpp", """
        namespace app { template <typename T> class Box final : public Base {
            auto s = R"x(raw "text")x"; std::vector<int> v; this->run(nullptr);
        }; }
        """, ["namespace": "storage.type", "Box": "entity.name.type", "final": "storage.modifier",
              "R\"x(raw \"text\")x\"": "string", "std": "entity.name.namespace", "this": "variable.language",
              "run": "support.function", "nullptr": "constant.language"]),
        ("objective-c", """
        @interface Foo : NSObject
        @property (nonatomic, strong) NSString *name;
        - (void)doThing:(int)x { [self doOther:@"hi" count:@3]; return YES; }
        @end
        """, ["@interface": "keyword", "NSObject": "entity.name.type", "nonatomic": "storage.modifier",
              "@\"hi\"": "string", "self": "variable.language", "doOther": "support.function", "YES": "constant.language",
              "@end": "keyword"]),
        ("csharp", """
        [Serializable]
        public sealed record Person(string Name) {
            var s = $"Hi {Name.ToUpper()}!"; var v = @"C:\\path"; // done
        }
        """, ["Serializable": "storage.modifier.attribute", "public": "storage.modifier", "record": "storage.type",
              "Person": "entity.name.type", "string": "support.type", "$\"Hi ": "string",
              "{": "punctuation.section.embedded", "ToUpper": "support.function", "@\"C:\\path\"": "string",
              "// done": "comment.line"]),
        ("java", """
        @Override public static void main(String[] args) { var x = 1.5e3; String t = \"\"\"
            block\"\"\"; }
        """, ["@Override": "storage.modifier.attribute", "static": "storage.modifier", "void": "storage.type",
              "main": "support.function", "String": "entity.name.type", "1.5e3": "constant.numeric",
              "    block\"\"\"": "string"]),
        ("kotlin", """
        data class User(val name: String) { fun greet() = "Hi ${name.length} $name" }
        """, ["data": "storage.type", "User": "entity.name.type", "val": "storage.type", "greet": "entity.name.function",
              "\"Hi ": "string", "${": "punctuation.section.embedded", "$name": "variable"]),
        ("dart", """
        @override Widget build(BuildContext context) => Text('Hi $name ${x + 1}', style: r'raw\\n');
        """, ["@override": "storage.modifier.attribute", "Widget": "entity.name.type", "build": "support.function",
              "'Hi ": "string", "$name": "variable", "r'raw\\n'": "string"]),
        ("go", """
        package main
        func (s *Server) Handle(w http.ResponseWriter) error { defer close(ch); x := `raw
        string`; return nil }
        """, ["package": "storage.type", "Handle": "entity.name.function", "error": "support.type",
              "defer": "keyword.control", "close": "support.function.builtin", "`raw": "string", "nil": "constant.language"]),
        ("rust", """
        #[derive(Debug)]
        pub fn parse<'a>(s: &'a str) -> Result<u32, Error> { let r = r#"raw "x""#; println!("{}", s); Ok(1u32) }
        """, ["#[derive(Debug)]": "storage.modifier.attribute", "pub": "storage.modifier", "parse": "entity.name.function",
              "'a": "entity.name.label", "str": "support.type", "r#\"raw \"x\"\"#": "string",
              "println!": "support.function", "Ok": "constant.language", "1u32": "constant.numeric"]),
        ("javascript", """
        import React from 'react';
        const re = /ab+c/gi, n = 10 / 2;
        export default function App({ title }) { return <div className="x">{title}</div>; }
        const tpl = `a ${b + `c ${d}`} e`;
        """, ["import": "storage.type", "'react'": "string", "/ab+c/gi": "string.regexp", "App": "entity.name.function",
              "div": "entity.name.tag", "className": "entity.other.attribute-name", "\"x\"": "string",
              "`a ": "string", "${": "punctuation.section.embedded"]),
        ("typescript", """
        interface Props { name: string; readonly id?: number }
        type T = keyof Props; const f = async (x: T): Promise<void> => { await g<T>(x); };
        """, ["interface": "storage.type", "Props": "entity.name.type", "string": "support.type",
              "readonly": "storage.modifier", "keyof": "storage.type", "f": "entity.name.function", "await": "keyword.control"]),
        ("json", """
        {"name": "swift", "version": 1.5e2, "ok": true, "none": null, "esc": "a\\u00e9b"}
        """, ["\"name\"": "support.type.property-name", "\"swift\"": "string", "1.5e2": "constant.numeric",
              "true": "constant.language", "null": "constant.language", "\\u00e9": "constant.character.escape"]),
        ("html", """
        <!DOCTYPE html>
        <div class="a" data-x='y'>Hi &amp; bye<!-- note --></div>
        <script type="module">const x = 1; // js
        </script><style>.a { color: #fff; }</style>
        """, ["<!DOCTYPE html>": "meta.preprocessor", "div": "entity.name.tag", "class": "entity.other.attribute-name",
              "\"a\"": "string", "&amp;": "constant.character.escape", "<!-- note -->": "comment.block",
              "const": "storage.type", "// js": "comment.line", ".a": "entity.other.attribute-name",
              "color": "support.type.property-name", "#fff": "constant.other", "script": "entity.name.tag"]),
        ("xml", """
        <?xml version="1.0"?>
        <plist version="1.0"><dict><key>A</key><![CDATA[ raw ]]></dict></plist>
        """, ["<?xml version=\"1.0\"?>": "meta.preprocessor", "plist": "entity.name.tag", "version": "entity.other.attribute-name",
              " raw ": "string"]),
        ("css", """
        @media (max-width: 600px) { .card > a:hover, #main { margin: -4px 0 !important; color: rgb(0 0 0 / 50%); } }
        """, ["@media": "keyword", ".card": "entity.other.attribute-name", ":hover": "keyword", "#main": "constant.other",
              "margin": "support.type.property-name", "-4px": "constant.numeric", "!important": "keyword",
              "rgb": "support.function"]),
        ("scss", """
        $primary: #333; // comment
        .btn { &:hover { color: darken($primary, 10%); } .icon-#{$name} { @include size(2px); } }
        """, ["$primary": "variable", "// comment": "comment.line", "&:hover": "keyword", "darken": "support.function",
              "#{": "punctuation.section.embedded", "@include": "keyword"]),
        ("graphql", """
        query GetUser($id: ID!) @cached { user(id: $id) { name } } # c
        """, ["query": "storage.type", "GetUser": "entity.name.type", "$id": "variable", "ID": "entity.name.type",
              "@cached": "storage.modifier.attribute", "# c": "comment.line"]),
        ("python", """
        @dataclass
        class Point(Base):
            def dist(self, other) -> float:  # comment
                return f"{self.x!r:>10} {{literal}}" + rb'\\d' + '''multi
        line''' + len(x) if True else None
        """, ["@dataclass": "storage.modifier.attribute", "class": "storage.type", "Point": "entity.name.type",
              "dist": "entity.name.function", "self": "variable.language", "# comment": "comment.line",
              "f\"": "string", "{": "punctuation.section.embedded", "{{": "constant.character.escape",
              "rb'\\d'": "string", "line'''": "string", "len": "support.function.builtin", "True": "constant.language",
              "if": "keyword.control"]),
        ("ruby", """
        class Foo < Bar
          attr_reader :name
          def valid?(x) = x.empty? && @count > 0 # check
          puts "Hi #{name.upcase}", key: :sym, re: /a+b/i
        end
        """, ["class": "storage.type", "Foo": "entity.name.type", "attr_reader": "storage.type", ":name": "constant.other",
              "valid?": "entity.name.function", "empty?": "support.function", "@count": "variable",
              "# check": "comment.line", "\"Hi ": "string", "#{": "punctuation.section.embedded", "key:": "constant.other",
              "/a+b/i": "string.regexp", "end": "keyword.control"]),
        ("php", """
        <?php
        #[Route('/x')]
        final class A { public function run(int $n): ?string { return "n=$n {$this->x}"; } }
        """, ["<?php": "meta.preprocessor", "#[Route('/x')]": "storage.modifier.attribute", "final": "storage.modifier",
              "run": "entity.name.function", "int": "support.type", "$n": "variable", "\"n=": "string"]),
        ("lua", """
        local function greet(name) --[==[ long
        comment ]==] return "hi " .. name end
        print([[raw]], #t)
        """, ["local": "storage.type", "greet": "entity.name.function", "--[==[ long": "comment.block",
              "comment ]==]": "comment.block", "\"hi \"": "string", "print": "support.function.builtin", "[[raw]]": "string"]),
        ("shell", """
        #!/bin/bash
        # comment
        NAME="world ${USER:-me} $(date +%s)"
        if [ -f "$FILE" ]; then echo 'single' | grep a#b; fi
        cat <<EOF
        heredoc $body
        EOF
        """, ["#!/bin/bash": "comment.line", "# comment": "comment.line", "NAME": "variable", "\"world ": "string",
              "${": "punctuation.section.embedded", "$(": "punctuation.section.embedded", "if": "keyword.control",
              "\"": "string", "$FILE": "variable", "echo": "support.function.builtin", "'single'": "string",
              "<<EOF": "keyword.operator", "heredoc $body": "string", "EOF": "keyword.operator"]),
        ("yaml", """
        # config
        name: "app" # trailing
        list:
          - key: value
            count: 42
            enabled: true
        anchor: &base
        """, ["# config": "comment.line", "name": "support.type.property-name", "\"app\"": "string",
              "# trailing": "comment.line", "- ": "punctuation.definition.list", "key": "support.type.property-name",
              "42": "constant.numeric", "true": "constant.language", "&base": "variable"]),
        ("toml", """
        [package]
        name = "demo" # c
        version.major = 1_000
        date = 2024-01-02T03:04:05Z
        [[bin]]
        """, ["package": "entity.name.type", "name": "support.type.property-name", "\"demo\"": "string",
              "version.major": "support.type.property-name", "1_000": "constant.numeric",
              "2024-01-02T03:04:05Z": "constant.other", "bin": "entity.name.type"]),
        ("ini", """
        ; comment
        [section]
        key = value
        enabled=true
        """, ["; comment": "comment.line", "section": "entity.name.type", "key": "support.type.property-name",
              "true": "constant.language"]),
        ("sql", """
        SELECT u.id, COUNT(*) AS n FROM users u -- comment
        WHERE u.name = 'O''Brien' AND created_at > $1 /* block */ LIMIT 10;
        """, ["SELECT": "keyword", "COUNT": "support.function", "AS": "keyword", "-- comment": "comment.line",
              "'O": "string", "''": "constant.character.escape", "$1": "variable", "/* block */": "comment.block",
              "10": "constant.numeric"]),
        ("protobuf", """
        syntax = "proto3";
        message User { repeated string tags = 1; }
        service Api { rpc Get(Req) returns (User); }
        """, ["syntax": "storage.type", "message": "storage.type", "User": "entity.name.type", "repeated": "storage.modifier",
              "string": "support.type", "Get": "entity.name.function"]),
        ("dockerfile", """
        # syntax=docker/dockerfile:1
        FROM swift:6.0 AS build
        RUN apt-get update && echo "$HOME" # c
        COPY --from=build /app /app
        """, ["# syntax=docker/dockerfile:1": "meta.preprocessor", "FROM": "keyword", "AS": "keyword", "RUN": "keyword",
              "echo": "support.function.builtin", "\"": "string", "$HOME": "variable", "--from": "entity.other.attribute-name"]),
        ("makefile", """
        CC := clang
        build: main.o # comment
        \t$(CC) -o $@ $(wildcard *.c)
        ifeq ($(OS),Darwin)
        endif
        """, ["CC": "variable", "build": "entity.name.function", "# comment": "comment.line", "$(": "punctuation.section.embedded",
              "$@": "variable", "wildcard": "support.function.builtin", "ifeq": "keyword"]),
        ("diff", """
        diff --git a/x b/x
        --- a/x
        +++ b/x
        @@ -1,2 +1,2 @@ func
        -old
        +new
         same
        """, ["diff --git a/x b/x": "meta.diff.header", "--- a/x": "meta.diff.header", "@@ -1,2 +1,2 @@": "meta.diff.range",
              "-old": "markup.deleted", "+new": "markup.inserted"]),
        ("markdown", """
        # Title
        Some **bold**, *italic*, `code`, snake_case_word and [link](https://x.com "t").
        > quote
        - item
        ```swift
        let x = 1
        ```
        """, ["# Title": "markup.heading", "**bold**": "markup.bold", "*italic*": "markup.italic", "`code`": "markup.inline.raw",
              "link": "string.other", "https://x.com": "markup.underline.link", "quote": "markup.quote",
              "-": "punctuation.definition.list", "```": "punctuation", "swift": "entity.name.label",
              "let": "storage.type", "1": "constant.numeric"]),
    ]

    @Test(arguments: samples.indices)
    func sample(_ index: Int) {
        let (id, code, expectations) = Self.samples[index]
        let language = builtin(id)
        let tokens = language.tokenize(code)
        #expect(validate(tokens, in: code), "\(id): invalid tokens")
        for (text, expected) in expectations.sorted(by: { $0.key < $1.key }) {
            let actual = tokens.first { $0.text(in: code) == text }?.scope.name
            #expect(actual == expected, "\(id): \(text.debugDescription) is \(actual ?? "unscoped"), expected \(expected)")
        }
    }

    @Test func markdownIgnoresIntrawordUnderscores() {
        let code = "snake_case_word and __init__ too"
        #expect(!pairs(code, builtin("markdown")).contains { $0.contains("markup.italic") })
    }

    @Test func htmlScriptEndsAtClosingTag() {
        let code = "<script>let s = \"</script>\"; x</script><p>after</p>"
        let pairs = pairs(code, builtin("html"))
        #expect(pairs.contains("p→entity.name.tag"))
    }

    @Test func unknownFenceLanguageIsPlain() {
        let code = "```nosuchlang\nif x\n```\n# after"
        let pairs = pairs(code, builtin("markdown"))
        #expect(pairs.contains("# after→markup.heading"))
        #expect(!pairs.contains { $0.hasPrefix("if→") })
    }

    /// Every built-in grammar must tokenize its sample identically with and without
    /// auto-possessification.
    @Test func possessificationPreservesTokens() throws {
        for (id, code, _) in Self.samples {
            let grammar = try #require(Grammar.builtin(id))
            let plain = try Language(grammar, possessify: false)
            #expect(builtin(id).tokenize(code) == plain.tokenize(code), "\(id)")
        }
    }
}

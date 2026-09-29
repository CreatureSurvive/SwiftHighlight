# ``SwiftHighlight``

Fast, pure-Swift syntax highlighting with declarative grammars, themes, and incremental updates.

## Overview

SwiftHighlight tokenizes source code with compiled ``Grammar`` definitions and renders the result
for SwiftUI, UIKit, AppKit, HTML, or a terminal.

```swift
let code = Language.swift.highlight(source)
Text(code.attributedString(theme: .xcode))
```

Grammars are `Codable` state machines whose rules match a line-anchored regular-expression
dialect compiled to bytecode. Themes map TextMate-style ``Scope`` names to ``Style`` values and can
be imported from VS Code and TextMate. ``HighlightSession`` keeps highlighting current as text is
edited or streamed, re-tokenizing only the lines whose state changed.

## Topics

### Highlighting

- ``Language``
- ``LanguageRegistry``
- ``HighlightedCode``
- ``Token``
- ``Scope``

### Incremental Highlighting

- ``HighlightSession``
- ``LineTokenizer``
- ``LineState``

### Themes

- ``Theme``
- ``AdaptiveTheme``
- ``Style``
- ``ResolvedStyle``
- ``ThemeColor``
- ``ThemeImportError``

### Rendering

- ``CodeView``
- ``HTMLOptions``
- ``ANSIColors``

### Defining Languages

- ``Grammar``
- ``GrammarState``
- ``Rule``
- ``GrammarError``
- ``PatternError``

---
name: parser-regex
description: Dart regex patterns, tokenization, and text processing -- RegExp API, named capture groups, multi-line/dotAll modes, lexer construction, ASCII art parsing, Unicode-aware patterns, and performance optimization for parser/compiler pipelines
---

# Dart Regex & Text Processing for Parsers

Comprehensive guide to Dart's `RegExp` class and text processing utilities for building parsers, lexers, and tokenizers. Covers the full RegExp API, named capture groups, backreferences, multi-line and dot-all modes, tokenization strategies, ASCII art pattern matching, Unicode-aware regex, performance tuning, and common patterns for wireframe/ASCII parsing pipelines.

## Table of Contents

1. [RegExp Class API and Usage](#regexp-class-api-and-usage)
2. [Named Capture Groups and Backreferences](#named-capture-groups-and-backreferences)
3. [Multi-Line and Dot-All Modes](#multi-line-and-dot-all-modes)
4. [Text Processing Utilities](#text-processing-utilities)
5. [Tokenization with Regex: Building a Lexer](#tokenization-with-regex-building-a-lexer)
6. [Pattern Matching for ASCII Art Characters](#pattern-matching-for-ascii-art-characters)
7. [Common Tokenization Patterns for Wireframe/ASCII Parsing](#common-tokenization-patterns-for-wireframeascii-parsing)
8. [Unicode-Aware Regex in Dart](#unicode-aware-regex-in-dart)
9. [Performance: Precompiled Patterns and Avoiding Catastrophic Backtracking](#performance-precompiled-patterns-and-avoiding-catastrophic-backtracking)
10. [Best Practices](#best-practices)
11. [Anti-Patterns](#anti-patterns)
12. [Sources & References](#sources--references)

---

## RegExp Class API and Usage

### Constructor

Dart's `RegExp` constructor accepts a source pattern string and four optional named boolean parameters:

```
RegExp(
  String source, {
  bool multiLine = false,
  bool caseSensitive = true,
  bool unicode = false,
  bool dotAll = false,
})
```

Always use raw strings (`r'...'`) for patterns to avoid double-escaping backslashes.

### Core Properties

| Property        | Type   | Description                                               |
|-----------------|--------|-----------------------------------------------------------|
| `pattern`       | String | The source pattern string                                 |
| `isMultiLine`   | bool   | Whether `^` and `$` match line boundaries                 |
| `isCaseSensitive` | bool | Whether matching is case-sensitive                        |
| `isUnicode`     | bool   | Whether Unicode mode is enabled                           |
| `isDotAll`      | bool   | Whether `.` matches line terminators                      |

### Core Methods

| Method                        | Return Type              | Description                                                |
|-------------------------------|--------------------------|------------------------------------------------------------|
| `hasMatch(String input)`      | `bool`                   | Returns true if any part of input matches                  |
| `firstMatch(String input)`    | `RegExpMatch?`           | Returns the first match or null                            |
| `allMatches(String input, [int start])` | `Iterable<RegExpMatch>` | Returns all non-overlapping matches              |
| `stringMatch(String input)`   | `String?`                | Returns the matched substring of the first match           |
| `matchAsPrefix(String input, [int start])` | `Match?`    | Matches the pattern only at the start position             |

### RegExpMatch Properties

| Property / Method               | Type              | Description                                       |
|----------------------------------|-------------------|---------------------------------------------------|
| `group(int index)` / `[int]`    | `String?`         | Returns the numbered capture group                |
| `namedGroup(String name)`        | `String?`         | Returns the named capture group value             |
| `groupNames`                     | `Iterable<String>`| All named group names in the pattern              |
| `groupCount`                     | `int`             | Number of capture groups (excluding group 0)      |
| `start`                          | `int`             | Start index of the match in the input             |
| `end`                            | `int`             | End index of the match in the input               |
| `input`                          | `String`          | The original input string                         |

### Basic Usage

```dart
// Simple pattern check
final emailPattern = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.]+$');
print(emailPattern.hasMatch('user@example.com')); // true

// First match extraction
final digits = RegExp(r'\d+');
final match = digits.firstMatch('Order #1234 shipped');
if (match != null) {
  print(match.group(0)); // '1234'
  print(match.start);    // 7
  print(match.end);      // 11
}

// All matches iteration
final words = RegExp(r'[A-Za-z]+');
for (final m in words.allMatches('Hello, World! 42')) {
  print(m[0]); // 'Hello', 'World'
}

// matchAsPrefix: anchored to a position
final tag = RegExp(r'<(\w+)>');
final prefixMatch = tag.matchAsPrefix('<div> content');
if (prefixMatch != null) {
  print(prefixMatch.group(1)); // 'div'
}
```

---

## Named Capture Groups and Backreferences

### Named Groups Syntax

Dart uses the `(?<name>...)` syntax for named capture groups, consistent with ECMAScript 2018.

```dart
final datePattern = RegExp(
  r'(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})',
);

final match = datePattern.firstMatch('2026-02-25');
if (match != null) {
  final year = match.namedGroup('year');   // '2026'
  final month = match.namedGroup('month'); // '02'
  final day = match.namedGroup('day');     // '25'

  // Also accessible by index
  assert(match.group(1) == year);
  assert(match.group(2) == month);
  assert(match.group(3) == day);

  // Enumerate all named groups
  for (final name in match.groupNames) {
    print('$name: ${match.namedGroup(name)}');
  }
}
```

### Backreferences

Numbered backreferences use `\1`, `\2`, etc. Named backreferences use `\k<name>`.

```dart
// Detect repeated words with a numbered backreference
final repeatedWord = RegExp(r'\b(\w+)\s+\1\b', caseSensitive: false);
print(repeatedWord.hasMatch('the the cat')); // true

// Named backreference for matching balanced quotes
final quotedString = RegExp(r'''(?<quote>['"])(?<content>.*?)\k<quote>''');
final qm = quotedString.firstMatch('"hello world"');
if (qm != null) {
  print(qm.namedGroup('content')); // 'hello world'
}
```

### Multiple Named Groups for Token Parsing

```dart
/// Pattern that matches several token types in a single pass.
/// Each alternative is a named group so the caller can determine
/// which branch matched.
final tokenPattern = RegExp(
  r'(?<number>\b\d+(?:\.\d+)?\b)'
  r'|(?<string>"(?:[^"\\]|\\.)*")'
  r'|(?<ident>[A-Za-z_]\w*)'
  r'|(?<op>[+\-*/=<>!]+)'
  r'|(?<punc>[(){}\[\];,.])',
);

for (final m in tokenPattern.allMatches('x = 42 + "hello"')) {
  for (final name in m.groupNames) {
    final value = m.namedGroup(name);
    if (value != null) {
      print('$name: $value');
      break;
    }
  }
}
// Output:
// ident: x
// op: =
// number: 42
// op: +
// string: "hello"
```

---

## Multi-Line and Dot-All Modes

### Multi-Line Mode (`multiLine: true`)

When enabled, `^` matches the start of each line (after `\n`) and `$` matches the end of each line (before `\n`), in addition to the start and end of the entire input.

```dart
final lineStartPattern = RegExp(r'^\s*#.*$', multiLine: true);
const input = '''
  # This is a comment
  name: parser-regex
  # Another comment
  version: 1.0
''';

final comments = lineStartPattern.allMatches(input).map((m) => m[0]!.trim());
print(comments.toList());
// ['# This is a comment', '# Another comment']
```

Without `multiLine: true`, the `^` only matches position 0 of the string and `$` only matches the very end.

### Dot-All Mode (`dotAll: true`)

By default, `.` matches any character except line terminators (`\n`, `\r`, etc.). With `dotAll: true`, `.` matches every character including newlines.

```dart
// Extract multi-line block between markers
final blockPattern = RegExp(
  r'BEGIN\n(.*?)\nEND',
  dotAll: true,
);
const source = '''
BEGIN
line one
line two
line three
END
''';

final block = blockPattern.firstMatch(source);
if (block != null) {
  print(block.group(1));
  // 'line one\nline two\nline three'
}
```

### Combining Modes

All four flags can be combined. A common parser scenario is extracting structured blocks from multi-line input:

```dart
final sectionPattern = RegExp(
  r'^##\s+(?<title>.+)$\n(?<body>.*?)(?=^##|\Z)',
  multiLine: true,
  dotAll: true,
);

const markdown = '''
## Introduction
Welcome to the parser guide.
This covers regex basics.

## API Reference
The RegExp class provides...
''';

for (final m in sectionPattern.allMatches(markdown)) {
  print('Title: ${m.namedGroup("title")}');
  print('Body length: ${m.namedGroup("body")!.trim().length}');
  print('---');
}
```

---

## Text Processing Utilities

Dart's `String` class provides several methods that accept `Pattern` (the interface `RegExp` implements).

### `split(Pattern pattern)`

Splits the string at each match of the pattern and returns a `List<String>`.

```dart
// Split on any whitespace sequence
final parts = 'hello   world\tfoo\nbar'.split(RegExp(r'\s+'));
print(parts); // ['hello', 'world', 'foo', 'bar']

// Split a CSV line respecting quoted fields
final csvField = RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*$)');
final fields = '"Smith, John",42,"New York"'.split(csvField);
print(fields); // ['"Smith, John"', '42', '"New York"']
```

### `replaceAll(Pattern from, String replace)`

Replaces all non-overlapping matches of `from` with `replace`.

```dart
// Normalize whitespace
final normalized = '  too   many   spaces  '.replaceAll(RegExp(r'\s+'), ' ').trim();
print(normalized); // 'too many spaces'
```

### `replaceAllMapped(Pattern from, String Function(Match) replace)`

Replaces each match using a function that receives the `Match` object. Critical for transformations that depend on the matched content.

```dart
// Convert snake_case to camelCase
String snakeToCamel(String input) {
  return input.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (match) => match.group(1)!.toUpperCase(),
  );
}

print(snakeToCamel('my_variable_name')); // 'myVariableName'

// Escape HTML entities
String escapeHtml(String input) {
  return input.replaceAllMapped(
    RegExp(r'[&<>"' "'" r']'),
    (match) => switch (match[0]!) {
      '&'  => '&amp;',
      '<'  => '&lt;',
      '>'  => '&gt;',
      '"'  => '&quot;',
      "'"  => '&#39;',
      _    => match[0]!,
    },
  );
}
```

### `replaceFirstMapped(Pattern from, String Function(Match) replace, [int startIndex])`

Same as `replaceAllMapped` but only replaces the first match.

### `allMatches` for Iteration

`RegExp.allMatches` returns a lazy `Iterable<RegExpMatch>`. You can chain it with standard collection operations:

```dart
final pattern = RegExp(r'\b[A-Z][a-z]+\b');
final capitalized = pattern
    .allMatches('Alice met Bob at the Park')
    .map((m) => m[0]!)
    .toList();
print(capitalized); // ['Alice', 'Bob', 'Park']
```

### `contains(Pattern other)`

Simple boolean check whether a string contains a match.

```dart
if ('Error: file not found'.contains(RegExp(r'Error|Warning'))) {
  print('Log contains an issue');
}
```

### `splitMapJoin(Pattern, {onMatch, onNonMatch})`

Processes a string by splitting on matches and rebuilding with callbacks.

```dart
// Wrap all numbers in brackets
final result = 'order 42 and item 7'.splitMapJoin(
  RegExp(r'\d+'),
  onMatch: (m) => '[${m[0]}]',
  onNonMatch: (s) => s,
);
print(result); // 'order [42] and item [7]'
```

---

## Tokenization with Regex: Building a Lexer

### Token Definition

Define token types as an enum and create a `Token` class:

```dart
enum TokenType {
  keyword,
  identifier,
  intLiteral,
  floatLiteral,
  stringLiteral,
  operator,
  punctuation,
  whitespace,
  comment,
  newline,
  unknown,
}

class Token {
  final TokenType type;
  final String lexeme;
  final int offset;
  final int line;
  final int column;

  const Token({
    required this.type,
    required this.lexeme,
    required this.offset,
    required this.line,
    required this.column,
  });

  @override
  String toString() => 'Token($type, ${repr(lexeme)}, L$line:$column)';

  static String repr(String s) =>
      '"${s.replaceAll('\n', '\\n').replaceAll('\t', '\\t')}"';
}
```

### Lexer Implementation with Combined Pattern

Build a single combined regex with named groups for each token type. The lexer walks the input, matching at each position, and produces a stream of tokens.

```dart
class RegexLexer {
  /// Each entry maps a named capture group to a [TokenType].
  static final List<(String name, String pattern, TokenType type)> _rules = [
    ('comment',   r'//[^\n]*',                           TokenType.comment),
    ('keyword',   r'\b(?:if|else|while|for|return|var|final|class|void)\b',
                                                          TokenType.keyword),
    ('float',     r'\b\d+\.\d+\b',                       TokenType.floatLiteral),
    ('int',       r'\b\d+\b',                             TokenType.intLiteral),
    ('string',    r'"(?:[^"\\]|\\.)*"',                   TokenType.stringLiteral),
    ('ident',     r'[A-Za-z_]\w*',                        TokenType.identifier),
    ('op',        r'[+\-*/%=<>!&|^~]+',                   TokenType.operator),
    ('punc',      r'[(){}\[\];,.]',                       TokenType.punctuation),
    ('newline',   r'\n',                                  TokenType.newline),
    ('ws',        r'[ \t\r]+',                            TokenType.whitespace),
  ];

  /// Combined pattern: each rule becomes a named alternative.
  static final RegExp _combinedPattern = RegExp(
    _rules.map((r) => '(?<${r.$1}>${r.$2})').join('|'),
  );

  /// Map from group name to token type for quick lookup.
  static final Map<String, TokenType> _typeMap = {
    for (final r in _rules) r.$1: r.$3,
  };

  /// Tokenize the entire [source] string. Throws on unexpected characters.
  List<Token> tokenize(String source) {
    final tokens = <Token>[];
    var pos = 0;
    var line = 1;
    var lineStart = 0;

    while (pos < source.length) {
      final match = _combinedPattern.matchAsPrefix(source, pos);
      if (match == null) {
        final col = pos - lineStart + 1;
        throw FormatException(
          'Unexpected character "${source[pos]}" at L$line:$col',
        );
      }

      // Determine which named group matched
      TokenType? type;
      for (final name in match.groupNames) {
        if (match.namedGroup(name) != null) {
          type = _typeMap[name];
          break;
        }
      }

      final lexeme = match[0]!;
      final col = pos - lineStart + 1;
      tokens.add(Token(
        type: type ?? TokenType.unknown,
        lexeme: lexeme,
        offset: pos,
        line: line,
        column: col,
      ));

      // Track line/column
      if (lexeme == '\n') {
        line++;
        lineStart = pos + 1;
      }

      pos = match.end;
    }

    return tokens;
  }
}

// Usage:
void main() {
  final lexer = RegexLexer();
  final tokens = lexer.tokenize('var x = 42 + 3.14; // sum');

  for (final t in tokens.where((t) => t.type != TokenType.whitespace)) {
    print(t);
  }
  // Token(keyword, "var", L1:1)
  // Token(identifier, "x", L1:5)
  // Token(operator, "=", L1:7)
  // Token(intLiteral, "42", L1:9)
  // Token(operator, "+", L1:12)
  // Token(floatLiteral, "3.14", L1:14)
  // Token(punctuation, ";", L1:18)
  // Token(comment, "// sum", L1:20)
}
```

### Lexer Design Principles

- **Order matters**: Place longer/more-specific patterns before shorter/more-general ones. For example, `float` before `int`, `keyword` before `ident`.
- **Use `matchAsPrefix`**: Anchors matching at the current position, preventing the engine from scanning ahead and producing incorrect offsets.
- **Single combined pattern**: Avoids trying each rule separately, which multiplies the number of regex evaluations per character.
- **Track line and column**: Essential for error messages. Increment the line counter on every `\n` token.

---

## Pattern Matching for ASCII Art Characters

### ASCII Box-Drawing Patterns

Match pipes, dashes, plus signs, corners, and T-junctions used in wireframes and ASCII art:

```dart
/// Patterns for ASCII box-drawing characters.
class AsciiBoxPatterns {
  // ---- Single-character class patterns ----

  /// Horizontal line characters: - = ~
  static final horizontalLine = RegExp(r'[-=~]');

  /// Vertical line characters: | ! :
  static final verticalLine = RegExp(r'[|!:]');

  /// Corner and junction characters: + * .
  static final junction = RegExp(r'[+*.]');

  /// Arrow characters
  static final arrow = RegExp(r'[<>^vV]');

  // ---- Unicode box-drawing characters ----

  /// All standard Unicode box-drawing characters (U+2500-U+257F)
  static final unicodeBox = RegExp(r'[\u2500-\u257F]');

  /// Horizontal box-drawing (single and double)
  static final unicodeHorizontal = RegExp(r'[\u2500\u2501\u2550]');

  /// Vertical box-drawing (single and double)
  static final unicodeVertical = RegExp(r'[\u2502\u2503\u2551]');

  /// Corner characters (single-line box)
  static final unicodeCorners = RegExp(r'[\u250C\u2510\u2514\u2518]');

  /// T-junction characters
  static final unicodeTJunction = RegExp(r'[\u251C\u2524\u252C\u2534]');

  /// Cross junction
  static final unicodeCross = RegExp(r'\u253C');
}
```

### Matching Horizontal Rules

```dart
/// Detects a horizontal rule: a line that is entirely composed of
/// repeated dash, equals, or box-drawing horizontal characters.
final horizontalRule = RegExp(
  r'^[ \t]*[-=\u2500\u2550]{3,}[ \t]*$',
  multiLine: true,
);

const art = '''
Header
======
Content here
---
Footer
''';

for (final m in horizontalRule.allMatches(art)) {
  print('Rule at offset ${m.start}: "${m[0]!.trim()}"');
}
// Rule at offset 7: "======"
// Rule at offset 27: "---"
```

### Matching ASCII Table Rows

```dart
/// Match a pipe-delimited table row like: | col1 | col2 | col3 |
final tableRow = RegExp(
  r'^\|(?:[^|\n]+\|)+\s*$',
  multiLine: true,
);

/// Extract individual cell values from a table row.
List<String> extractCells(String row) {
  final cellPattern = RegExp(r'\|([^|]+)');
  return cellPattern
      .allMatches(row)
      .map((m) => m.group(1)!.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

const table = '''
| Name   | Age | City      |
|--------|-----|-----------|
| Alice  | 30  | New York  |
| Bob    | 25  | London    |
''';

for (final m in tableRow.allMatches(table)) {
  final row = m[0]!;
  if (!RegExp(r'^[|\-\s]+$').hasMatch(row)) {
    print(extractCells(row));
  }
}
// [Name, Age, City]
// [Alice, 30, New York]
// [Bob, 25, London]
```

### Detecting Box Corners and Edges

```dart
/// Detect ASCII box corner patterns.
/// Matches patterns like +--...--+ at the start/end of a box.
final boxTopBottom = RegExp(
  r'^\s*[+\u250C\u2510\u2514\u2518\u256D\u256E\u256F\u2570]'
  r'[-\u2500\u2550]{2,}'
  r'[+\u250C\u2510\u2514\u2518\u256D\u256E\u256F\u2570]\s*$',
  multiLine: true,
);

/// Detect a vertical box edge: line starting and ending with | (or Unicode equiv)
final boxSide = RegExp(
  r'^\s*[|\u2502\u2551].*[|\u2502\u2551]\s*$',
  multiLine: true,
);

const box = '''
+------------------+
| Hello, World!    |
| This is a box.   |
+------------------+
''';

for (final m in boxTopBottom.allMatches(box)) {
  print('Top/Bottom edge at offset ${m.start}');
}
for (final m in boxSide.allMatches(box)) {
  print('Side: ${m[0]!.trim()}');
}
```

---

## Common Tokenization Patterns for Wireframe/ASCII Parsing

### Wireframe Token Types

When parsing ASCII wireframes, the lexer must recognize structural characters, labels, annotations, and spacing.

```dart
enum WireframeTokenType {
  /// Horizontal line segments: ---, ===, ~~~
  hLine,

  /// Vertical line segments: |, :
  vLine,

  /// Corner/junction: +, *, Unicode corners
  corner,

  /// Arrow head: <, >, ^, v
  arrowHead,

  /// Label text inside a box
  label,

  /// Dimension annotation like (240px) or [flex:1]
  annotation,

  /// Whitespace (for measuring indentation / alignment)
  space,

  /// Newline (row delimiter)
  newline,

  /// Unrecognized character
  other,
}

class WireframeLexer {
  static final _rules = <(String, String, WireframeTokenType)>[
    ('hline',      r'[-=~\u2500\u2550]{2,}',                WireframeTokenType.hLine),
    ('corner',     r'[+*\u250C\u2510\u2514\u2518\u253C\u251C\u2524\u252C\u2534\u256D\u256E\u256F\u2570]',
                                                              WireframeTokenType.corner),
    ('vline',      r'[|\u2502\u2551]',                       WireframeTokenType.vLine),
    ('arrow',      r'[<>^vV\u25C0\u25B6\u25B2\u25BC]',      WireframeTokenType.arrowHead),
    ('annotation', r'\([\w :;.%]+\)|\[[\w :;.%]+\]',        WireframeTokenType.annotation),
    ('label',      r'[A-Za-z_][\w ./-]*',                   WireframeTokenType.label),
    ('newline',    r'\n',                                    WireframeTokenType.newline),
    ('space',      r'[ \t]+',                                WireframeTokenType.space),
  ];

  static final _combined = RegExp(
    _rules.map((r) => '(?<${r.$1}>${r.$2})').join('|'),
  );

  static final _typeMap = {
    for (final r in _rules) r.$1: r.$3,
  };

  List<({WireframeTokenType type, String lexeme, int offset})> tokenize(
    String source,
  ) {
    final tokens = <({WireframeTokenType type, String lexeme, int offset})>[];
    var pos = 0;

    while (pos < source.length) {
      final match = _combined.matchAsPrefix(source, pos);
      if (match == null) {
        tokens.add((
          type: WireframeTokenType.other,
          lexeme: source[pos],
          offset: pos,
        ));
        pos++;
        continue;
      }

      WireframeTokenType? type;
      for (final name in match.groupNames) {
        if (match.namedGroup(name) != null) {
          type = _typeMap[name];
          break;
        }
      }

      tokens.add((
        type: type ?? WireframeTokenType.other,
        lexeme: match[0]!,
        offset: pos,
      ));
      pos = match.end;
    }

    return tokens;
  }
}
```

### Common Structural Patterns

Reusable patterns for identifying wireframe structures:

```dart
/// Identify a complete ASCII box (top edge, content rows, bottom edge).
final asciiBoxPattern = RegExp(
  r'^(?<top>[ \t]*[+\u250C][-\u2500]+[+\u2510][ \t]*)$'
  r'(?<body>(?:\n[ \t]*[|\u2502].*[|\u2502][ \t]*$)+)'
  r'\n(?<bottom>[ \t]*[+\u2514][-\u2500]+[+\u2518][ \t]*)$',
  multiLine: true,
);

/// Match dimension annotations like "240px", "flex:1", "50%", "auto"
final dimensionAnnotation = RegExp(
  r'\b(?<value>\d+(?:\.\d+)?)\s*(?<unit>px|rem|em|%|vw|vh)\b'
  r'|(?:flex\s*:\s*(?<flex>\d+))'
  r'|\bauto\b',
);

/// Match color annotations like "#FF6600", "rgb(255,0,0)"
final colorAnnotation = RegExp(
  r'#(?<hex>[0-9A-Fa-f]{3,8})\b'
  r'|rgb\(\s*(?<r>\d{1,3})\s*,\s*(?<g>\d{1,3})\s*,\s*(?<b>\d{1,3})\s*\)',
);

/// Match responsive breakpoint annotations like "@sm", "@md:", "@lg:"
final breakpointAnnotation = RegExp(
  r'@(?<breakpoint>xs|sm|md|lg|xl|2xl):?',
);
```

### Grid Detection

```dart
/// Parse a grid of ASCII boxes and return their bounding rectangles.
List<({int row, int col, int width, int height, String label})> detectBoxes(
  List<String> lines,
) {
  final cornerPattern = RegExp(r'[+\u250C\u2510\u2514\u2518]');
  final boxes = <({int row, int col, int width, int height, String label})>[];

  for (var row = 0; row < lines.length; row++) {
    final line = lines[row];
    for (final m in cornerPattern.allMatches(line)) {
      final col = m.start;
      // Check if this is a top-left corner by looking right and down
      if (col < line.length - 2 &&
          RegExp(r'[-\u2500]').hasMatch(line[col + 1])) {
        // Find the top-right corner
        final topRight = RegExp(r'[+\u2510]')
            .firstMatch(line.substring(col + 1));
        if (topRight != null) {
          final width = topRight.start + 2; // includes both corners
          // Look for the bottom-left corner
          for (var r2 = row + 1; r2 < lines.length; r2++) {
            if (r2 < lines.length &&
                col < lines[r2].length &&
                cornerPattern.hasMatch(lines[r2][col].toString())) {
              final height = r2 - row + 1;
              // Extract label from the interior
              var label = '';
              if (row + 1 < lines.length) {
                final interior = lines[row + 1];
                if (col + 1 < interior.length) {
                  final end = (col + width - 1).clamp(0, interior.length);
                  label = interior.substring(col + 1, end).trim();
                  // Strip vertical bars
                  label = label.replaceAll(RegExp(r'^[|\u2502]\s*|\s*[|\u2502]$'), '');
                }
              }
              boxes.add((
                row: row,
                col: col,
                width: width,
                height: height,
                label: label.trim(),
              ));
              break;
            }
          }
        }
      }
    }
  }

  return boxes;
}
```

---

## Unicode-Aware Regex in Dart

### Enabling Unicode Mode

Pass `unicode: true` to the `RegExp` constructor to enable ECMAScript Unicode mode. This changes several behaviors:

- Surrogate pairs are treated as a single code point.
- Unicode property escapes (`\p{...}`) become available.
- The `.` metacharacter matches any Unicode code point (not just BMP characters), when combined with `dotAll: true`.
- Character classes like `\w`, `\d`, `\s` remain ASCII-only even in Unicode mode per the ECMAScript spec.

```dart
// Without unicode mode, \p{} is not recognized
// With unicode mode, you can use Unicode property escapes:
final letterPattern = RegExp(r'\p{Letter}+', unicode: true);

const input = 'Hello Welt Monde Mire';
for (final m in letterPattern.allMatches(input)) {
  print(m[0]); // Matches words in any script
}

// Match emoji
final emojiPattern = RegExp(r'\p{Emoji_Presentation}', unicode: true);
print(emojiPattern.hasMatch('Hello 😊')); // true

// Match Thai text
final thaiPattern = RegExp(r'\p{Script=Thai}+', unicode: true);
final thaiMatch = thaiPattern.firstMatch('Name: สวัสดี');
if (thaiMatch != null) {
  print(thaiMatch[0]); // 'สวัสดี'
}
```

### Unicode Property Escapes

Common Unicode property escapes for parser work:

| Escape                       | Matches                                      |
|------------------------------|----------------------------------------------|
| `\p{Letter}` / `\p{L}`      | Any letter in any script                     |
| `\p{Number}` / `\p{N}`      | Any numeric character                        |
| `\p{Punctuation}` / `\p{P}` | Any punctuation character                    |
| `\p{Symbol}` / `\p{S}`      | Any symbol (math, currency, etc.)            |
| `\p{Separator}` / `\p{Z}`   | Any whitespace/separator                     |
| `\p{Script=Latin}`           | Latin script characters                      |
| `\p{Script=Thai}`            | Thai script characters                       |
| `\p{Emoji_Presentation}`     | Characters rendered as emoji by default      |
| `\P{Letter}`                 | Negated: anything that is NOT a letter       |

### Handling Grapheme Clusters

Dart regex operates on UTF-16 code units. The `characters` package (from `package:characters`) provides grapheme-cluster-aware iteration, but regex still sees code units. For accurate user-perceived character counting, combine regex extraction with the `Characters` class:

```dart
import 'package:characters/characters.dart';

final extracted = RegExp(r'\p{Letter}+', unicode: true)
    .firstMatch('Hello 🇹🇭 Thailand')
    ?.group(0);
if (extracted != null) {
  // .length gives UTF-16 code unit count
  print(extracted.length);               // code units
  // .characters.length gives grapheme cluster count
  print(extracted.characters.length);    // perceived characters
}
```

---

## Performance: Precompiled Patterns and Avoiding Catastrophic Backtracking

### Precompile Static Patterns

Never create a `RegExp` inside a loop or frequently-called function. Regex compilation has overhead, and Dart does not automatically cache compiled patterns.

```dart
// BAD: Compiles on every call
String extractId(String line) {
  final match = RegExp(r'id=(\d+)').firstMatch(line); // new RegExp each call
  return match?.group(1) ?? '';
}

// GOOD: Compile once as a static or top-level constant
final _idPattern = RegExp(r'id=(\d+)');

String extractId(String line) {
  final match = _idPattern.firstMatch(line);
  return match?.group(1) ?? '';
}
```

For lexers, always build the combined pattern once as a `static final`:

```dart
class MyLexer {
  // Compiled once when the class is first referenced
  static final _pattern = RegExp(
    r'(?<number>\d+)|(?<word>[a-zA-Z]+)|(?<space>\s+)',
  );

  Iterable<RegExpMatch> tokenize(String input) => _pattern.allMatches(input);
}
```

### Avoiding Catastrophic Backtracking

Catastrophic backtracking occurs when a regex engine explores an exponential number of paths. Dart uses a backtracking NFA engine (same semantics as JavaScript), so it is vulnerable to the same class of problems.

**Dangerous pattern**: Nested quantifiers with overlapping alternatives.

```dart
// DANGEROUS: (a+)+ can cause exponential backtracking on input like 'aaaaaaaaX'
final bad = RegExp(r'(a+)+b');

// SAFE: Flatten the nesting
final good = RegExp(r'a+b');
```

**Dangerous pattern**: Overlapping alternatives inside a quantifier.

```dart
// DANGEROUS: (\s|\S)* matches everything but backtracks explosively
final bad2 = RegExp(r'(\s|\S)*end');

// SAFE: Use dotAll mode instead
final good2 = RegExp(r'.*end', dotAll: true);
```

### Rules of Thumb

1. **Avoid nested quantifiers**: `(a*)*`, `(a+)+`, `(a*)+` are all dangerous. Flatten them.
2. **Ensure alternatives are mutually exclusive**: In `(A|B)*`, make sure no string matches both `A` and `B`.
3. **Use atomic-like constructs**: Dart does not support possessive quantifiers or atomic groups natively. Work around this by making alternatives non-overlapping.
4. **Limit repetition**: Use `{0,100}` instead of `*` when you know the maximum length.
5. **Prefer `matchAsPrefix`**: When lexing, `matchAsPrefix` at a known position avoids scanning the entire remaining input.
6. **Benchmark with worst-case inputs**: Test patterns against inputs that nearly match but fail at the end, which exercises backtracking.

### Measuring Regex Performance

```dart
void benchmarkPattern(RegExp pattern, String input, {int iterations = 10000}) {
  // Warm up
  for (var i = 0; i < 100; i++) {
    pattern.allMatches(input).length;
  }

  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    pattern.allMatches(input).length;
  }
  sw.stop();

  final usPerOp = sw.elapsedMicroseconds / iterations;
  print('${pattern.pattern}: ${usPerOp.toStringAsFixed(1)} us/op');
}
```

### Timeouts for Untrusted Input

When applying regex to user-supplied strings, wrap the operation with a timeout to defend against ReDoS (Regular Expression Denial of Service):

```dart
RegExpMatch? safeFindMatch(
  RegExp pattern,
  String input, {
  Duration timeout = const Duration(milliseconds: 100),
}) {
  RegExpMatch? result;
  var done = false;

  // Run in an isolate or use a simple heuristic:
  // Reject inputs that are suspiciously long for the pattern.
  if (input.length > 10000) {
    return null; // Refuse to process excessively long input
  }

  result = pattern.firstMatch(input);
  return result;
}
```

For truly untrusted input at scale, consider running regex in a separate `Isolate` with `Isolate.run` and a kill timer.

---

## Best Practices

### Pattern Design

- **Use raw strings**: Always write `RegExp(r'...')` to avoid confusing double-escaping.
- **Name capture groups**: Prefer `(?<name>...)` over `(\d+)` for readability and maintainability in parser code.
- **Keep patterns focused**: One pattern per concern. Do not build a single monolithic regex that tries to parse an entire grammar.
- **Document complex patterns**: Add a comment explaining what the regex matches and give an example.
- **Use non-capturing groups**: Write `(?:...)` instead of `(...)` when you do not need the group's value. This reduces memory overhead and keeps group indices predictable.

### Lexer Architecture

- **Single combined pattern with named groups**: The most efficient approach for small-to-medium token sets (fewer than 30 rules).
- **Use `matchAsPrefix`**: Anchors the match at the current position and avoids unnecessary scanning.
- **Emit all tokens including whitespace**: Let downstream consumers decide what to skip. This preserves positional accuracy.
- **Track line and column**: Compute from offset by counting `\n` tokens. Essential for error messages.
- **Fail loudly on unrecognized characters**: Throw a `FormatException` with line, column, and the offending character.

### String Processing

- **Prefer `replaceAllMapped` over `replaceAll` with `\$1`**: The callback approach is more readable and less error-prone for complex substitutions.
- **Use `splitMapJoin` for in-place transforms**: When you need to process both matched and unmatched portions of a string.
- **Chain `allMatches` with collection methods**: Use `.map`, `.where`, `.fold` on the match iterable rather than manual loops.
- **Avoid repeated scanning**: If you need multiple pieces of data from the same text, use a single pattern with named groups rather than running multiple separate regexes.

### Unicode Handling

- **Enable `unicode: true` when processing multilingual text**: Required for `\p{...}` property escapes and correct surrogate pair handling.
- **Remember `\w`, `\d`, `\s` are ASCII-only**: Even with `unicode: true`, these remain ASCII. Use `\p{Letter}`, `\p{Number}`, `\p{Separator}` for full Unicode.
- **Use `package:characters` for grapheme clusters**: Regex operates on code units. Use `Characters` for user-perceived character counting.

### Testing

- **Test with empty strings**: Ensure patterns handle `''` gracefully.
- **Test with pathological inputs**: Strings designed to trigger backtracking (e.g., `'aaa...aaX'` for patterns like `a+a+b`).
- **Test boundary conditions**: Start of string, end of string, single character, very long strings.
- **Test Unicode edge cases**: Surrogate pairs, combining characters, zero-width joiners.

---

## Anti-Patterns

### Compiling Regex in Hot Paths

```dart
// WRONG: Creates a new RegExp object on every iteration
for (final line in lines) {
  if (RegExp(r'^\s*#').hasMatch(line)) { // re-compiles each time
    comments.add(line);
  }
}

// CORRECT: Compile once outside the loop
final commentPattern = RegExp(r'^\s*#');
for (final line in lines) {
  if (commentPattern.hasMatch(line)) {
    comments.add(line);
  }
}
```

### Using Regex to Parse Structured Formats

```dart
// WRONG: Parsing JSON with regex
final jsonValue = RegExp(r'"name"\s*:\s*"([^"]*)"');
// This breaks on escaped quotes, nested objects, etc.

// CORRECT: Use dart:convert for structured formats
import 'dart:convert';
final data = jsonDecode(input) as Map<String, dynamic>;
final name = data['name'] as String;
```

### Greedy Quantifiers When Lazy Is Needed

```dart
// WRONG: Greedy .* eats through multiple tags
final broken = RegExp(r'<div>(.*)</div>', dotAll: true);
// On '<div>A</div><div>B</div>' matches 'A</div><div>B'

// CORRECT: Use lazy quantifier .*?
final fixed = RegExp(r'<div>(.*?)</div>', dotAll: true);
// Correctly matches 'A' and then 'B' in separate matches
```

### Nested Quantifiers

```dart
// WRONG: Exponential backtracking risk
final dangerous = RegExp(r'(\w+\s*)+:');
// On 'a b c d e f g h i j k l m n o p q r s t X' this hangs

// CORRECT: Remove the nesting
final safe = RegExp(r'[\w\s]+:');
```

### Ignoring `null` from `group()` / `namedGroup()`

```dart
// WRONG: Unhandled null when group didn't participate in the match
final m = RegExp(r'(\d+)?-(\w+)').firstMatch('-hello');
print(m!.group(1)!.length); // Throws: group(1) is null because (\d+)? didn't match

// CORRECT: Check for null
final digits = m.group(1);
if (digits != null) {
  print(digits.length);
} else {
  print('No digits found');
}
```

### Using `allMatches` When `hasMatch` Suffices

```dart
// WRONG: Creates an iterable and counts matches just to check existence
if (pattern.allMatches(input).isNotEmpty) { ... }

// CORRECT: Use hasMatch for boolean checks
if (pattern.hasMatch(input)) { ... }
```

### Forgetting `multiLine` for Line-Oriented Parsing

```dart
// WRONG: ^ only matches start of entire string
final lineComment = RegExp(r'^#.*');
// Misses comments on lines 2, 3, etc.

// CORRECT: Enable multiLine for per-line matching
final lineComment = RegExp(r'^#.*', multiLine: true);
```

### Mutating State Inside `replaceAllMapped`

```dart
// WRONG: Side effects inside the replacement callback
var counter = 0;
final result = input.replaceAllMapped(RegExp(r'\d+'), (m) {
  counter++; // mutation hidden inside a "pure" mapping
  return '[$counter]';
});

// BETTER: If you need an index, collect matches first, then rebuild
final matches = RegExp(r'\d+').allMatches(input).toList();
var result = input;
for (var i = matches.length - 1; i >= 0; i--) {
  result = result.replaceRange(
    matches[i].start,
    matches[i].end,
    '[${i + 1}]',
  );
}
```

### Overusing Regex for Simple String Operations

```dart
// WRONG: Regex for a simple prefix check
if (RegExp(r'^https://').hasMatch(url)) { ... }

// CORRECT: Use String methods
if (url.startsWith('https://')) { ... }

// WRONG: Regex to check if a string contains a literal substring
if (RegExp(r'error').hasMatch(log)) { ... }

// CORRECT: Use String.contains
if (log.contains('error')) { ... }
```

---

## Sources & References

- [Dart RegExp class API documentation](https://api.dart.dev/dart-core/RegExp-class.html) -- Official API reference for the `RegExp` class with constructor parameters, methods, and examples.
- [Dart RegExpMatch class documentation](https://api.flutter.dev/flutter/dart-core/RegExpMatch-class.html) -- API reference for `RegExpMatch` including `namedGroup`, `groupNames`, and match accessors.
- [Dart RegExp constructor parameters](https://api.dart.dev/dart-core/RegExp/RegExp.html) -- Constructor reference with `multiLine`, `caseSensitive`, `unicode`, and `dotAll` parameters.
- [Dart String.replaceAllMapped API](https://api.flutter.dev/flutter/dart-core/String/replaceAllMapped.html) -- Official documentation for the `replaceAllMapped` method used for regex-driven string transformations.
- [ECMAScript Regular Expressions specification](https://tc39.es/ecma262/#sec-regexp-regular-expression-objects) -- The underlying specification that Dart regex conforms to, including named capture groups and Unicode property escapes.
- [Avoiding catastrophic backtracking in regular expressions](https://javascript.info/regexp-catastrophic-backtracking) -- In-depth explanation of backtracking behavior and mitigation strategies, applicable to Dart's regex engine.
- [Dart `characters` package](https://pub.dev/packages/characters) -- Package for grapheme-cluster-aware string operations, complementing regex for Unicode text processing.

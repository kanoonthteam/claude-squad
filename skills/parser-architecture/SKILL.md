---
name: parser-architecture
description: Parser/Compiler Engineer skill — multi-pass lexer/parser pipelines, recursive descent parsing, sealed class AST hierarchies, visitor pattern traversal, error recovery strategies, parser combinators, token stream design, and performance optimization in Dart 3.x
---

# Parser Architecture in Dart

Comprehensive guide for building production-quality parsers and compilers in Dart 3.x. Covers the full pipeline from source text to validated AST, including tokenization, recursive descent parsing, sealed class node hierarchies, visitor-based traversal, error recovery, and performance tuning for sub-10ms parse targets.

## Table of Contents

1. [Multi-Pass Lexer/Parser Architecture](#multi-pass-lexerparser-architecture)
2. [Token Stream Design](#token-stream-design)
3. [Lexer Implementation](#lexer-implementation)
4. [Recursive Descent Parser Implementation](#recursive-descent-parser-implementation)
5. [Sealed Class Hierarchies for AST Nodes](#sealed-class-hierarchies-for-ast-nodes)
6. [Visitor Pattern for AST Traversal](#visitor-pattern-for-ast-traversal)
7. [Error Recovery Strategies](#error-recovery-strategies)
8. [Parser Combinators vs Hand-Written Parsers](#parser-combinators-vs-hand-written-parsers)
9. [Validation Pass](#validation-pass)
10. [Performance Optimization](#performance-optimization)
11. [Best Practices](#best-practices)
12. [Anti-Patterns](#anti-patterns)
13. [Sources & References](#sources--references)

---

## Multi-Pass Lexer/Parser Architecture

A well-structured compiler front end separates concerns across distinct passes. Each pass transforms the input from one representation to the next, enabling independent testing, clearer error reporting, and easier maintenance.

```
Source Text
    │
    ▼
┌──────────────────────────────────────────────────────┐
│  Pass 1: Lexical Analysis (Tokenization)             │
│  - Converts raw characters into a stream of tokens   │
│  - Strips whitespace and comments                    │
│  - Detects invalid characters early                  │
│  - Produces: List<Token>                             │
└──────────────────────────┬───────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────┐
│  Pass 2: Syntactic Analysis (Parsing)                │
│  - Consumes token stream, builds AST                 │
│  - Enforces grammar rules                            │
│  - Performs error recovery on syntax errors           │
│  - Produces: AstNode (tree)                          │
└──────────────────────────┬───────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────┐
│  Pass 3: Semantic Validation                         │
│  - Walks the AST via visitor pattern                 │
│  - Checks type consistency, scope resolution         │
│  - Detects undefined references, duplicate decls     │
│  - Produces: List<AnalysisError> + annotated AST     │
└──────────────────────────┬───────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────┐
│  Pass 4: Transformation / Code Generation            │
│  - Rewrites AST or emits target output               │
│  - Constant folding, dead code elimination           │
│  - Produces: Target code, IR, or modified AST        │
└──────────────────────────────────────────────────────┘
```

### Pipeline Orchestration

The pipeline orchestrator coordinates each pass and collects diagnostics. If a pass produces fatal errors, later passes can be skipped while still reporting all recoverable errors found so far.

```dart
// lib/compiler/pipeline.dart

import 'package:meta/meta.dart';

/// Orchestrates the full compilation pipeline.
/// Each pass is independently testable and replaceable.
class CompilerPipeline {
  final Lexer _lexer;
  final Parser _parser;
  final SemanticValidator _validator;
  final CodeGenerator _generator;

  const CompilerPipeline({
    required Lexer lexer,
    required Parser parser,
    required SemanticValidator validator,
    required CodeGenerator generator,
  })  : _lexer = lexer,
        _parser = parser,
        _validator = validator,
        _generator = generator;

  CompilationResult compile(String source, {String? fileName}) {
    final diagnostics = <Diagnostic>[];
    final stopwatch = Stopwatch()..start();

    // Pass 1: Tokenization
    final tokenResult = _lexer.tokenize(source, fileName: fileName);
    diagnostics.addAll(tokenResult.diagnostics);

    if (tokenResult.hasFatalErrors) {
      return CompilationResult.failed(
        diagnostics: diagnostics,
        duration: stopwatch.elapsed,
      );
    }

    // Pass 2: Parsing
    final parseResult = _parser.parse(tokenResult.tokens);
    diagnostics.addAll(parseResult.diagnostics);

    if (parseResult.hasFatalErrors) {
      return CompilationResult.failed(
        diagnostics: diagnostics,
        duration: stopwatch.elapsed,
      );
    }

    // Pass 3: Semantic validation
    final validationResult = _validator.validate(parseResult.ast);
    diagnostics.addAll(validationResult.diagnostics);

    if (validationResult.hasFatalErrors) {
      return CompilationResult.failed(
        diagnostics: diagnostics,
        duration: stopwatch.elapsed,
      );
    }

    // Pass 4: Code generation
    final output = _generator.generate(validationResult.annotatedAst);
    stopwatch.stop();

    return CompilationResult.success(
      output: output,
      diagnostics: diagnostics,
      duration: stopwatch.elapsed,
    );
  }
}

/// Result of the full compilation pipeline.
sealed class CompilationResult {
  final List<Diagnostic> diagnostics;
  final Duration duration;

  const CompilationResult({
    required this.diagnostics,
    required this.duration,
  });

  factory CompilationResult.success({
    required String output,
    required List<Diagnostic> diagnostics,
    required Duration duration,
  }) = CompilationSuccess._;

  factory CompilationResult.failed({
    required List<Diagnostic> diagnostics,
    required Duration duration,
  }) = CompilationFailure._;

  bool get hasWarnings =>
      diagnostics.any((d) => d.severity == Severity.warning);
}

final class CompilationSuccess extends CompilationResult {
  final String output;

  const CompilationSuccess._({
    required this.output,
    required super.diagnostics,
    required super.duration,
  });
}

final class CompilationFailure extends CompilationResult {
  const CompilationFailure._({
    required super.diagnostics,
    required super.duration,
  });
}
```

### Pass Independence

Each pass should:
- Accept a well-defined input type and produce a well-defined output type
- Collect its own diagnostics without throwing on recoverable errors
- Be testable in isolation with fixture data
- Have no mutable shared state with other passes

---

## Token Stream Design

Tokens are the atomic units produced by the lexer. A good token design captures the type, lexeme, source location, and any preceding trivia (whitespace, comments) for error reporting and source-map generation.

### Token Types

Use an enum to enumerate every token kind. Group related tokens with doc comments so the parser can efficiently check membership.

```dart
// lib/compiler/token.dart

/// Every distinct token kind recognized by the lexer.
enum TokenType {
  // Literals
  integerLiteral,
  doubleLiteral,
  stringLiteral,
  booleanLiteral,

  // Identifiers & keywords
  identifier,
  kwLet,
  kwConst,
  kwFn,
  kwReturn,
  kwIf,
  kwElse,
  kwWhile,
  kwFor,
  kwIn,
  kwTrue,
  kwFalse,
  kwNull,
  kwType,
  kwMatch,

  // Operators
  plus,
  minus,
  star,
  slash,
  percent,
  equalEqual,
  bangEqual,
  less,
  lessEqual,
  greater,
  greaterEqual,
  ampersandAmpersand,
  pipePipe,
  bang,

  // Assignment
  equal,
  plusEqual,
  minusEqual,
  starEqual,
  slashEqual,

  // Delimiters
  leftParen,
  rightParen,
  leftBrace,
  rightBrace,
  leftBracket,
  rightBracket,

  // Punctuation
  comma,
  dot,
  dotDot,
  colon,
  semicolon,
  arrow,       // ->
  fatArrow,    // =>

  // Special
  eof,
  error,
}

/// Keyword lookup table, populated once at startup.
final Map<String, TokenType> keywords = {
  'let': TokenType.kwLet,
  'const': TokenType.kwConst,
  'fn': TokenType.kwFn,
  'return': TokenType.kwReturn,
  'if': TokenType.kwIf,
  'else': TokenType.kwElse,
  'while': TokenType.kwWhile,
  'for': TokenType.kwFor,
  'in': TokenType.kwIn,
  'true': TokenType.kwTrue,
  'false': TokenType.kwFalse,
  'null': TokenType.kwNull,
  'type': TokenType.kwType,
  'match': TokenType.kwMatch,
};
```

### Token Class

```dart
// lib/compiler/token.dart (continued)

/// A single token with its source location and optional trivia.
@immutable
final class Token {
  final TokenType type;
  final String lexeme;
  final SourceSpan span;
  final Object? literal;

  const Token({
    required this.type,
    required this.lexeme,
    required this.span,
    this.literal,
  });

  bool get isKeyword => type.name.startsWith('kw');
  bool get isOperator => type.index >= TokenType.plus.index &&
      type.index <= TokenType.bang.index;
  bool get isEof => type == TokenType.eof;
  bool get isError => type == TokenType.error;

  @override
  String toString() => 'Token($type, "$lexeme", ${span.start.line}:${span.start.column})';
}

/// Represents a position in source text.
@immutable
final class SourcePosition {
  final int offset;
  final int line;
  final int column;

  const SourcePosition({
    required this.offset,
    required this.line,
    required this.column,
  });

  @override
  String toString() => '$line:$column';
}

/// A contiguous range in source text.
@immutable
final class SourceSpan {
  final SourcePosition start;
  final SourcePosition end;
  final String? fileName;

  const SourceSpan({
    required this.start,
    required this.end,
    this.fileName,
  });

  int get length => end.offset - start.offset;

  @override
  String toString() {
    final prefix = fileName != null ? '$fileName:' : '';
    return '$prefix$start-$end';
  }
}
```

### Token Stream Abstraction

Rather than passing a raw `List<Token>`, wrap it in a stream that provides lookahead and backtracking support for the parser.

```dart
// lib/compiler/token_stream.dart

/// Provides sequential access to tokens with lookahead and mark/reset.
class TokenStream {
  final List<Token> _tokens;
  int _position = 0;
  final List<int> _marks = [];

  TokenStream(this._tokens);

  /// Current token without advancing.
  Token get current => _tokens[_position];

  /// Peek ahead by [offset] tokens (0 = current).
  Token peek([int offset = 0]) {
    final index = _position + offset;
    if (index >= _tokens.length) return _tokens.last; // EOF
    return _tokens[index];
  }

  /// Advance and return the previous token.
  Token advance() {
    final token = current;
    if (!current.isEof) _position++;
    return token;
  }

  /// Consume a token of the expected type, or return null.
  Token? tryConsume(TokenType type) {
    if (current.type == type) return advance();
    return null;
  }

  /// Consume a token of the expected type, or throw.
  Token expect(TokenType type) {
    if (current.type == type) return advance();
    throw ParseException(
      'Expected ${type.name} but found ${current.type.name}',
      span: current.span,
    );
  }

  /// Check if the current token matches any of the given types.
  bool check(Set<TokenType> types) => types.contains(current.type);

  /// Save the current position for potential backtracking.
  void mark() => _marks.add(_position);

  /// Restore to the last marked position.
  void reset() {
    if (_marks.isNotEmpty) {
      _position = _marks.removeLast();
    }
  }

  /// Discard the last mark (commit to current position).
  void commit() => _marks.isNotEmpty ? _marks.removeLast() : null;

  bool get isAtEnd => current.isEof;
  int get position => _position;
  int get length => _tokens.length;
}
```

---

## Lexer Implementation

The lexer (scanner) converts a raw source string into a list of tokens. It should be a single-pass, linear-time operation. Handle every possible character; unknown characters produce error tokens rather than throwing exceptions.

### Core Lexer

```dart
// lib/compiler/lexer.dart

/// Result of the tokenization pass.
@immutable
final class TokenizeResult {
  final List<Token> tokens;
  final List<Diagnostic> diagnostics;

  const TokenizeResult({
    required this.tokens,
    required this.diagnostics,
  });

  bool get hasFatalErrors =>
      diagnostics.any((d) => d.severity == Severity.error);
}

/// Converts source text into a stream of tokens.
class Lexer {
  final String _source;
  final String? _fileName;
  final List<Token> _tokens = [];
  final List<Diagnostic> _diagnostics = [];

  int _start = 0;
  int _current = 0;
  int _line = 1;
  int _column = 1;
  int _startLine = 1;
  int _startColumn = 1;

  Lexer(this._source, {String? fileName}) : _fileName = fileName;

  TokenizeResult tokenize(String source, {String? fileName}) {
    final lexer = Lexer(source, fileName: fileName);
    return lexer._scanAll();
  }

  TokenizeResult _scanAll() {
    while (!_isAtEnd) {
      _start = _current;
      _startLine = _line;
      _startColumn = _column;
      _scanToken();
    }

    _tokens.add(Token(
      type: TokenType.eof,
      lexeme: '',
      span: _currentSpan(),
    ));

    return TokenizeResult(tokens: _tokens, diagnostics: _diagnostics);
  }

  void _scanToken() {
    final c = _advance();
    switch (c) {
      case '(' : _addToken(TokenType.leftParen);
      case ')' : _addToken(TokenType.rightParen);
      case '{' : _addToken(TokenType.leftBrace);
      case '}' : _addToken(TokenType.rightBrace);
      case '[' : _addToken(TokenType.leftBracket);
      case ']' : _addToken(TokenType.rightBracket);
      case ',' : _addToken(TokenType.comma);
      case ';' : _addToken(TokenType.semicolon);
      case ':' : _addToken(TokenType.colon);

      case '+' : _addToken(_match('=') ? TokenType.plusEqual : TokenType.plus);
      case '*' : _addToken(_match('=') ? TokenType.starEqual : TokenType.star);
      case '%' : _addToken(TokenType.percent);

      case '-' when _match('>') : _addToken(TokenType.arrow);
      case '-' when _match('=') : _addToken(TokenType.minusEqual);
      case '-' : _addToken(TokenType.minus);

      case '=' when _match('>') : _addToken(TokenType.fatArrow);
      case '=' when _match('=') : _addToken(TokenType.equalEqual);
      case '=' : _addToken(TokenType.equal);

      case '!' when _match('=') : _addToken(TokenType.bangEqual);
      case '!' : _addToken(TokenType.bang);

      case '<' when _match('=') : _addToken(TokenType.lessEqual);
      case '<' : _addToken(TokenType.less);

      case '>' when _match('=') : _addToken(TokenType.greaterEqual);
      case '>' : _addToken(TokenType.greater);

      case '&' when _match('&') : _addToken(TokenType.ampersandAmpersand);
      case '|' when _match('|') : _addToken(TokenType.pipePipe);

      case '.' when _match('.') : _addToken(TokenType.dotDot);
      case '.' : _addToken(TokenType.dot);

      case '/' when _match('/') : _skipLineComment();
      case '/' when _match('*') : _skipBlockComment();
      case '/' when _match('=') : _addToken(TokenType.slashEqual);
      case '/' : _addToken(TokenType.slash);

      case ' ' || '\t' || '\r' : break; // skip whitespace
      case '\n' : _line++; _column = 1;

      case '"' : _scanString();

      _ when _isDigit(c) : _scanNumber();
      _ when _isAlpha(c) : _scanIdentifier();

      _ : _errorToken('Unexpected character: "$c"');
    }
  }

  void _scanString() {
    while (!_isAtEnd && _peek() != '"') {
      if (_peek() == '\n') { _line++; _column = 1; }
      if (_peek() == '\\') _advance(); // skip escape char
      _advance();
    }
    if (_isAtEnd) {
      _errorToken('Unterminated string literal');
      return;
    }
    _advance(); // closing "
    final value = _source.substring(_start + 1, _current - 1);
    _addToken(TokenType.stringLiteral, literal: value);
  }

  void _scanNumber() {
    while (_isDigit(_peek())) _advance();

    if (_peek() == '.' && _isDigit(_peekNext())) {
      _advance(); // consume '.'
      while (_isDigit(_peek())) _advance();
      final value = double.parse(_currentLexeme);
      _addToken(TokenType.doubleLiteral, literal: value);
    } else {
      final value = int.parse(_currentLexeme);
      _addToken(TokenType.integerLiteral, literal: value);
    }
  }

  void _scanIdentifier() {
    while (_isAlphaNumeric(_peek())) _advance();
    final text = _currentLexeme;
    final type = keywords[text] ?? TokenType.identifier;
    if (type == TokenType.kwTrue) {
      _addToken(type, literal: true);
    } else if (type == TokenType.kwFalse) {
      _addToken(type, literal: false);
    } else {
      _addToken(type);
    }
  }

  void _skipLineComment() {
    while (!_isAtEnd && _peek() != '\n') _advance();
  }

  void _skipBlockComment() {
    var depth = 1;
    while (!_isAtEnd && depth > 0) {
      if (_peek() == '/' && _peekNext() == '*') { depth++; _advance(); }
      else if (_peek() == '*' && _peekNext() == '/') { depth--; _advance(); }
      if (_peek() == '\n') { _line++; _column = 1; }
      _advance();
    }
    if (depth > 0) {
      _errorToken('Unterminated block comment');
    }
  }

  // --- Helper methods ---

  String _advance() {
    final c = _source[_current];
    _current++;
    _column++;
    return c;
  }

  bool _match(String expected) {
    if (_isAtEnd || _source[_current] != expected) return false;
    _current++;
    _column++;
    return true;
  }

  String _peek() => _isAtEnd ? '\x00' : _source[_current];
  String _peekNext() =>
      _current + 1 >= _source.length ? '\x00' : _source[_current + 1];

  bool get _isAtEnd => _current >= _source.length;
  String get _currentLexeme => _source.substring(_start, _current);

  bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  bool _isAlpha(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
           (code >= 97 && code <= 122) ||
           c == '_';
  }
  bool _isAlphaNumeric(String c) => _isAlpha(c) || _isDigit(c);

  SourceSpan _currentSpan() => SourceSpan(
    start: SourcePosition(offset: _start, line: _startLine, column: _startColumn),
    end: SourcePosition(offset: _current, line: _line, column: _column),
    fileName: _fileName,
  );

  void _addToken(TokenType type, {Object? literal}) {
    _tokens.add(Token(
      type: type,
      lexeme: _currentLexeme,
      span: _currentSpan(),
      literal: literal,
    ));
  }

  void _errorToken(String message) {
    _tokens.add(Token(
      type: TokenType.error,
      lexeme: _currentLexeme,
      span: _currentSpan(),
    ));
    _diagnostics.add(Diagnostic(
      message: message,
      span: _currentSpan(),
      severity: Severity.error,
    ));
  }
}
```

### Diagnostics

```dart
// lib/compiler/diagnostic.dart

enum Severity { error, warning, info, hint }

/// A compiler diagnostic with source location.
@immutable
final class Diagnostic {
  final String message;
  final SourceSpan span;
  final Severity severity;
  final String? code;

  const Diagnostic({
    required this.message,
    required this.span,
    required this.severity,
    this.code,
  });

  @override
  String toString() {
    final prefix = switch (severity) {
      Severity.error   => 'error',
      Severity.warning => 'warning',
      Severity.info    => 'info',
      Severity.hint    => 'hint',
    };
    return '$prefix: $message at $span';
  }
}
```

---

## Recursive Descent Parser Implementation

A recursive descent parser is a top-down parser where each grammar rule maps to a method. This is the most common hand-written parser architecture because it is straightforward to implement, debug, and extend.

### Grammar Notation

Document the grammar in EBNF so every parsing method has a clear contract:

```
program        = declaration* EOF ;
declaration    = letDecl | fnDecl | typeDecl | statement ;
letDecl        = "let" IDENTIFIER ( ":" type )? "=" expression ";" ;
fnDecl         = "fn" IDENTIFIER "(" parameters? ")" ( "->" type )? block ;
typeDecl       = "type" IDENTIFIER "=" type ";" ;
statement      = exprStmt | ifStmt | whileStmt | forStmt | returnStmt | block ;
block          = "{" declaration* "}" ;
ifStmt         = "if" expression block ( "else" ( ifStmt | block ) )? ;
whileStmt      = "while" expression block ;
forStmt        = "for" IDENTIFIER "in" expression block ;
returnStmt     = "return" expression? ";" ;
exprStmt       = expression ";" ;

expression     = assignment ;
assignment     = IDENTIFIER ( "=" | "+=" | "-=" ) assignment | logicalOr ;
logicalOr      = logicalAnd ( "||" logicalAnd )* ;
logicalAnd     = equality ( "&&" equality )* ;
equality       = comparison ( ( "==" | "!=" ) comparison )* ;
comparison     = addition ( ( "<" | "<=" | ">" | ">=" ) addition )* ;
addition       = multiplication ( ( "+" | "-" ) multiplication )* ;
multiplication = unary ( ( "*" | "/" | "%" ) unary )* ;
unary          = ( "!" | "-" ) unary | call ;
call           = primary ( "(" arguments? ")" | "." IDENTIFIER )* ;
primary        = NUMBER | STRING | BOOLEAN | "null"
               | IDENTIFIER | "(" expression ")" | matchExpr ;
matchExpr      = "match" expression "{" matchArm ( "," matchArm )* "}" ;
matchArm       = pattern "=>" expression ;
```

### Parser Implementation

```dart
// lib/compiler/parser.dart

/// Result of the parsing pass.
@immutable
final class ParseResult {
  final List<AstNode> ast;
  final List<Diagnostic> diagnostics;

  const ParseResult({required this.ast, required this.diagnostics});

  bool get hasFatalErrors =>
      diagnostics.any((d) => d.severity == Severity.error);
}

class ParseException implements Exception {
  final String message;
  final SourceSpan span;

  const ParseException(this.message, {required this.span});
}

/// Recursive descent parser that transforms a token stream into an AST.
class Parser {
  late TokenStream _stream;
  final List<Diagnostic> _diagnostics = [];

  ParseResult parse(List<Token> tokens) {
    _stream = TokenStream(tokens);
    _diagnostics.clear();

    final declarations = <AstNode>[];
    while (!_stream.isAtEnd) {
      try {
        declarations.add(_declaration());
      } on ParseException catch (e) {
        _diagnostics.add(Diagnostic(
          message: e.message,
          span: e.span,
          severity: Severity.error,
        ));
        _synchronize();
      }
    }

    return ParseResult(ast: declarations, diagnostics: _diagnostics);
  }

  // --- Declarations ---

  AstNode _declaration() {
    if (_stream.check({TokenType.kwLet})) return _letDeclaration();
    if (_stream.check({TokenType.kwFn})) return _fnDeclaration();
    if (_stream.check({TokenType.kwType})) return _typeDeclaration();
    return _statement();
  }

  LetDeclaration _letDeclaration() {
    final keyword = _stream.expect(TokenType.kwLet);
    final name = _stream.expect(TokenType.identifier);

    TypeAnnotation? typeAnnotation;
    if (_stream.tryConsume(TokenType.colon) != null) {
      typeAnnotation = _typeAnnotation();
    }

    _stream.expect(TokenType.equal);
    final initializer = _expression();
    _stream.expect(TokenType.semicolon);

    return LetDeclaration(
      name: name,
      typeAnnotation: typeAnnotation,
      initializer: initializer,
      span: _spanFrom(keyword),
    );
  }

  FnDeclaration _fnDeclaration() {
    final keyword = _stream.expect(TokenType.kwFn);
    final name = _stream.expect(TokenType.identifier);

    _stream.expect(TokenType.leftParen);
    final params = <Parameter>[];
    if (!_stream.check({TokenType.rightParen})) {
      do {
        final paramName = _stream.expect(TokenType.identifier);
        _stream.expect(TokenType.colon);
        final paramType = _typeAnnotation();
        params.add(Parameter(name: paramName, type: paramType));
      } while (_stream.tryConsume(TokenType.comma) != null);
    }
    _stream.expect(TokenType.rightParen);

    TypeAnnotation? returnType;
    if (_stream.tryConsume(TokenType.arrow) != null) {
      returnType = _typeAnnotation();
    }

    final body = _block();

    return FnDeclaration(
      name: name,
      parameters: params,
      returnType: returnType,
      body: body,
      span: _spanFrom(keyword),
    );
  }

  TypeDeclaration _typeDeclaration() {
    final keyword = _stream.expect(TokenType.kwType);
    final name = _stream.expect(TokenType.identifier);
    _stream.expect(TokenType.equal);
    final typeExpr = _typeAnnotation();
    _stream.expect(TokenType.semicolon);

    return TypeDeclaration(
      name: name,
      type: typeExpr,
      span: _spanFrom(keyword),
    );
  }

  // --- Statements ---

  AstNode _statement() {
    if (_stream.check({TokenType.kwIf})) return _ifStatement();
    if (_stream.check({TokenType.kwWhile})) return _whileStatement();
    if (_stream.check({TokenType.kwFor})) return _forStatement();
    if (_stream.check({TokenType.kwReturn})) return _returnStatement();
    if (_stream.check({TokenType.leftBrace})) return _block();
    return _expressionStatement();
  }

  IfStatement _ifStatement() {
    final keyword = _stream.expect(TokenType.kwIf);
    final condition = _expression();
    final thenBranch = _block();

    AstNode? elseBranch;
    if (_stream.tryConsume(TokenType.kwElse) != null) {
      elseBranch = _stream.check({TokenType.kwIf})
          ? _ifStatement()
          : _block();
    }

    return IfStatement(
      condition: condition,
      thenBranch: thenBranch,
      elseBranch: elseBranch,
      span: _spanFrom(keyword),
    );
  }

  WhileStatement _whileStatement() {
    final keyword = _stream.expect(TokenType.kwWhile);
    final condition = _expression();
    final body = _block();

    return WhileStatement(
      condition: condition,
      body: body,
      span: _spanFrom(keyword),
    );
  }

  ForStatement _forStatement() {
    final keyword = _stream.expect(TokenType.kwFor);
    final variable = _stream.expect(TokenType.identifier);
    _stream.expect(TokenType.kwIn);
    final iterable = _expression();
    final body = _block();

    return ForStatement(
      variable: variable,
      iterable: iterable,
      body: body,
      span: _spanFrom(keyword),
    );
  }

  ReturnStatement _returnStatement() {
    final keyword = _stream.expect(TokenType.kwReturn);
    Expression? value;
    if (!_stream.check({TokenType.semicolon})) {
      value = _expression();
    }
    _stream.expect(TokenType.semicolon);

    return ReturnStatement(
      value: value,
      span: _spanFrom(keyword),
    );
  }

  Block _block() {
    final brace = _stream.expect(TokenType.leftBrace);
    final statements = <AstNode>[];

    while (!_stream.check({TokenType.rightBrace}) && !_stream.isAtEnd) {
      statements.add(_declaration());
    }

    _stream.expect(TokenType.rightBrace);
    return Block(statements: statements, span: _spanFrom(brace));
  }

  ExpressionStatement _expressionStatement() {
    final expr = _expression();
    _stream.expect(TokenType.semicolon);
    return ExpressionStatement(expression: expr, span: expr.span);
  }

  // --- Expressions (precedence climbing) ---

  Expression _expression() => _assignment();

  Expression _assignment() {
    final expr = _logicalOr();

    if (_stream.check({TokenType.equal, TokenType.plusEqual,
                       TokenType.minusEqual, TokenType.starEqual,
                       TokenType.slashEqual})) {
      final op = _stream.advance();
      final value = _assignment(); // right-associative

      if (expr is IdentifierExpression) {
        return AssignmentExpression(
          name: expr.name,
          operator: op,
          value: value,
          span: _spanBetween(expr.span, value.span),
        );
      }
      throw ParseException(
        'Invalid assignment target',
        span: expr.span,
      );
    }

    return expr;
  }

  Expression _logicalOr() {
    var left = _logicalAnd();
    while (_stream.tryConsume(TokenType.pipePipe) case final op?) {
      final right = _logicalAnd();
      left = BinaryExpression(
        left: left,
        operator: op,
        right: right,
        span: _spanBetween(left.span, right.span),
      );
    }
    return left;
  }

  Expression _logicalAnd() {
    var left = _equality();
    while (_stream.tryConsume(TokenType.ampersandAmpersand) case final op?) {
      final right = _equality();
      left = BinaryExpression(
        left: left,
        operator: op,
        right: right,
        span: _spanBetween(left.span, right.span),
      );
    }
    return left;
  }

  Expression _equality() {
    var left = _comparison();
    while (_stream.check({TokenType.equalEqual, TokenType.bangEqual})) {
      final op = _stream.advance();
      final right = _comparison();
      left = BinaryExpression(
        left: left,
        operator: op,
        right: right,
        span: _spanBetween(left.span, right.span),
      );
    }
    return left;
  }

  Expression _comparison() {
    var left = _addition();
    while (_stream.check({TokenType.less, TokenType.lessEqual,
                          TokenType.greater, TokenType.greaterEqual})) {
      final op = _stream.advance();
      final right = _addition();
      left = BinaryExpression(
        left: left,
        operator: op,
        right: right,
        span: _spanBetween(left.span, right.span),
      );
    }
    return left;
  }

  Expression _addition() {
    var left = _multiplication();
    while (_stream.check({TokenType.plus, TokenType.minus})) {
      final op = _stream.advance();
      final right = _multiplication();
      left = BinaryExpression(
        left: left,
        operator: op,
        right: right,
        span: _spanBetween(left.span, right.span),
      );
    }
    return left;
  }

  Expression _multiplication() {
    var left = _unary();
    while (_stream.check({TokenType.star, TokenType.slash, TokenType.percent})) {
      final op = _stream.advance();
      final right = _unary();
      left = BinaryExpression(
        left: left,
        operator: op,
        right: right,
        span: _spanBetween(left.span, right.span),
      );
    }
    return left;
  }

  Expression _unary() {
    if (_stream.check({TokenType.bang, TokenType.minus})) {
      final op = _stream.advance();
      final operand = _unary();
      return UnaryExpression(
        operator: op,
        operand: operand,
        span: _spanBetween(op.span, operand.span),
      );
    }
    return _call();
  }

  Expression _call() {
    var expr = _primary();

    while (true) {
      if (_stream.tryConsume(TokenType.leftParen) != null) {
        final args = <Expression>[];
        if (!_stream.check({TokenType.rightParen})) {
          do {
            args.add(_expression());
          } while (_stream.tryConsume(TokenType.comma) != null);
        }
        final paren = _stream.expect(TokenType.rightParen);
        expr = CallExpression(
          callee: expr,
          arguments: args,
          span: _spanBetween(expr.span, paren.span),
        );
      } else if (_stream.tryConsume(TokenType.dot) != null) {
        final name = _stream.expect(TokenType.identifier);
        expr = MemberExpression(
          object: expr,
          name: name,
          span: _spanBetween(expr.span, name.span),
        );
      } else {
        break;
      }
    }

    return expr;
  }

  Expression _primary() {
    final token = _stream.current;

    return switch (token.type) {
      TokenType.integerLiteral ||
      TokenType.doubleLiteral ||
      TokenType.stringLiteral => () {
        _stream.advance();
        return LiteralExpression(value: token.literal!, span: token.span);
      }(),
      TokenType.kwTrue || TokenType.kwFalse => () {
        _stream.advance();
        return LiteralExpression(value: token.literal!, span: token.span);
      }(),
      TokenType.kwNull => () {
        _stream.advance();
        return LiteralExpression(value: null, span: token.span);
      }(),
      TokenType.identifier => () {
        _stream.advance();
        return IdentifierExpression(name: token, span: token.span);
      }(),
      TokenType.leftParen => () {
        _stream.advance();
        final expr = _expression();
        _stream.expect(TokenType.rightParen);
        return GroupExpression(expression: expr, span: _spanFrom(token));
      }(),
      TokenType.kwMatch => _matchExpression(),
      _ => throw ParseException(
        'Expected expression, found ${token.type.name}',
        span: token.span,
      ),
    };
  }

  MatchExpression _matchExpression() {
    final keyword = _stream.expect(TokenType.kwMatch);
    final subject = _expression();
    _stream.expect(TokenType.leftBrace);

    final arms = <MatchArm>[];
    while (!_stream.check({TokenType.rightBrace}) && !_stream.isAtEnd) {
      final pattern = _pattern();
      _stream.expect(TokenType.fatArrow);
      final body = _expression();
      arms.add(MatchArm(pattern: pattern, body: body));
      _stream.tryConsume(TokenType.comma);
    }

    _stream.expect(TokenType.rightBrace);
    return MatchExpression(
      subject: subject,
      arms: arms,
      span: _spanFrom(keyword),
    );
  }

  // --- Helpers ---

  TypeAnnotation _typeAnnotation() {
    final name = _stream.expect(TokenType.identifier);
    return TypeAnnotation(name: name, span: name.span);
  }

  Pattern _pattern() {
    final token = _stream.current;
    return switch (token.type) {
      TokenType.integerLiteral ||
      TokenType.stringLiteral ||
      TokenType.kwTrue ||
      TokenType.kwFalse => () {
        _stream.advance();
        return LiteralPattern(token: token, span: token.span);
      }(),
      TokenType.identifier => () {
        _stream.advance();
        return BindingPattern(name: token, span: token.span);
      }(),
      _ => throw ParseException(
        'Expected pattern, found ${token.type.name}',
        span: token.span,
      ),
    };
  }

  SourceSpan _spanFrom(Token start) => SourceSpan(
    start: start.span.start,
    end: _stream.peek(-1).span.end,
    fileName: start.span.fileName,
  );

  SourceSpan _spanBetween(SourceSpan start, SourceSpan end) => SourceSpan(
    start: start.start,
    end: end.end,
    fileName: start.fileName,
  );

  /// Error recovery: skip tokens until a synchronization point.
  void _synchronize() {
    _stream.advance();
    while (!_stream.isAtEnd) {
      // Synchronize after a semicolon
      if (_stream.peek(-1).type == TokenType.semicolon) return;

      // Synchronize at statement/declaration starters
      if (_stream.check({
        TokenType.kwLet,
        TokenType.kwFn,
        TokenType.kwType,
        TokenType.kwIf,
        TokenType.kwWhile,
        TokenType.kwFor,
        TokenType.kwReturn,
      })) return;

      _stream.advance();
    }
  }
}
```

---

## Sealed Class Hierarchies for AST Nodes

Dart 3.x sealed classes enable exhaustive pattern matching on AST nodes. The compiler verifies that every switch on a sealed hierarchy handles all subtypes, eliminating missed-case bugs.

### Design Principles

- Use `sealed class` for the root and each major category (Expression, Statement, Declaration)
- Use `final class` for concrete leaf nodes
- Attach a `SourceSpan` to every node for error reporting and source maps
- Keep nodes immutable to allow safe sharing across passes

### AST Node Hierarchy

```dart
// lib/compiler/ast.dart

/// Root of the AST hierarchy. Every node carries its source span.
sealed class AstNode {
  SourceSpan get span;
}

// --- Declarations ---

sealed class Declaration extends AstNode {}

final class LetDeclaration extends Declaration {
  final Token name;
  final TypeAnnotation? typeAnnotation;
  final Expression initializer;

  @override
  final SourceSpan span;

  const LetDeclaration({
    required this.name,
    this.typeAnnotation,
    required this.initializer,
    required this.span,
  });
}

final class FnDeclaration extends Declaration {
  final Token name;
  final List<Parameter> parameters;
  final TypeAnnotation? returnType;
  final Block body;

  @override
  final SourceSpan span;

  const FnDeclaration({
    required this.name,
    required this.parameters,
    this.returnType,
    required this.body,
    required this.span,
  });
}

final class TypeDeclaration extends Declaration {
  final Token name;
  final TypeAnnotation type;

  @override
  final SourceSpan span;

  const TypeDeclaration({
    required this.name,
    required this.type,
    required this.span,
  });
}

// --- Statements ---

sealed class Statement extends AstNode {}

final class IfStatement extends Statement {
  final Expression condition;
  final AstNode thenBranch;
  final AstNode? elseBranch;

  @override
  final SourceSpan span;

  const IfStatement({
    required this.condition,
    required this.thenBranch,
    this.elseBranch,
    required this.span,
  });
}

final class WhileStatement extends Statement {
  final Expression condition;
  final AstNode body;

  @override
  final SourceSpan span;

  const WhileStatement({
    required this.condition,
    required this.body,
    required this.span,
  });
}

final class ForStatement extends Statement {
  final Token variable;
  final Expression iterable;
  final AstNode body;

  @override
  final SourceSpan span;

  const ForStatement({
    required this.variable,
    required this.iterable,
    required this.body,
    required this.span,
  });
}

final class ReturnStatement extends Statement {
  final Expression? value;

  @override
  final SourceSpan span;

  const ReturnStatement({this.value, required this.span});
}

final class ExpressionStatement extends Statement {
  final Expression expression;

  @override
  final SourceSpan span;

  const ExpressionStatement({
    required this.expression,
    required this.span,
  });
}

final class Block extends Statement {
  final List<AstNode> statements;

  @override
  final SourceSpan span;

  const Block({required this.statements, required this.span});
}

// --- Expressions ---

sealed class Expression extends AstNode {}

final class LiteralExpression extends Expression {
  final Object? value;

  @override
  final SourceSpan span;

  const LiteralExpression({required this.value, required this.span});
}

final class IdentifierExpression extends Expression {
  final Token name;

  @override
  final SourceSpan span;

  const IdentifierExpression({required this.name, required this.span});
}

final class BinaryExpression extends Expression {
  final Expression left;
  final Token operator;
  final Expression right;

  @override
  final SourceSpan span;

  const BinaryExpression({
    required this.left,
    required this.operator,
    required this.right,
    required this.span,
  });
}

final class UnaryExpression extends Expression {
  final Token operator;
  final Expression operand;

  @override
  final SourceSpan span;

  const UnaryExpression({
    required this.operator,
    required this.operand,
    required this.span,
  });
}

final class AssignmentExpression extends Expression {
  final Token name;
  final Token operator;
  final Expression value;

  @override
  final SourceSpan span;

  const AssignmentExpression({
    required this.name,
    required this.operator,
    required this.value,
    required this.span,
  });
}

final class CallExpression extends Expression {
  final Expression callee;
  final List<Expression> arguments;

  @override
  final SourceSpan span;

  const CallExpression({
    required this.callee,
    required this.arguments,
    required this.span,
  });
}

final class MemberExpression extends Expression {
  final Expression object;
  final Token name;

  @override
  final SourceSpan span;

  const MemberExpression({
    required this.object,
    required this.name,
    required this.span,
  });
}

final class GroupExpression extends Expression {
  final Expression expression;

  @override
  final SourceSpan span;

  const GroupExpression({required this.expression, required this.span});
}

final class MatchExpression extends Expression {
  final Expression subject;
  final List<MatchArm> arms;

  @override
  final SourceSpan span;

  const MatchExpression({
    required this.subject,
    required this.arms,
    required this.span,
  });
}

// --- Match & Patterns ---

final class MatchArm {
  final Pattern pattern;
  final Expression body;

  const MatchArm({required this.pattern, required this.body});
}

sealed class Pattern {
  SourceSpan get span;
}

final class LiteralPattern extends Pattern {
  final Token token;

  @override
  final SourceSpan span;

  const LiteralPattern({required this.token, required this.span});
}

final class BindingPattern extends Pattern {
  final Token name;

  @override
  final SourceSpan span;

  const BindingPattern({required this.name, required this.span});
}

// --- Supporting types ---

final class Parameter {
  final Token name;
  final TypeAnnotation type;

  const Parameter({required this.name, required this.type});
}

final class TypeAnnotation {
  final Token name;
  final SourceSpan span;

  const TypeAnnotation({required this.name, required this.span});
}
```

### Exhaustive Switching with Sealed Classes

When you switch on a sealed type, the Dart 3.x compiler ensures exhaustiveness:

```dart
String describeExpression(Expression expr) {
  return switch (expr) {
    LiteralExpression(:final value) => 'Literal($value)',
    IdentifierExpression(:final name) => 'Ident(${name.lexeme})',
    BinaryExpression(:final left, :final operator, :final right) =>
      '(${describeExpression(left)} ${operator.lexeme} ${describeExpression(right)})',
    UnaryExpression(:final operator, :final operand) =>
      '(${operator.lexeme}${describeExpression(operand)})',
    AssignmentExpression(:final name, :final value) =>
      '${name.lexeme} = ${describeExpression(value)}',
    CallExpression(:final callee, :final arguments) =>
      '${describeExpression(callee)}(${arguments.map(describeExpression).join(", ")})',
    MemberExpression(:final object, :final name) =>
      '${describeExpression(object)}.${name.lexeme}',
    GroupExpression(:final expression) =>
      '(${describeExpression(expression)})',
    MatchExpression(:final subject, :final arms) =>
      'match ${describeExpression(subject)} { ${arms.length} arms }',
  };
  // No default needed -- compiler enforces all cases are covered.
}
```

---

## Visitor Pattern for AST Traversal

The visitor pattern decouples AST node definitions from the operations performed on them. Each analysis pass (type checking, optimization, code generation) is a separate visitor class, avoiding the need to modify node classes when adding new passes.

### Generic Visitor Interface

```dart
// lib/compiler/visitor.dart

/// Visitor interface with a return type [R].
/// Each sealed subtype of AstNode has a corresponding visit method.
abstract interface class AstVisitor<R> {
  // Declarations
  R visitLetDeclaration(LetDeclaration node);
  R visitFnDeclaration(FnDeclaration node);
  R visitTypeDeclaration(TypeDeclaration node);

  // Statements
  R visitIfStatement(IfStatement node);
  R visitWhileStatement(WhileStatement node);
  R visitForStatement(ForStatement node);
  R visitReturnStatement(ReturnStatement node);
  R visitExpressionStatement(ExpressionStatement node);
  R visitBlock(Block node);

  // Expressions
  R visitLiteral(LiteralExpression node);
  R visitIdentifier(IdentifierExpression node);
  R visitBinary(BinaryExpression node);
  R visitUnary(UnaryExpression node);
  R visitAssignment(AssignmentExpression node);
  R visitCall(CallExpression node);
  R visitMember(MemberExpression node);
  R visitGroup(GroupExpression node);
  R visitMatch(MatchExpression node);
}

/// Dispatch helper. Call this to route any AstNode to the correct visitor method.
R acceptNode<R>(AstNode node, AstVisitor<R> visitor) {
  return switch (node) {
    LetDeclaration n     => visitor.visitLetDeclaration(n),
    FnDeclaration n      => visitor.visitFnDeclaration(n),
    TypeDeclaration n    => visitor.visitTypeDeclaration(n),
    IfStatement n        => visitor.visitIfStatement(n),
    WhileStatement n     => visitor.visitWhileStatement(n),
    ForStatement n       => visitor.visitForStatement(n),
    ReturnStatement n    => visitor.visitReturnStatement(n),
    ExpressionStatement n => visitor.visitExpressionStatement(n),
    Block n              => visitor.visitBlock(n),
    LiteralExpression n  => visitor.visitLiteral(n),
    IdentifierExpression n => visitor.visitIdentifier(n),
    BinaryExpression n   => visitor.visitBinary(n),
    UnaryExpression n    => visitor.visitUnary(n),
    AssignmentExpression n => visitor.visitAssignment(n),
    CallExpression n     => visitor.visitCall(n),
    MemberExpression n   => visitor.visitMember(n),
    GroupExpression n    => visitor.visitGroup(n),
    MatchExpression n    => visitor.visitMatch(n),
  };
}
```

### Default Recursive Visitor

A base class that walks the entire tree by default. Subclasses override only the methods they care about.

```dart
// lib/compiler/recursive_visitor.dart

/// Walks the entire AST, returning void. Override specific methods
/// to inject behavior at certain node types.
class RecursiveAstVisitor implements AstVisitor<void> {
  const RecursiveAstVisitor();

  void visit(AstNode node) => acceptNode(node, this);
  void visitAll(List<AstNode> nodes) {
    for (final node in nodes) {
      visit(node);
    }
  }

  @override
  void visitLetDeclaration(LetDeclaration node) {
    visit(node.initializer);
  }

  @override
  void visitFnDeclaration(FnDeclaration node) {
    visit(node.body);
  }

  @override
  void visitTypeDeclaration(TypeDeclaration node) {}

  @override
  void visitIfStatement(IfStatement node) {
    visit(node.condition);
    visit(node.thenBranch);
    if (node.elseBranch case final elseBranch?) {
      visit(elseBranch);
    }
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    visit(node.condition);
    visit(node.body);
  }

  @override
  void visitForStatement(ForStatement node) {
    visit(node.iterable);
    visit(node.body);
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    if (node.value case final value?) {
      visit(value);
    }
  }

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    visit(node.expression);
  }

  @override
  void visitBlock(Block node) {
    visitAll(node.statements);
  }

  @override
  void visitLiteral(LiteralExpression node) {}

  @override
  void visitIdentifier(IdentifierExpression node) {}

  @override
  void visitBinary(BinaryExpression node) {
    visit(node.left);
    visit(node.right);
  }

  @override
  void visitUnary(UnaryExpression node) {
    visit(node.operand);
  }

  @override
  void visitAssignment(AssignmentExpression node) {
    visit(node.value);
  }

  @override
  void visitCall(CallExpression node) {
    visit(node.callee);
    for (final arg in node.arguments) {
      visit(arg);
    }
  }

  @override
  void visitMember(MemberExpression node) {
    visit(node.object);
  }

  @override
  void visitGroup(GroupExpression node) {
    visit(node.expression);
  }

  @override
  void visitMatch(MatchExpression node) {
    visit(node.subject);
    for (final arm in node.arms) {
      visit(arm.body);
    }
  }
}
```

### Concrete Visitor: Scope Resolver

A practical visitor that resolves variable scopes and detects undefined references.

```dart
// lib/compiler/analysis/scope_resolver.dart

/// Resolves variable scopes and reports undefined references.
class ScopeResolver extends RecursiveAstVisitor {
  final List<Map<String, Token>> _scopes = [];
  final List<Diagnostic> diagnostics = [];

  void _beginScope() => _scopes.add({});
  void _endScope() => _scopes.removeLast();

  void _declare(Token name) {
    if (_scopes.isEmpty) return;
    final scope = _scopes.last;
    if (scope.containsKey(name.lexeme)) {
      diagnostics.add(Diagnostic(
        message: 'Variable "${name.lexeme}" already declared in this scope',
        span: name.span,
        severity: Severity.error,
        code: 'duplicate_declaration',
      ));
      return;
    }
    scope[name.lexeme] = name;
  }

  bool _resolve(Token name) {
    for (var i = _scopes.length - 1; i >= 0; i--) {
      if (_scopes[i].containsKey(name.lexeme)) return true;
    }
    return false;
  }

  @override
  void visitLetDeclaration(LetDeclaration node) {
    visit(node.initializer);
    _declare(node.name);
  }

  @override
  void visitFnDeclaration(FnDeclaration node) {
    _declare(node.name);
    _beginScope();
    for (final param in node.parameters) {
      _declare(param.name);
    }
    visit(node.body);
    _endScope();
  }

  @override
  void visitBlock(Block node) {
    _beginScope();
    visitAll(node.statements);
    _endScope();
  }

  @override
  void visitForStatement(ForStatement node) {
    visit(node.iterable);
    _beginScope();
    _declare(node.variable);
    visit(node.body);
    _endScope();
  }

  @override
  void visitIdentifier(IdentifierExpression node) {
    if (!_resolve(node.name)) {
      diagnostics.add(Diagnostic(
        message: 'Undefined variable "${node.name.lexeme}"',
        span: node.span,
        severity: Severity.error,
        code: 'undefined_variable',
      ));
    }
  }
}
```

### Concrete Visitor: AST Printer

A debugging visitor that pretty-prints the AST as an indented string representation.

```dart
// lib/compiler/debug/ast_printer.dart

/// Pretty-prints the AST for debugging.
class AstPrinter implements AstVisitor<String> {
  int _indent = 0;

  String print(AstNode node) => acceptNode(node, this);

  String _indented(String text) => '${"  " * _indent}$text';

  String _withIndent(String Function() body) {
    _indent++;
    final result = body();
    _indent--;
    return result;
  }

  @override
  String visitLetDeclaration(LetDeclaration node) {
    final type = node.typeAnnotation != null
        ? ': ${node.typeAnnotation!.name.lexeme}'
        : '';
    final init = _withIndent(() => print(node.initializer));
    return _indented('LetDecl(${node.name.lexeme}$type)\n$init');
  }

  @override
  String visitFnDeclaration(FnDeclaration node) {
    final params = node.parameters.map((p) => p.name.lexeme).join(', ');
    final body = _withIndent(() => print(node.body));
    return _indented('FnDecl(${node.name.lexeme}($params))\n$body');
  }

  @override
  String visitTypeDeclaration(TypeDeclaration node) =>
      _indented('TypeDecl(${node.name.lexeme} = ${node.type.name.lexeme})');

  @override
  String visitBinary(BinaryExpression node) {
    final left = _withIndent(() => print(node.left));
    final right = _withIndent(() => print(node.right));
    return _indented('Binary(${node.operator.lexeme})\n$left\n$right');
  }

  @override
  String visitUnary(UnaryExpression node) {
    final operand = _withIndent(() => print(node.operand));
    return _indented('Unary(${node.operator.lexeme})\n$operand');
  }

  @override
  String visitLiteral(LiteralExpression node) =>
      _indented('Literal(${node.value})');

  @override
  String visitIdentifier(IdentifierExpression node) =>
      _indented('Ident(${node.name.lexeme})');

  @override
  String visitAssignment(AssignmentExpression node) {
    final value = _withIndent(() => print(node.value));
    return _indented('Assign(${node.name.lexeme} ${node.operator.lexeme})\n$value');
  }

  @override
  String visitCall(CallExpression node) {
    final callee = _withIndent(() => print(node.callee));
    final args = node.arguments.map((a) => _withIndent(() => print(a))).join('\n');
    return _indented('Call\n$callee\n$args');
  }

  @override
  String visitMember(MemberExpression node) {
    final obj = _withIndent(() => print(node.object));
    return _indented('Member(.${node.name.lexeme})\n$obj');
  }

  @override
  String visitGroup(GroupExpression node) {
    final inner = _withIndent(() => print(node.expression));
    return _indented('Group\n$inner');
  }

  @override
  String visitMatch(MatchExpression node) {
    final subject = _withIndent(() => print(node.subject));
    final arms = node.arms.map((a) =>
      _withIndent(() => '${_indented("Arm")} => ${print(a.body)}'),
    ).join('\n');
    return _indented('Match\n$subject\n$arms');
  }

  @override
  String visitIfStatement(IfStatement node) {
    final cond = _withIndent(() => print(node.condition));
    final then = _withIndent(() => print(node.thenBranch));
    final elseStr = node.elseBranch != null
        ? '\n${_withIndent(() => print(node.elseBranch!))}'
        : '';
    return _indented('If\n$cond\n$then$elseStr');
  }

  @override
  String visitWhileStatement(WhileStatement node) {
    final cond = _withIndent(() => print(node.condition));
    final body = _withIndent(() => print(node.body));
    return _indented('While\n$cond\n$body');
  }

  @override
  String visitForStatement(ForStatement node) {
    final iter = _withIndent(() => print(node.iterable));
    final body = _withIndent(() => print(node.body));
    return _indented('For(${node.variable.lexeme})\n$iter\n$body');
  }

  @override
  String visitReturnStatement(ReturnStatement node) {
    final value = node.value != null
        ? '\n${_withIndent(() => print(node.value!))}'
        : '';
    return _indented('Return$value');
  }

  @override
  String visitExpressionStatement(ExpressionStatement node) =>
      print(node.expression);

  @override
  String visitBlock(Block node) {
    final stmts = node.statements.map((s) => _withIndent(() => print(s))).join('\n');
    return _indented('Block\n$stmts');
  }
}
```

---

## Error Recovery Strategies

Good error recovery is what separates a production parser from a toy parser. The goal is to report as many meaningful errors as possible from a single parse attempt, rather than stopping at the first syntax error.

### Panic Mode Recovery

The most widely used strategy. When the parser encounters an unexpected token, it enters "panic mode" and discards tokens until it reaches a **synchronization token** -- a token that reliably starts a new statement or declaration.

Synchronization tokens for a typical language:
- Semicolons (`;`) -- end of statement
- Keywords that begin declarations: `let`, `fn`, `type`, `class`
- Keywords that begin statements: `if`, `while`, `for`, `return`
- Closing braces (`}`) -- end of block

The `_synchronize()` method in the parser above implements this strategy:

```dart
void _synchronize() {
  _stream.advance(); // skip the problematic token

  while (!_stream.isAtEnd) {
    // Successfully passed a semicolon: the next token starts a new statement
    if (_stream.peek(-1).type == TokenType.semicolon) return;

    // Reached a declaration/statement keyword: synchronize here
    if (_stream.check({
      TokenType.kwLet,
      TokenType.kwFn,
      TokenType.kwType,
      TokenType.kwIf,
      TokenType.kwWhile,
      TokenType.kwFor,
      TokenType.kwReturn,
    })) return;

    _stream.advance();
  }
}
```

### Error Productions

Instead of only recovering after an error, you can define **error productions** in the grammar that anticipate common mistakes and produce specific, helpful error messages.

```dart
/// Handles common mistake: missing semicolon after expression.
ExpressionStatement _expressionStatement() {
  final expr = _expression();

  // Error production: missing semicolon
  if (_stream.tryConsume(TokenType.semicolon) == null) {
    _diagnostics.add(Diagnostic(
      message: 'Expected ";" after expression',
      span: SourceSpan(
        start: expr.span.end,
        end: expr.span.end,
        fileName: expr.span.fileName,
      ),
      severity: Severity.error,
      code: 'missing_semicolon',
    ));
    // Continue parsing as if the semicolon were present
  }

  return ExpressionStatement(expression: expr, span: expr.span);
}

/// Handles common mistake: using = instead of == in conditions.
Expression _equality() {
  var left = _comparison();

  while (_stream.check({TokenType.equalEqual, TokenType.bangEqual})) {
    final op = _stream.advance();
    final right = _comparison();
    left = BinaryExpression(
      left: left, operator: op, right: right,
      span: _spanBetween(left.span, right.span),
    );
  }

  // Error production: = used instead of ==
  if (_stream.check({TokenType.equal}) &&
      _isInsideCondition) {
    final op = _stream.advance();
    _diagnostics.add(Diagnostic(
      message: 'Did you mean "==" instead of "="?',
      span: op.span,
      severity: Severity.error,
      code: 'assignment_in_condition',
    ));
    final right = _comparison();
    left = BinaryExpression(
      left: left, operator: op, right: right,
      span: _spanBetween(left.span, right.span),
    );
  }

  return left;
}
```

### Token Insertion Recovery

When the parser expects a specific token (like a closing parenthesis), it can synthesize the missing token, report the error, and continue.

```dart
/// Expects a token, but inserts a synthetic one if missing.
Token _expectOrSynthesize(TokenType type, String message) {
  if (_stream.current.type == type) {
    return _stream.advance();
  }

  _diagnostics.add(Diagnostic(
    message: message,
    span: _stream.current.span,
    severity: Severity.error,
    code: 'missing_token',
  ));

  // Return a synthetic token so parsing can continue
  return Token(
    type: type,
    lexeme: '',
    span: SourceSpan(
      start: _stream.current.span.start,
      end: _stream.current.span.start,
      fileName: _stream.current.span.fileName,
    ),
  );
}
```

### Bracket Matching Recovery

For languages with nested brackets, maintain a stack of expected closing delimiters. When the parser encounters a mismatched closing bracket, it can report a better error.

```dart
/// Tracks nesting to provide better mismatch errors.
class BracketTracker {
  final List<Token> _stack = [];

  void push(Token openToken) => _stack.add(openToken);

  Diagnostic? pop(Token closeToken) {
    if (_stack.isEmpty) {
      return Diagnostic(
        message: 'Unexpected "${closeToken.lexeme}" with no matching opener',
        span: closeToken.span,
        severity: Severity.error,
        code: 'unmatched_close',
      );
    }

    final open = _stack.removeLast();
    final expected = _matchingClose(open.type);

    if (closeToken.type != expected) {
      return Diagnostic(
        message: 'Expected "${_tokenName(expected)}" to close '
            '"${open.lexeme}" at ${open.span}, '
            'but found "${closeToken.lexeme}"',
        span: closeToken.span,
        severity: Severity.error,
        code: 'mismatched_brackets',
      );
    }

    return null;
  }

  List<Diagnostic> checkUnclosed() {
    return _stack.reversed.map((open) => Diagnostic(
      message: 'Unclosed "${open.lexeme}" opened at ${open.span}',
      span: open.span,
      severity: Severity.error,
      code: 'unclosed_bracket',
    )).toList();
  }

  TokenType _matchingClose(TokenType open) => switch (open) {
    TokenType.leftParen   => TokenType.rightParen,
    TokenType.leftBrace   => TokenType.rightBrace,
    TokenType.leftBracket => TokenType.rightBracket,
    _                     => TokenType.eof,
  };

  String _tokenName(TokenType type) => switch (type) {
    TokenType.rightParen   => ')',
    TokenType.rightBrace   => '}',
    TokenType.rightBracket => ']',
    _                      => type.name,
  };
}
```

### Recovery Strategy Comparison

| Strategy | Complexity | Error Quality | Use Case |
|----------|-----------|---------------|----------|
| Panic mode | Low | Good for statement-level | General-purpose, default choice |
| Error productions | Medium | Excellent, targeted messages | Common known mistakes |
| Token insertion | Low | Good for missing delimiters | Closing brackets, semicolons |
| Bracket matching | Medium | Excellent for nesting errors | Bracket-heavy grammars |
| Backtracking | High | Variable | Ambiguous grammars |

---

## Parser Combinators vs Hand-Written Parsers

### Parser Combinators

Combinators treat parsers as composable values. Each combinator is a function that takes parsers as input and returns a new parser. This approach is declarative and maps closely to the grammar.

```dart
// lib/compiler/combinator/combinator.dart

/// A parser combinator: a function from input to a parse result.
typedef Parser<T> = ParseCombinatorResult<T> Function(TokenStream stream);

sealed class ParseCombinatorResult<T> {
  const ParseCombinatorResult();
}

final class CombinatorSuccess<T> extends ParseCombinatorResult<T> {
  final T value;
  const CombinatorSuccess(this.value);
}

final class CombinatorFailure<T> extends ParseCombinatorResult<T> {
  final String message;
  final SourceSpan span;
  const CombinatorFailure(this.message, this.span);
}

// --- Primitive combinators ---

/// Matches a single token of the given type.
Parser<Token> token(TokenType type) {
  return (stream) {
    if (stream.current.type == type) {
      return CombinatorSuccess(stream.advance());
    }
    return CombinatorFailure(
      'Expected ${type.name}, found ${stream.current.type.name}',
      stream.current.span,
    );
  };
}

/// Matches one of several token types.
Parser<Token> oneOf(Set<TokenType> types) {
  return (stream) {
    if (types.contains(stream.current.type)) {
      return CombinatorSuccess(stream.advance());
    }
    final expected = types.map((t) => t.name).join(' | ');
    return CombinatorFailure(
      'Expected $expected, found ${stream.current.type.name}',
      stream.current.span,
    );
  };
}

// --- Combining combinators ---

/// Runs [parser] and transforms its result with [transform].
Parser<U> map<T, U>(Parser<T> parser, U Function(T) transform) {
  return (stream) {
    final result = parser(stream);
    return switch (result) {
      CombinatorSuccess(:final value) => CombinatorSuccess(transform(value)),
      CombinatorFailure(:final message, :final span) =>
          CombinatorFailure(message, span),
    };
  };
}

/// Tries [first], falls back to [second] on failure (with backtracking).
Parser<T> or<T>(Parser<T> first, Parser<T> second) {
  return (stream) {
    stream.mark();
    final result = first(stream);
    if (result is CombinatorSuccess<T>) {
      stream.commit();
      return result;
    }
    stream.reset();
    return second(stream);
  };
}

/// Parses [parser] zero or more times.
Parser<List<T>> many<T>(Parser<T> parser) {
  return (stream) {
    final results = <T>[];
    while (true) {
      stream.mark();
      final result = parser(stream);
      if (result is CombinatorSuccess<T>) {
        stream.commit();
        results.add(result.value);
      } else {
        stream.reset();
        break;
      }
    }
    return CombinatorSuccess(results);
  };
}

/// Parses [left], then [content], then [right], returning [content]'s result.
Parser<T> between<T>(
  Parser<dynamic> left,
  Parser<T> content,
  Parser<dynamic> right,
) {
  return (stream) {
    final l = left(stream);
    if (l is CombinatorFailure) {
      return CombinatorFailure(
        (l as CombinatorFailure).message,
        (l as CombinatorFailure).span,
      );
    }
    final c = content(stream);
    if (c is CombinatorFailure) {
      return CombinatorFailure(
        (c as CombinatorFailure).message,
        (c as CombinatorFailure).span,
      );
    }
    final r = right(stream);
    if (r is CombinatorFailure) {
      return CombinatorFailure(
        (r as CombinatorFailure).message,
        (r as CombinatorFailure).span,
      );
    }
    return c;
  };
}

/// Parses items separated by a delimiter.
Parser<List<T>> separatedBy<T>(Parser<T> item, Parser<dynamic> separator) {
  return (stream) {
    final results = <T>[];
    final first = item(stream);
    if (first is CombinatorFailure) return CombinatorSuccess(results);
    results.add((first as CombinatorSuccess<T>).value);

    while (true) {
      stream.mark();
      final sep = separator(stream);
      if (sep is CombinatorFailure) {
        stream.reset();
        break;
      }
      stream.commit();
      final next = item(stream);
      if (next is CombinatorFailure) break;
      results.add((next as CombinatorSuccess<T>).value);
    }

    return CombinatorSuccess(results);
  };
}
```

### Comparison: Combinators vs Hand-Written

| Aspect | Parser Combinators | Hand-Written Recursive Descent |
|--------|-------------------|-------------------------------|
| **Readability** | Declarative, mirrors grammar | Imperative, method-per-rule |
| **Error messages** | Generic by default, need effort to customize | Easy to provide context-specific messages |
| **Error recovery** | Difficult to implement well | Full control over recovery strategy |
| **Performance** | Overhead from closures, backtracking | Direct token access, minimal overhead |
| **Left recursion** | Requires workarounds or Pratt parsing | Handle via loop-based precedence climbing |
| **Debugging** | Harder (stack traces through lambdas) | Easy (stack traces name the grammar rule) |
| **Maintenance** | Adding rules = composing new combinators | Adding rules = adding new methods |
| **Best for** | Simple grammars, DSLs, config languages | Production compilers, complex grammars |

**Recommendation:** Use hand-written recursive descent for production parsers where error recovery and performance matter. Use combinators for quick prototypes, simple DSLs, or configuration file parsers.

---

## Validation Pass

The semantic validation pass walks the AST after parsing to check constraints that cannot be expressed in the grammar alone: type mismatches, undefined references, unreachable code, and more.

```dart
// lib/compiler/analysis/semantic_validator.dart

/// Result of the semantic validation pass.
@immutable
final class ValidationResult {
  final AstNode annotatedAst;
  final List<Diagnostic> diagnostics;

  const ValidationResult({
    required this.annotatedAst,
    required this.diagnostics,
  });

  bool get hasFatalErrors =>
      diagnostics.any((d) => d.severity == Severity.error);
}

/// Runs multiple analysis visitors over the AST.
class SemanticValidator {
  ValidationResult validate(List<AstNode> ast) {
    final allDiagnostics = <Diagnostic>[];

    // Pass 3a: Resolve scopes and detect undefined variables
    final scopeResolver = ScopeResolver();
    for (final node in ast) {
      scopeResolver.visit(node);
    }
    allDiagnostics.addAll(scopeResolver.diagnostics);

    // Pass 3b: Check for unreachable code after return statements
    final reachabilityChecker = ReachabilityChecker();
    for (final node in ast) {
      reachabilityChecker.visit(node);
    }
    allDiagnostics.addAll(reachabilityChecker.diagnostics);

    // Pass 3c: Validate match expression exhaustiveness
    final matchChecker = MatchExhaustivenessChecker();
    for (final node in ast) {
      matchChecker.visit(node);
    }
    allDiagnostics.addAll(matchChecker.diagnostics);

    return ValidationResult(
      annotatedAst: Block(
        statements: ast,
        span: ast.isEmpty
            ? const SourceSpan(
                start: SourcePosition(offset: 0, line: 1, column: 1),
                end: SourcePosition(offset: 0, line: 1, column: 1),
              )
            : SourceSpan(
                start: ast.first.span.start,
                end: ast.last.span.end,
              ),
      ),
      diagnostics: allDiagnostics,
    );
  }
}

/// Detects unreachable code after return statements within blocks.
class ReachabilityChecker extends RecursiveAstVisitor {
  final List<Diagnostic> diagnostics = [];

  @override
  void visitBlock(Block node) {
    var foundReturn = false;
    for (final stmt in node.statements) {
      if (foundReturn) {
        diagnostics.add(Diagnostic(
          message: 'Unreachable code after return statement',
          span: stmt.span,
          severity: Severity.warning,
          code: 'unreachable_code',
        ));
        break; // Only report once per block
      }
      if (stmt is ReturnStatement) {
        foundReturn = true;
      }
      visit(stmt);
    }
  }
}
```

---

## Performance Optimization

Production parsers must meet strict latency targets. For interactive use cases (IDE integration, live preview), a full parse should complete in under 10 milliseconds for files up to 10,000 lines.

### Profiling the Pipeline

Always measure before optimizing. Break the pipeline into timed segments:

```dart
// lib/compiler/profiled_pipeline.dart

class ProfiledPipeline {
  final CompilerPipeline _inner;

  const ProfiledPipeline(this._inner);

  CompilationResult compile(String source, {String? fileName}) {
    final total = Stopwatch()..start();

    final lexStopwatch = Stopwatch()..start();
    final tokenResult = _inner._lexer.tokenize(source, fileName: fileName);
    lexStopwatch.stop();

    final parseStopwatch = Stopwatch()..start();
    final parseResult = _inner._parser.parse(tokenResult.tokens);
    parseStopwatch.stop();

    final validateStopwatch = Stopwatch()..start();
    final validationResult = _inner._validator.validate(parseResult.ast);
    validateStopwatch.stop();

    total.stop();

    print('Lexer:      ${lexStopwatch.elapsedMicroseconds}us '
        '(${tokenResult.tokens.length} tokens)');
    print('Parser:     ${parseStopwatch.elapsedMicroseconds}us');
    print('Validator:  ${validateStopwatch.elapsedMicroseconds}us');
    print('Total:      ${total.elapsedMicroseconds}us');

    // Fail if any pass exceeds budget
    assert(total.elapsedMilliseconds < 10,
        'Parse exceeded 10ms budget: ${total.elapsedMilliseconds}ms');

    return _inner.compile(source, fileName: fileName);
  }
}
```

### Key Optimization Techniques

**1. Avoid string allocation in the lexer**

Use offsets into the original source string instead of creating substring copies for each token lexeme. Only materialize the string when needed.

```dart
// Instead of:
final lexeme = _source.substring(_start, _current); // allocates a new String

// Use a lazy approach:
final class Token {
  final TokenType type;
  final int startOffset;
  final int endOffset;
  final String _source; // reference to the full source

  String get lexeme => _source.substring(startOffset, endOffset); // only when needed
}
```

**2. Pre-size collections**

When the approximate token count is known (roughly 1 token per 4-5 characters of source), pre-allocate the list:

```dart
TokenizeResult _scanAll() {
  final estimatedTokenCount = _source.length ~/ 4;
  final tokens = List<Token>.empty(growable: true)
    ..length = 0; // Dart does not support capacity hints directly
  // Alternative: use a fixed-size list and track count manually for hot paths
  // ...
}
```

**3. Use code unit comparisons instead of string comparisons**

Character comparisons via `codeUnitAt` are faster than comparing single-character strings:

```dart
// Faster than: if (c == '(')
bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
bool _isAlpha(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5A) || // A-Z
    (codeUnit >= 0x61 && codeUnit <= 0x7A) || // a-z
    codeUnit == 0x5F;                          // _

void _scanToken() {
  final c = _source.codeUnitAt(_current);
  _current++;
  switch (c) {
    case 0x28: _addToken(TokenType.leftParen);  // '('
    case 0x29: _addToken(TokenType.rightParen); // ')'
    // ... etc
  }
}
```

**4. Keyword lookup via perfect hashing or sorted switch**

For a small, fixed set of keywords, a switch statement on string length followed by character checks can outperform HashMap lookups:

```dart
TokenType? _lookupKeyword(String lexeme) {
  return switch (lexeme.length) {
    2 => switch (lexeme) {
      'fn' => TokenType.kwFn,
      'if' => TokenType.kwIf,
      'in' => TokenType.kwIn,
      _ => null,
    },
    3 => switch (lexeme) {
      'let' => TokenType.kwLet,
      'for' => TokenType.kwFor,
      _ => null,
    },
    4 => switch (lexeme) {
      'else' => TokenType.kwElse,
      'true' => TokenType.kwTrue,
      'null' => TokenType.kwNull,
      'type' => TokenType.kwType,
      _ => null,
    },
    5 => switch (lexeme) {
      'const' => TokenType.kwConst,
      'while' => TokenType.kwWhile,
      'false' => TokenType.kwFalse,
      'match' => TokenType.kwMatch,
      _ => null,
    },
    6 => switch (lexeme) {
      'return' => TokenType.kwReturn,
      _ => null,
    },
    _ => null,
  };
}
```

**5. Minimize visitor allocations**

Reuse visitor instances across multiple files. Avoid creating closures or temporary lists during tree walks. Use mutable state within the visitor rather than building up result values functionally.

**6. Incremental parsing**

For IDE integration, re-parse only the changed region of the file. Track which AST nodes correspond to which source ranges. When the user edits a line, invalidate only the AST subtree that overlaps the edit and re-parse from the enclosing block boundary.

### Performance Budget Guidelines

| File Size | Token Count | Target Lex | Target Parse | Target Total |
|-----------|-------------|-----------|-------------|-------------|
| 100 lines | ~500 | <0.5ms | <1ms | <2ms |
| 1,000 lines | ~5,000 | <2ms | <3ms | <6ms |
| 10,000 lines | ~50,000 | <5ms | <8ms | <15ms |
| 100,000 lines | ~500,000 | <30ms | <50ms | <100ms |

For files under 10,000 lines (typical for a single source file), the total pipeline should complete within 10-15ms on modern hardware.

---

## Best Practices

1. **Separate passes cleanly.** Each pass (lex, parse, validate, generate) should have a well-defined input type, output type, and diagnostic list. Never let pass N depend on internal state of pass N-1.

2. **Attach source spans to every AST node.** This is non-negotiable for useful error messages, IDE integration, and source maps. Propagate spans through all transformations.

3. **Use sealed classes for exhaustive matching.** Dart 3.x sealed hierarchies let the compiler verify you handle every node type. A missing case is a compile error, not a runtime bug.

4. **Prefer `final class` for leaf AST nodes.** This prevents external subclassing and enables the compiler to reason about the sealed hierarchy precisely.

5. **Collect errors, do not throw on the first one.** A parser that reports only one error per run forces the user into a frustrating fix-one-recompile loop. Use error recovery to report multiple errors.

6. **Document the grammar in EBNF.** Every parsing method should correspond to a named grammar rule. Keep the grammar in a comment or separate file so it can be reviewed independently.

7. **Test each pass in isolation.** Write unit tests for the lexer with raw strings as input and expected token lists as output. Test the parser with token lists and expected ASTs. Test validators with handcrafted ASTs.

8. **Keep the lexer stateless between tokens.** The lexer should not need to know what the parser is doing. If you find yourself needing context-sensitive tokenization, consider a two-phase approach where a post-lexer fixup pass re-classifies tokens.

9. **Use the visitor pattern for all tree operations.** Avoid adding methods directly to AST node classes for operations like printing, type checking, or code generation. Visitors keep node classes focused on data.

10. **Profile before optimizing.** Measure where time is actually spent. Typically the lexer dominates for simple grammars, and the validator dominates for complex languages.

11. **Handle Unicode properly.** If your language supports Unicode identifiers, use `String.runes` or a Unicode-aware library rather than assuming ASCII code points.

12. **Version your AST format.** If the AST is serialized (for caching or IPC), include a version number so stale caches can be invalidated when the grammar changes.

---

## Anti-Patterns

- **Mixing lexing and parsing into a single pass.** This makes the code harder to test, debug, and maintain. Even if performance is critical, keep the logical separation and inline only after profiling proves it necessary.

- **Using dynamic types or `Map<String, dynamic>` for AST nodes.** You lose exhaustiveness checking, autocomplete, and refactoring safety. Always use typed sealed class hierarchies.

- **Throwing exceptions for recoverable syntax errors.** Exceptions should be reserved for truly unexpected situations (internal compiler bugs). Syntax errors are expected input; collect them as diagnostics and continue parsing.

- **Forgetting source locations on AST nodes.** Once you build an AST without spans, retrofitting them is extremely painful. Add spans from the start.

- **Building a parser without a written grammar.** Ad-hoc parsing methods that do not correspond to documented production rules become unmaintainable as the language grows.

- **Using regexes for tokenization.** Regular expressions have overhead from compilation and backtracking that hand-written character-by-character scanning avoids. For a lexer that runs millions of times, this overhead compounds.

- **Mutating AST nodes after construction.** Mutable ASTs lead to aliasing bugs and make it unsafe to share subtrees across passes. Use immutable nodes and create new nodes when transformations are needed.

- **Ignoring operator precedence in expression parsing.** Implementing all binary operators at the same precedence level produces incorrect parse trees. Use precedence climbing (as shown above) or a Pratt parser.

- **Single-error-and-stop parsing.** Reporting only the first error and halting forces users into a tedious fix-one-recompile cycle. Invest in error recovery from the beginning.

- **Allocating strings for every token lexeme eagerly.** In the lexer, store offsets into the source string and materialize substrings lazily. This can reduce GC pressure by 30-50% on large files.

- **Not testing error recovery paths.** Error recovery code paths are some of the most important to test. Write tests with intentionally malformed input and assert that the parser recovers and reports reasonable subsequent errors.

- **Deeply nested visitor dispatch via if/else chains.** Use Dart 3.x `switch` expressions on sealed types instead of manual `is` checks. The compiler enforces exhaustiveness and the code is more concise.

---

## Sources & References

- Crafting Interpreters by Robert Nystrom (comprehensive guide to lexer/parser/interpreter design): https://craftinginterpreters.com/
- Dart Language Specification -- Sealed Classes and Pattern Matching: https://dart.dev/language/class-modifiers#sealed
- Dart Language Tour -- Patterns: https://dart.dev/language/patterns
- Engineering a Compiler (Cooper & Torczon), Chapter 3 -- Parsing: https://www.elsevier.com/books/engineering-a-compiler/cooper/978-0-12-815412-0
- Modern Compiler Implementation in ML (Appel), Chapter 3 -- Recursive Descent: https://www.cs.princeton.edu/~appel/modern/ml/
- Simple but Powerful Pratt Parsing (Nystrom): https://journal.stuffwithstuff.com/2011/03/19/pratt-parsers-expression-parsing-made-easy/
- Writing a Parser Combinator from Scratch in Haskell (applicable concepts): https://serokell.io/blog/parser-combinators-in-haskell
- Resilient LL Parsing (for IDE-grade error recovery): https://matklad.github.io/2023/05/21/resilient-ll-parsing-tutorial.html

---
name: graph-export
description: Mermaid diagram generation, PlantUML diagram generation, SVG rendering and optimization, JSON serialization with round-trip verification, and export pipeline architecture for AST/graph structures in Dart
---

# Graph & AST Export

Export pipeline patterns for converting AST and graph structures into Mermaid diagrams, PlantUML diagrams, SVG images, and JSON interchange formats. Covers syntax generation, format detection, content negotiation, round-trip serialization, and optimization techniques using Dart 3.x.

## Table of Contents

1. [Mermaid Diagram Syntax](#mermaid-diagram-syntax)
2. [Generating Mermaid from AST/Graph Structures](#generating-mermaid-from-astgraph-structures)
3. [PlantUML Diagram Syntax](#plantuml-diagram-syntax)
4. [Generating PlantUML from AST/Graph Structures](#generating-plantuml-from-astgraph-structures)
5. [SVG Generation](#svg-generation)
6. [SVG Optimization and Minification](#svg-optimization-and-minification)
7. [JSON Serialization of AST Trees](#json-serialization-of-ast-trees)
8. [JSON Schema for AST Interchange Format](#json-schema-for-ast-interchange-format)
9. [Round-Trip Serialization](#round-trip-serialization)
10. [Export Pipeline Architecture](#export-pipeline-architecture)
11. [Format Detection and Content Negotiation](#format-detection-and-content-negotiation)
12. [Best Practices](#best-practices)
13. [Anti-Patterns](#anti-patterns)
14. [Sources & References](#sources--references)

---

## Mermaid Diagram Syntax

Mermaid is a JavaScript-based diagramming and charting tool that uses a Markdown-like text syntax to produce diagrams in the browser. When generating Mermaid output from AST or graph structures, it is essential to understand the syntax for the three primary diagram types: flowcharts, class diagrams, and sequence diagrams.

### Flowcharts

Flowcharts use a direction keyword followed by node and edge declarations. Valid directions are `TB` (top to bottom), `TD` (top down, same as TB), `BT` (bottom to top), `LR` (left to right), and `RL` (right to left).

Node shapes:
- `A[Text]` -- rectangle
- `A(Text)` -- rounded rectangle
- `A([Text])` -- stadium shape
- `A{Text}` -- diamond (decision)
- `A((Text))` -- circle
- `A>Text]` -- asymmetric / flag
- `A[/Text/]` -- parallelogram
- `A[\Text\]` -- reverse parallelogram
- `A[/Text\]` -- trapezoid
- `A[\Text/]` -- reverse trapezoid

Edge types:
- `A --> B` -- arrow
- `A --- B` -- line (no arrow)
- `A -.- B` -- dotted line
- `A -.-> B` -- dotted arrow
- `A ==> B` -- thick arrow
- `A -- label --> B` -- arrow with label
- `A -. label .-> B` -- dotted arrow with label

Subgraphs group related nodes:

```
flowchart TD
    subgraph parsing[Parsing Phase]
        A[Lexer] --> B[Token Stream]
        B --> C[Parser]
    end
    subgraph analysis[Analysis Phase]
        C --> D{Valid AST?}
        D -- yes --> E[Semantic Analyzer]
        D -- no --> F[Error Reporter]
    end
```

### Class Diagrams

Class diagrams declare classes, their members, and relationships using UML-like syntax:

```
classDiagram
    class AstNode {
        +String type
        +List~AstNode~ children
        +Map~String, dynamic~ metadata
        +accept(AstVisitor visitor) T
    }
    class Expression {
        +Token operator
        +Expression left
        +Expression right
    }
    AstNode <|-- Expression : extends
    AstNode <|-- Statement : extends
    AstNode o-- AstNode : children
```

Relationship types:
- `A <|-- B` -- inheritance (B extends A)
- `A *-- B` -- composition (A owns B)
- `A o-- B` -- aggregation (A has B)
- `A --> B` -- association
- `A ..> B` -- dependency
- `A ..|> B` -- realization / implements

Visibility markers: `+` public, `-` private, `#` protected, `~` package-private.

Generics are expressed with tildes: `List~AstNode~` renders as `List<AstNode>`.

### Sequence Diagrams

Sequence diagrams show interactions between participants over time:

```
sequenceDiagram
    participant C as Client
    participant P as Parser
    participant L as Lexer
    participant E as Exporter

    C->>P: parse(source)
    P->>L: tokenize(source)
    L-->>P: List<Token>
    P-->>C: AstNode
    C->>E: export(ast, format)
    E-->>C: String
```

Arrow types:
- `->` solid line without arrowhead
- `->>` solid line with arrowhead
- `-->` dashed line without arrowhead
- `-->>` dashed line with arrowhead
- `-x` solid line with cross (async)
- `--x` dashed line with cross (async)

Activation boxes use `activate`/`deactivate` or the `+`/`-` suffixes on arrows (e.g., `->>+` activates, `-->>-` deactivates).

---

## Generating Mermaid from AST/Graph Structures

The key challenge is mapping AST node types and edges to valid Mermaid syntax while handling identifier uniqueness, special character escaping, and layout direction.

### Node ID Generation

Mermaid node IDs must be alphanumeric (with underscores). Avoid hyphens, dots, and spaces. A reliable approach is to generate short unique IDs and use labels for display text:

```dart
/// Generates Mermaid diagram syntax from an AST or directed graph.
///
/// Supports flowchart, classDiagram, and sequenceDiagram output.
/// Node IDs are auto-generated to avoid conflicts with Mermaid keywords.
class MermaidGenerator {
  final StringBuffer _buffer = StringBuffer();
  int _idCounter = 0;
  final Map<AstNode, String> _nodeIds = {};

  /// Returns a unique, Mermaid-safe identifier for [node].
  ///
  /// Re-uses the same ID if the node has already been registered,
  /// ensuring edges reference the correct node.
  String _idFor(AstNode node) {
    return _nodeIds.putIfAbsent(node, () => 'n${_idCounter++}');
  }

  /// Escapes label text so that Mermaid renders it literally.
  ///
  /// Wraps labels containing special characters in double quotes
  /// and escapes internal quotes.
  String _escapeLabel(String text) {
    if (RegExp(r'["\[\]{}()<>|/\\]').hasMatch(text)) {
      return '"${text.replaceAll('"', '#quot;')}"';
    }
    return text;
  }

  /// Determines the appropriate Mermaid node shape based on
  /// the AST node's semantic role.
  String _shapeFor(AstNode node, String id, String label) => switch (node) {
    DecisionNode() => '$id{$label}',
    TerminalNode() => '$id([$label])',
    GroupNode()    => '$id[[$label]]',
    _              => '$id[$label]',
  };

  /// Generates a complete Mermaid flowchart from the given [root] node.
  ///
  /// Traverses the AST depth-first and emits node declarations and
  /// edges. The [direction] controls the layout orientation.
  String generateFlowchart(
    AstNode root, {
    FlowDirection direction = FlowDirection.topDown,
  }) {
    _buffer.clear();
    _nodeIds.clear();
    _idCounter = 0;

    _buffer.writeln('flowchart ${direction.mermaidCode}');
    _visitNode(root);
    return _buffer.toString();
  }

  void _visitNode(AstNode node) {
    final id = _idFor(node);
    final label = _escapeLabel(node.displayLabel);
    final shape = _shapeFor(node, id, label);

    _buffer.writeln('    $shape');

    for (final child in node.children) {
      final childId = _idFor(child);
      final edgeLabel = node.edgeLabelTo(child);

      if (edgeLabel != null) {
        _buffer.writeln('    $id -- ${_escapeLabel(edgeLabel)} --> $childId');
      } else {
        _buffer.writeln('    $id --> $childId');
      }

      _visitNode(child);
    }
  }

  /// Generates a Mermaid class diagram from a list of type definitions.
  ///
  /// Each [TypeDefinition] is rendered as a class with its fields,
  /// methods, and relationships to other types.
  String generateClassDiagram(List<TypeDefinition> types) {
    _buffer.clear();
    _buffer.writeln('classDiagram');

    for (final type in types) {
      _buffer.writeln('    class ${type.name} {');
      for (final field in type.fields) {
        final visibility = field.isPublic ? '+' : '-';
        final genericType = field.typeString.replaceAll('<', '~').replaceAll('>', '~');
        _buffer.writeln('        $visibility$genericType ${field.name}');
      }
      for (final method in type.methods) {
        final visibility = method.isPublic ? '+' : '-';
        final returnType = method.returnType.replaceAll('<', '~').replaceAll('>', '~');
        final params = method.parameters.map((p) => p.typeString).join(', ');
        _buffer.writeln('        $visibility${method.name}($params) $returnType');
      }
      _buffer.writeln('    }');
    }

    // Emit relationships after all class bodies.
    for (final type in types) {
      if (type.superType case final superType?) {
        _buffer.writeln('    ${superType.name} <|-- ${type.name}');
      }
      for (final iface in type.interfaces) {
        _buffer.writeln('    ${iface.name} ..|> ${type.name}');
      }
      for (final comp in type.compositions) {
        _buffer.writeln('    ${type.name} *-- ${comp.name}');
      }
    }

    return _buffer.toString();
  }
}

/// Layout direction for Mermaid flowcharts.
enum FlowDirection {
  topDown('TD'),
  bottomUp('BT'),
  leftRight('LR'),
  rightLeft('RL');

  const FlowDirection(this.mermaidCode);
  final String mermaidCode;
}
```

### Subgraph Handling

When a node is a `GroupNode` (representing a scope, module, or namespace), wrap its children in a Mermaid `subgraph` block. Indent consistently (four spaces) and ensure the subgraph ID is unique.

### Escaping Pitfalls

- Mermaid interprets `(`, `)`, `[`, `]`, `{`, `}` as shape delimiters. If these appear in labels, wrap the label in double quotes.
- The `#` character introduces HTML entity codes in Mermaid. Use `#35;` to render a literal `#`.
- Semicolons can terminate statements early. Wrap labels containing semicolons in quotes.

---

## PlantUML Diagram Syntax

PlantUML uses a text-based DSL wrapped in `@startuml` / `@enduml` blocks. It supports a broader range of diagram types than Mermaid. The three most relevant for AST/graph export are component diagrams, activity diagrams, and class diagrams.

### Component Diagrams

Component diagrams show high-level system structure:

```
@startuml
package "Compiler Frontend" {
    [Lexer] --> [Parser]
    [Parser] --> [AST Builder]
}

package "Compiler Backend" {
    [Code Generator]
    [Optimizer]
}

[AST Builder] --> [Optimizer]
[Optimizer] --> [Code Generator]
@enduml
```

Components are declared with `[Name]`. Packages group related components. Interfaces use `()` syntax: `() "API" as api`.

### Activity Diagrams (New Syntax)

PlantUML's new activity diagram syntax uses `:` and `;` for actions and structured control flow:

```
@startuml
start
:Read source file;
:Tokenize input;
if (Valid tokens?) then (yes)
    :Build AST;
    if (Semantic errors?) then (yes)
        :Report errors;
        stop
    else (no)
        :Optimize AST;
    endif
else (no)
    :Report lexer errors;
    stop
endif
:Export to selected format;
stop
@enduml
```

Control structures: `if/then/else/endif`, `while/endwhile`, `repeat/repeat while`, `fork/fork again/end fork`, `switch/case/endswitch`.

### Class Diagrams

PlantUML class diagrams follow UML notation:

```
@startuml
abstract class AstNode {
    + type: String
    + children: List<AstNode>
    + {abstract} accept(visitor: AstVisitor): T
}

class BinaryExpression extends AstNode {
    + operator: Token
    + left: Expression
    + right: Expression
}

class UnaryExpression extends AstNode {
    + operator: Token
    + operand: Expression
}

AstNode "1" *-- "0..*" AstNode : children
@enduml
```

Relationship arrows:
- `A <|-- B` -- extension
- `A <|.. B` -- implementation
- `A *-- B` -- composition
- `A o-- B` -- aggregation
- `A --> B` -- directed association
- `A ..> B` -- dependency

Visibility: `+` public, `-` private, `#` protected, `~` package.

Stereotypes are declared with `<<stereotype>>` on the class line.

---

## Generating PlantUML from AST/Graph Structures

Generating PlantUML follows a similar visitor-based approach as Mermaid, but the syntax differences require a separate formatter. PlantUML is more verbose but supports richer features like notes, stereotypes, and skinparams.

```dart
/// Generates PlantUML diagram text from AST/graph structures.
///
/// Supports component, activity, and class diagram output formats.
/// Each diagram is wrapped in @startuml / @enduml markers and can
/// include optional skinparam customization.
class PlantUmlGenerator {
  final StringBuffer _buffer = StringBuffer();
  final PlantUmlTheme _theme;

  PlantUmlGenerator({PlantUmlTheme? theme})
      : _theme = theme ?? const PlantUmlTheme.defaultTheme();

  /// Generates a PlantUML class diagram from type definitions.
  ///
  /// Each type is rendered with its fields, methods, relationships,
  /// and optional stereotypes. Abstract classes and interfaces are
  /// distinguished by their declaration keyword.
  String generateClassDiagram(List<TypeDefinition> types) {
    _buffer.clear();
    _buffer.writeln('@startuml');
    _writeSkinParams();

    for (final type in types) {
      final keyword = switch (type.kind) {
        TypeKind.abstract_  => 'abstract class',
        TypeKind.interface_ => 'interface',
        TypeKind.enum_      => 'enum',
        _                   => 'class',
      };

      final stereotype = type.stereotype != null
          ? ' <<${type.stereotype}>>'
          : '';

      final extends_ = type.superType != null
          ? ' extends ${type.superType!.name}'
          : '';

      final implements_ = type.interfaces.isNotEmpty
          ? ' implements ${type.interfaces.map((i) => i.name).join(', ')}'
          : '';

      _buffer.writeln('$keyword ${type.name}$stereotype$extends_$implements_ {');

      for (final field in type.fields) {
        final vis = _visibility(field.isPublic);
        _buffer.writeln('    $vis ${field.name}: ${field.typeString}');
      }

      for (final method in type.methods) {
        final vis = _visibility(method.isPublic);
        final abstract_ = method.isAbstract ? '{abstract} ' : '';
        final static_ = method.isStatic ? '{static} ' : '';
        final params = method.parameters
            .map((p) => '${p.name}: ${p.typeString}')
            .join(', ');
        _buffer.writeln('    $vis $abstract_$static_${method.name}($params): ${method.returnType}');
      }

      _buffer.writeln('}');
      _buffer.writeln();
    }

    // Emit composition and aggregation relationships.
    for (final type in types) {
      for (final comp in type.compositions) {
        final card = comp.cardinality ?? '"1" -- "0..*"';
        _buffer.writeln('${type.name} $card ${comp.targetName} : ${comp.label}');
      }
    }

    _buffer.writeln('@enduml');
    return _buffer.toString();
  }

  /// Generates a PlantUML activity diagram from a control-flow graph.
  ///
  /// Walks the CFG and emits PlantUML new-syntax activity actions,
  /// conditionals, loops, and fork/join blocks.
  String generateActivityDiagram(ControlFlowGraph cfg) {
    _buffer.clear();
    _buffer.writeln('@startuml');
    _writeSkinParams();
    _buffer.writeln('start');

    _walkCfgBlock(cfg.entryBlock);

    _buffer.writeln('stop');
    _buffer.writeln('@enduml');
    return _buffer.toString();
  }

  /// Generates a PlantUML component diagram from module dependencies.
  String generateComponentDiagram(List<ModuleNode> modules) {
    _buffer.clear();
    _buffer.writeln('@startuml');
    _writeSkinParams();

    // Group modules into packages by their parent namespace.
    final grouped = <String, List<ModuleNode>>{};
    for (final m in modules) {
      grouped.putIfAbsent(m.namespace, () => []).add(m);
    }

    for (final MapEntry(:key, :value) in grouped.entries) {
      _buffer.writeln('package "$key" {');
      for (final m in value) {
        _buffer.writeln('    [${m.name}]');
      }
      _buffer.writeln('}');
      _buffer.writeln();
    }

    // Emit inter-module dependencies.
    for (final m in modules) {
      for (final dep in m.dependencies) {
        _buffer.writeln('[${m.name}] --> [${dep.name}]');
      }
    }

    _buffer.writeln('@enduml');
    return _buffer.toString();
  }

  void _writeSkinParams() {
    _buffer.writeln('skinparam backgroundColor ${_theme.backgroundColor}');
    _buffer.writeln('skinparam classFontSize ${_theme.fontSize}');
    _buffer.writeln('skinparam defaultFontName "${_theme.fontFamily}"');
    _buffer.writeln();
  }

  String _visibility(bool isPublic) => isPublic ? '+' : '-';

  void _walkCfgBlock(CfgBlock block) {
    for (final stmt in block.statements) {
      switch (stmt) {
        case ActionStatement(:final label):
          _buffer.writeln(':$label;');

        case ConditionalStatement(:final condition, :final thenBlock, :final elseBlock):
          _buffer.writeln('if ($condition) then (yes)');
          _walkCfgBlock(thenBlock);
          if (elseBlock != null) {
            _buffer.writeln('else (no)');
            _walkCfgBlock(elseBlock);
          }
          _buffer.writeln('endif');

        case LoopStatement(:final condition, :final body):
          _buffer.writeln('while ($condition)');
          _walkCfgBlock(body);
          _buffer.writeln('endwhile');

        case ForkStatement(:final branches):
          _buffer.writeln('fork');
          for (var i = 0; i < branches.length; i++) {
            if (i > 0) _buffer.writeln('fork again');
            _walkCfgBlock(branches[i]);
          }
          _buffer.writeln('end fork');
      }
    }
  }
}

/// Theme settings for PlantUML skin parameters.
class PlantUmlTheme {
  final String backgroundColor;
  final int fontSize;
  final String fontFamily;

  const PlantUmlTheme({
    required this.backgroundColor,
    required this.fontSize,
    required this.fontFamily,
  });

  const PlantUmlTheme.defaultTheme()
      : backgroundColor = '#FFFFFF',
        fontSize = 13,
        fontFamily = 'Helvetica';
}
```

### Notes and Stereotypes

Add notes to PlantUML diagrams for documentation-heavy exports:

```
note right of AstNode
    Base class for all AST nodes.
    Accepts visitors for traversal.
end note
```

Stereotypes annotate classes with roles: `class Parser <<Service>>`.

---

## SVG Generation

SVG (Scalable Vector Graphics) is an XML-based vector image format. When exporting graph visualizations directly (without relying on Mermaid or PlantUML rendering tools), generating SVG programmatically gives full control over layout, styling, and interactivity.

### XML Building

Build SVG documents using Dart's `xml` package or manual string building. For production code, use `package:xml` to ensure well-formed output with proper escaping.

Key SVG structural elements:
- `<svg>` root element with `xmlns`, `viewBox`, `width`, `height`
- `<defs>` for reusable definitions (markers, gradients, filters)
- `<g>` for grouping and applying transforms
- `<rect>`, `<circle>`, `<ellipse>` for shapes
- `<path>` for arbitrary curves and lines
- `<text>` and `<tspan>` for labels
- `<line>`, `<polyline>`, `<polygon>` for line-based shapes
- `<marker>` for arrowheads on edges

### ViewBox and Coordinate System

The `viewBox` attribute defines the coordinate system: `viewBox="minX minY width height"`. Set the viewBox to encompass all nodes and edges with padding. The `width` and `height` attributes on the `<svg>` element define the rendered size, while `viewBox` defines the coordinate space. Using `preserveAspectRatio="xMidYMid meet"` ensures the diagram scales uniformly.

### Building SVG for Graphs

```dart
import 'package:xml/xml.dart';

/// Renders an AST or directed graph as an SVG document.
///
/// Performs a simple layered layout (Sugiyama-style) and produces
/// SVG XML with rectangles for nodes, paths for edges, arrowhead
/// markers, and text labels.
class SvgGraphRenderer {
  final SvgStyle style;
  final double nodeWidth;
  final double nodeHeight;
  final double layerGap;
  final double nodeGap;

  SvgGraphRenderer({
    this.style = const SvgStyle(),
    this.nodeWidth = 160,
    this.nodeHeight = 40,
    this.layerGap = 80,
    this.nodeGap = 30,
  });

  /// Renders the [graph] to an SVG XML string.
  ///
  /// Performs layout computation, then generates SVG elements for
  /// each node (rect + text) and each edge (path + arrowhead).
  /// Returns a complete, standalone SVG document.
  String render(DirectedGraph graph) {
    final layout = _computeLayout(graph);
    final bounds = _calculateBounds(layout);

    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');

    builder.element('svg', nest: () {
      builder.attribute('xmlns', 'http://www.w3.org/2000/svg');
      builder.attribute('viewBox',
          '${bounds.left - 20} ${bounds.top - 20} '
          '${bounds.width + 40} ${bounds.height + 40}');
      builder.attribute('width', '${bounds.width + 40}');
      builder.attribute('height', '${bounds.height + 40}');

      // Define arrowhead marker.
      builder.element('defs', nest: () {
        builder.element('marker', nest: () {
          builder.attribute('id', 'arrowhead');
          builder.attribute('markerWidth', '10');
          builder.attribute('markerHeight', '7');
          builder.attribute('refX', '10');
          builder.attribute('refY', '3.5');
          builder.attribute('orient', 'auto');
          builder.element('polygon', nest: () {
            builder.attribute('points', '0 0, 10 3.5, 0 7');
            builder.attribute('fill', style.edgeColor);
          });
        });

        // Optional drop shadow filter.
        if (style.dropShadow) {
          builder.element('filter', nest: () {
            builder.attribute('id', 'shadow');
            builder.attribute('x', '-10%');
            builder.attribute('y', '-10%');
            builder.attribute('width', '130%');
            builder.attribute('height', '130%');
            builder.element('feDropShadow', nest: () {
              builder.attribute('dx', '2');
              builder.attribute('dy', '2');
              builder.attribute('stdDeviation', '3');
              builder.attribute('flood-opacity', '0.15');
            });
          });
        }
      });

      // Render edges first so nodes draw on top.
      for (final edge in layout.edges) {
        _renderEdge(builder, edge);
      }

      // Render nodes.
      for (final node in layout.nodes) {
        _renderNode(builder, node);
      }
    });

    return builder.buildDocument().toXmlString(pretty: true);
  }

  void _renderNode(XmlBuilder builder, LayoutNode node) {
    final filter = style.dropShadow ? 'url(#shadow)' : null;

    builder.element('g', nest: () {
      builder.attribute('class', 'node');
      builder.attribute('data-node-id', node.id);

      // Background rectangle.
      builder.element('rect', nest: () {
        builder.attribute('x', '${node.x}');
        builder.attribute('y', '${node.y}');
        builder.attribute('width', '$nodeWidth');
        builder.attribute('height', '$nodeHeight');
        builder.attribute('rx', '${style.borderRadius}');
        builder.attribute('ry', '${style.borderRadius}');
        builder.attribute('fill', style.nodeFill);
        builder.attribute('stroke', style.nodeStroke);
        builder.attribute('stroke-width', '${style.strokeWidth}');
        if (filter != null) {
          builder.attribute('filter', filter);
        }
      });

      // Label text, centered in the rectangle.
      builder.element('text', nest: () {
        builder.attribute('x', '${node.x + nodeWidth / 2}');
        builder.attribute('y', '${node.y + nodeHeight / 2}');
        builder.attribute('text-anchor', 'middle');
        builder.attribute('dominant-baseline', 'central');
        builder.attribute('font-family', style.fontFamily);
        builder.attribute('font-size', '${style.fontSize}');
        builder.attribute('fill', style.textColor);
        builder.text(node.label);
      });
    });
  }

  void _renderEdge(XmlBuilder builder, LayoutEdge edge) {
    // Cubic bezier from source bottom-center to target top-center.
    final sx = edge.sourceX + nodeWidth / 2;
    final sy = edge.sourceY + nodeHeight;
    final tx = edge.targetX + nodeWidth / 2;
    final ty = edge.targetY;
    final cy1 = sy + layerGap * 0.4;
    final cy2 = ty - layerGap * 0.4;

    builder.element('path', nest: () {
      builder.attribute('d', 'M $sx $sy C $sx $cy1, $tx $cy2, $tx $ty');
      builder.attribute('fill', 'none');
      builder.attribute('stroke', style.edgeColor);
      builder.attribute('stroke-width', '${style.edgeWidth}');
      builder.attribute('marker-end', 'url(#arrowhead)');
    });

    // Edge label, if present.
    if (edge.label case final label?) {
      final midX = (sx + tx) / 2;
      final midY = (sy + ty) / 2;
      builder.element('text', nest: () {
        builder.attribute('x', '$midX');
        builder.attribute('y', '$midY');
        builder.attribute('text-anchor', 'middle');
        builder.attribute('font-family', style.fontFamily);
        builder.attribute('font-size', '${style.fontSize - 1}');
        builder.attribute('fill', style.edgeLabelColor);
        builder.text(label);
      });
    }
  }

  /// Simple layered layout: assigns each node to a layer based on
  /// its depth, then spaces nodes horizontally within each layer.
  _GraphLayout _computeLayout(DirectedGraph graph) {
    final depths = <String, int>{};
    void assignDepth(GraphNode node, int depth) {
      final current = depths[node.id];
      if (current == null || depth > current) {
        depths[node.id] = depth;
        for (final child in node.successors) {
          assignDepth(child, depth + 1);
        }
      }
    }
    for (final root in graph.roots) {
      assignDepth(root, 0);
    }

    // Group nodes by layer.
    final layers = <int, List<GraphNode>>{};
    for (final node in graph.nodes) {
      final d = depths[node.id] ?? 0;
      layers.putIfAbsent(d, () => []).add(node);
    }

    final layoutNodes = <LayoutNode>[];
    final layoutEdges = <LayoutEdge>[];
    final positions = <String, (double, double)>{};

    for (final MapEntry(:key, :value) in layers.entries) {
      for (var i = 0; i < value.length; i++) {
        final x = i * (nodeWidth + nodeGap);
        final y = key * (nodeHeight + layerGap);
        positions[value[i].id] = (x, y);
        layoutNodes.add(LayoutNode(
          id: value[i].id,
          label: value[i].label,
          x: x,
          y: y,
        ));
      }
    }

    for (final node in graph.nodes) {
      final (sx, sy) = positions[node.id]!;
      for (final succ in node.successors) {
        final (tx, ty) = positions[succ.id]!;
        layoutEdges.add(LayoutEdge(
          sourceX: sx, sourceY: sy,
          targetX: tx, targetY: ty,
          label: node.edgeLabelTo(succ),
        ));
      }
    }

    return _GraphLayout(nodes: layoutNodes, edges: layoutEdges);
  }

  Rect _calculateBounds(_GraphLayout layout) {
    if (layout.nodes.isEmpty) return Rect(0, 0, 200, 100);
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final n in layout.nodes) {
      if (n.x < minX) minX = n.x;
      if (n.y < minY) minY = n.y;
      if (n.x + nodeWidth > maxX) maxX = n.x + nodeWidth;
      if (n.y + nodeHeight > maxY) maxY = n.y + nodeHeight;
    }
    return Rect(minX, minY, maxX - minX, maxY - minY);
  }
}

/// Visual style configuration for SVG rendering.
class SvgStyle {
  final String nodeFill;
  final String nodeStroke;
  final String textColor;
  final String edgeColor;
  final String edgeLabelColor;
  final String fontFamily;
  final double fontSize;
  final double strokeWidth;
  final double edgeWidth;
  final double borderRadius;
  final bool dropShadow;

  const SvgStyle({
    this.nodeFill = '#f8f9fa',
    this.nodeStroke = '#343a40',
    this.textColor = '#212529',
    this.edgeColor = '#6c757d',
    this.edgeLabelColor = '#868e96',
    this.fontFamily = 'sans-serif',
    this.fontSize = 13,
    this.strokeWidth = 1.5,
    this.edgeWidth = 1.5,
    this.borderRadius = 6,
    this.dropShadow = false,
  });
}
```

### Path Commands Reference

SVG `<path>` elements use a mini-language for drawing:
- `M x y` -- move to (start point)
- `L x y` -- line to
- `H x` -- horizontal line to
- `V y` -- vertical line to
- `C x1 y1 x2 y2 x y` -- cubic bezier
- `Q x1 y1 x y` -- quadratic bezier
- `A rx ry rotation large-arc sweep x y` -- elliptical arc
- `Z` -- close path

Lowercase variants (`m`, `l`, `c`, `q`, `a`, `z`) use relative coordinates.

---

## SVG Optimization and Minification

Generated SVG files can be large. Apply these techniques to reduce file size:

### Coordinate Precision

Round coordinate values to 1-2 decimal places. Most displays cannot render sub-pixel differences beyond that:

```dart
String _fmt(double v) => v.toStringAsFixed(1);
// Instead of: "M 123.456789 78.901234"
// Produce:    "M 123.5 78.9"
```

### Attribute Reduction

- Omit default attribute values (`fill="black"` is default for text, `stroke="none"` is default for shapes).
- Use CSS `<style>` blocks for repeated styling instead of inline attributes on every element.
- Consolidate identical `transform` attributes using `<g>` wrappers.

### Structural Optimization

- Remove empty `<g>` elements that contain no children.
- Collapse single-child `<g>` elements by merging attributes into the child.
- Remove XML comments and processing instructions (except the XML declaration if required).
- Use `<use>` elements with `<defs>` for repeated shapes (e.g., identical node shapes).

### CSS-Based Styling

Instead of repeating `fill`, `stroke`, `font-family` on every element:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 600">
  <style>
    .node rect { fill: #f8f9fa; stroke: #343a40; stroke-width: 1.5; rx: 6; }
    .node text { font-family: sans-serif; font-size: 13px; fill: #212529;
                 text-anchor: middle; dominant-baseline: central; }
    .edge { fill: none; stroke: #6c757d; stroke-width: 1.5; }
  </style>
  <!-- nodes and edges reference classes instead of inline styles -->
</svg>
```

### Minification Steps

1. Remove unnecessary whitespace between tags.
2. Remove comments.
3. Shorten color values: `#FFFFFF` to `#FFF`, `#AABBCC` to `#ABC`.
4. Collapse self-closing tags: `<rect ... ></rect>` to `<rect ... />`.
5. Remove the `px` unit from attribute values (it is the default).

A Dart minification utility:

```dart
/// Minifies an SVG XML string for production output.
///
/// Removes comments, collapses whitespace, shortens hex colors,
/// and removes redundant default attributes.
String minifySvg(String svg) {
  var result = svg;

  // Remove XML comments.
  result = result.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  // Collapse whitespace between tags.
  result = result.replaceAll(RegExp(r'>\s+<'), '><');

  // Remove leading/trailing whitespace within tags.
  result = result.replaceAll(RegExp(r'\s+/>'), '/>');
  result = result.replaceAll(RegExp(r'\s{2,}'), ' ');

  // Shorten 6-digit hex colors where possible.
  result = result.replaceAllMapped(
    RegExp(r'#([0-9a-fA-F])\1([0-9a-fA-F])\2([0-9a-fA-F])\3'),
    (m) => '#${m[1]}${m[2]}${m[3]}',
  );

  // Remove default px units.
  result = result.replaceAll(RegExp(r'(\d)px'), r'$1');

  return result.trim();
}
```

---

## JSON Serialization of AST Trees

JSON is the most common interchange format for AST data. Dart's `json_serializable` and `json_annotation` packages provide code-generated `fromJson`/`toJson` methods that are type-safe and maintainable.

### fromJson/toJson Patterns

For sealed class hierarchies (common in ASTs), use a discriminator field to distinguish node types:

```dart
import 'package:json_annotation/json_annotation.dart';

part 'ast_node.g.dart';

/// Base sealed class for all AST nodes.
///
/// Uses a `type` discriminator field for JSON polymorphic
/// deserialization. Each subtype registers its own type string.
@JsonSerializable()
sealed class AstNode {
  final String type;
  final SourceSpan? span;

  AstNode({required this.type, this.span});

  /// Deserializes an [AstNode] from JSON by dispatching on the
  /// `type` discriminator field.
  ///
  /// Throws [FormatException] if the type is not recognized.
  factory AstNode.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'program'            => ProgramNode.fromJson(json),
      'binary_expression'  => BinaryExpression.fromJson(json),
      'unary_expression'   => UnaryExpression.fromJson(json),
      'literal'            => LiteralNode.fromJson(json),
      'identifier'         => IdentifierNode.fromJson(json),
      'function_decl'      => FunctionDeclaration.fromJson(json),
      'block'              => BlockStatement.fromJson(json),
      'if_statement'       => IfStatement.fromJson(json),
      'return_statement'   => ReturnStatement.fromJson(json),
      _ => throw FormatException('Unknown AST node type: $type'),
    };
  }

  Map<String, dynamic> toJson();

  /// Returns all direct child nodes for traversal.
  List<AstNode> get children;
}

@JsonSerializable()
class ProgramNode extends AstNode {
  final List<AstNode> statements;

  ProgramNode({required this.statements, super.span})
      : super(type: 'program');

  factory ProgramNode.fromJson(Map<String, dynamic> json) =>
      _$ProgramNodeFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$ProgramNodeToJson(this);

  @override
  List<AstNode> get children => statements;
}

@JsonSerializable()
class BinaryExpression extends AstNode {
  final String operator;
  final AstNode left;
  final AstNode right;

  BinaryExpression({
    required this.operator,
    required this.left,
    required this.right,
    super.span,
  }) : super(type: 'binary_expression');

  factory BinaryExpression.fromJson(Map<String, dynamic> json) =>
      _$BinaryExpressionFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$BinaryExpressionToJson(this);

  @override
  List<AstNode> get children => [left, right];
}

@JsonSerializable()
class LiteralNode extends AstNode {
  final dynamic value;
  final String literalType; // 'int', 'double', 'string', 'bool'

  LiteralNode({
    required this.value,
    required this.literalType,
    super.span,
  }) : super(type: 'literal');

  factory LiteralNode.fromJson(Map<String, dynamic> json) =>
      _$LiteralNodeFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$LiteralNodeToJson(this);

  @override
  List<AstNode> get children => [];
}

@JsonSerializable()
class IdentifierNode extends AstNode {
  final String name;

  IdentifierNode({required this.name, super.span})
      : super(type: 'identifier');

  factory IdentifierNode.fromJson(Map<String, dynamic> json) =>
      _$IdentifierNodeFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$IdentifierNodeToJson(this);

  @override
  List<AstNode> get children => [];
}

/// Source location span for error reporting and source maps.
@JsonSerializable()
class SourceSpan {
  final int startOffset;
  final int endOffset;
  final int startLine;
  final int startColumn;
  final int endLine;
  final int endColumn;

  const SourceSpan({
    required this.startOffset,
    required this.endOffset,
    required this.startLine,
    required this.startColumn,
    required this.endLine,
    required this.endColumn,
  });

  factory SourceSpan.fromJson(Map<String, dynamic> json) =>
      _$SourceSpanFromJson(json);

  Map<String, dynamic> toJson() => _$SourceSpanToJson(this);
}
```

### Custom JsonConverter for Polymorphic Children

When `json_serializable` cannot automatically handle sealed class fields, write a custom converter:

```dart
class AstNodeConverter implements JsonConverter<AstNode, Map<String, dynamic>> {
  const AstNodeConverter();

  @override
  AstNode fromJson(Map<String, dynamic> json) => AstNode.fromJson(json);

  @override
  Map<String, dynamic> toJson(AstNode node) => node.toJson();
}

class AstNodeListConverter
    implements JsonConverter<List<AstNode>, List<dynamic>> {
  const AstNodeListConverter();

  @override
  List<AstNode> fromJson(List<dynamic> json) => json
      .cast<Map<String, dynamic>>()
      .map(AstNode.fromJson)
      .toList();

  @override
  List<dynamic> toJson(List<AstNode> nodes) =>
      nodes.map((n) => n.toJson()).toList();
}
```

Annotate fields with `@AstNodeConverter()` or `@AstNodeListConverter()` to enable automatic code generation.

### Pretty Printing and Compact Output

Use `JsonEncoder` for controlling output format:

```dart
import 'dart:convert';

String toJsonPretty(AstNode node) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(node.toJson());
}

String toJsonCompact(AstNode node) {
  return jsonEncode(node.toJson());
}
```

---

## JSON Schema for AST Interchange Format

Define a JSON Schema that validates exported AST documents. This enables interoperability with tools in other languages and provides a contract for consumers.

### Schema Structure

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://example.com/ast-schema/v1",
  "title": "AST Interchange Format",
  "description": "Schema for serialized AST nodes with type discriminator",
  "type": "object",
  "required": ["type"],
  "properties": {
    "type": {
      "type": "string",
      "description": "Discriminator identifying the AST node kind"
    },
    "span": { "$ref": "#/$defs/sourceSpan" }
  },
  "oneOf": [
    { "$ref": "#/$defs/programNode" },
    { "$ref": "#/$defs/binaryExpression" },
    { "$ref": "#/$defs/literalNode" },
    { "$ref": "#/$defs/identifierNode" }
  ],
  "$defs": {
    "sourceSpan": {
      "type": "object",
      "required": ["startOffset", "endOffset", "startLine", "startColumn", "endLine", "endColumn"],
      "properties": {
        "startOffset": { "type": "integer", "minimum": 0 },
        "endOffset": { "type": "integer", "minimum": 0 },
        "startLine": { "type": "integer", "minimum": 1 },
        "startColumn": { "type": "integer", "minimum": 0 },
        "endLine": { "type": "integer", "minimum": 1 },
        "endColumn": { "type": "integer", "minimum": 0 }
      },
      "additionalProperties": false
    },
    "programNode": {
      "type": "object",
      "properties": {
        "type": { "const": "program" },
        "statements": {
          "type": "array",
          "items": { "$ref": "#" }
        }
      },
      "required": ["type", "statements"]
    },
    "binaryExpression": {
      "type": "object",
      "properties": {
        "type": { "const": "binary_expression" },
        "operator": { "type": "string" },
        "left": { "$ref": "#" },
        "right": { "$ref": "#" }
      },
      "required": ["type", "operator", "left", "right"]
    },
    "literalNode": {
      "type": "object",
      "properties": {
        "type": { "const": "literal" },
        "value": {},
        "literalType": {
          "type": "string",
          "enum": ["int", "double", "string", "bool"]
        }
      },
      "required": ["type", "value", "literalType"]
    },
    "identifierNode": {
      "type": "object",
      "properties": {
        "type": { "const": "identifier" },
        "name": { "type": "string" }
      },
      "required": ["type", "name"]
    }
  }
}
```

### Validating Against the Schema in Dart

Use `package:json_schema` to validate JSON output at runtime or in tests:

```dart
import 'package:json_schema/json_schema.dart';

Future<bool> validateAstJson(Map<String, dynamic> astJson) async {
  final schemaJson = await loadSchemaFromAsset('ast_schema.json');
  final schema = JsonSchema.create(schemaJson);
  final result = schema.validate(astJson);
  if (!result.isValid) {
    for (final error in result.errors) {
      print('Validation error at ${error.instancePath}: ${error.message}');
    }
  }
  return result.isValid;
}
```

### Schema Versioning

Include a `version` field in the root of exported JSON documents. When the schema evolves, bump the version and maintain backward-compatible readers:

```dart
Map<String, dynamic> exportWithVersion(AstNode root) {
  return {
    'version': 1,
    'schema': 'https://example.com/ast-schema/v1',
    'root': root.toJson(),
    'metadata': {
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'toolVersion': '2.4.0',
    },
  };
}
```

---

## Round-Trip Serialization

Round-trip serialization is the process of serializing a data structure to a format (JSON, Mermaid, etc.), deserializing it back, and verifying that the result equals the original. This is a critical quality gate for export pipelines.

### Serialize, Deserialize, Verify Equality

Implement `==` and `hashCode` on all AST node classes (or use Freezed / Equatable) so that round-trip tests can assert deep equality:

```dart
import 'dart:convert';
import 'package:test/test.dart';

void main() {
  group('AST JSON round-trip', () {
    test('ProgramNode survives round-trip', () {
      final original = ProgramNode(
        statements: [
          BinaryExpression(
            operator: '+',
            left: LiteralNode(value: 1, literalType: 'int'),
            right: IdentifierNode(name: 'x'),
          ),
        ],
      );

      final json = jsonEncode(original.toJson());
      final decoded = AstNode.fromJson(jsonDecode(json) as Map<String, dynamic>);

      expect(decoded, isA<ProgramNode>());
      expect(decoded, equals(original));
    });

    test('deeply nested AST survives round-trip', () {
      final original = ProgramNode(
        statements: [
          IfStatement(
            condition: BinaryExpression(
              operator: '>',
              left: IdentifierNode(name: 'n'),
              right: LiteralNode(value: 0, literalType: 'int'),
            ),
            thenBlock: BlockStatement(
              statements: [
                ReturnStatement(
                  expression: BinaryExpression(
                    operator: '*',
                    left: IdentifierNode(name: 'n'),
                    right: BinaryExpression(
                      operator: '-',
                      left: IdentifierNode(name: 'n'),
                      right: LiteralNode(value: 1, literalType: 'int'),
                    ),
                  ),
                ),
              ],
            ),
            elseBlock: null,
          ),
        ],
      );

      final json = jsonEncode(original.toJson());
      final restored = AstNode.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );

      expect(restored, equals(original));
      _verifyTreeStructure(original, restored as ProgramNode);
    });

    test('SourceSpan data is preserved', () {
      final span = SourceSpan(
        startOffset: 10,
        endOffset: 25,
        startLine: 2,
        startColumn: 4,
        endLine: 2,
        endColumn: 19,
      );

      final node = IdentifierNode(name: 'foo', span: span);
      final json = jsonEncode(node.toJson());
      final restored = AstNode.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      ) as IdentifierNode;

      expect(restored.span, equals(span));
      expect(restored.name, equals('foo'));
    });
  });
}

/// Recursively verifies structural equivalence between two AST trees,
/// checking node type, children count, and leaf values.
void _verifyTreeStructure(AstNode expected, AstNode actual) {
  expect(actual.type, equals(expected.type));
  expect(actual.children.length, equals(expected.children.length));
  for (var i = 0; i < expected.children.length; i++) {
    _verifyTreeStructure(expected.children[i], actual.children[i]);
  }
}
```

### Handling Non-Round-Trippable Formats

Mermaid and PlantUML are not round-trippable because they are lossy display formats. The general approach for testing these:

1. Generate the text output from an AST.
2. Parse the generated text to verify syntactic validity (e.g., no unclosed brackets, correct keyword usage).
3. Assert that key structural elements are present (node IDs, edge declarations, relationship arrows).
4. Do NOT attempt to reconstruct the original AST from Mermaid/PlantUML output.

For SVG, limited round-tripping is possible by embedding AST data in `data-*` attributes or in a `<metadata>` block within the SVG, then extracting it on re-import.

### Property-Based Testing

Use `package:glados` or manual generators to create random AST trees and verify round-trip invariants:

```dart
AstNode randomAst(Random rng, int maxDepth) {
  if (maxDepth <= 0 || rng.nextBool()) {
    return rng.nextBool()
        ? LiteralNode(value: rng.nextInt(1000), literalType: 'int')
        : IdentifierNode(name: 'var${rng.nextInt(26)}');
  }

  return BinaryExpression(
    operator: ['+', '-', '*', '/'][rng.nextInt(4)],
    left: randomAst(rng, maxDepth - 1),
    right: randomAst(rng, maxDepth - 1),
  );
}

void main() {
  test('random AST round-trip (100 iterations)', () {
    final rng = Random(42); // deterministic seed
    for (var i = 0; i < 100; i++) {
      final ast = randomAst(rng, 6);
      final json = jsonEncode(ast.toJson());
      final restored = AstNode.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      expect(restored, equals(ast),
          reason: 'Round-trip failed on iteration $i');
    }
  });
}
```

---

## Export Pipeline Architecture

The export pipeline transforms an internal AST representation into one or more output formats. It follows a staged architecture: AST in, formatter transforms, output out.

### Pipeline Stages

```
AST (in-memory) --> Validator --> Transformer --> Formatter --> Serializer --> Output (string/bytes)
```

1. **Validator** -- Checks that the AST is well-formed before export. Rejects trees with cycles, dangling references, or missing required fields.
2. **Transformer** -- Optional stage that normalizes or simplifies the AST for a specific output format (e.g., flattening nested groups for Mermaid, inserting synthetic nodes for layout).
3. **Formatter** -- Converts the AST into the target format's intermediate representation (Mermaid text lines, PlantUML text lines, SVG XML nodes, JSON map).
4. **Serializer** -- Converts the intermediate representation to the final string or byte output.

### Implementation with Strategy Pattern

```dart
/// The entry point for exporting AST trees to various formats.
///
/// Uses a [ExportFormatter] strategy to produce output in the
/// requested format. Performs validation before formatting.
class ExportPipeline {
  final List<AstValidator> _validators;
  final Map<ExportFormat, ExportFormatter> _formatters;
  final List<AstTransformer> _transformers;

  ExportPipeline({
    List<AstValidator>? validators,
    List<AstTransformer>? transformers,
    required Map<ExportFormat, ExportFormatter> formatters,
  })  : _validators = validators ?? [const DefaultAstValidator()],
        _transformers = transformers ?? [],
        _formatters = formatters;

  /// Exports the given [ast] to the specified [format].
  ///
  /// Runs all validators first, then applies transformers in order,
  /// and finally delegates to the appropriate formatter.
  ///
  /// Throws [ValidationException] if the AST is malformed.
  /// Throws [UnsupportedFormatException] if no formatter is registered.
  ExportResult export(AstNode ast, ExportFormat format) {
    // 1. Validate.
    for (final validator in _validators) {
      final errors = validator.validate(ast);
      if (errors.isNotEmpty) {
        throw ValidationException(errors);
      }
    }

    // 2. Transform.
    var transformed = ast;
    for (final transformer in _transformers) {
      transformed = transformer.transform(transformed, format);
    }

    // 3. Format.
    final formatter = _formatters[format];
    if (formatter == null) {
      throw UnsupportedFormatException(format);
    }

    final output = formatter.format(transformed);

    return ExportResult(
      content: output,
      format: format,
      mimeType: format.mimeType,
      metadata: {
        'nodeCount': _countNodes(ast),
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  /// Returns all formats this pipeline supports.
  Set<ExportFormat> get supportedFormats => _formatters.keys.toSet();

  int _countNodes(AstNode node) {
    return 1 + node.children.fold(0, (sum, child) => sum + _countNodes(child));
  }
}

/// Strategy interface for format-specific AST rendering.
abstract interface class ExportFormatter {
  String format(AstNode ast);
}

/// Strategy interface for pre-export AST transformations.
abstract interface class AstTransformer {
  AstNode transform(AstNode ast, ExportFormat targetFormat);
}

/// Strategy interface for AST validation.
abstract interface class AstValidator {
  List<ValidationError> validate(AstNode ast);
}

/// Supported export formats with associated MIME types.
enum ExportFormat {
  mermaid('text/x-mermaid'),
  plantUml('text/x-plantuml'),
  svg('image/svg+xml'),
  json('application/json'),
  jsonPretty('application/json');

  const ExportFormat(this.mimeType);
  final String mimeType;
}

/// Result of an export operation.
class ExportResult {
  final String content;
  final ExportFormat format;
  final String mimeType;
  final Map<String, dynamic> metadata;

  const ExportResult({
    required this.content,
    required this.format,
    required this.mimeType,
    this.metadata = const {},
  });

  /// Returns the content as UTF-8 bytes.
  List<int> get bytes => utf8.encode(content);

  /// Content length in bytes.
  int get contentLength => bytes.length;
}

/// Validates AST structure for common issues.
class DefaultAstValidator implements AstValidator {
  const DefaultAstValidator();

  @override
  List<ValidationError> validate(AstNode ast) {
    final errors = <ValidationError>[];
    final visited = <int>{};
    _checkCycles(ast, visited, [], errors);
    return errors;
  }

  void _checkCycles(
    AstNode node,
    Set<int> visited,
    List<String> path,
    List<ValidationError> errors,
  ) {
    final id = identityHashCode(node);
    if (visited.contains(id)) {
      errors.add(ValidationError(
        'Cycle detected at path: ${path.join(' -> ')}',
        node,
      ));
      return;
    }
    visited.add(id);
    for (final child in node.children) {
      _checkCycles(child, visited, [...path, node.type], errors);
    }
    visited.remove(id);
  }
}

class ValidationError {
  final String message;
  final AstNode? node;
  const ValidationError(this.message, [this.node]);
}

class ValidationException implements Exception {
  final List<ValidationError> errors;
  const ValidationException(this.errors);

  @override
  String toString() => 'ValidationException: ${errors.map((e) => e.message).join('; ')}';
}

class UnsupportedFormatException implements Exception {
  final ExportFormat format;
  const UnsupportedFormatException(this.format);

  @override
  String toString() => 'UnsupportedFormatException: No formatter for ${format.name}';
}
```

### Wiring Up the Pipeline

```dart
final pipeline = ExportPipeline(
  formatters: {
    ExportFormat.mermaid: MermaidFlowchartFormatter(),
    ExportFormat.plantUml: PlantUmlClassFormatter(),
    ExportFormat.svg: SvgFormatter(renderer: SvgGraphRenderer()),
    ExportFormat.json: JsonFormatter(),
    ExportFormat.jsonPretty: JsonFormatter(pretty: true),
  },
  transformers: [
    RemoveInternalNodesTransformer(),
    FlattenSingleChildGroupsTransformer(),
  ],
);

// Usage:
final result = pipeline.export(myAst, ExportFormat.mermaid);
print(result.content);       // The Mermaid diagram text.
print(result.mimeType);      // text/x-mermaid
print(result.metadata);      // {nodeCount: 42, exportedAt: ...}
```

---

## Format Detection and Content Negotiation

When the export format is not explicitly specified, detect it from context: file extension, HTTP Accept header, or content sniffing.

### File Extension Detection

```dart
/// Detects the export format from a file path's extension.
///
/// Returns `null` if the extension is not recognized.
ExportFormat? detectFormatFromPath(String path) {
  final ext = path.split('.').last.toLowerCase();
  return switch (ext) {
    'mmd' || 'mermaid' => ExportFormat.mermaid,
    'puml' || 'plantuml' || 'uml' => ExportFormat.plantUml,
    'svg' => ExportFormat.svg,
    'json' => ExportFormat.json,
    _ => null,
  };
}
```

### HTTP Accept Header Negotiation

For API endpoints that serve AST exports, parse the `Accept` header and select the best matching format:

```dart
/// Negotiates the best export format based on an HTTP Accept header.
///
/// Supports quality values (q=) and returns the highest-priority
/// format that the pipeline supports. Falls back to JSON if no
/// acceptable format is found.
ExportFormat negotiateFormat(
  String acceptHeader,
  Set<ExportFormat> supported,
) {
  final entries = _parseAcceptHeader(acceptHeader);

  // Sort by quality descending.
  entries.sort((a, b) => b.quality.compareTo(a.quality));

  for (final entry in entries) {
    for (final format in supported) {
      if (_mimeMatches(entry.mimeType, format.mimeType)) {
        return format;
      }
    }
  }

  // Default to JSON if nothing matches.
  return ExportFormat.json;
}

List<_AcceptEntry> _parseAcceptHeader(String header) {
  return header.split(',').map((part) {
    final segments = part.trim().split(';');
    final mimeType = segments.first.trim();
    var quality = 1.0;
    for (final seg in segments.skip(1)) {
      final kv = seg.trim().split('=');
      if (kv.length == 2 && kv[0].trim() == 'q') {
        quality = double.tryParse(kv[1].trim()) ?? 1.0;
      }
    }
    return _AcceptEntry(mimeType, quality);
  }).toList();
}

bool _mimeMatches(String requested, String supported) {
  if (requested == '*/*') return true;
  if (requested == supported) return true;
  final reqParts = requested.split('/');
  final supParts = supported.split('/');
  if (reqParts.length == 2 && supParts.length == 2) {
    return reqParts[0] == supParts[0] &&
        (reqParts[1] == '*' || reqParts[1] == supParts[1]);
  }
  return false;
}

class _AcceptEntry {
  final String mimeType;
  final double quality;
  const _AcceptEntry(this.mimeType, this.quality);
}
```

### Content-Type Sniffing

When importing or re-processing exported files, detect the format from content:

```dart
/// Detects the format of exported content by inspecting its structure.
///
/// Checks for format-specific markers: XML declaration / <svg> for SVG,
/// @startuml for PlantUML, flowchart/classDiagram/sequenceDiagram for
/// Mermaid, and opening brace for JSON.
ExportFormat? detectFormatFromContent(String content) {
  final trimmed = content.trimLeft();

  // SVG detection: XML declaration or <svg tag.
  if (trimmed.startsWith('<?xml') || trimmed.startsWith('<svg')) {
    return ExportFormat.svg;
  }

  // PlantUML detection: @startuml marker.
  if (trimmed.startsWith('@startuml')) {
    return ExportFormat.plantUml;
  }

  // Mermaid detection: diagram type keyword at start of line.
  final mermaidKeywords = [
    'flowchart',
    'graph',
    'classDiagram',
    'sequenceDiagram',
    'stateDiagram',
    'erDiagram',
    'gantt',
    'pie',
    'gitGraph',
  ];
  for (final keyword in mermaidKeywords) {
    if (trimmed.startsWith(keyword)) {
      return ExportFormat.mermaid;
    }
  }

  // JSON detection: starts with { or [.
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return ExportFormat.json;
  }

  return null;
}
```

### Multi-Format Export

Export to all supported formats in one call:

```dart
/// Exports the AST to all formats supported by the pipeline.
///
/// Returns a map from format to export result. Formats that fail
/// are excluded from the result and their errors are collected.
({
  Map<ExportFormat, ExportResult> results,
  Map<ExportFormat, Object> errors,
}) exportAll(ExportPipeline pipeline, AstNode ast) {
  final results = <ExportFormat, ExportResult>{};
  final errors = <ExportFormat, Object>{};

  for (final format in pipeline.supportedFormats) {
    try {
      results[format] = pipeline.export(ast, format);
    } catch (e) {
      errors[format] = e;
    }
  }

  return (results: results, errors: errors);
}
```

---

## Best Practices

1. **Use the discriminator pattern for polymorphic JSON serialization.** Always include a `type` field in serialized AST nodes so that deserialization can dispatch to the correct subclass constructor without ambiguity.

2. **Generate unique, deterministic node IDs for diagram output.** Use a counter-based scheme (`n0`, `n1`, `n2`) that is stable across repeated exports of the same AST. Avoid using `hashCode` or memory addresses as IDs because they are not deterministic across runs.

3. **Escape user-provided text in all output formats.** Mermaid, PlantUML, SVG, and JSON all have characters that carry special meaning. Always escape labels through a dedicated function rather than inlining raw strings.

4. **Separate the formatting strategy from the pipeline orchestration.** The `ExportPipeline` class should not know how to generate Mermaid syntax or SVG XML. Each format gets its own `ExportFormatter` implementation, making the pipeline open for extension without modification.

5. **Validate before formatting.** Run structural validators (cycle detection, required field checks, type consistency) before passing the AST to a formatter. This prevents formatters from encountering unexpected structures that produce invalid output.

6. **Implement deep equality on AST node classes.** Use `Equatable`, `Freezed`, or manually implement `operator ==` and `hashCode` so that round-trip tests can assert structural equality rather than reference equality.

7. **Test round-trip serialization with property-based tests.** Generate random AST trees, serialize them, deserialize, and verify equality. This catches edge cases that hand-written tests miss (deeply nested structures, special characters, empty lists, null optional fields).

8. **Use CSS classes in SVG instead of inline styles.** Define a `<style>` block in the SVG and reference CSS classes on elements. This reduces file size by 30-60% for graphs with many nodes and makes post-generation style changes straightforward.

9. **Version your JSON interchange format.** Include a `version` field in the envelope so that consumers can detect breaking changes and apply migration logic.

10. **Provide content negotiation for API endpoints.** Parse the `Accept` header and return the most appropriate format. Fall back to JSON when no preference is expressed.

11. **Keep formatting idempotent.** Running the same AST through the same formatter twice should produce identical output. Avoid relying on mutable state, timestamps, or random values in the formatter itself.

12. **Minimize SVG output by reducing coordinate precision, using CSS classes, and applying structural optimizations.** Production SVG exports should go through a minification step before being served or stored.

---

## Anti-Patterns

- **Embedding format-specific logic in AST node classes.** Nodes should not have `toMermaid()` or `toSvg()` methods. This couples the data model to presentation concerns and violates the single responsibility principle. Use external formatter classes instead.

- **Using string concatenation without escaping for diagram labels.** Raw interpolation like `'$id[$label]'` breaks when `label` contains `[`, `]`, `{`, `}`, `(`, `)`, `"`, or `#`. Always escape through a dedicated function.

- **Attempting to round-trip Mermaid or PlantUML text back to an AST.** These formats are lossy presentation formats. They discard semantic information (source spans, type metadata, scoping rules) that cannot be recovered from the diagram text.

- **Using `identityHashCode` or `hashCode` as stable node identifiers in diagram output.** These values change across runs and VM instances. Use a deterministic counter or derive IDs from the AST structure.

- **Serializing the entire AST without a type discriminator.** Without a `type` field, deserialization code must guess the node kind from available fields, leading to fragile and ambiguous parsing logic.

- **Skipping validation before export.** If the AST contains cycles, the formatter will loop infinitely. If required fields are null, the output will be malformed. Always validate first.

- **Mixing pretty-printed and compact JSON in the same interchange pipeline.** Choose one format per context (pretty for human-readable debugging output, compact for API responses and storage) and be consistent.

- **Hardcoding style values throughout SVG generation code.** Scattering color strings, font sizes, and stroke widths across rendering methods makes theming impossible. Centralize all style values in a configuration object like `SvgStyle`.

- **Ignoring the `viewBox` when generating SVG.** Without a proper `viewBox`, the SVG will not scale correctly when embedded in HTML or displayed at different sizes. Always compute the bounding box of all elements and set `viewBox` accordingly.

- **Building SVG strings with raw string interpolation instead of an XML builder.** Manual string building leads to malformed XML (unescaped `<`, `>`, `&` in text, missing closing tags). Use `package:xml` or equivalent for well-formed output.

---

## Sources & References

- Mermaid Official Documentation -- Syntax reference for flowcharts, class diagrams, sequence diagrams, and all diagram types: https://mermaid.js.org/intro/
- PlantUML Language Reference Guide -- Complete syntax reference for class, component, activity, and sequence diagrams: https://plantuml.com/guide
- W3C SVG 2 Specification -- Authoritative reference for SVG elements, attributes, coordinate systems, and the path data mini-language: https://www.w3.org/TR/SVG2/
- Dart `json_serializable` Package Documentation -- Code generation for `fromJson`/`toJson` with custom converters and polymorphic support: https://pub.dev/packages/json_serializable
- JSON Schema Specification (2020-12) -- Defining and validating JSON interchange formats with `$ref`, `oneOf`, discriminators, and `$defs`: https://json-schema.org/specification
- Dart `xml` Package Documentation -- Building and parsing XML documents in Dart, used for SVG generation: https://pub.dev/packages/xml
- SVG Path Data Specification -- Detailed reference for the `d` attribute mini-language (M, L, C, Q, A, Z commands): https://developer.mozilla.org/en-US/docs/Web/SVG/Tutorial/Paths

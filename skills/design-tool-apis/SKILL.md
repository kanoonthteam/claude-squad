---
name: design-tool-apis
description: Export/Integration Engineer skill covering Figma REST API v1, Sketch SDK (.sketch file format), Adobe XD SDK/plugin API, and design token sync. Includes authentication patterns, node tree traversal, component read/write, webhooks, design token extraction, cross-tool sync, rate limiting, pagination, caching, error handling, and retry strategies -- all with production Dart 3.x examples.
---

# Design Tool APIs -- Figma, Sketch, Adobe XD & Design Token Sync

Comprehensive reference for an Export/Integration Engineer agent working with design tool APIs in Dart. Covers Figma REST API v1 for reading/writing design files, Sketch SDK for parsing and generating .sketch archives, Adobe XD plugin/SDK integration, and design token extraction and synchronization across all three platforms.

## Table of Contents

1. [Figma REST API v1 -- Overview & Authentication](#figma-rest-api-v1----overview--authentication)
2. [Figma File Access & Node Tree Structure](#figma-file-access--node-tree-structure)
3. [Figma Node Tree Traversal](#figma-node-tree-traversal)
4. [Reading Figma Designs & Converting to Internal Representation](#reading-figma-designs--converting-to-internal-representation)
5. [Writing & Creating Figma Components Programmatically](#writing--creating-figma-components-programmatically)
6. [Figma Components & Styles](#figma-components--styles)
7. [Figma Webhooks for Change Notifications](#figma-webhooks-for-change-notifications)
8. [Sketch File Format (.sketch) Structure & SDK](#sketch-file-format-sketch-structure--sdk)
9. [Reading .sketch Files](#reading-sketch-files)
10. [Writing .sketch Files](#writing-sketch-files)
11. [Adobe XD SDK & Plugin API](#adobe-xd-sdk--plugin-api)
12. [Design Token Extraction](#design-token-extraction)
13. [Design Token Sync Between Tools](#design-token-sync-between-tools)
14. [API Authentication Patterns](#api-authentication-patterns)
15. [Rate Limiting & Pagination](#rate-limiting--pagination)
16. [Error Handling & Retry Strategies](#error-handling--retry-strategies)
17. [Caching API Responses for Performance](#caching-api-responses-for-performance)
18. [Best Practices](#best-practices)
19. [Anti-Patterns](#anti-patterns)
20. [Sources & References](#sources--references)

---

## Figma REST API v1 -- Overview & Authentication

The Figma REST API v1 is the primary interface for programmatic access to Figma files, components, styles, and images. All requests go through `https://api.figma.com/v1/`.

### Authentication Methods

Figma supports two authentication mechanisms:

1. **Personal Access Tokens (PAT)** -- Generated from Figma account settings. Passed via the `X-Figma-Token` header. Suitable for server-side tools, CI/CD pipelines, and personal automation scripts.

2. **OAuth 2.0** -- For applications acting on behalf of users. Uses the standard authorization code flow with `https://www.figma.com/oauth` as the authorization endpoint and `https://api.figma.com/v1/oauth/token` for token exchange.

### Core Endpoints

| Endpoint | Method | Purpose |
|---|---|---|
| `/v1/files/:key` | GET | Retrieve a full file document |
| `/v1/files/:key/nodes` | GET | Retrieve specific nodes by IDs |
| `/v1/files/:key/images` | GET | Render nodes as image exports |
| `/v1/files/:key/components` | GET | List published components |
| `/v1/files/:key/styles` | GET | List published styles |
| `/v1/files/:key/comments` | GET/POST | Read/write comments |
| `/v1/images/:key` | GET | Export images from a file |
| `/v1/teams/:team_id/components` | GET | List team components |
| `/v1/teams/:team_id/styles` | GET | List team styles |
| `/v1/webhooks` | POST | Register webhooks |

### Request Headers

Every authenticated request must include either:
- `X-Figma-Token: <personal_access_token>` for PAT auth, or
- `Authorization: Bearer <oauth_token>` for OAuth auth.

---

## Figma File Access & Node Tree Structure

A Figma file is a tree of nodes. The root is a `DOCUMENT` node containing one or more `CANVAS` (page) nodes. Each canvas contains frames, groups, components, vectors, text, and other node types.

### Node Type Hierarchy

```
DOCUMENT
  +-- CANVAS (Page)
       +-- FRAME
       |    +-- GROUP
       |    |    +-- RECTANGLE
       |    |    +-- TEXT
       |    |    +-- ELLIPSE
       |    +-- COMPONENT
       |    |    +-- TEXT
       |    |    +-- VECTOR
       |    +-- INSTANCE (reference to COMPONENT)
       +-- COMPONENT_SET (variant container)
            +-- COMPONENT (variant A)
            +-- COMPONENT (variant B)
```

### Key Node Properties

Every node has these common properties:

- `id` -- Unique node identifier (e.g., `"1:2"`)
- `name` -- Human-readable name from the layers panel
- `type` -- Node type string (`FRAME`, `TEXT`, `COMPONENT`, etc.)
- `children` -- Array of child nodes (for container types)
- `absoluteBoundingBox` -- Position and size `{x, y, width, height}`
- `fills` -- Array of paint objects (solid, gradient, image)
- `strokes` -- Array of stroke paint objects
- `effects` -- Array of effects (shadow, blur)
- `constraints` -- Layout constraints relative to parent
- `layoutMode` -- Auto-layout direction (`HORIZONTAL`, `VERTICAL`, `NONE`)

### Component-Specific Properties

- `componentId` -- For `INSTANCE` nodes, the ID of the source `COMPONENT`
- `componentProperties` -- Exposed properties on component instances
- `variantProperties` -- Variant axis values for components inside a `COMPONENT_SET`

---

## Figma Node Tree Traversal

Traversing the Figma node tree is essential for extracting design information. The tree can be deep and wide, so efficient traversal matters.

### Depth-First Traversal

```dart
// lib/figma/node_traversal.dart

import 'dart:collection';

/// Represents a Figma node from the API response.
sealed class FigmaNode {
  final String id;
  final String name;
  final String type;
  final List<FigmaNode> children;
  final BoundingBox? absoluteBoundingBox;
  final List<Paint> fills;
  final Map<String, dynamic> rawJson;

  FigmaNode({
    required this.id,
    required this.name,
    required this.type,
    this.children = const [],
    this.absoluteBoundingBox,
    this.fills = const [],
    this.rawJson = const {},
  });

  factory FigmaNode.fromJson(Map<String, dynamic> json) {
    final children = (json['children'] as List<dynamic>?)
            ?.map((c) => FigmaNode.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [];
    final bbox = json['absoluteBoundingBox'] as Map<String, dynamic>?;
    final fills = (json['fills'] as List<dynamic>?)
            ?.map((f) => Paint.fromJson(f as Map<String, dynamic>))
            .toList() ??
        [];

    return switch (json['type'] as String) {
      'DOCUMENT' => DocumentNode(
          id: json['id'] as String,
          name: json['name'] as String,
          children: children,
          rawJson: json,
        ),
      'CANVAS' => CanvasNode(
          id: json['id'] as String,
          name: json['name'] as String,
          children: children,
          backgroundColor: json['backgroundColor'] as Map<String, dynamic>?,
          rawJson: json,
        ),
      'COMPONENT' => ComponentNode(
          id: json['id'] as String,
          name: json['name'] as String,
          children: children,
          absoluteBoundingBox:
              bbox != null ? BoundingBox.fromJson(bbox) : null,
          fills: fills,
          componentKey: json['key'] as String? ?? '',
          rawJson: json,
        ),
      'INSTANCE' => InstanceNode(
          id: json['id'] as String,
          name: json['name'] as String,
          children: children,
          absoluteBoundingBox:
              bbox != null ? BoundingBox.fromJson(bbox) : null,
          fills: fills,
          componentId: json['componentId'] as String? ?? '',
          rawJson: json,
        ),
      'TEXT' => TextNode(
          id: json['id'] as String,
          name: json['name'] as String,
          absoluteBoundingBox:
              bbox != null ? BoundingBox.fromJson(bbox) : null,
          fills: fills,
          characters: json['characters'] as String? ?? '',
          style: json['style'] as Map<String, dynamic>? ?? {},
          rawJson: json,
        ),
      _ => GenericNode(
          id: json['id'] as String,
          name: json['name'] as String,
          type: json['type'] as String,
          children: children,
          absoluteBoundingBox:
              bbox != null ? BoundingBox.fromJson(bbox) : null,
          fills: fills,
          rawJson: json,
        ),
    };
  }
}

class DocumentNode extends FigmaNode {
  DocumentNode({
    required super.id,
    required super.name,
    super.children,
    super.rawJson,
  }) : super(type: 'DOCUMENT');
}

class CanvasNode extends FigmaNode {
  final Map<String, dynamic>? backgroundColor;

  CanvasNode({
    required super.id,
    required super.name,
    super.children,
    this.backgroundColor,
    super.rawJson,
  }) : super(type: 'CANVAS');
}

class ComponentNode extends FigmaNode {
  final String componentKey;

  ComponentNode({
    required super.id,
    required super.name,
    super.children,
    super.absoluteBoundingBox,
    super.fills,
    required this.componentKey,
    super.rawJson,
  }) : super(type: 'COMPONENT');
}

class InstanceNode extends FigmaNode {
  final String componentId;

  InstanceNode({
    required super.id,
    required super.name,
    super.children,
    super.absoluteBoundingBox,
    super.fills,
    required this.componentId,
    super.rawJson,
  }) : super(type: 'INSTANCE');
}

class TextNode extends FigmaNode {
  final String characters;
  final Map<String, dynamic> style;

  TextNode({
    required super.id,
    required super.name,
    super.absoluteBoundingBox,
    super.fills,
    required this.characters,
    required this.style,
    super.rawJson,
  }) : super(type: 'TEXT');
}

class GenericNode extends FigmaNode {
  GenericNode({
    required super.id,
    required super.name,
    required super.type,
    super.children,
    super.absoluteBoundingBox,
    super.fills,
    super.rawJson,
  });
}

class BoundingBox {
  final double x;
  final double y;
  final double width;
  final double height;

  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory BoundingBox.fromJson(Map<String, dynamic> json) => BoundingBox(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
      );
}

class Paint {
  final String type;
  final Map<String, dynamic>? color;
  final double opacity;

  const Paint({required this.type, this.color, this.opacity = 1.0});

  factory Paint.fromJson(Map<String, dynamic> json) => Paint(
        type: json['type'] as String,
        color: json['color'] as Map<String, dynamic>?,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      );
}

/// Traversal utilities for the Figma node tree.
class FigmaTreeTraversal {
  /// Depth-first traversal yielding each node.
  static Iterable<FigmaNode> depthFirst(FigmaNode root) sync* {
    yield root;
    for (final child in root.children) {
      yield* depthFirst(child);
    }
  }

  /// Breadth-first traversal yielding each node.
  static Iterable<FigmaNode> breadthFirst(FigmaNode root) sync* {
    final queue = Queue<FigmaNode>()..add(root);
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      yield current;
      queue.addAll(current.children);
    }
  }

  /// Find all nodes matching a predicate.
  static List<FigmaNode> findAll(
    FigmaNode root,
    bool Function(FigmaNode) predicate,
  ) {
    return depthFirst(root).where(predicate).toList();
  }

  /// Find all nodes of a specific type.
  static List<T> findAllOfType<T extends FigmaNode>(FigmaNode root) {
    return depthFirst(root).whereType<T>().toList();
  }

  /// Find the first node matching a predicate, or null.
  static FigmaNode? findFirst(
    FigmaNode root,
    bool Function(FigmaNode) predicate,
  ) {
    for (final node in depthFirst(root)) {
      if (predicate(node)) return node;
    }
    return null;
  }

  /// Build a path from root to a target node by ID.
  static List<FigmaNode>? pathTo(FigmaNode root, String targetId) {
    if (root.id == targetId) return [root];
    for (final child in root.children) {
      final subPath = pathTo(child, targetId);
      if (subPath != null) return [root, ...subPath];
    }
    return null;
  }
}
```

### Usage Patterns

- Use `depthFirst` when you need to process every node (e.g., extracting all colors).
- Use `breadthFirst` when you want to process top-level frames before diving deeper.
- Use `findAllOfType<ComponentNode>` to collect all components for a component catalog.
- Use `pathTo` to understand the nesting context of a particular node.

---

## Reading Figma Designs & Converting to Internal Representation

Once you retrieve a file from the Figma API, you need to convert the raw JSON tree into your application's internal design representation. This intermediate representation decouples your pipeline from Figma-specific structures.

### Internal Representation Model

Define a clean, tool-agnostic model:

```dart
// lib/models/design_element.dart

/// Tool-agnostic internal representation of a design element.
class DesignElement {
  final String id;
  final String name;
  final DesignElementType type;
  final Rect bounds;
  final List<DesignElement> children;
  final DesignStyle style;
  final String? textContent;
  final String? sourceComponentId;
  final Map<String, String> metadata;

  const DesignElement({
    required this.id,
    required this.name,
    required this.type,
    required this.bounds,
    this.children = const [],
    this.style = const DesignStyle(),
    this.textContent,
    this.sourceComponentId,
    this.metadata = const {},
  });
}

enum DesignElementType {
  page,
  frame,
  group,
  component,
  instance,
  text,
  rectangle,
  ellipse,
  vector,
  image,
  unknown,
}

class Rect {
  final double x;
  final double y;
  final double width;
  final double height;

  const Rect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class DesignStyle {
  final DesignColor? fillColor;
  final DesignColor? strokeColor;
  final double? strokeWeight;
  final double? cornerRadius;
  final double? opacity;
  final TextStyle? textStyle;
  final List<Shadow> shadows;
  final BlurEffect? blur;

  const DesignStyle({
    this.fillColor,
    this.strokeColor,
    this.strokeWeight,
    this.cornerRadius,
    this.opacity,
    this.textStyle,
    this.shadows = const [],
    this.blur,
  });
}

class DesignColor {
  final double r;
  final double g;
  final double b;
  final double a;

  const DesignColor({
    required this.r,
    required this.g,
    required this.b,
    this.a = 1.0,
  });

  String toHex() {
    final ri = (r * 255).round().clamp(0, 255);
    final gi = (g * 255).round().clamp(0, 255);
    final bi = (b * 255).round().clamp(0, 255);
    return '#${ri.toRadixString(16).padLeft(2, '0')}'
        '${gi.toRadixString(16).padLeft(2, '0')}'
        '${bi.toRadixString(16).padLeft(2, '0')}';
  }
}

class TextStyle {
  final String fontFamily;
  final double fontSize;
  final double fontWeight;
  final double? lineHeight;
  final double? letterSpacing;
  final String? textAlign;

  const TextStyle({
    required this.fontFamily,
    required this.fontSize,
    required this.fontWeight,
    this.lineHeight,
    this.letterSpacing,
    this.textAlign,
  });
}

class Shadow {
  final DesignColor color;
  final double offsetX;
  final double offsetY;
  final double blurRadius;
  final double? spreadRadius;

  const Shadow({
    required this.color,
    required this.offsetX,
    required this.offsetY,
    required this.blurRadius,
    this.spreadRadius,
  });
}

class BlurEffect {
  final double radius;
  final String type; // 'LAYER_BLUR' or 'BACKGROUND_BLUR'

  const BlurEffect({required this.radius, required this.type});
}
```

### Figma-to-Internal Converter

The converter maps Figma-specific types and properties into the internal model:

- Map `CANVAS` to `DesignElementType.page`, `FRAME` to `frame`, `COMPONENT` to `component`, etc.
- Extract the first solid fill as `fillColor`.
- Map Figma text style properties (`fontFamily`, `fontSize`, `fontWeight`, `lineHeightPx`, `letterSpacing`) into `TextStyle`.
- Recursively convert children to produce a nested `DesignElement` tree.

This pattern lets you add Sketch and Adobe XD converters that produce the same `DesignElement` tree, allowing a single downstream pipeline.

---

## Writing & Creating Figma Components Programmatically

Figma's REST API is primarily read-only. To programmatically create or modify Figma files, you use the **Figma Plugin API** (runs inside Figma) or the **Figma REST API for variables and styles** (limited write capabilities added in recent API updates).

### Plugin API Approach

Figma plugins written in TypeScript run inside the Figma editor. Your Dart backend can generate plugin manifests or communicate with a running plugin via WebSocket relay.

### REST API Write Capabilities

Recent additions allow:

- **POST /v1/files/:key/variables** -- Create and update variables (design tokens).
- **POST /v1/files/:key/styles** -- Publish style changes.
- **POST /v1/files/:key/comments** -- Add comments to files.
- **POST /v1/webhooks** -- Register event listeners.

### Variable Creation via REST API

When creating variables (color tokens, spacing values) through the REST API:

1. Identify or create a `VariableCollection` to group related tokens.
2. Define each variable with a name, type (`COLOR`, `FLOAT`, `STRING`, `BOOLEAN`), and mode values.
3. POST the variable definitions to the endpoint.

The response includes the created variable IDs, which you can then reference elsewhere.

### Component Publishing Workflow

The typical workflow for getting components into Figma programmatically:

1. Generate a Figma plugin bundle from your Dart tool (outputting the plugin's TypeScript).
2. The plugin reads your internal representation (JSON) and calls `figma.createComponent()`, `figma.createFrame()`, etc.
3. Published components become available in the team library.

---

## Figma Components & Styles

### Published Components

Use `GET /v1/files/:key/components` to list all published components. Each component has:

- `key` -- Unique component key for cross-file references
- `name` -- Component name (may include slash-separated categories, e.g., `Icons/Arrow`)
- `description` -- Published description
- `containing_frame` -- The frame holding the component
- `thumbnail_url` -- Preview image URL

### Published Styles

Use `GET /v1/files/:key/styles` to list all published styles:

- `key` -- Unique style key
- `name` -- Style name
- `style_type` -- One of `FILL`, `TEXT`, `EFFECT`, `GRID`
- `description` -- Published description
- `thumbnail_url` -- Preview image URL

### Team-Level Queries

For organization-wide design systems, query at the team level:

- `GET /v1/teams/:team_id/components` with `?page_size=50&after=<cursor>` for pagination
- `GET /v1/teams/:team_id/styles` with the same pagination parameters

---

## Figma Webhooks for Change Notifications

Figma webhooks notify your server when changes occur in files or projects, enabling real-time sync pipelines.

### Supported Events

| Event Type | Trigger |
|---|---|
| `FILE_UPDATE` | A file is saved (versioned) |
| `FILE_DELETE` | A file is deleted |
| `FILE_VERSION_UPDATE` | A named version is created |
| `FILE_COMMENT` | A comment is added |
| `LIBRARY_PUBLISH` | A library is published |

### Registering a Webhook

Send a POST to `https://api.figma.com/v2/webhooks`:

```json
{
  "event_type": "FILE_UPDATE",
  "team_id": "123456",
  "endpoint": "https://your-server.com/api/figma/webhook",
  "passcode": "your-secret-passcode",
  "description": "Design token sync trigger"
}
```

### Webhook Payload Structure

The webhook POST body includes:

- `event_type` -- Which event fired
- `file_key` -- The affected file key
- `file_name` -- Human-readable file name
- `timestamp` -- ISO 8601 timestamp
- `passcode` -- The passcode you provided at registration (for verification)
- `triggered_by` -- User information for who triggered the event

### Verification

Always verify the `passcode` field in incoming webhook payloads matches what you registered. This prevents spoofed webhook calls.

### Webhook Management

- `GET /v2/webhooks/:webhook_id` -- Retrieve a specific webhook
- `PUT /v2/webhooks/:webhook_id` -- Update a webhook
- `DELETE /v2/webhooks/:webhook_id` -- Remove a webhook
- `GET /v2/teams/:team_id/webhooks` -- List all webhooks for a team

---

## Sketch File Format (.sketch) Structure & SDK

### .sketch File Format

A `.sketch` file is a ZIP archive containing:

```
document.json         -- Document metadata, pages list, foreign symbols
meta.json             -- Sketch version, app version, fonts used
user.json             -- Viewport state per page (optional)
pages/
  <uuid>.json         -- Each page as a separate JSON file
images/
  <sha256>.png        -- Embedded bitmap images
previews/
  preview.png         -- Thumbnail preview
```

### Document Structure

`document.json` contains:

- `do_objectID` -- Unique document identifier
- `pages` -- Array of page references (each with `_ref` pointing to `pages/<uuid>`)
- `foreignLayerStyles` -- Styles imported from other libraries
- `foreignSymbols` -- Symbols (components) imported from other libraries
- `foreignTextStyles` -- Text styles from other libraries
- `layerStyles` -- Document-level shared layer styles
- `layerTextStyles` -- Document-level shared text styles
- `colorSpace` -- Color space (0 = unmanaged, 1 = sRGB, 2 = P3)

### Page JSON Structure

Each `pages/<uuid>.json` file contains a root layer (artboard container) with nested layers:

- `_class` -- Layer class: `artboard`, `group`, `rectangle`, `oval`, `text`, `symbolMaster`, `symbolInstance`, `shapePath`, `bitmap`, etc.
- `do_objectID` -- UUID for this layer
- `name` -- Layer name
- `frame` -- `{x, y, width, height}` relative to parent
- `style` -- Fills, borders, shadows, blur
- `layers` -- Child layers array (for container types)
- `isVisible` -- Visibility flag
- `rotation` -- Rotation in degrees

### Symbol System

Sketch "symbols" are the equivalent of Figma components:

- `symbolMaster` -- The definition of a reusable component. Has a `symbolID` (UUID) and `overrideProperties`.
- `symbolInstance` -- A usage of a symbol. References `symbolID` and can have `overrideValues` for text, images, and nested symbols.

---

## Reading .sketch Files

Since `.sketch` files are ZIP archives, reading them in Dart involves:

1. Extracting the ZIP.
2. Parsing `document.json` and `meta.json`.
3. Iterating over page JSON files.
4. Traversing the layer tree within each page.

```dart
// lib/sketch/sketch_reader.dart

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';

/// Reads and parses a .sketch file into structured data.
class SketchReader {
  final Map<String, dynamic> document;
  final Map<String, dynamic> meta;
  final Map<String, dynamic> user;
  final Map<String, Map<String, dynamic>> pages;
  final Map<String, List<int>> images;

  SketchReader._({
    required this.document,
    required this.meta,
    required this.user,
    required this.pages,
    required this.images,
  });

  /// Open and parse a .sketch file from disk.
  static Future<SketchReader> open(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final fileMap = <String, ArchiveFile>{};
    for (final file in archive) {
      fileMap[file.name] = file;
    }

    final document = _decodeJson(fileMap['document.json']!);
    final meta = _decodeJson(fileMap['meta.json']!);
    final user = fileMap.containsKey('user.json')
        ? _decodeJson(fileMap['user.json']!)
        : <String, dynamic>{};

    // Parse each page referenced in document.json
    final pages = <String, Map<String, dynamic>>{};
    final pageRefs = document['pages'] as List<dynamic>? ?? [];
    for (final pageRef in pageRefs) {
      final ref = pageRef['_ref'] as String;
      final pageFile = fileMap['$ref.json'];
      if (pageFile != null) {
        pages[ref] = _decodeJson(pageFile);
      }
    }

    // Collect embedded images
    final images = <String, List<int>>{};
    for (final entry in fileMap.entries) {
      if (entry.key.startsWith('images/')) {
        images[entry.key] = entry.value.content as List<int>;
      }
    }

    return SketchReader._(
      document: document,
      meta: meta,
      user: user,
      pages: pages,
      images: images,
    );
  }

  static Map<String, dynamic> _decodeJson(ArchiveFile file) {
    final content = utf8.decode(file.content as List<int>);
    return jsonDecode(content) as Map<String, dynamic>;
  }

  /// Retrieve all layer trees from all pages.
  List<Map<String, dynamic>> getAllLayers() {
    final allLayers = <Map<String, dynamic>>[];
    for (final page in pages.values) {
      _collectLayers(page, allLayers);
    }
    return allLayers;
  }

  /// Find all symbol masters across all pages.
  List<Map<String, dynamic>> getSymbolMasters() {
    return getAllLayers()
        .where((layer) => layer['_class'] == 'symbolMaster')
        .toList();
  }

  /// Find all symbol instances across all pages.
  List<Map<String, dynamic>> getSymbolInstances() {
    return getAllLayers()
        .where((layer) => layer['_class'] == 'symbolInstance')
        .toList();
  }

  /// Extract shared layer styles from the document.
  List<Map<String, dynamic>> getSharedLayerStyles() {
    final styles = document['layerStyles'] as Map<String, dynamic>?;
    if (styles == null) return [];
    return (styles['objects'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
  }

  /// Extract shared text styles from the document.
  List<Map<String, dynamic>> getSharedTextStyles() {
    final styles = document['layerTextStyles'] as Map<String, dynamic>?;
    if (styles == null) return [];
    return (styles['objects'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
  }

  void _collectLayers(
    Map<String, dynamic> node,
    List<Map<String, dynamic>> result,
  ) {
    result.add(node);
    final children = node['layers'] as List<dynamic>?;
    if (children != null) {
      for (final child in children) {
        _collectLayers(child as Map<String, dynamic>, result);
      }
    }
  }
}
```

### Converting Sketch Layers to Internal Representation

Map Sketch classes to `DesignElementType`:

| Sketch `_class` | DesignElementType |
|---|---|
| `artboard` | `frame` |
| `group` | `group` |
| `rectangle` | `rectangle` |
| `oval` | `ellipse` |
| `text` | `text` |
| `symbolMaster` | `component` |
| `symbolInstance` | `instance` |
| `bitmap` | `image` |
| `shapePath` | `vector` |

Extract fills from `style.fills[0].color` (RGBA with values 0-1), borders from `style.borders`, shadows from `style.shadows`, and text attributes from `attributedString.attributes`.

---

## Writing .sketch Files

Creating or modifying `.sketch` files involves building the correct JSON structures and packaging them into a ZIP archive.

### Writing Workflow

1. Construct `document.json` with page references and shared styles.
2. Build each page JSON with the layer tree.
3. Add any required images to the `images/` directory.
4. Generate `meta.json` with the correct Sketch version metadata.
5. Package everything into a ZIP and rename to `.sketch`.

Key considerations when writing:

- Every object needs a unique `do_objectID` (UUID v4).
- Layer frames use coordinates relative to their parent.
- Symbol masters need globally unique `symbolID` values.
- The `meta.json` must list all pages and artboards for Sketch to properly index the file.
- Color values are floating-point 0.0 to 1.0 for RGBA.

---

## Adobe XD SDK & Plugin API

### Overview

Adobe XD plugins extend the XD editor. The plugin API is JavaScript-based, but your Dart backend can generate plugin code, communicate with plugins via network, or parse XD file formats.

### .xd File Format

An `.xd` file is also a ZIP-based archive (similar to `.sketch`), containing:

```
manifest.json          -- Plugin/file manifest
artwork/
  artboard-<uuid>.agc  -- Artboard data in Adobe's AGC format
  pasteboard.agc       -- Pasteboard (canvas) data
resources/
  graphics/            -- Embedded images and SVGs
interactions/
  interactions.json    -- Prototype interactions and transitions
```

### Plugin API Key Concepts

Adobe XD plugins interact through scenegraph nodes:

- `Artboard` -- Top-level container (like Figma frames)
- `Group` -- Grouping container
- `Rectangle`, `Ellipse`, `Polygon`, `Line`, `Path` -- Shape nodes
- `Text` -- Text nodes
- `SymbolInstance` -- Component instance
- `RepeatGrid` -- Repeated element grid (unique to XD)
- `LinkedGraphic` -- Linked external asset

### Plugin Communication Pattern

For Dart integration, establish a bridge:

1. Write a minimal XD plugin in JavaScript that exposes scenegraph data via a local HTTP server or WebSocket.
2. The Dart backend connects to the plugin endpoint.
3. Exchange data as JSON matching the internal representation format.

### XD Cloud API

Adobe XD files stored in Creative Cloud can be accessed via the Adobe Creative Cloud API:

- Authenticate via Adobe IMS OAuth 2.0
- Access shared documents and prototypes
- Export artboards as images

---

## Design Token Extraction

Design tokens are the atomic values of a design system: colors, typography scales, spacing values, border radii, shadows, and more.

### Token Categories

| Category | Figma Source | Sketch Source | XD Source |
|---|---|---|---|
| Colors | Fills, styles, variables | Shared layer styles, fills | Color assets, fills |
| Typography | Text styles, font properties | Shared text styles | Character styles |
| Spacing | Auto-layout padding/gap | Layout settings | Padding, stack spacing |
| Border radius | Corner radius property | Points, corner radius | Corner radius |
| Shadows | Drop shadow effects | Shadow style properties | Shadow objects |
| Opacity | Node opacity + fill opacity | Layer opacity + fill opacity | Opacity property |

### Token Data Model

```dart
// lib/tokens/design_token.dart

/// A single design token with its value, metadata, and source provenance.
class DesignToken {
  final String name;
  final String category;
  final TokenValue value;
  final String? description;
  final TokenSource source;
  final Map<String, TokenValue> modeValues;

  const DesignToken({
    required this.name,
    required this.category,
    required this.value,
    this.description,
    required this.source,
    this.modeValues = const {},
  });

  /// Convert to W3C Design Token Community Group format.
  Map<String, dynamic> toW3CFormat() {
    return {
      r'$value': value.toJson(),
      r'$type': category,
      if (description != null) r'$description': description,
    };
  }
}

/// Represents the source of a design token.
class TokenSource {
  final DesignTool tool;
  final String fileId;
  final String nodeId;
  final String? styleName;
  final DateTime extractedAt;

  const TokenSource({
    required this.tool,
    required this.fileId,
    required this.nodeId,
    this.styleName,
    required this.extractedAt,
  });
}

enum DesignTool { figma, sketch, adobeXd }

/// Sealed hierarchy for typed token values.
sealed class TokenValue {
  const TokenValue();

  Map<String, dynamic> toJson();
}

class ColorTokenValue extends TokenValue {
  final double r;
  final double g;
  final double b;
  final double a;

  const ColorTokenValue({
    required this.r,
    required this.g,
    required this.b,
    this.a = 1.0,
  });

  @override
  Map<String, dynamic> toJson() => {'r': r, 'g': g, 'b': b, 'a': a};

  String toHex() {
    final ri = (r * 255).round().clamp(0, 255);
    final gi = (g * 255).round().clamp(0, 255);
    final bi = (b * 255).round().clamp(0, 255);
    final ai = (a * 255).round().clamp(0, 255);
    if (ai == 255) {
      return '#${ri.toRadixString(16).padLeft(2, '0')}'
          '${gi.toRadixString(16).padLeft(2, '0')}'
          '${bi.toRadixString(16).padLeft(2, '0')}';
    }
    return '#${ri.toRadixString(16).padLeft(2, '0')}'
        '${gi.toRadixString(16).padLeft(2, '0')}'
        '${bi.toRadixString(16).padLeft(2, '0')}'
        '${ai.toRadixString(16).padLeft(2, '0')}';
  }
}

class TypographyTokenValue extends TokenValue {
  final String fontFamily;
  final double fontSize;
  final double fontWeight;
  final double? lineHeight;
  final double? letterSpacing;

  const TypographyTokenValue({
    required this.fontFamily,
    required this.fontSize,
    required this.fontWeight,
    this.lineHeight,
    this.letterSpacing,
  });

  @override
  Map<String, dynamic> toJson() => {
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'fontWeight': fontWeight,
        if (lineHeight != null) 'lineHeight': lineHeight,
        if (letterSpacing != null) 'letterSpacing': letterSpacing,
      };
}

class DimensionTokenValue extends TokenValue {
  final double value;
  final String unit;

  const DimensionTokenValue({required this.value, this.unit = 'px'});

  @override
  Map<String, dynamic> toJson() => {'value': value, 'unit': unit};
}

class ShadowTokenValue extends TokenValue {
  final double offsetX;
  final double offsetY;
  final double blur;
  final double spread;
  final ColorTokenValue color;

  const ShadowTokenValue({
    required this.offsetX,
    required this.offsetY,
    required this.blur,
    this.spread = 0,
    required this.color,
  });

  @override
  Map<String, dynamic> toJson() => {
        'offsetX': offsetX,
        'offsetY': offsetY,
        'blur': blur,
        'spread': spread,
        'color': color.toJson(),
      };
}

/// Extracts design tokens from an internal DesignElement tree.
class DesignTokenExtractor {
  final DesignTool sourceTool;
  final String fileId;

  DesignTokenExtractor({required this.sourceTool, required this.fileId});

  /// Extract all color tokens from fills across the element tree.
  List<DesignToken> extractColors(List<FigmaNode> nodes) {
    final tokens = <DesignToken>[];
    final seenColors = <String>{};

    for (final node in nodes) {
      for (final fill in node.fills) {
        if (fill.type == 'SOLID' && fill.color != null) {
          final c = fill.color!;
          final colorValue = ColorTokenValue(
            r: (c['r'] as num).toDouble(),
            g: (c['g'] as num).toDouble(),
            b: (c['b'] as num).toDouble(),
            a: (c['a'] as num?)?.toDouble() ?? 1.0,
          );
          final hex = colorValue.toHex();
          if (!seenColors.contains(hex)) {
            seenColors.add(hex);
            tokens.add(DesignToken(
              name: _generateColorName(node.name, hex),
              category: 'color',
              value: colorValue,
              source: TokenSource(
                tool: sourceTool,
                fileId: fileId,
                nodeId: node.id,
                extractedAt: DateTime.now(),
              ),
            ));
          }
        }
      }
    }
    return tokens;
  }

  /// Extract typography tokens from text nodes.
  List<DesignToken> extractTypography(List<TextNode> textNodes) {
    final tokens = <DesignToken>[];
    final seenStyles = <String>{};

    for (final node in textNodes) {
      final style = node.style;
      final key = '${style['fontFamily']}-${style['fontSize']}-'
          '${style['fontWeight']}';
      if (!seenStyles.contains(key)) {
        seenStyles.add(key);
        tokens.add(DesignToken(
          name: _generateTypographyName(node.name),
          category: 'typography',
          value: TypographyTokenValue(
            fontFamily: style['fontFamily'] as String? ?? 'Unknown',
            fontSize: (style['fontSize'] as num?)?.toDouble() ?? 16,
            fontWeight: (style['fontWeight'] as num?)?.toDouble() ?? 400,
            lineHeight:
                (style['lineHeightPx'] as num?)?.toDouble(),
            letterSpacing:
                (style['letterSpacing'] as num?)?.toDouble(),
          ),
          source: TokenSource(
            tool: sourceTool,
            fileId: fileId,
            nodeId: node.id,
            extractedAt: DateTime.now(),
          ),
        ));
      }
    }
    return tokens;
  }

  String _generateColorName(String nodeName, String hex) {
    final sanitized = nodeName
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-')
        .toLowerCase();
    return 'color-$sanitized';
  }

  String _generateTypographyName(String nodeName) {
    final sanitized = nodeName
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-')
        .toLowerCase();
    return 'typography-$sanitized';
  }
}
```

---

## Design Token Sync Between Tools

Synchronizing tokens across Figma, Sketch, and Adobe XD requires a canonical intermediate format and bidirectional converters.

### W3C Design Token Community Group Format

The emerging standard (DTCG) format uses JSON with `$value` and `$type` keys:

```json
{
  "color": {
    "primary": {
      "$value": "#1a73e8",
      "$type": "color",
      "$description": "Primary brand color"
    },
    "secondary": {
      "$value": "#ea4335",
      "$type": "color"
    }
  },
  "spacing": {
    "sm": {
      "$value": "8px",
      "$type": "dimension"
    },
    "md": {
      "$value": "16px",
      "$type": "dimension"
    }
  }
}
```

### Sync Pipeline Architecture

```
Figma API  ---extract---> Canonical Tokens (DTCG JSON)
Sketch SDK ---extract--->        |
XD Plugin  ---extract--->        |
                                 v
                          Token Registry
                          (versioned store)
                                 |
                    +------------+------------+
                    |            |            |
                    v            v            v
              Figma Vars   Sketch Styles  XD Assets
              (write back) (write back)   (write back)
```

### Sync Strategy

1. **Extract** -- Pull tokens from each tool into the canonical DTCG format.
2. **Merge** -- Reconcile tokens from multiple sources. Use naming conventions or explicit mappings.
3. **Diff** -- Compare the merged token set against the last known state to detect additions, changes, and deletions.
4. **Push** -- Write updated tokens back to each tool's native format.

### Conflict Resolution

When the same token is modified in multiple tools between syncs:

- **Last-write-wins** -- Simple but can lose changes. Use only for low-stakes tokens.
- **Source-of-truth tool** -- Designate one tool (usually Figma) as authoritative. Changes in other tools are overwritten.
- **Manual review** -- Flag conflicts for human review. Best for critical brand tokens.

---

## API Authentication Patterns

### Personal Access Tokens (Figma)

Best for server-side automation, CI/CD pipelines, and scripts run by a single user.

```
X-Figma-Token: figd_XXXXXXXXXXXXXXXXXXXXX
```

Store in environment variables. Never commit to source control.

### OAuth 2.0 (Figma)

For multi-user applications:

1. **Authorization URL**: `https://www.figma.com/oauth?client_id=<ID>&redirect_uri=<URI>&scope=files:read&state=<STATE>&response_type=code`
2. **Token Exchange**: POST to `https://api.figma.com/v1/oauth/token` with `client_id`, `client_secret`, `redirect_uri`, `code`, and `grant_type=authorization_code`.
3. **Refresh**: POST the same endpoint with `grant_type=refresh_token` and `refresh_token`.

### Adobe IMS OAuth 2.0

Adobe uses Identity Management System (IMS) for OAuth:

1. **Authorization**: `https://ims-na1.adobelogin.com/ims/authorize/v2`
2. **Token Exchange**: `https://ims-na1.adobelogin.com/ims/token/v3`
3. Scopes: `openid`, `creative_cloud`, `creative_sdk`

### Token Storage

- Use OS keychain/credential manager in desktop tools.
- Use encrypted secrets in CI/CD environments.
- Implement token rotation: refresh OAuth tokens before expiry.
- Never log tokens. Redact them from error messages.

---

## Rate Limiting & Pagination

### Figma Rate Limits

Figma enforces rate limits per personal access token or OAuth token:

- **Approximate limit**: ~30 requests per minute for file reads (undocumented; varies).
- Responses include `X-RateLimit-Remaining` and `X-RateLimit-Reset` headers when approaching limits.
- HTTP 429 (Too Many Requests) is returned when the limit is exceeded, with a `Retry-After` header.

### Pagination

Team-level endpoints use cursor-based pagination:

- Request: `GET /v1/teams/:team_id/components?page_size=50`
- Response includes a `meta.cursor` field.
- Next page: `GET /v1/teams/:team_id/components?page_size=50&after=<cursor>`
- Continue until `meta.cursor` is absent or the returned list is shorter than `page_size`.

### Handling Large Files

For very large Figma files:

- Use `GET /v1/files/:key/nodes?ids=<comma-separated>` to fetch only specific nodes instead of the entire file tree.
- Set `depth=1` or `depth=2` query parameters to limit tree depth.
- Use `geometry=paths` only when you need vector path data (increases response size significantly).

---

## Error Handling & Retry Strategies

### Common Error Codes

| HTTP Status | Meaning | Action |
|---|---|---|
| 400 | Bad request (invalid parameters) | Fix the request; do not retry |
| 401 | Unauthorized (bad/expired token) | Refresh OAuth token or check PAT |
| 403 | Forbidden (no access to resource) | Check file sharing permissions |
| 404 | File/node not found | Verify file key and node IDs |
| 429 | Rate limited | Retry after `Retry-After` header delay |
| 500 | Figma server error | Retry with exponential backoff |
| 503 | Service unavailable | Retry with exponential backoff |

### Exponential Backoff with Jitter

```dart
// lib/api/retry_strategy.dart

import 'dart:math';

/// Configurable retry strategy with exponential backoff and jitter.
class RetryStrategy {
  final int maxRetries;
  final Duration initialDelay;
  final double backoffMultiplier;
  final Duration maxDelay;
  final Set<int> retryableStatusCodes;
  final Random _random = Random();

  RetryStrategy({
    this.maxRetries = 5,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 60),
    this.retryableStatusCodes = const {429, 500, 502, 503, 504},
  });

  /// Calculate delay for the given attempt (0-indexed).
  Duration delayForAttempt(int attempt, {Duration? retryAfter}) {
    if (retryAfter != null) return retryAfter;

    final baseDelay = initialDelay.inMilliseconds *
        pow(backoffMultiplier, attempt).toDouble();
    final cappedDelay = min(baseDelay, maxDelay.inMilliseconds.toDouble());

    // Add jitter: random value between 0 and cappedDelay
    final jitter = _random.nextDouble() * cappedDelay;
    final finalDelay = (cappedDelay + jitter) / 2;

    return Duration(milliseconds: finalDelay.round());
  }

  /// Whether a given status code should trigger a retry.
  bool shouldRetry(int statusCode, int attemptsSoFar) {
    return attemptsSoFar < maxRetries &&
        retryableStatusCodes.contains(statusCode);
  }

  /// Execute an async operation with retries.
  Future<T> execute<T>(
    Future<T> Function() operation, {
    bool Function(Exception)? shouldRetryOn,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await operation();
      } on ApiException catch (e) {
        if (!shouldRetry(e.statusCode, attempt)) rethrow;

        final delay = delayForAttempt(
          attempt,
          retryAfter: e.retryAfter,
        );
        await Future.delayed(delay);
        attempt++;
      } on Exception catch (e) {
        if (shouldRetryOn != null && shouldRetryOn(e) && attempt < maxRetries) {
          final delay = delayForAttempt(attempt);
          await Future.delayed(delay);
          attempt++;
        } else {
          rethrow;
        }
      }
    }
  }
}

/// Exception representing an API error with HTTP status information.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Duration? retryAfter;
  final Map<String, dynamic>? responseBody;

  const ApiException({
    required this.statusCode,
    required this.message,
    this.retryAfter,
    this.responseBody,
  });

  bool get isRateLimited => statusCode == 429;
  bool get isServerError => statusCode >= 500;
  bool get isAuthError => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
```

### Circuit Breaker Pattern

For sustained failures, implement a circuit breaker to avoid overwhelming a failing service:

- **Closed** (normal): Requests flow through. Track failure count.
- **Open** (tripped): All requests fail immediately without hitting the API. After a timeout, transition to half-open.
- **Half-open** (testing): Allow a single request through. If it succeeds, close the circuit. If it fails, reopen.

---

## Caching API Responses for Performance

### Why Cache

Figma API calls for large files can take several seconds. Caching avoids redundant calls during:

- Repeated token extraction runs
- UI previews that re-render
- Multi-step pipelines that query the same file multiple times

### Cache Invalidation Strategies

1. **Time-based (TTL)** -- Cache entries expire after a fixed duration. Simple but may serve stale data.
2. **Version-based** -- Figma files have a `version` field. Cache the version alongside the data and invalidate when the version changes. Query `GET /v1/files/:key?depth=0` (lightweight) to check the current version.
3. **Webhook-driven** -- Use Figma webhooks to invalidate cache entries when files change. Most efficient for real-time sync.

### Cache Implementation Considerations

- **In-memory LRU cache** -- Fast, but lost on restart. Good for short-lived processes.
- **Disk cache** -- Persistent across restarts. Store JSON files keyed by `fileKey-version`.
- **Distributed cache (Redis)** -- For multi-instance deployments. Use with TTL and version-based invalidation.

### Cache Key Design

Use a composite key that includes all query parameters:

```
figma:file:<file_key>:v<version>:depth<depth>:ids<sorted_ids_hash>
```

This ensures different queries for the same file are cached independently.

### Partial Cache Updates

When only specific nodes change:

1. Fetch the file at `depth=0` to get the new version.
2. Compare with cached version.
3. If different, fetch only the changed nodes via `/v1/files/:key/nodes?ids=<changed_ids>`.
4. Merge the updated nodes into the cached tree.

---

## Best Practices

### General API Integration

1. **Use the narrowest possible query.** Fetch specific nodes with `?ids=` rather than entire files. Use `?depth=` to limit tree depth. This reduces response size and latency.

2. **Implement idempotent operations.** Design token extraction and sync operations should produce the same result when run multiple times with the same input.

3. **Version your token schema.** Include a schema version in your canonical token format so downstream consumers know how to parse it.

4. **Use structured logging.** Log API call durations, cache hit/miss rates, token counts, and sync outcomes. This data is invaluable for debugging sync failures.

5. **Validate API responses.** Do not assume the shape of API responses. Validate required fields and handle missing or unexpected data gracefully.

6. **Separate extraction from transformation.** Keep the "read from API" step separate from the "convert to internal format" step. This makes each step independently testable.

7. **Use semantic token names.** Name tokens by their purpose (`color-primary`, `spacing-page-margin`) rather than their value (`color-blue-500`, `spacing-16`). This makes the token set resilient to value changes.

8. **Pin API versions.** Use explicit API version paths (`/v1/`, `/v2/`) and monitor deprecation announcements.

9. **Handle partial failures.** When syncing tokens to multiple tools, a failure in one tool should not block updates to others. Log the failure and continue.

10. **Test with real API responses.** Record actual API responses and use them as test fixtures. Mock-based tests that drift from real responses cause production bugs.

### Figma-Specific

11. **Prefer team-level endpoints for design systems.** Use `/v1/teams/:team_id/components` and `/v1/teams/:team_id/styles` for organization-wide token extraction.

12. **Use variables for tokens.** Figma Variables are the native token mechanism. Prefer reading/writing variables over parsing fills and styles when the file uses variables.

13. **Handle component variants correctly.** A `COMPONENT_SET` contains multiple `COMPONENT` children, each representing a variant. Extract variant properties from `variantProperties`.

14. **Cache the file version.** Always store `file.version` alongside cached data. Use the lightweight `?depth=0` call to check for updates before re-fetching.

### Sketch-Specific

15. **Handle the ZIP structure carefully.** Always close file handles after reading. Use streaming decompression for large files.

16. **Validate UUIDs.** Every Sketch object needs a valid `do_objectID`. Generate proper UUID v4 values when creating new objects.

17. **Respect the coordinate system.** Sketch uses top-left origin with Y increasing downward. Frame coordinates are relative to the parent.

### Adobe XD Specific

18. **Use the plugin bridge pattern.** Since XD has no public REST API for file access, build a lightweight plugin that exposes scenegraph data via local HTTP or WebSocket.

19. **Handle XD's unique features.** RepeatGrid, responsive resize, and stacked layouts have no direct equivalents in Figma or Sketch. Map them to the closest internal representation and preserve the original data as metadata.

---

## Anti-Patterns

### 1. Fetching Entire Files Repeatedly

**Wrong:** Calling `GET /v1/files/:key` on every operation without caching or limiting depth.

**Why it is wrong:** Large files can produce multi-megabyte JSON responses. Repeated full-file fetches burn through rate limits and create latency.

**Correct approach:** Cache responses with version-based invalidation. Use `?ids=` to fetch only needed nodes. Use `?depth=` to limit tree depth.

### 2. Ignoring Rate Limits

**Wrong:** Sending requests as fast as possible and only handling 429 after the fact.

**Why it is wrong:** Sustained 429 errors trigger increasingly long backoff periods. Your pipeline stalls unpredictably.

**Correct approach:** Proactively throttle requests. Track `X-RateLimit-Remaining` headers. Use a token bucket or leaky bucket rate limiter on the client side.

### 3. Hardcoding Authentication Tokens

**Wrong:** Embedding personal access tokens or OAuth secrets directly in source code.

**Why it is wrong:** Tokens in source code end up in version control, CI logs, and error reports. Compromised tokens grant full access to all files the token owner can see.

**Correct approach:** Use environment variables, secret managers, or OS keychain. Rotate tokens regularly.

### 4. Parsing Node Trees Without Type Checking

**Wrong:** Assuming all nodes have `children`, `fills`, or `style` properties without checking the node type.

**Why it is wrong:** Different node types have different property sets. A `TEXT` node has `characters` and `style` but a `BOOLEAN_OPERATION` has `booleanOperation`. Accessing missing properties causes null errors.

**Correct approach:** Use the sealed class hierarchy (see traversal section) and pattern matching to handle each node type safely.

### 5. Synchronous Token Sync

**Wrong:** Running token extraction and sync for all tools sequentially in a single blocking operation.

**Why it is wrong:** If Figma's API is slow or Sketch file parsing takes long, the entire pipeline blocks. Failures in one tool cascade.

**Correct approach:** Run extraction from each tool concurrently with `Future.wait`. Handle failures independently per tool.

### 6. Using Mutable State for Token Merging

**Wrong:** Building a shared mutable `Map<String, DesignToken>` that multiple concurrent extractors write to.

**Why it is wrong:** Concurrent writes without synchronization cause data races and lost updates.

**Correct approach:** Each extractor returns an immutable list of tokens. Merge them in a single-threaded merge step after all extractions complete.

### 7. Not Validating Webhook Passcodes

**Wrong:** Accepting all incoming POST requests to your webhook endpoint without verifying the passcode.

**Why it is wrong:** Anyone who discovers your webhook URL can trigger fake sync events, causing unnecessary API calls or cache invalidations.

**Correct approach:** Always compare the `passcode` field in the webhook payload against the passcode you registered. Return 401 for mismatches.

### 8. Storing Full API Responses in Cache

**Wrong:** Caching the entire raw JSON response from Figma including metadata, user info, and timestamps.

**Why it is wrong:** Wastes cache storage. Cached user info may become stale or leak PII.

**Correct approach:** Cache only the data you need -- typically the document node tree and version number. Strip metadata and user-specific fields.

### 9. Generating Non-Deterministic Token Names

**Wrong:** Including timestamps, random suffixes, or extraction-order indices in token names.

**Why it is wrong:** Every extraction run produces different names, breaking downstream consumers that reference tokens by name.

**Correct approach:** Derive token names deterministically from the design element's name, path, or style key. Same input should always produce the same token name.

### 10. Treating All Design Tools Identically

**Wrong:** Assuming Figma, Sketch, and Adobe XD use the same coordinate systems, color models, typography units, or component semantics.

**Why it is wrong:** Each tool has subtle differences. Sketch uses integer `fontWeight` (1-12 scale historically), while Figma uses CSS-style weights (100-900). XD uses `fontSize` in points while Figma uses pixels. Blind mapping produces incorrect tokens.

**Correct approach:** Build tool-specific extractors that normalize values to a common unit system during conversion. Document the normalization rules.

---

## Sources & References

1. **Figma REST API Reference** -- Official documentation for all Figma REST API v1 endpoints, authentication, rate limits, and response schemas.
   https://www.figma.com/developers/api

2. **Figma Plugin API Documentation** -- Reference for the Figma Plugin API used for reading and writing to the Figma canvas from plugins.
   https://www.figma.com/plugin-docs/

3. **Sketch Developer Documentation** -- Official reference for the Sketch file format, plugin API, and JavaScript-based plugin development.
   https://developer.sketch.com/file-format/

4. **Adobe XD Plugin API Reference** -- Documentation for Adobe XD plugin development, scenegraph API, and UI toolkit.
   https://developer.adobe.com/xd/uxp/develop/

5. **W3C Design Tokens Community Group (DTCG) Specification** -- The emerging standard for design token file format and semantics.
   https://design-tokens.github.io/community-group/format/

6. **Figma Webhooks Guide** -- Documentation for registering and managing Figma webhooks for real-time file change notifications.
   https://www.figma.com/developers/api#webhooks

7. **Dart `archive` package** -- Dart library for reading and writing ZIP archives, used for .sketch and .xd file handling.
   https://pub.dev/packages/archive

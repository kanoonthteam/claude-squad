---
name: gltf-format
description: glTF 2.0 specification covering JSON structure, binary buffers, accessors, buffer views, mesh primitives, vertex attributes, index buffers, base64 embedded buffers, GLB binary container format, PBR materials, texture mapping, node hierarchy, transforms, extensions (KHR_draco_mesh_compression, KHR_materials_unlit), programmatic construction with Python, validation with glTF-Validator, and round-trip serialization
---

# glTF 2.0 Format & Binary Buffer Engineering

Comprehensive guide for a 3D/CAD engineer working with the glTF 2.0 specification. Covers the complete JSON structure, binary data layout, mesh primitives, vertex attributes, index buffers, base64 data URIs, GLB binary containers, PBR materials, textures, node transforms, extensions, programmatic construction in Python, validation, and round-trip serialization.

## Table of Contents

1. [glTF 2.0 JSON Structure Overview](#gltf-20-json-structure-overview)
2. [Scenes and Nodes](#scenes-and-nodes)
3. [Node Hierarchy and Transforms](#node-hierarchy-and-transforms)
4. [Meshes and Mesh Primitives](#meshes-and-mesh-primitives)
5. [Vertex Attributes](#vertex-attributes)
6. [Buffers, Buffer Views, and Accessors](#buffers-buffer-views-and-accessors)
7. [Buffer and BufferView Layout](#buffer-and-bufferview-layout)
8. [Index Buffers](#index-buffers)
9. [Component Types and Data Alignment](#component-types-and-data-alignment)
10. [Base64 Data URIs for Embedded Buffers](#base64-data-uris-for-embedded-buffers)
11. [GLB Binary Container Format](#glb-binary-container-format)
12. [Materials and PBR Metallic-Roughness](#materials-and-pbr-metallic-roughness)
13. [Texture Mapping and Image Embedding](#texture-mapping-and-image-embedding)
14. [glTF Extensions](#gltf-extensions)
15. [Programmatic glTF Construction in Python](#programmatic-gltf-construction-in-python)
16. [Building a Complete Triangle from Scratch](#building-a-complete-triangle-from-scratch)
17. [Constructing Indexed Geometry with Normals and UVs](#constructing-indexed-geometry-with-normals-and-uvs)
18. [Validation with glTF-Validator](#validation-with-gltf-validator)
19. [Round-Trip Serialization and Verification](#round-trip-serialization-and-verification)
20. [Best Practices](#best-practices)
21. [Anti-Patterns](#anti-patterns)
22. [Sources & References](#sources--references)

---

## glTF 2.0 JSON Structure Overview

glTF (GL Transmission Format) 2.0 is a royalty-free specification published by the Khronos Group for the efficient transmission and loading of 3D scenes and models. A glTF asset consists of a JSON file describing the scene graph structure and references to binary data for geometry, animations, and textures.

The top-level JSON object contains the following primary properties:

- **asset** (required): Metadata including the glTF version (must be `"2.0"`), generator name, and copyright.
- **scene**: Index of the default scene to display.
- **scenes**: Array of scene objects, each containing an array of root node indices.
- **nodes**: Array of node objects forming the scene graph hierarchy.
- **meshes**: Array of mesh objects, each containing one or more primitives.
- **accessors**: Array of accessor objects that define typed views into buffer data.
- **bufferViews**: Array of bufferView objects that define byte ranges within buffers.
- **buffers**: Array of buffer objects pointing to raw binary data.
- **materials**: Array of material objects defining surface appearance.
- **textures**: Array of texture objects referencing images and samplers.
- **images**: Array of image objects (URI or bufferView references).
- **samplers**: Array of sampler objects defining texture filtering and wrapping.
- **animations**: Array of animation objects with channels and samplers.
- **skins**: Array of skin objects for skeletal animation.
- **cameras**: Array of camera objects (perspective or orthographic).
- **extensions**: Object containing extension data.
- **extensionsUsed**: Array of extension names used in the asset.
- **extensionsRequired**: Array of extension names required to load the asset.

The minimal valid glTF file requires only the `asset` property with the version string:

```json
{
  "asset": {
    "version": "2.0",
    "generator": "custom-exporter-1.0"
  }
}
```

Every index-based reference in glTF uses zero-based integer indices into the corresponding top-level array. For example, a node's `mesh` property is an index into the `meshes` array, and an accessor's `bufferView` property is an index into the `bufferViews` array.

---

## Scenes and Nodes

A **scene** defines a set of root nodes that form the visible content. The `scenes` array can contain multiple scenes, and the top-level `scene` property selects the default one.

Each scene object has:
- **nodes**: An array of indices into the top-level `nodes` array, representing the root nodes of the scene.
- **name** (optional): A human-readable name.

```json
{
  "scene": 0,
  "scenes": [
    {
      "name": "MainScene",
      "nodes": [0, 1]
    }
  ],
  "nodes": [
    {
      "name": "MeshNode",
      "mesh": 0
    },
    {
      "name": "CameraNode",
      "camera": 0,
      "translation": [0.0, 1.5, 5.0]
    }
  ]
}
```

Nodes that are not referenced by any scene or by any other node's `children` array are considered orphan nodes. While technically valid, orphan nodes are typically unintentional and should be avoided.

---

## Node Hierarchy and Transforms

Nodes form a directed acyclic graph (DAG) through the `children` property. Each node can optionally define a local transform using either:

1. **TRS decomposition** (translation, rotation, scale): Three separate properties.
2. **Matrix**: A single 4x4 column-major transformation matrix.

TRS properties:
- **translation**: `[x, y, z]` -- defaults to `[0, 0, 0]`.
- **rotation**: `[x, y, z, w]` quaternion -- defaults to `[0, 0, 0, 1]` (identity).
- **scale**: `[x, y, z]` -- defaults to `[1, 1, 1]`.

Matrix property:
- **matrix**: 16-element array in column-major order -- defaults to the 4x4 identity matrix.

TRS and matrix are mutually exclusive. If both are present, the behavior is undefined. The specification recommends using TRS for animatable transforms and matrix for static baked transforms.

The global transform of a node is computed by multiplying the transforms along the path from the scene root to the node:

```
globalTransform = parentGlobalTransform * localTransform
```

For TRS, the local transform matrix is computed as:

```
M = T * R * S
```

Where T is the translation matrix, R is the rotation matrix from the quaternion, and S is the scale matrix. The rotation quaternion must be normalized (unit length).

Example node hierarchy:

```json
{
  "nodes": [
    {
      "name": "Root",
      "children": [1, 2],
      "translation": [0.0, 0.0, 0.0]
    },
    {
      "name": "LeftArm",
      "mesh": 0,
      "translation": [-1.0, 0.0, 0.0],
      "rotation": [0.0, 0.0, 0.3826834, 0.9238795],
      "scale": [1.0, 1.0, 1.0]
    },
    {
      "name": "RightArm",
      "mesh": 0,
      "translation": [1.0, 0.0, 0.0],
      "rotation": [0.0, 0.0, -0.3826834, 0.9238795],
      "scale": [1.0, 1.0, 1.0]
    }
  ]
}
```

Circular references in the node hierarchy are forbidden. A node must not be a descendant of itself. Each node can only have one parent; sharing a child across multiple parents is not allowed.

---

## Meshes and Mesh Primitives

A **mesh** contains one or more **primitives**, each representing a drawable unit of geometry. Each primitive defines:

- **attributes** (required): An object mapping attribute semantic names to accessor indices.
- **indices** (optional): An accessor index for the index buffer. If absent, non-indexed drawing is used.
- **material** (optional): An index into the `materials` array.
- **mode** (optional): The rendering primitive topology. Defaults to `4` (TRIANGLES).

Primitive mode values:
| Value | Topology |
|-------|----------|
| 0 | POINTS |
| 1 | LINES |
| 2 | LINE_LOOP |
| 3 | LINE_STRIP |
| 4 | TRIANGLES |
| 5 | TRIANGLE_STRIP |
| 6 | TRIANGLE_FAN |

A mesh with multiple primitives allows different materials on different parts of the same logical object. Each primitive is drawn independently.

```json
{
  "meshes": [
    {
      "name": "CubeWithTwoMaterials",
      "primitives": [
        {
          "attributes": {
            "POSITION": 0,
            "NORMAL": 1,
            "TEXCOORD_0": 2
          },
          "indices": 3,
          "material": 0,
          "mode": 4
        },
        {
          "attributes": {
            "POSITION": 4,
            "NORMAL": 5,
            "TEXCOORD_0": 6
          },
          "indices": 7,
          "material": 1,
          "mode": 4
        }
      ]
    }
  ]
}
```

---

## Vertex Attributes

glTF defines a set of standard attribute semantics. Each attribute name maps to an accessor that describes the data type, count, and location in the buffer.

Standard attribute semantics:

| Attribute | Accessor Type | Component Type | Description |
|-----------|--------------|----------------|-------------|
| POSITION | VEC3 | FLOAT (5126) | Vertex positions in local space |
| NORMAL | VEC3 | FLOAT (5126) | Vertex normals (unit length) |
| TANGENT | VEC4 | FLOAT (5126) | Tangent vectors (w = handedness, +1 or -1) |
| TEXCOORD_0 | VEC2 | FLOAT (5126) or normalized UNSIGNED_BYTE/UNSIGNED_SHORT | First UV set |
| TEXCOORD_1 | VEC2 | FLOAT (5126) or normalized UNSIGNED_BYTE/UNSIGNED_SHORT | Second UV set |
| COLOR_0 | VEC3 or VEC4 | FLOAT or normalized UNSIGNED_BYTE/UNSIGNED_SHORT | Vertex colors |
| JOINTS_0 | VEC4 | UNSIGNED_BYTE (5121) or UNSIGNED_SHORT (5123) | Joint indices for skinning |
| WEIGHTS_0 | VEC4 | FLOAT (5126) or normalized UNSIGNED_BYTE/UNSIGNED_SHORT | Joint weights for skinning |

The POSITION accessor must include `min` and `max` properties defining the axis-aligned bounding box. This is required by the specification and used by loaders for culling and bounding volume computation.

All attributes within a single primitive must have the same `count` (number of vertices). If NORMAL is not provided, the loader may compute flat normals from the face geometry. If TANGENT is not provided but a normal map texture is assigned, the loader may compute tangents using the MikkTSpace algorithm.

Custom attributes use the `_` prefix convention (e.g., `_CUSTOM_ATTR`).

---

## Buffers, Buffer Views, and Accessors

The three-level data architecture of glTF separates raw binary storage from typed interpretation:

### Buffers

A **buffer** represents a contiguous block of raw binary data. It has:
- **uri** (optional): A URI pointing to the binary data. Can be a relative file path, an absolute URL, or a base64 data URI. Omitted when the buffer is stored in a GLB binary chunk.
- **byteLength** (required): The total size of the buffer in bytes.
- **name** (optional): Human-readable name.

### Buffer Views

A **bufferView** defines a byte-level slice of a buffer. It has:
- **buffer** (required): Index of the parent buffer.
- **byteOffset** (optional): Byte offset from the start of the buffer. Defaults to 0.
- **byteLength** (required): Length of the view in bytes.
- **byteStride** (optional): Stride in bytes between consecutive elements. Only used for vertex attribute data (not indices). Must be in the range [4, 252] and a multiple of 4.
- **target** (optional): Intended GPU buffer binding target.
  - `34962` = ARRAY_BUFFER (vertex attributes)
  - `34963` = ELEMENT_ARRAY_BUFFER (indices)

### Accessors

An **accessor** provides a typed view into a bufferView. It has:
- **bufferView** (optional): Index of the bufferView. Can be omitted for zero-initialized data.
- **byteOffset** (optional): Additional byte offset relative to the bufferView's offset. Defaults to 0.
- **componentType** (required): The data type of each component.
- **type** (required): The element type (`"SCALAR"`, `"VEC2"`, `"VEC3"`, `"VEC4"`, `"MAT2"`, `"MAT3"`, `"MAT4"`).
- **count** (required): The number of elements.
- **normalized** (optional): Whether integer data should be normalized to [0, 1] or [-1, 1].
- **min** / **max** (optional): Per-component minimum and maximum values.
- **sparse** (optional): Sparse storage for mostly-zero or mostly-default data.

Component type values:

| Value | Type | Size (bytes) |
|-------|------|-------------|
| 5120 | BYTE | 1 |
| 5121 | UNSIGNED_BYTE | 1 |
| 5122 | SHORT | 2 |
| 5123 | UNSIGNED_SHORT | 2 |
| 5125 | UNSIGNED_INT | 4 |
| 5126 | FLOAT | 4 |

---

## Buffer and BufferView Layout

Understanding byte-level layout is critical for correct glTF construction. The total byte offset of an element in a buffer is:

```
elementOffset = buffer.byteOffset (implicit 0)
              + bufferView.byteOffset
              + accessor.byteOffset
              + (elementIndex * effectiveStride)
```

Where `effectiveStride` is either:
- The `byteStride` specified on the bufferView (interleaved vertex data), or
- The natural size of the accessor element type (tightly packed data).

Natural element sizes:
- SCALAR: `componentSize * 1`
- VEC2: `componentSize * 2`
- VEC3: `componentSize * 3`
- VEC4: `componentSize * 4`
- MAT4: `componentSize * 16`

Alignment rules:
- The `byteOffset` of an accessor must be a multiple of the component type's size. For example, a FLOAT accessor must have a `byteOffset` that is a multiple of 4.
- The `byteOffset` of a bufferView for vertex data should typically be a multiple of 4 for best GPU performance.
- For interleaved buffers, `byteStride` must be a multiple of 4 and large enough to contain one complete element plus any padding.

Example layout for a mesh with 3 vertices (positions + normals interleaved):

```
Buffer layout (72 bytes total):
Offset  0: Pos0.x (float)  Pos0.y (float)  Pos0.z (float)
Offset 12: Norm0.x (float) Norm0.y (float) Norm0.z (float)
Offset 24: Pos1.x (float)  Pos1.y (float)  Pos1.z (float)
Offset 36: Norm1.x (float) Norm1.y (float) Norm1.z (float)
Offset 48: Pos2.x (float)  Pos2.y (float)  Pos2.z (float)
Offset 60: Norm2.x (float) Norm2.y (float) Norm2.z (float)
```

The corresponding bufferView uses `byteStride: 24` (12 bytes position + 12 bytes normal). The POSITION accessor has `byteOffset: 0` and the NORMAL accessor has `byteOffset: 12`, both referencing the same bufferView.

Alternatively, with tightly packed (non-interleaved) layout, each attribute gets its own bufferView with no stride:

```
Buffer layout (72 bytes total):
Offset  0: Pos0.x Pos0.y Pos0.z Pos1.x Pos1.y Pos1.z Pos2.x Pos2.y Pos2.z  (36 bytes)
Offset 36: Norm0.x Norm0.y Norm0.z Norm1.x Norm1.y Norm1.z Norm2.x Norm2.y Norm2.z  (36 bytes)
```

---

## Index Buffers

Index buffers allow vertex reuse across multiple triangles. Without indices, every triangle requires 3 unique vertices, even when triangles share vertices. An index buffer stores integer indices into the vertex arrays.

Index buffer rules:
- The accessor's `componentType` must be `UNSIGNED_BYTE` (5121), `UNSIGNED_SHORT` (5123), or `UNSIGNED_INT` (5125).
- The accessor's `type` must be `"SCALAR"`.
- The bufferView's `target` should be `34963` (ELEMENT_ARRAY_BUFFER).
- The bufferView for indices must not have a `byteStride` property.
- Index values must be less than the `count` of the vertex attribute accessors.

For TRIANGLES mode, the index count must be a multiple of 3. Each consecutive triple of indices defines one triangle.

Example: a quad (two triangles sharing an edge) with 4 vertices and 6 indices:

```
Vertices: v0, v1, v2, v3
Indices:  [0, 1, 2, 2, 3, 0]

Triangle 1: v0, v1, v2
Triangle 2: v2, v3, v0
```

Choosing the right index type depends on vertex count:
- Up to 255 vertices: UNSIGNED_BYTE (1 byte per index)
- Up to 65535 vertices: UNSIGNED_SHORT (2 bytes per index) -- most common
- Up to 4294967295 vertices: UNSIGNED_INT (4 bytes per index) -- requires checking renderer support

---

## Component Types and Data Alignment

Proper data alignment is essential for GPU compatibility and specification compliance. Key alignment constraints:

1. **Accessor byteOffset alignment**: Must be a multiple of the component type size.
   - BYTE / UNSIGNED_BYTE: 1-byte alignment
   - SHORT / UNSIGNED_SHORT: 2-byte alignment
   - UNSIGNED_INT / FLOAT: 4-byte alignment

2. **BufferView byteOffset alignment**: While not strictly required by the spec for all cases, aligning to 4 bytes is strongly recommended for performance. GLB binary chunks require 4-byte alignment.

3. **BufferView byteStride alignment**: Must be a multiple of 4 when specified.

4. **Buffer total size**: In GLB format, the binary chunk must be padded to a multiple of 4 bytes using zero bytes (0x00).

When packing multiple accessors into a single buffer, padding bytes may be needed between data blocks to satisfy alignment requirements. For example, after a block of UNSIGNED_SHORT index data (2-byte aligned), you may need 2 padding bytes before a FLOAT attribute block (4-byte aligned).

---

## Base64 Data URIs for Embedded Buffers

For self-contained glTF files (`.gltf` with no external binary files), buffer data can be embedded directly in the JSON using base64-encoded data URIs.

The data URI format is:

```
data:application/octet-stream;base64,<base64-encoded-data>
```

The MIME type `application/octet-stream` is used for generic binary data. For images embedded as buffer data, the image object references a bufferView, and the image's `mimeType` property specifies the actual format.

For image URIs embedded directly (not via bufferView), use the appropriate MIME type:

```
data:image/png;base64,<base64-encoded-png>
data:image/jpeg;base64,<base64-encoded-jpeg>
```

Example buffer with base64-embedded data for a single triangle (3 vertices, 36 bytes of position data):

```json
{
  "buffers": [
    {
      "uri": "data:application/octet-stream;base64,AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA",
      "byteLength": 36
    }
  ]
}
```

The base64-encoded data above represents 9 floats (3 vec3 positions):
- Vertex 0: (0.0, 0.0, 0.0)
- Vertex 1: (1.0, 0.0, 0.0)
- Vertex 2: (0.0, 1.0, 0.0)

Considerations for base64 embedding:
- Base64 encoding increases data size by approximately 33%.
- Suitable for small assets, prototyping, and single-file distribution.
- For production assets larger than a few kilobytes, use external `.bin` files or GLB format.
- The base64 string must not contain line breaks or whitespace.

---

## GLB Binary Container Format

GLB is the binary container format for glTF that packages the JSON and binary data into a single file. It is more efficient than base64-embedded glTF because it avoids the 33% size overhead of base64 encoding and allows memory-mapped access to binary data.

### GLB File Structure

A GLB file consists of a 12-byte header followed by one or more chunks:

**Header (12 bytes):**
| Offset | Size | Field | Value |
|--------|------|-------|-------|
| 0 | 4 bytes | magic | `0x46546C67` ("glTF" in ASCII) |
| 4 | 4 bytes | version | `2` (uint32, little-endian) |
| 8 | 4 bytes | length | Total file size in bytes (uint32, little-endian) |

**Chunk structure (8-byte header + data):**
| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 bytes | chunkLength | Length of chunkData in bytes (uint32, little-endian) |
| 4 | 4 bytes | chunkType | Chunk type identifier |
| 8 | chunkLength | chunkData | The chunk payload |

**Chunk types:**
- `0x4E4F534A` ("JSON"): The JSON chunk. Must be the first chunk. Padded with space characters (0x20) to a 4-byte boundary.
- `0x004E4942` ("BIN\0"): The binary chunk. Optional. If present, must be the second chunk. Padded with zero bytes (0x00) to a 4-byte boundary.

In a GLB file, the first buffer (index 0) must not have a `uri` property. Its data is implicitly the content of the BIN chunk. Additional buffers (index 1+) can still use URIs for external data, though this is uncommon.

### GLB Byte Layout Example

```
Bytes 0-3:   67 6C 54 46   (magic: "glTF")
Bytes 4-7:   02 00 00 00   (version: 2)
Bytes 8-11:  XX XX XX XX   (total file length)
Bytes 12-15: YY YY YY YY   (JSON chunk length)
Bytes 16-19: 4A 53 4F 4E   (chunk type: "JSON")
Bytes 20-??: JSON data, padded with 0x20 to 4-byte boundary
Next 4:      ZZ ZZ ZZ ZZ   (BIN chunk length)
Next 4:      42 49 4E 00   (chunk type: "BIN\0")
Remaining:   Binary data, padded with 0x00 to 4-byte boundary
```

---

## Materials and PBR Metallic-Roughness

glTF 2.0 uses a physically-based rendering (PBR) material model. The default and primary model is **metallic-roughness**, defined in the `pbrMetallicRoughness` property of a material.

Material properties:

- **pbrMetallicRoughness**: The metallic-roughness material model.
  - **baseColorFactor**: RGBA color factor `[r, g, b, a]`, default `[1, 1, 1, 1]`. Multiplied with baseColorTexture.
  - **baseColorTexture**: Texture info object for the base color map.
  - **metallicFactor**: Metallic factor `[0, 1]`, default `1.0`.
  - **roughnessFactor**: Roughness factor `[0, 1]`, default `1.0`.
  - **metallicRoughnessTexture**: Texture where blue channel = metallic, green channel = roughness.
- **normalTexture**: Normal map texture with optional `scale` factor.
- **occlusionTexture**: Ambient occlusion map with optional `strength` factor. Red channel stores AO.
- **emissiveTexture**: Emissive map texture.
- **emissiveFactor**: RGB emissive color factor `[r, g, b]`, default `[0, 0, 0]`.
- **alphaMode**: `"OPAQUE"` (default), `"MASK"`, or `"BLEND"`.
- **alphaCutoff**: Threshold for MASK mode, default `0.5`.
- **doubleSided**: Whether the material is double-sided, default `false`.

Example material with textures:

```json
{
  "materials": [
    {
      "name": "MetalFloor",
      "pbrMetallicRoughness": {
        "baseColorFactor": [1.0, 1.0, 1.0, 1.0],
        "baseColorTexture": {
          "index": 0,
          "texCoord": 0
        },
        "metallicFactor": 1.0,
        "roughnessFactor": 0.4,
        "metallicRoughnessTexture": {
          "index": 1,
          "texCoord": 0
        }
      },
      "normalTexture": {
        "index": 2,
        "texCoord": 0,
        "scale": 1.0
      },
      "occlusionTexture": {
        "index": 3,
        "texCoord": 0,
        "strength": 1.0
      },
      "emissiveFactor": [0.0, 0.0, 0.0],
      "alphaMode": "OPAQUE",
      "doubleSided": false
    }
  ]
}
```

For non-metallic materials (dielectrics like wood, plastic, fabric), set `metallicFactor` to 0.0. For pure metals (gold, steel, aluminum), set `metallicFactor` to 1.0. Values between 0 and 1 are physically implausible but technically allowed.

---

## Texture Mapping and Image Embedding

Textures in glTF are defined through three interrelated objects:

### Textures

A **texture** references a source image and a sampler:
- **source**: Index into the `images` array.
- **sampler**: Index into the `samplers` array. If omitted, a default sampler with repeat wrapping and auto-filtering is used.

### Samplers

A **sampler** defines texture filtering and wrapping:
- **magFilter**: Magnification filter (`9728` = NEAREST, `9729` = LINEAR).
- **minFilter**: Minification filter (`9728`, `9729`, `9984`-`9987` for mipmap variants).
- **wrapS**: Horizontal wrap mode (`33071` = CLAMP_TO_EDGE, `33648` = MIRRORED_REPEAT, `10497` = REPEAT).
- **wrapT**: Vertical wrap mode (same values as wrapS).

### Images

An **image** can be provided in two ways:

1. **External URI**: A relative path or absolute URL to a PNG or JPEG file.
2. **Embedded via bufferView**: The image data is stored in a buffer and referenced by a bufferView index and `mimeType`.

```json
{
  "images": [
    {
      "uri": "textures/basecolor.png",
      "name": "BaseColor"
    },
    {
      "bufferView": 5,
      "mimeType": "image/png",
      "name": "NormalMap"
    },
    {
      "uri": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==",
      "name": "WhitePixel"
    }
  ],
  "samplers": [
    {
      "magFilter": 9729,
      "minFilter": 9987,
      "wrapS": 10497,
      "wrapT": 10497
    }
  ],
  "textures": [
    {
      "source": 0,
      "sampler": 0
    },
    {
      "source": 1,
      "sampler": 0
    }
  ]
}
```

The `texCoord` property on a texture info object specifies which UV set to use (`0` for `TEXCOORD_0`, `1` for `TEXCOORD_1`, etc.). Texture coordinates in glTF follow the OpenGL convention: the origin (0, 0) is at the bottom-left of the image, and (1, 1) is at the top-right. However, note that PNG and JPEG images store pixels top-to-bottom, so loaders must flip the V coordinate or adjust the image data.

Only PNG and JPEG formats are supported in the core specification. Other formats (WebP, KTX2) are available through extensions.

---

## glTF Extensions

Extensions add optional capabilities to glTF. They are declared in `extensionsUsed` (informational) and `extensionsRequired` (mandatory for loading).

### KHR_draco_mesh_compression

Draco compression dramatically reduces mesh geometry size (often 10-20x smaller). When this extension is used, the mesh primitive's geometry data is stored in a compressed Draco buffer instead of raw binary.

The extension replaces the standard accessor-based geometry pipeline. A Draco-compressed primitive contains:
- **bufferView**: Index of the bufferView containing the compressed Draco data.
- **attributes**: A mapping from attribute semantics to Draco attribute IDs (not glTF accessor indices).

```json
{
  "meshes": [
    {
      "primitives": [
        {
          "attributes": {
            "POSITION": 0,
            "NORMAL": 1
          },
          "indices": 2,
          "extensions": {
            "KHR_draco_mesh_compression": {
              "bufferView": 3,
              "attributes": {
                "POSITION": 0,
                "NORMAL": 1
              }
            }
          }
        }
      ]
    }
  ],
  "extensionsUsed": ["KHR_draco_mesh_compression"],
  "extensionsRequired": ["KHR_draco_mesh_compression"]
}
```

The standard `attributes` and `indices` accessors on the primitive are still present as fallback metadata (providing count, type, min/max). Loaders that support Draco decode from the extension data; loaders that do not support Draco and the extension is not in `extensionsRequired` can fall back to the standard accessors (if populated with uncompressed data).

### KHR_materials_unlit

This extension defines a simple unlit material that ignores lighting calculations. Useful for pre-baked lighting, stylized rendering, or performance-critical applications.

When applied, only the `baseColorFactor` and `baseColorTexture` from `pbrMetallicRoughness` are used. All other PBR properties, normal maps, and occlusion maps are ignored by compliant renderers.

```json
{
  "materials": [
    {
      "name": "UnlitMaterial",
      "pbrMetallicRoughness": {
        "baseColorFactor": [0.8, 0.2, 0.1, 1.0],
        "baseColorTexture": {
          "index": 0
        }
      },
      "extensions": {
        "KHR_materials_unlit": {}
      }
    }
  ],
  "extensionsUsed": ["KHR_materials_unlit"]
}
```

### Other Notable Extensions

- **KHR_texture_basisu**: Adds support for KTX2/Basis Universal compressed textures.
- **KHR_materials_transmission**: Models thin and volumetric transmissive materials (glass).
- **KHR_materials_clearcoat**: Adds a clearcoat layer for automotive paint, lacquered wood.
- **KHR_mesh_quantization**: Allows quantized (integer) vertex attributes for smaller file sizes.
- **EXT_meshopt_compression**: An alternative mesh compression using meshoptimizer.
- **KHR_lights_punctual**: Adds point, spot, and directional lights to the scene.

---

## Programmatic glTF Construction in Python

Building glTF assets programmatically requires constructing the JSON structure and the binary buffer data in lockstep. The following example demonstrates building a minimal glTF from scratch using only Python standard library modules.

```python
import struct
import json
import base64


def build_triangle_gltf() -> dict:
    """Build a minimal glTF 2.0 asset with a single triangle."""

    # Define 3 vertex positions (vec3 float)
    positions = [
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
    ]

    # Pack positions into binary (little-endian floats)
    position_data = b""
    for x, y, z in positions:
        position_data += struct.pack("<3f", x, y, z)

    # Compute bounding box for POSITION accessor (required by spec)
    xs = [p[0] for p in positions]
    ys = [p[1] for p in positions]
    zs = [p[2] for p in positions]

    # Encode buffer as base64 data URI
    buffer_bytes = position_data
    buffer_b64 = base64.b64encode(buffer_bytes).decode("ascii")
    buffer_uri = f"data:application/octet-stream;base64,{buffer_b64}"

    gltf = {
        "asset": {"version": "2.0", "generator": "python-gltf-builder"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [
            {
                "primitives": [
                    {
                        "attributes": {"POSITION": 0},
                        "mode": 4,
                    }
                ]
            }
        ],
        "accessors": [
            {
                "bufferView": 0,
                "byteOffset": 0,
                "componentType": 5126,  # FLOAT
                "count": 3,
                "type": "VEC3",
                "min": [min(xs), min(ys), min(zs)],
                "max": [max(xs), max(ys), max(zs)],
            }
        ],
        "bufferViews": [
            {
                "buffer": 0,
                "byteOffset": 0,
                "byteLength": len(position_data),
                "target": 34962,  # ARRAY_BUFFER
            }
        ],
        "buffers": [
            {
                "uri": buffer_uri,
                "byteLength": len(buffer_bytes),
            }
        ],
    }

    return gltf


if __name__ == "__main__":
    gltf = build_triangle_gltf()
    with open("triangle.gltf", "w") as f:
        json.dump(gltf, f, indent=2)
    print(f"Wrote triangle.gltf ({len(json.dumps(gltf))} bytes JSON)")
```

---

## Building a Complete Triangle from Scratch

The following example shows every step of constructing a complete glTF file with a colored, indexed triangle including normals and vertex colors, written as both `.gltf` (with base64) and `.glb` (binary).

```python
import struct
import json
import base64
from pathlib import Path


def build_colored_triangle():
    """Build a triangle with positions, normals, colors, and indices."""

    # Vertex data
    positions = [
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.5, 1.0, 0.0),
    ]
    normals = [
        (0.0, 0.0, 1.0),
        (0.0, 0.0, 1.0),
        (0.0, 0.0, 1.0),
    ]
    colors = [
        (1.0, 0.0, 0.0, 1.0),  # Red
        (0.0, 1.0, 0.0, 1.0),  # Green
        (0.0, 0.0, 1.0, 1.0),  # Blue
    ]
    indices = [0, 1, 2]

    # Pack binary data
    pos_data = b"".join(struct.pack("<3f", *p) for p in positions)    # 36 bytes
    norm_data = b"".join(struct.pack("<3f", *n) for n in normals)     # 36 bytes
    color_data = b"".join(struct.pack("<4f", *c) for c in colors)     # 48 bytes
    index_data = struct.pack(f"<{len(indices)}H", *indices)           # 6 bytes

    # Pad index data to 4-byte alignment
    index_padding = (4 - len(index_data) % 4) % 4
    index_data_padded = index_data + b"\x00" * index_padding

    # Concatenate all data blocks
    buffer_data = index_data_padded + pos_data + norm_data + color_data

    # Calculate byte offsets
    idx_offset = 0
    pos_offset = len(index_data_padded)
    norm_offset = pos_offset + len(pos_data)
    color_offset = norm_offset + len(norm_data)

    # Compute POSITION bounding box
    pos_min = [min(p[i] for p in positions) for i in range(3)]
    pos_max = [max(p[i] for p in positions) for i in range(3)]

    gltf = {
        "asset": {"version": "2.0", "generator": "python-gltf-builder"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": "ColorTriangle"}],
        "meshes": [
            {
                "name": "TriangleMesh",
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": 1,
                            "NORMAL": 2,
                            "COLOR_0": 3,
                        },
                        "indices": 0,
                        "mode": 4,
                    }
                ],
            }
        ],
        "accessors": [
            {  # 0: indices
                "bufferView": 0,
                "componentType": 5123,  # UNSIGNED_SHORT
                "count": 3,
                "type": "SCALAR",
                "max": [2],
                "min": [0],
            },
            {  # 1: positions
                "bufferView": 1,
                "componentType": 5126,  # FLOAT
                "count": 3,
                "type": "VEC3",
                "min": pos_min,
                "max": pos_max,
            },
            {  # 2: normals
                "bufferView": 2,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
            },
            {  # 3: colors
                "bufferView": 3,
                "componentType": 5126,
                "count": 3,
                "type": "VEC4",
            },
        ],
        "bufferViews": [
            {  # 0: indices
                "buffer": 0,
                "byteOffset": idx_offset,
                "byteLength": len(index_data),
                "target": 34963,  # ELEMENT_ARRAY_BUFFER
            },
            {  # 1: positions
                "buffer": 0,
                "byteOffset": pos_offset,
                "byteLength": len(pos_data),
                "target": 34962,  # ARRAY_BUFFER
            },
            {  # 2: normals
                "buffer": 0,
                "byteOffset": norm_offset,
                "byteLength": len(norm_data),
                "target": 34962,
            },
            {  # 3: colors
                "buffer": 0,
                "byteOffset": color_offset,
                "byteLength": len(color_data),
                "target": 34962,
            },
        ],
        "buffers": [
            {"byteLength": len(buffer_data)}
        ],
    }

    return gltf, buffer_data


def write_gltf_embedded(gltf: dict, buffer_data: bytes, path: str):
    """Write a .gltf file with base64-embedded buffer."""
    b64 = base64.b64encode(buffer_data).decode("ascii")
    gltf["buffers"][0]["uri"] = f"data:application/octet-stream;base64,{b64}"
    with open(path, "w") as f:
        json.dump(gltf, f, indent=2)


def write_glb(gltf: dict, buffer_data: bytes, path: str):
    """Write a .glb binary container file."""
    # Ensure buffer has no URI for GLB
    gltf_copy = json.loads(json.dumps(gltf))
    gltf_copy["buffers"][0].pop("uri", None)

    # Encode JSON chunk
    json_bytes = json.dumps(gltf_copy, separators=(",", ":")).encode("utf-8")
    # Pad JSON to 4-byte boundary with spaces
    json_padding = (4 - len(json_bytes) % 4) % 4
    json_bytes += b" " * json_padding

    # Pad BIN to 4-byte boundary with zeros
    bin_padding = (4 - len(buffer_data) % 4) % 4
    bin_data = buffer_data + b"\x00" * bin_padding

    # GLB header
    total_length = 12 + 8 + len(json_bytes) + 8 + len(bin_data)
    header = struct.pack("<III", 0x46546C67, 2, total_length)

    # JSON chunk header
    json_chunk_header = struct.pack("<II", len(json_bytes), 0x4E4F534A)

    # BIN chunk header
    bin_chunk_header = struct.pack("<II", len(bin_data), 0x004E4942)

    with open(path, "wb") as f:
        f.write(header)
        f.write(json_chunk_header)
        f.write(json_bytes)
        f.write(bin_chunk_header)
        f.write(bin_data)


if __name__ == "__main__":
    gltf, buffer_data = build_colored_triangle()
    write_gltf_embedded(gltf, buffer_data, "triangle.gltf")
    write_glb(gltf, buffer_data, "triangle.glb")
    print("Wrote triangle.gltf and triangle.glb")
```

---

## Constructing Indexed Geometry with Normals and UVs

When building production-quality meshes, you typically need positions, normals, texture coordinates, and an index buffer. The following example constructs a textured quad (two triangles) with full vertex attributes.

```python
import struct
import json
import base64
import math


def build_textured_quad():
    """Build a textured quad with positions, normals, UVs, and indices."""

    # Quad vertices (4 unique vertices, 2 triangles via index buffer)
    positions = [
        (-0.5, -0.5, 0.0),  # bottom-left
        ( 0.5, -0.5, 0.0),  # bottom-right
        ( 0.5,  0.5, 0.0),  # top-right
        (-0.5,  0.5, 0.0),  # top-left
    ]
    normals = [(0.0, 0.0, 1.0)] * 4  # All facing +Z
    texcoords = [
        (0.0, 0.0),  # bottom-left
        (1.0, 0.0),  # bottom-right
        (1.0, 1.0),  # top-right
        (0.0, 1.0),  # top-left
    ]
    indices = [
        0, 1, 2,  # First triangle
        0, 2, 3,  # Second triangle
    ]

    # Pack binary data
    pos_bytes = b"".join(struct.pack("<3f", *p) for p in positions)      # 48 bytes
    norm_bytes = b"".join(struct.pack("<3f", *n) for n in normals)       # 48 bytes
    uv_bytes = b"".join(struct.pack("<2f", *t) for t in texcoords)       # 32 bytes
    idx_bytes = struct.pack(f"<{len(indices)}H", *indices)               # 12 bytes

    # Pad index data to 4-byte alignment
    idx_pad = (4 - len(idx_bytes) % 4) % 4
    idx_bytes_padded = idx_bytes + b"\x00" * idx_pad

    # Build buffer: indices first, then vertex attributes
    buffer = idx_bytes_padded + pos_bytes + norm_bytes + uv_bytes
    total_len = len(buffer)

    # Offsets
    idx_off = 0
    pos_off = len(idx_bytes_padded)
    norm_off = pos_off + len(pos_bytes)
    uv_off = norm_off + len(norm_bytes)

    # Bounding box
    pos_min = [min(p[i] for p in positions) for i in range(3)]
    pos_max = [max(p[i] for p in positions) for i in range(3)]

    b64 = base64.b64encode(buffer).decode("ascii")

    gltf = {
        "asset": {"version": "2.0", "generator": "python-quad-builder"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": "TexturedQuad"}],
        "meshes": [
            {
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": 1,
                            "NORMAL": 2,
                            "TEXCOORD_0": 3,
                        },
                        "indices": 0,
                        "material": 0,
                        "mode": 4,
                    }
                ]
            }
        ],
        "materials": [
            {
                "name": "QuadMaterial",
                "pbrMetallicRoughness": {
                    "baseColorFactor": [0.8, 0.8, 0.8, 1.0],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.8,
                },
                "doubleSided": True,
            }
        ],
        "accessors": [
            {  # 0: indices
                "bufferView": 0,
                "componentType": 5123,
                "count": len(indices),
                "type": "SCALAR",
                "min": [min(indices)],
                "max": [max(indices)],
            },
            {  # 1: positions
                "bufferView": 1,
                "componentType": 5126,
                "count": len(positions),
                "type": "VEC3",
                "min": pos_min,
                "max": pos_max,
            },
            {  # 2: normals
                "bufferView": 2,
                "componentType": 5126,
                "count": len(normals),
                "type": "VEC3",
            },
            {  # 3: texcoords
                "bufferView": 3,
                "componentType": 5126,
                "count": len(texcoords),
                "type": "VEC2",
            },
        ],
        "bufferViews": [
            {"buffer": 0, "byteOffset": idx_off, "byteLength": len(idx_bytes), "target": 34963},
            {"buffer": 0, "byteOffset": pos_off, "byteLength": len(pos_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": norm_off, "byteLength": len(norm_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": uv_off, "byteLength": len(uv_bytes), "target": 34962},
        ],
        "buffers": [
            {
                "uri": f"data:application/octet-stream;base64,{b64}",
                "byteLength": total_len,
            }
        ],
    }

    return gltf


if __name__ == "__main__":
    gltf = build_textured_quad()
    with open("quad.gltf", "w") as f:
        json.dump(gltf, f, indent=2)
    print("Wrote quad.gltf")
```

---

## Validation with glTF-Validator

The official glTF-Validator from the Khronos Group checks glTF assets for specification compliance. It catches issues such as:

- Missing required properties (e.g., `asset.version`, POSITION `min`/`max`).
- Invalid accessor types or component types for standard attribute semantics.
- Buffer data out of bounds (accessor references beyond buffer length).
- Misaligned byte offsets.
- Invalid index values (referencing non-existent vertices).
- Unused or orphaned objects.
- Extension compliance issues.

### Installation

```bash
# Install via npm
npm install -g gltf-validator

# Or download the standalone binary from:
# https://github.com/KhronosGroup/glTF-Validator/releases
```

### Command-line Usage

```bash
# Validate a glTF file
gltf_validator model.gltf

# Validate a GLB file
gltf_validator model.glb

# Output detailed JSON report
gltf_validator model.gltf -o report.json

# Validate with maximum verbosity
gltf_validator model.gltf -w
```

### Python Validation via Subprocess

```python
import subprocess
import json
from pathlib import Path


def validate_gltf(filepath: str) -> dict:
    """Validate a glTF/GLB file and return the report."""
    result = subprocess.run(
        ["gltf_validator", filepath, "-o", "-"],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0 and not result.stdout:
        raise RuntimeError(f"Validator failed: {result.stderr}")

    report = json.loads(result.stdout)
    return report


def check_validation(filepath: str) -> bool:
    """Check if a glTF file passes validation with no errors."""
    report = validate_gltf(filepath)

    errors = report.get("issues", {}).get("numErrors", 0)
    warnings = report.get("issues", {}).get("numWarnings", 0)
    infos = report.get("issues", {}).get("numInfos", 0)

    print(f"Validation: {errors} errors, {warnings} warnings, {infos} infos")

    if errors > 0:
        for issue in report.get("issues", {}).get("messages", []):
            if issue.get("severity") == 0:  # Error
                print(f"  ERROR: {issue['message']}")
                if "pointer" in issue:
                    print(f"         at {issue['pointer']}")
        return False

    return True


if __name__ == "__main__":
    is_valid = check_validation("triangle.gltf")
    print(f"File is {'valid' if is_valid else 'INVALID'}")
```

### Common Validation Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `ACCESSOR_MIN_MISMATCH` | POSITION min/max do not match actual data | Recompute min/max from vertex data |
| `BUFFER_VIEW_TOO_SHORT` | bufferView.byteLength too small for accessor | Recalculate: `count * elementSize` |
| `ACCESSOR_OFFSET_ALIGNMENT` | byteOffset not aligned to componentType size | Pad to next multiple of component size |
| `MESH_PRIMITIVE_ATTRIBUTES_ACCESSOR_COUNT_MISMATCH` | Different vertex counts across attributes | Ensure all attribute accessors have same count |
| `BUFFER_VIEW_TARGET_MISSING` | Missing target on bufferView | Add `34962` for vertex data, `34963` for indices |
| `UNUSED_OBJECT` | Object not referenced by anything | Remove the unused object or add a reference |

---

## Round-Trip Serialization and Verification

Round-trip testing ensures that a glTF asset can be written, read back, and produce identical results. This is critical for export pipelines, format converters, and build systems.

### JSON Round-Trip

```python
import json
import struct
import base64


def roundtrip_gltf_json(gltf: dict) -> bool:
    """Verify JSON round-trip: serialize, deserialize, compare."""
    serialized = json.dumps(gltf, sort_keys=True, separators=(",", ":"))
    deserialized = json.loads(serialized)
    reserialized = json.dumps(deserialized, sort_keys=True, separators=(",", ":"))

    if serialized != reserialized:
        print("JSON round-trip FAILED: serialized forms differ")
        return False

    print("JSON round-trip passed")
    return True


def roundtrip_buffer_data(
    original_positions: list[tuple[float, float, float]],
    buffer_b64: str,
) -> bool:
    """Verify buffer data round-trip: encode, decode, compare positions."""
    raw = base64.b64decode(buffer_b64)

    num_floats = len(raw) // 4
    floats = struct.unpack(f"<{num_floats}f", raw)

    decoded_positions = [
        (floats[i * 3], floats[i * 3 + 1], floats[i * 3 + 2])
        for i in range(len(floats) // 3)
    ]

    for i, (orig, decoded) in enumerate(zip(original_positions, decoded_positions)):
        for j in range(3):
            if abs(orig[j] - decoded[j]) > 1e-7:
                print(f"Buffer round-trip FAILED at vertex {i}, component {j}: "
                      f"{orig[j]} != {decoded[j]}")
                return False

    print("Buffer data round-trip passed")
    return True


def roundtrip_glb(gltf: dict, buffer_data: bytes, glb_path: str) -> bool:
    """Write GLB, read it back, and verify JSON and binary match."""
    # Write GLB
    gltf_copy = json.loads(json.dumps(gltf))
    gltf_copy["buffers"][0].pop("uri", None)

    json_bytes = json.dumps(gltf_copy, separators=(",", ":")).encode("utf-8")
    json_pad = (4 - len(json_bytes) % 4) % 4
    json_bytes += b" " * json_pad

    bin_pad = (4 - len(buffer_data) % 4) % 4
    bin_data = buffer_data + b"\x00" * bin_pad

    total = 12 + 8 + len(json_bytes) + 8 + len(bin_data)

    with open(glb_path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(bin_data), 0x004E4942))
        f.write(bin_data)

    # Read GLB back
    with open(glb_path, "rb") as f:
        magic, version, length = struct.unpack("<III", f.read(12))
        assert magic == 0x46546C67, "Not a GLB file"
        assert version == 2, f"Unexpected version: {version}"

        # Read JSON chunk
        json_len, json_type = struct.unpack("<II", f.read(8))
        assert json_type == 0x4E4F534A, "First chunk is not JSON"
        json_content = f.read(json_len)

        # Read BIN chunk
        bin_len, bin_type = struct.unpack("<II", f.read(8))
        assert bin_type == 0x004E4942, "Second chunk is not BIN"
        bin_content = f.read(bin_len)

    # Compare JSON
    read_gltf = json.loads(json_content.rstrip())
    orig_json = json.dumps(gltf_copy, sort_keys=True, separators=(",", ":"))
    read_json = json.dumps(read_gltf, sort_keys=True, separators=(",", ":"))

    if orig_json != read_json:
        print("GLB round-trip FAILED: JSON content differs")
        return False

    # Compare binary (original data portion only, ignoring padding)
    if bin_content[:len(buffer_data)] != buffer_data:
        print("GLB round-trip FAILED: binary data differs")
        return False

    print("GLB round-trip passed")
    return True
```

### Verification Checklist

When verifying a glTF export pipeline, check:

1. **Structural integrity**: All index references are valid (no out-of-bounds).
2. **Data fidelity**: Vertex positions, normals, and UVs survive encode/decode.
3. **Bounding box accuracy**: POSITION accessor min/max matches actual vertex data.
4. **Index buffer validity**: All index values are less than vertex count.
5. **Byte alignment**: All offsets satisfy alignment constraints.
6. **Buffer size**: `buffer.byteLength` matches actual data size.
7. **GLB integrity**: Magic number, version, chunk types, and total length are correct.
8. **Material correctness**: PBR factors are in valid ranges ([0, 1] for most).
9. **Texture references**: All texture source/sampler indices are valid.
10. **Extension consistency**: `extensionsUsed` lists all extensions present in the asset.

---

## Best Practices

1. **Always set POSITION min/max**: The specification requires it, and loaders use it for bounding box computation, frustum culling, and spatial indexing. Compute it directly from vertex data, never hardcode.

2. **Use index buffers**: Even for simple geometry, index buffers reduce vertex duplication and improve GPU cache efficiency. A cube without indices needs 36 vertices (6 faces x 2 triangles x 3 vertices); with indices, it needs only 24 (or 8 if normals are not needed).

3. **Pack indices before vertex data**: Place the index bufferView before vertex bufferViews in the binary buffer. This is a common convention and ensures natural 4-byte alignment for float vertex data after potentially smaller index types.

4. **Respect alignment constraints**: Pad buffer data to satisfy accessor alignment requirements. Use zero bytes for padding in binary data and space characters for JSON chunk padding in GLB.

5. **Use UNSIGNED_SHORT for indices when possible**: It covers up to 65535 vertices and is universally supported. Only use UNSIGNED_INT when the mesh has more than 65535 vertices. UNSIGNED_BYTE indices save space but are rarely worth the reduced vertex limit.

6. **Prefer GLB for production**: GLB avoids base64 overhead and allows memory-mapped buffer access. Use embedded base64 only for debugging, prototyping, or when a single JSON file is required.

7. **Set bufferView targets**: While optional per the spec, setting `target` to `34962` (ARRAY_BUFFER) for vertex data and `34963` (ELEMENT_ARRAY_BUFFER) for index data helps loaders optimize GPU buffer allocation.

8. **Normalize quaternions**: Rotation quaternions in node transforms must be unit-length. Always normalize after computation. A quaternion `[0, 0, 0, 0]` is invalid.

9. **Use separate bufferViews for index and vertex data**: Do not mix index data and vertex attribute data in the same bufferView. The `target` hints are different, and some GPU drivers optimize them differently.

10. **Validate early and often**: Run `gltf_validator` on every generated asset during development. Integrate validation into CI/CD pipelines for export tools.

11. **Set meaningful names**: Use the `name` property on nodes, meshes, materials, and other objects. Names are not required by the spec but are invaluable for debugging, inspection in viewers, and identifying objects in complex scenes.

12. **Keep buffer count minimal**: Prefer a single buffer with multiple bufferViews over multiple buffers. This reduces HTTP requests for external files and simplifies GLB packaging.

13. **Use tightly packed data by default**: Unless interleaved data offers a measurable performance benefit for your target platform, use one bufferView per attribute with no stride. This is simpler to construct, debug, and validate.

14. **Document extensions**: If using extensions, always populate `extensionsUsed`. Only add an extension to `extensionsRequired` if the asset is meaningless without it (e.g., Draco compression with no fallback data).

---

## Anti-Patterns

1. **Omitting POSITION min/max**: This violates the spec and causes failures in viewers and validators. Some loaders will refuse to render the mesh entirely.

2. **Misaligned byte offsets**: Setting a FLOAT accessor's byteOffset to a non-multiple of 4. This causes validation errors and undefined behavior on some GPUs.

3. **Reusing bufferViews across index and vertex data**: Mixing index data and vertex data in the same bufferView with different targets. This confuses loaders and violates the intended usage.

4. **Setting byteStride on index bufferViews**: The spec explicitly forbids `byteStride` on bufferViews used for index data (target = ELEMENT_ARRAY_BUFFER). Index data is always tightly packed.

5. **Using non-normalized quaternions**: Rotation quaternions that are not unit-length cause unpredictable deformations. The identity quaternion is `[0, 0, 0, 1]`, not `[0, 0, 0, 0]`.

6. **Exceeding buffer bounds**: An accessor that reads beyond the end of its bufferView or a bufferView that extends beyond its buffer. Always verify: `bufferView.byteOffset + bufferView.byteLength <= buffer.byteLength`.

7. **Hardcoding bounding boxes**: Setting min/max to arbitrary values like `[-1, -1, -1]` and `[1, 1, 1]` instead of computing from actual vertex data. This causes incorrect culling and bounding volume errors.

8. **Using MAT3/MAT4 accessor types for transforms**: Node transforms use the `matrix` property (a JSON array), not an accessor. Accessors with MAT types are for skinning inverse bind matrices.

9. **Embedding large buffers as base64**: For assets over 100KB of binary data, base64 adds 33% overhead. Use external `.bin` files or GLB format instead.

10. **Circular node hierarchies**: A node referencing itself (directly or indirectly) in its children array. This violates the DAG constraint and causes infinite loops in traversal.

11. **Specifying both TRS and matrix on a node**: The spec says behavior is undefined when both are present. Use one or the other, never both.

12. **Forgetting to pad GLB chunks**: JSON chunks must be padded with spaces (0x20) and BIN chunks with zeros (0x00) to 4-byte boundaries. Incorrect padding corrupts the file structure.

13. **Using `extensionsRequired` without fallback consideration**: Adding an extension to `extensionsRequired` means any loader that does not support the extension must reject the file entirely. Only require extensions that are truly essential.

14. **Inconsistent vertex counts across attributes**: If POSITION has 100 vertices but NORMAL has 99, the primitive is invalid. All attribute accessors in a single primitive must have the same count.

15. **Ignoring winding order**: glTF uses counter-clockwise front-face winding by default. Incorrect winding order causes backface culling to hide geometry that should be visible.

---

## Sources & References

- [glTF 2.0 Specification (Khronos Group)](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html) -- The complete official specification document covering all properties, data types, and constraints.
- [glTF Tutorials (Khronos Group)](https://github.com/KhronosGroup/glTF-Tutorials/blob/main/gltfTutorial/README.md) -- Step-by-step tutorials covering scenes, nodes, meshes, buffers, materials, and animations with visual examples.
- [glTF-Validator (Khronos Group)](https://github.com/KhronosGroup/glTF-Validator) -- Official validation tool source code, release binaries, and documentation for checking specification compliance.
- [glTF Extensions Registry (Khronos Group)](https://github.com/KhronosGroup/glTF/tree/main/extensions) -- Complete registry of ratified and vendor extensions including KHR_draco_mesh_compression, KHR_materials_unlit, KHR_texture_basisu, and more.
- [glTF Sample Assets (Khronos Group)](https://github.com/KhronosGroup/glTF-Sample-Assets) -- Official collection of sample glTF models for testing loaders, validators, and renderers, ranging from simple primitives to complex PBR scenes.
- [pygltflib (Python)](https://gitlab.com/dodgyville/pygltflib) -- Python library for reading and writing glTF 2.0 files with support for GLB, base64, and external buffers.
- [trimesh glTF Export (Python)](https://trimesh.org/trimesh.exchange.gltf.html) -- Documentation for the trimesh library's glTF/GLB export functionality for programmatic mesh generation.

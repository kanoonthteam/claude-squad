---
name: cad-formats
description: 3D/CAD format specifications (DWG, DXF, STEP, IGES, STL, OBJ), conversion pipelines, 2D-to-3D geometry extrusion, and FreeCAD Python scripting for engineering workflows
---

# CAD/3D Format Engineering -- Expert Patterns

Production-quality patterns for reading, writing, converting, and processing CAD and 3D geometry formats using Python 3.11+, FreeCAD, ezdxf, and open-source toolchains.

## Table of Contents
1. [STEP (ISO 10303) Format Structure](#step-iso-10303-format-structure)
2. [IGES Format Structure and Entity Types](#iges-format-structure-and-entity-types)
3. [DXF Format Structure and Parsing](#dxf-format-structure-and-parsing)
4. [DWG Format Overview and Conversion](#dwg-format-overview-and-conversion)
5. [STL Format (ASCII and Binary)](#stl-format-ascii-and-binary)
6. [OBJ Format (Vertices, Normals, Faces, Materials)](#obj-format-vertices-normals-faces-materials)
7. [Coordinate System Conventions](#coordinate-system-conventions)
8. [Unit Handling and Conversion](#unit-handling-and-conversion)
9. [Format Feature Comparison Matrix](#format-feature-comparison-matrix)
10. [Format Conversion Pipelines](#format-conversion-pipelines)
11. [2D Profile Extrusion to 3D Geometry](#2d-profile-extrusion-to-3d-geometry)
12. [FreeCAD Python Scripting](#freecad-python-scripting)
13. [ezdxf Library for DXF Reading/Writing](#ezdxf-library-for-dxf-readingwriting)
14. [Best Practices](#best-practices)
15. [Anti-Patterns](#anti-patterns)
16. [Sources & References](#sources--references)

---

## STEP (ISO 10303) Format Structure

STEP (Standard for the Exchange of Product model data) is defined by ISO 10303. It is the most widely adopted neutral CAD exchange format for B-Rep (Boundary Representation) solid models, assemblies, and product metadata.

### File Structure

A STEP file (typically `.step` or `.stp`) is a plain-text file using the STEP Physical File (SPF) format defined in ISO 10303-21. The file has two main sections:

- **HEADER section**: Contains metadata -- file description, implementation level, originating system, and timestamps.
- **DATA section**: Contains entity instances, each referenced by a unique integer ID prefixed with `#`.

Example minimal STEP file skeleton:

```
ISO-10303-21;
HEADER;
FILE_DESCRIPTION(('FreeCAD Model'),'2;1');
FILE_NAME('part.step','2026-02-25T12:00:00',('Author'),('Org'),'FreeCAD','FreeCAD','');
FILE_SCHEMA(('AUTOMOTIVE_DESIGN'));
HEADER_END;
DATA;
#1=APPLICATION_PROTOCOL_DEFINITION('international standard','automotive_design',2000,#2);
#2=APPLICATION_CONTEXT('core data for automotive mechanical design processes');
...
DATA_END;
END-ISO-10303-21;
```

### Key Entity Types (AP214 / AP203 / AP242)

| Entity | Purpose |
|---|---|
| `PRODUCT` | Top-level product definition |
| `PRODUCT_DEFINITION` | A specific version/configuration of a product |
| `SHAPE_REPRESENTATION` | Associates geometry with a product definition |
| `ADVANCED_BREP_SHAPE_REPRESENTATION` | B-Rep solid geometry |
| `CLOSED_SHELL` | A watertight boundary of a solid |
| `ADVANCED_FACE` | A face bounded by edge loops on a surface |
| `FACE_OUTER_BOUND` / `FACE_BOUND` | Outer or inner boundary loops of a face |
| `EDGE_LOOP` | Ordered list of oriented edges forming a closed loop |
| `ORIENTED_EDGE` | An edge with direction |
| `EDGE_CURVE` | An edge defined by a 3D curve between two vertices |
| `VERTEX_POINT` | A vertex at a CARTESIAN_POINT |
| `CARTESIAN_POINT` | An (x, y, z) coordinate |
| `DIRECTION` | A unit direction vector |
| `AXIS2_PLACEMENT_3D` | A local coordinate system (origin + Z-axis + X-axis) |
| `PLANE` / `CYLINDRICAL_SURFACE` / `TOROIDAL_SURFACE` | Underlying surface geometry |
| `LINE` / `CIRCLE` / `B_SPLINE_CURVE_WITH_KNOTS` | Curve geometry |
| `MANIFOLD_SOLID_BREP` | A solid defined by a closed shell |
| `COLOUR_RGB` | Color specification for presentation |
| `MECHANICAL_DESIGN_GEOMETRIC_PRESENTATION_CONTEXT` | Presentation layer |

### Application Protocols

- **AP203**: Configuration-controlled 3D design (legacy, widely supported).
- **AP214**: Core data for automotive mechanical design processes. Adds color, layers, GD&T.
- **AP242**: Managed model-based 3D engineering. The modern successor combining AP203 and AP214 with PMI (Product Manufacturing Information), tessellation, and composite materials.

### Parsing STEP with PythonOCC / OCP

PythonOCC (the Python wrapper for OpenCASCADE Technology) is the standard open-source library for reading STEP files programmatically.

```python
"""Read a STEP file, extract solid shapes, compute bounding boxes, and export to STL."""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Sequence

from OCP.STEPControl import STEPControl_Reader
from OCP.IFSelect import IFSelect_RetDone
from OCP.BRepBndLib import BRepBndLib
from OCP.Bnd import Bnd_Box
from OCP.StlAPI import StlAPI_Writer
from OCP.BRepMesh import BRepMesh_IncrementalMesh
from OCP.TopoDS import TopoDS_Shape


def read_step(file_path: Path) -> list[TopoDS_Shape]:
    """Read a STEP file and return all root shapes.

    Args:
        file_path: Path to the .step or .stp file.

    Returns:
        List of TopoDS_Shape objects found in the file.

    Raises:
        RuntimeError: If the STEP reader fails to parse the file.
    """
    reader = STEPControl_Reader()
    status = reader.ReadFile(str(file_path))
    if status != IFSelect_RetDone:
        raise RuntimeError(f"STEP read failed with status {status}: {file_path}")

    reader.TransferRoots()
    shapes: list[TopoDS_Shape] = []
    for i in range(1, reader.NbShapes() + 1):
        shapes.append(reader.Shape(i))
    return shapes


def bounding_box(shape: TopoDS_Shape) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    """Compute the axis-aligned bounding box of a shape.

    Returns:
        Tuple of (min_corner, max_corner) as (x, y, z) tuples.
    """
    bbox = Bnd_Box()
    BRepBndLib.Add_s(shape, bbox)
    xmin, ymin, zmin, xmax, ymax, zmax = bbox.Get()
    return (xmin, ymin, zmin), (xmax, ymax, zmax)


def export_stl(
    shape: TopoDS_Shape,
    output_path: Path,
    linear_deflection: float = 0.1,
    angular_deflection: float = 0.5,
    ascii_mode: bool = False,
) -> None:
    """Tessellate a shape and export as STL.

    Args:
        shape: The B-Rep shape to tessellate.
        output_path: Destination .stl file path.
        linear_deflection: Chord deviation tolerance (smaller = finer mesh).
        angular_deflection: Angle tolerance in radians.
        ascii_mode: If True, write ASCII STL; otherwise binary.
    """
    mesh = BRepMesh_IncrementalMesh(shape, linear_deflection, False, angular_deflection, True)
    mesh.Perform()
    if not mesh.IsDone():
        raise RuntimeError("Tessellation failed")

    writer = StlAPI_Writer()
    writer.SetASCIIMode(ascii_mode)
    writer.Write(shape, str(output_path))


def main(step_file: str) -> None:
    path = Path(step_file)
    shapes = read_step(path)
    print(f"Loaded {len(shapes)} shape(s) from {path.name}")

    for i, shape in enumerate(shapes):
        bb_min, bb_max = bounding_box(shape)
        print(f"  Shape {i}: bbox min={bb_min}, max={bb_max}")

        stl_path = path.with_suffix(f".shape{i}.stl")
        export_stl(shape, stl_path, linear_deflection=0.05)
        print(f"  Exported to {stl_path}")


if __name__ == "__main__":
    main(sys.argv[1])
```

---

## IGES Format Structure and Entity Types

IGES (Initial Graphics Exchange Specification) is an older neutral format (ANSI Y14.26M) for exchanging 2D/3D geometry. While superseded by STEP for most purposes, IGES is still encountered in legacy systems, especially in aerospace and tooling.

### File Structure

An IGES file is a fixed-column ASCII format with five sections, each identified by a letter in column 73:

| Section | Col 73 | Purpose |
|---|---|---|
| Start (S) | `S` | Human-readable file description |
| Global (G) | `G` | File-level parameters: units, author, scale, precision |
| Directory Entry (D) | `D` | Index of all entities -- two lines per entity with type, layer, color, transformation, etc. |
| Parameter Data (P) | `P` | The actual geometric data for each entity, referenced by D-section pointer |
| Terminate (T) | `T` | Record counts for each section |

### Key Entity Types

| Type Code | Entity | Description |
|---|---|---|
| 100 | Circular Arc | Arc defined by center, start, and end points in a plane |
| 102 | Composite Curve | Ordered list of curves joined end-to-end |
| 104 | Conic Arc | General conic (ellipse, parabola, hyperbola) |
| 108 | Plane | An infinite or bounded plane |
| 110 | Line | A line segment between two points |
| 116 | Point | A single point in 3D space |
| 120 | Surface of Revolution | Surface generated by revolving a curve about an axis |
| 122 | Tabulated Cylinder | Surface generated by translating a curve along a direction |
| 124 | Transformation Matrix | 3x4 matrix for positioning entities |
| 126 | Rational B-Spline Curve | NURBS curve |
| 128 | Rational B-Spline Surface | NURBS surface |
| 142 | Curve on a Parametric Surface | Trim curve for bounded surfaces |
| 143 | Bounded Surface | A surface trimmed by boundary curves |
| 144 | Trimmed Parametric Surface | Surface with outer and optional inner trim loops |
| 186 | Manifold Solid B-Rep Object | Complete B-Rep solid (added in IGES 5.x) |
| 308 | Subfigure Definition | Reusable component definition (like a block/symbol) |
| 314 | Color Definition | RGB color |
| 402 | Associativity Instance | Grouping of entities |
| 406 | Property | Named properties (e.g., name, attributes) |

### Global Section Parameters (Selected)

| Index | Parameter | Example |
|---|---|---|
| 1 | Parameter delimiter | `,` |
| 2 | Record delimiter | `;` |
| 3 | Product ID (sending system) | `MyPart` |
| 4 | File name | `mypart.igs` |
| 13 | Model space scale | `1.0` |
| 14 | Units flag | `1` = inches, `2` = mm, `6` = meters |
| 15 | Units name | `MM` |

### Limitations of IGES

- No standardized assembly structure. Parts are flat lists of geometry.
- No product metadata or configuration management.
- Trimmed surface representation is fragile -- gaps and overlaps are common.
- Color and layer support is inconsistent across implementations.
- No PMI, GD&T, or annotation support in most implementations.

---

## DXF Format Structure and Parsing

DXF (Drawing Exchange Format) is AutoCAD's open text/binary format for 2D and 3D drawings. It is the most widely supported format for 2D CAD interchange.

### File Structure

A DXF file is organized into sections, each delimited by group codes:

| Section | Purpose |
|---|---|
| `HEADER` | Drawing variables (units, limits, version) |
| `CLASSES` | Custom object class definitions (DXF R13+) |
| `TABLES` | Symbol tables: layers, linetypes, dimension styles, text styles, viewports |
| `BLOCKS` | Block definitions (reusable geometry groups) |
| `ENTITIES` | The actual drawing entities (lines, arcs, text, etc.) |
| `OBJECTS` | Non-graphical objects (dictionaries, layouts, plot settings) |
| `THUMBNAILIMAGE` | Optional preview image |

### Group Code System

DXF uses a tag-based format where each data element is a pair: a group code (integer) and a value. Key group codes:

| Code Range | Meaning |
|---|---|
| 0 | Entity type / section marker |
| 1 | Primary text value |
| 2 | Name (block name, attribute tag) |
| 5 | Entity handle (hex) |
| 6 | Linetype name |
| 7 | Text style name |
| 8 | Layer name |
| 10-18 | Primary X coordinates |
| 20-28 | Primary Y coordinates |
| 30-38 | Primary Z coordinates |
| 40-48 | Floating-point values (radius, scale factors, text height) |
| 62 | Color number (ACI: 0-256) |
| 70-78 | Integer flags |
| 100 | Subclass marker |
| 210, 220, 230 | Extrusion direction (OCS normal) |
| 330 | Soft owner handle pointer |
| 370 | Lineweight |
| 420 | True color (24-bit RGB as integer) |

### Common Entity Types

| Entity | Description |
|---|---|
| `LINE` | Line segment (start point, end point) |
| `CIRCLE` | Circle (center, radius) |
| `ARC` | Circular arc (center, radius, start angle, end angle) |
| `ELLIPSE` | Ellipse (center, major axis endpoint, ratio, start/end parameter) |
| `LWPOLYLINE` | Lightweight polyline (2D, bulge-encoded arcs) |
| `POLYLINE` / `VERTEX` | Legacy polyline (2D/3D, can represent meshes) |
| `SPLINE` | NURBS curve (degree, knots, control points, fit points) |
| `3DFACE` | Triangular or quadrilateral face |
| `3DSOLID` | ACIS-based solid (proprietary binary data in group code 1) |
| `TEXT` / `MTEXT` | Single-line / multi-line text |
| `DIMENSION` | Associative dimension |
| `INSERT` | Block reference (instance of a BLOCKS definition) |
| `HATCH` | Filled region with pattern |
| `LEADER` / `MLEADER` | Leader line with annotation |
| `VIEWPORT` | Model/paper space viewport |
| `IMAGE` | Raster image reference |

### Object Coordinate System (OCS)

DXF 2D entities use an Object Coordinate System defined by an extrusion direction (group codes 210/220/230). The OCS normal defaults to (0, 0, 1) for entities in the XY plane. The "arbitrary axis algorithm" derives the OCS X and Y axes from the extrusion normal. This is critical for correctly interpreting coordinates of entities that are not in the world XY plane.

---

## DWG Format Overview and Conversion

DWG is AutoCAD's proprietary native binary format. It is NOT openly documented by Autodesk, though reverse-engineering efforts (OpenDWG Alliance, now Open Design Alliance) have produced extensive specifications.

### Key Characteristics

- **Binary format**: Compact, fast to load, not human-readable.
- **Version-specific**: Each AutoCAD release may introduce a new DWG version. Common version strings: `AC1015` (R2000), `AC1018` (R2004), `AC1021` (R2007), `AC1024` (R2010), `AC1027` (R2013), `AC1032` (R2018).
- **Superset of DXF**: DWG contains everything in DXF plus additional proprietary data (ACIS solid history, custom objects, xrefs).
- **Object ownership model**: Every object has an owner handle, forming a tree rooted at the HEADER object.

### DWG to DXF Conversion

Since DWG is proprietary, the standard open-source approach is to convert to DXF first:

**ODA File Converter** (Open Design Alliance):
- Free-as-in-beer command-line tool.
- Supports DWG R14 through R2025.
- Converts DWG to DXF (and vice versa) with high fidelity.
- Available for Linux, macOS, Windows.

```bash
# ODA File Converter CLI usage
# Syntax: ODAFileConverter <input_dir> <output_dir> <output_version> <output_format> [options]
# output_version: ACAD2018, ACAD2013, ACAD2010, ACAD2007, ACAD2004, ACAD2000
# output_format: DXF (text), DXB (binary DXF)

ODAFileConverter "/input/" "/output/" ACAD2018 DXF 0 1
```

**LibreDWG**:
- GPL-licensed C library for reading/writing DWG files.
- Provides `dwg2dxf` and `dwgread` command-line tools.
- Coverage varies by DWG version; best for R2000-R2018.

```bash
# Convert DWG to DXF using LibreDWG
dwg2dxf input.dwg
# Output: input.dxf
```

**Python with ezdxf**:
- `ezdxf` reads DXF natively but does NOT read DWG.
- Workflow: DWG -> (ODA/LibreDWG) -> DXF -> ezdxf.

---

## STL Format (ASCII and Binary)

STL (Stereolithography / Standard Tessellation Language) represents surfaces as unstructured triangular meshes. It contains only geometry -- no color, materials, textures, or topology.

### ASCII STL

```
solid part_name
  facet normal 0.0 0.0 1.0
    outer loop
      vertex 0.0 0.0 0.0
      vertex 1.0 0.0 0.0
      vertex 1.0 1.0 0.0
    endloop
  endfacet
  ...
endsolid part_name
```

Each facet has a normal vector and exactly three vertices, specified in counter-clockwise order when viewed from outside the solid (right-hand rule).

### Binary STL

| Offset | Size (bytes) | Field |
|---|---|---|
| 0 | 80 | Header (arbitrary, should NOT begin with "solid") |
| 80 | 4 | Number of triangles (uint32 LE) |
| 84 | 50 * N | Triangle records |

Each triangle record (50 bytes):
| Offset | Size | Field |
|---|---|---|
| 0 | 12 | Normal vector (3 x float32 LE) |
| 12 | 12 | Vertex 1 (3 x float32 LE) |
| 24 | 12 | Vertex 2 (3 x float32 LE) |
| 36 | 12 | Vertex 3 (3 x float32 LE) |
| 48 | 2 | Attribute byte count (uint16 LE, usually 0) |

### STL Limitations

- No units -- the file contains dimensionless numbers; units must be agreed upon out-of-band.
- No topology -- vertices are duplicated per-triangle; adjacency must be reconstructed.
- No color or material (except non-standard extensions using the attribute byte count field).
- Float32 precision only in binary format.
- No assembly structure.

---

## OBJ Format (Vertices, Normals, Faces, Materials)

Wavefront OBJ is a widely used plain-text 3D geometry format. It supports polygonal meshes, free-form curves/surfaces, vertex normals, texture coordinates, and material references.

### OBJ Syntax

```
# Comment
mtllib materials.mtl

o ObjectName
g GroupName
usemtl MaterialName

# Geometric vertices
v  1.0  2.0  3.0
v -1.0  2.0  3.0
v -1.0 -2.0  3.0
v  1.0 -2.0  3.0

# Texture coordinates
vt 0.0 0.0
vt 1.0 0.0
vt 1.0 1.0
vt 0.0 1.0

# Vertex normals
vn 0.0 0.0 1.0

# Faces (vertex/texture/normal indices, 1-based)
f 1/1/1 2/2/1 3/3/1 4/4/1
```

### MTL (Material Library) File

```
newmtl Steel_Brushed
Ka 0.1 0.1 0.1       # Ambient color
Kd 0.6 0.6 0.65      # Diffuse color
Ks 0.9 0.9 0.9       # Specular color
Ns 200.0              # Specular exponent
d 1.0                 # Dissolve (opacity)
illum 2               # Illumination model
map_Kd texture.png    # Diffuse texture map
map_Bump normal.png   # Bump/normal map
```

### Key Characteristics

- **1-based indexing**: All vertex/texture/normal indices start at 1.
- **Negative indices**: Supported as relative references (e.g., `f -4 -3 -2 -1` references the last four vertices).
- **Polygonal faces**: Not limited to triangles -- quads and n-gons are valid.
- **No units**: Like STL, units are implicit.
- **No hierarchy or assembly**: Flat structure with object/group names for organization.
- **Coordinate system**: Right-handed, Y-up by convention (but not enforced).

---

## Coordinate System Conventions

Different formats and applications use different coordinate system conventions. Mismatched conventions cause rotated or mirrored geometry on import.

| Format / Application | Handedness | Up Axis | Forward Axis | Notes |
|---|---|---|---|---|
| STEP / IGES | Right-handed | +Z | +X (by convention) | Defined by AXIS2_PLACEMENT_3D |
| DXF / DWG | Right-handed | +Z | +X | World Coordinate System (WCS) |
| STL | Right-handed | Undefined | Undefined | No convention; typically Z-up from CAD |
| OBJ | Right-handed | +Y | -Z (by convention) | De facto standard from graphics/animation |
| glTF | Right-handed | +Y | +Z | Specified by Khronos spec |
| FBX | Right-handed | +Y | +Z (configurable) | Axis conversion on export |
| USD | Right-handed | +Y | -Z | Stage-level metersPerUnit and upAxis |
| Blender | Right-handed | +Z | +Y | Applies axis conversion on import/export |
| Unity | Left-handed | +Y | +Z | Flips X-axis or winding on import |
| Unreal Engine | Left-handed | +Z | +X | Applies axis swizzle on import |
| FreeCAD | Right-handed | +Z | +X | Consistent with STEP/ISO convention |

### Conversion Rule

To convert between Z-up and Y-up right-handed systems, apply a -90 degree rotation about the X-axis:

```
Y_up = R_x(-90) * Z_up

     [ 1   0    0 ]
R =  [ 0   0   -1 ]
     [ 0   1    0 ]
```

So: `(x, y, z)_Zup` maps to `(x, -z, y)_Yup`.

---

## Unit Handling and Conversion

### Units in Each Format

| Format | Unit Specification | Default / Common |
|---|---|---|
| STEP | Encoded in `LENGTH_MEASURE` / `SI_UNIT` entities with prefix | Millimeters (typical) |
| IGES | Global section parameter 14 (units flag) and 15 (units name) | Inches or mm |
| DXF | `$INSUNITS` header variable | 0 = unitless, 1 = inches, 4 = mm, 6 = meters |
| DWG | Same as DXF (`$INSUNITS`) | Same as DXF |
| STL | No unit information | Assumed mm (3D printing) or meters (simulation) |
| OBJ | No unit information | Application-dependent |
| glTF | Meters (spec requirement) | Meters |
| FBX | Configurable, stored in file metadata | Centimeters (Maya/Blender default) |

### STEP Unit Entities

```
#10=( LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.) );
#11=( NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.) );
#12=( NAMED_UNIT(*) SI_UNIT($,.STERADIAN.) SOLID_ANGLE_UNIT() );
#13=UNCERTAINTY_MEASURE_WITH_UNIT(LENGTH_MEASURE(1.E-07),#10,'distance accuracy');
```

The prefix `.MILLI.` combined with `.METRE.` means millimeters. Common prefixes: `.MILLI.` (mm), `.CENTI.` (cm), `$` (no prefix = base unit, i.e., meters for length).

### DXF $INSUNITS Values

| Value | Unit |
|---|---|
| 0 | Unitless |
| 1 | Inches |
| 2 | Feet |
| 3 | Miles |
| 4 | Millimeters |
| 5 | Centimeters |
| 6 | Meters |
| 7 | Kilometers |
| 8 | Microinches |
| 9 | Mils |
| 10 | Yards |
| 11 | Angstroms |
| 12 | Nanometers |
| 13 | Microns |
| 14 | Decimeters |
| 15 | Decameters |
| 16 | Hectometers |
| 17 | Gigameters |
| 18 | Astronomical Units |
| 19 | Light Years |
| 20 | Parsecs |

### Conversion Factor Table (to meters)

| Unit | Multiply by |
|---|---|
| Inches | 0.0254 |
| Feet | 0.3048 |
| Millimeters | 0.001 |
| Centimeters | 0.01 |
| Meters | 1.0 |
| Kilometers | 1000.0 |
| Microns | 1e-6 |
| Mils (thousandths of inch) | 2.54e-5 |

---

## Format Feature Comparison Matrix

| Feature | STEP | IGES | DXF | DWG | STL | OBJ | glTF |
|---|---|---|---|---|---|---|---|
| B-Rep Solids | Yes | Partial | Partial* | Yes | No | No | No |
| NURBS Curves | Yes | Yes | Yes | Yes | No | Yes | No |
| NURBS Surfaces | Yes | Yes | No | Yes | No | Yes | No |
| Triangular Mesh | Via tessellation | No | 3DFACE/POLYFACE | Yes | Yes | Yes | Yes |
| Assembly Structure | Yes | No | INSERT blocks | Yes | No | No | Yes (nodes) |
| Colors | Yes (AP214+) | Yes (type 314) | Yes (ACI/RGB) | Yes | No** | Yes (MTL) | Yes (PBR) |
| Materials/Textures | Limited | No | No | No | No | Yes (MTL) | Yes (PBR) |
| Units | Yes | Yes | Yes | Yes | No | No | Meters |
| PMI / GD&T | Yes (AP242) | No | Partial | Yes | No | No | No |
| Animation | No | No | No | No | No | No | Yes |
| Text / Annotations | Yes | Yes (type 212) | Yes | Yes | No | No | No |
| Layers | Yes | Yes | Yes | Yes | No | Groups | No |
| File Size | Large | Large | Large | Compact | Small-Med | Medium | Small (binary) |
| Human Readable | Yes | Yes | Yes (ASCII) | No | ASCII variant | Yes | JSON+bin |
| Open Standard | ISO | ANSI | Autodesk pub. | Proprietary | Public domain | Open | Khronos |

\* DXF `3DSOLID` entities contain proprietary ACIS data.
\** Some non-standard extensions encode color in the attribute byte count field.

---

## Format Conversion Pipelines

### STEP to Mesh to glTF Pipeline

This is the most common pipeline for bringing CAD geometry into web viewers, game engines, and AR/VR:

```
STEP (.step/.stp)
  |
  v  [PythonOCC / OpenCASCADE / FreeCAD]
B-Rep tessellation (control linear/angular deflection)
  |
  v
Triangle mesh (in memory)
  |
  v  [trimesh / numpy-stl]
Mesh optimization (merge vertices, remove degenerates, decimate)
  |
  v  [trimesh.exchange / pygltflib]
glTF 2.0 (.glb/.gltf)
```

### Full Pipeline Implementation

```python
"""End-to-end STEP -> optimized glTF conversion pipeline.

Dependencies:
    pip install cadquery trimesh numpy pygltflib mapbox-earcut
    # cadquery bundles OCP (OpenCASCADE Python bindings)
"""
from __future__ import annotations

import json
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np
import trimesh
from OCP.BRep import BRep_Tool
from OCP.BRepMesh import BRepMesh_IncrementalMesh
from OCP.gp import gp_Pnt
from OCP.STEPControl import STEPControl_Reader
from OCP.IFSelect import IFSelect_RetDone
from OCP.TopAbs import TopAbs_FACE
from OCP.TopExp import TopExp_Explorer
from OCP.TopLoc import TopLoc_Location
from OCP.TopoDS import TopoDS, TopoDS_Shape


@dataclass
class TessellationConfig:
    """Configuration for B-Rep to mesh tessellation."""

    linear_deflection: float = 0.1
    """Maximum chord deviation in model units (smaller = finer mesh)."""

    angular_deflection: float = 0.5
    """Maximum angle deviation in radians."""

    relative: bool = False
    """If True, linear_deflection is relative to bounding box diagonal."""


@dataclass
class MeshOptimizationConfig:
    """Configuration for mesh post-processing."""

    merge_vertices: bool = True
    """Merge duplicate vertices within tolerance."""

    merge_tolerance: float = 1e-8
    """Vertex merge distance tolerance."""

    remove_degenerate: bool = True
    """Remove zero-area triangles."""

    decimate: bool = False
    """Apply quadric decimation."""

    target_face_count: int = 50_000
    """Target face count when decimation is enabled."""


@dataclass
class ConversionResult:
    """Result of a format conversion."""

    output_path: Path
    vertex_count: int
    face_count: int
    file_size_bytes: int
    warnings: list[str] = field(default_factory=list)


def _extract_triangles_from_shape(
    shape: TopoDS_Shape,
    config: TessellationConfig,
) -> trimesh.Trimesh:
    """Tessellate all faces in a TopoDS_Shape and return a unified trimesh.

    Args:
        shape: The B-Rep shape to tessellate.
        config: Tessellation quality parameters.

    Returns:
        A trimesh.Trimesh containing the tessellated mesh.
    """
    mesh_algo = BRepMesh_IncrementalMesh(
        shape,
        config.linear_deflection,
        config.relative,
        config.angular_deflection,
        True,
    )
    mesh_algo.Perform()

    all_vertices: list[np.ndarray] = []
    all_faces: list[np.ndarray] = []
    vertex_offset = 0

    explorer = TopExp_Explorer(shape, TopAbs_FACE)
    while explorer.More():
        face = TopoDS.Face_s(explorer.Current())
        location = TopLoc_Location()
        triangulation = BRep_Tool.Triangulation_s(face, location)

        if triangulation is not None:
            nb_nodes = triangulation.NbNodes()
            nb_tris = triangulation.NbTriangles()

            # Extract vertices
            vertices = np.empty((nb_nodes, 3), dtype=np.float64)
            for i in range(1, nb_nodes + 1):
                pnt: gp_Pnt = triangulation.Node(i)
                pnt_transformed = pnt.Transformed(location.Transformation())
                vertices[i - 1] = [
                    pnt_transformed.X(),
                    pnt_transformed.Y(),
                    pnt_transformed.Z(),
                ]
            all_vertices.append(vertices)

            # Extract triangle indices
            faces = np.empty((nb_tris, 3), dtype=np.int32)
            for i in range(1, nb_tris + 1):
                tri = triangulation.Triangle(i)
                n1, n2, n3 = tri.Get()
                faces[i - 1] = [
                    n1 - 1 + vertex_offset,
                    n2 - 1 + vertex_offset,
                    n3 - 1 + vertex_offset,
                ]
            all_faces.append(faces)
            vertex_offset += nb_nodes

        explorer.Next()

    if not all_vertices:
        return trimesh.Trimesh()

    combined_vertices = np.vstack(all_vertices)
    combined_faces = np.vstack(all_faces)
    return trimesh.Trimesh(vertices=combined_vertices, faces=combined_faces)


def _optimize_mesh(
    mesh: trimesh.Trimesh,
    config: MeshOptimizationConfig,
) -> trimesh.Trimesh:
    """Apply mesh optimization steps.

    Args:
        mesh: Input triangle mesh.
        config: Optimization parameters.

    Returns:
        Optimized trimesh.
    """
    if config.merge_vertices:
        mesh.merge_vertices(merge_tex=True, merge_norm=True)

    if config.remove_degenerate:
        mesh.remove_degenerate_faces()
        mesh.remove_unreferenced_vertices()

    if config.decimate and len(mesh.faces) > config.target_face_count:
        mesh = mesh.simplify_quadric_decimation(config.target_face_count)

    return mesh


def convert_step_to_gltf(
    step_path: Path,
    output_path: Path,
    tessellation: TessellationConfig | None = None,
    optimization: MeshOptimizationConfig | None = None,
    binary: bool = True,
    z_up_to_y_up: bool = True,
) -> ConversionResult:
    """Convert a STEP file to glTF 2.0.

    Args:
        step_path: Path to input .step/.stp file.
        output_path: Path for output .glb/.gltf file.
        tessellation: Tessellation quality config. Uses defaults if None.
        optimization: Mesh optimization config. Uses defaults if None.
        binary: If True, output .glb; otherwise .gltf with separate .bin.
        z_up_to_y_up: If True, rotate from CAD Z-up to glTF Y-up.

    Returns:
        ConversionResult with output metadata.

    Raises:
        RuntimeError: If STEP reading or tessellation fails.
        FileNotFoundError: If step_path does not exist.
    """
    if not step_path.exists():
        raise FileNotFoundError(f"STEP file not found: {step_path}")

    tess_config = tessellation or TessellationConfig()
    opt_config = optimization or MeshOptimizationConfig()
    warnings: list[str] = []

    # Read STEP
    reader = STEPControl_Reader()
    status = reader.ReadFile(str(step_path))
    if status != IFSelect_RetDone:
        raise RuntimeError(f"STEP read failed: status={status}")

    reader.TransferRoots()
    shape = reader.OneShape()

    # Tessellate
    mesh = _extract_triangles_from_shape(shape, tess_config)
    if len(mesh.faces) == 0:
        warnings.append("Tessellation produced zero triangles")

    # Optimize
    mesh = _optimize_mesh(mesh, opt_config)

    # Axis conversion: CAD Z-up -> glTF Y-up
    if z_up_to_y_up:
        rotation = trimesh.transformations.rotation_matrix(
            np.radians(-90), [1, 0, 0]
        )
        mesh.apply_transform(rotation)

    # Unit conversion: assume STEP is in mm, glTF requires meters
    mesh.apply_scale(0.001)

    # Export
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if binary:
        mesh.export(str(output_path), file_type="glb")
    else:
        mesh.export(str(output_path), file_type="gltf")

    file_size = output_path.stat().st_size

    return ConversionResult(
        output_path=output_path,
        vertex_count=len(mesh.vertices),
        face_count=len(mesh.faces),
        file_size_bytes=file_size,
        warnings=warnings,
    )
```

### Pipeline Variants

| Source | Target | Tool Chain |
|---|---|---|
| STEP -> STL | PythonOCC `StlAPI_Writer` or FreeCAD `Mesh.export` |
| STEP -> OBJ | PythonOCC tessellate -> trimesh -> `mesh.export("out.obj")` |
| STEP -> glTF | PythonOCC tessellate -> trimesh -> `mesh.export("out.glb")` |
| IGES -> STEP | FreeCAD `Import.open` + `Part.export` or OpenCASCADE `IGESControl_Reader` + `STEPControl_Writer` |
| DWG -> DXF | ODA File Converter or LibreDWG `dwg2dxf` |
| DXF -> SVG | ezdxf `addons.drawing` backend |
| DXF -> STEP | ezdxf read -> extrude profiles via FreeCAD/OCC -> STEP export |
| STL -> OBJ | trimesh `mesh.export("out.obj")` |
| Multiple STL -> glTF | trimesh `Scene` with named meshes -> `scene.export("out.glb")` |

---

## 2D Profile Extrusion to 3D Geometry

Converting 2D drawings (DXF profiles) into 3D solids is a fundamental CAD operation. The typical workflow:

1. Parse the DXF file to extract closed polyline/spline profiles.
2. Build wire(s) from the 2D geometry.
3. Create a face from the wire(s).
4. Extrude the face along a direction vector to create a solid.

### FreeCAD Extrusion Pipeline

```python
"""Extrude 2D DXF profiles into 3D STEP solids using FreeCAD.

Run with: freecad -c this_script.py
Requires FreeCAD 0.21+ (Python 3.11 compatible).
"""
from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

import FreeCAD
import Part
import Import
import importDXF


@dataclass
class ExtrusionSpec:
    """Specification for extruding a 2D profile."""

    dxf_path: Path
    """Path to the input DXF file containing closed 2D profiles."""

    extrusion_height: float
    """Height to extrude in the Z direction, in the DXF file's units."""

    layer_filter: str | None = None
    """If set, only process entities on this DXF layer."""

    output_path: Path | None = None
    """Output STEP file path. Defaults to input name with .step extension."""

    symmetric: bool = False
    """If True, extrude symmetrically about the XY plane (-height/2 to +height/2)."""


def load_dxf_wires(dxf_path: Path, layer_filter: str | None = None) -> list[Part.Wire]:
    """Load a DXF file and extract closed wires.

    Args:
        dxf_path: Path to the DXF file.
        layer_filter: Optional layer name to filter by.

    Returns:
        List of closed Part.Wire objects.

    Raises:
        FileNotFoundError: If the DXF file does not exist.
        ValueError: If no closed wires are found.
    """
    if not dxf_path.exists():
        raise FileNotFoundError(f"DXF file not found: {dxf_path}")

    doc = FreeCAD.newDocument("DXFImport")
    importDXF.insert(str(dxf_path), doc.Name)
    doc.recompute()

    wires: list[Part.Wire] = []

    for obj in doc.Objects:
        # Apply layer filter if specified
        if layer_filter and hasattr(obj, "Label"):
            if layer_filter.lower() not in obj.Label.lower():
                continue

        if hasattr(obj, "Shape") and obj.Shape is not None:
            shape = obj.Shape
            # Extract wires from the shape
            for wire in shape.Wires:
                if wire.isClosed():
                    wires.append(wire)

    FreeCAD.closeDocument(doc.Name)

    if not wires:
        raise ValueError(
            f"No closed wires found in {dxf_path}"
            + (f" on layer '{layer_filter}'" if layer_filter else "")
        )

    return wires


def classify_wires(
    wires: list[Part.Wire],
) -> list[tuple[Part.Wire, list[Part.Wire]]]:
    """Classify wires into outer boundaries and holes.

    Uses containment testing: a wire that is fully contained within another
    wire's bounding box (and passes a point-in-face test) is classified as
    a hole in the outer wire.

    Args:
        wires: List of closed wires.

    Returns:
        List of (outer_wire, [hole_wires]) tuples.
    """
    # Sort by bounding box area, largest first (outer profiles are larger)
    sorted_wires = sorted(
        wires,
        key=lambda w: w.BoundBox.XLength * w.BoundBox.YLength,
        reverse=True,
    )

    assigned: set[int] = set()
    result: list[tuple[Part.Wire, list[Part.Wire]]] = []

    for i, outer in enumerate(sorted_wires):
        if i in assigned:
            continue

        outer_face = Part.Face(outer)
        holes: list[Part.Wire] = []

        for j, candidate in enumerate(sorted_wires):
            if j <= i or j in assigned:
                continue

            # Check if the candidate's center point is inside the outer face
            center = candidate.BoundBox.Center
            # Project to 2D -- use (x, y, 0) for point-in-face
            test_point = FreeCAD.Vector(center.x, center.y, 0)

            # Use distToShape for containment test
            dist, _, _ = outer_face.distToShape(Part.Vertex(test_point))
            if dist < 1e-6:  # Point is on or inside the face
                holes.append(candidate)
                assigned.add(j)

        result.append((outer, holes))
        assigned.add(i)

    return result


def extrude_profiles(spec: ExtrusionSpec) -> list[Part.Shape]:
    """Execute the full extrusion pipeline.

    Args:
        spec: Extrusion specification.

    Returns:
        List of extruded solid shapes.

    Raises:
        FileNotFoundError: If DXF file is missing.
        ValueError: If no valid profiles are found.
    """
    wires = load_dxf_wires(spec.dxf_path, spec.layer_filter)
    classified = classify_wires(wires)

    solids: list[Part.Shape] = []

    for outer_wire, hole_wires in classified:
        # Create face with holes
        if hole_wires:
            face = Part.Face(outer_wire)
            for hole in hole_wires:
                hole_face = Part.Face(hole)
                face = face.cut(hole_face)
        else:
            face = Part.Face(outer_wire)

        # Extrusion direction
        direction = FreeCAD.Vector(0, 0, spec.extrusion_height)

        if spec.symmetric:
            # Move face down by half height, then extrude full height
            offset = FreeCAD.Vector(0, 0, -spec.extrusion_height / 2)
            face.translate(offset)

        solid = face.extrude(direction)

        if not solid.isValid():
            FreeCAD.Console.PrintWarning(
                f"Warning: extruded solid failed validity check\n"
            )

        solids.append(solid)

    return solids


def extrude_and_export(spec: ExtrusionSpec) -> Path:
    """Extrude DXF profiles and export as STEP.

    Args:
        spec: Full extrusion specification.

    Returns:
        Path to the exported STEP file.
    """
    solids = extrude_profiles(spec)

    # Fuse all solids into a single compound
    if len(solids) == 1:
        result_shape = solids[0]
    else:
        result_shape = Part.makeCompound(solids)

    output = spec.output_path or spec.dxf_path.with_suffix(".step")

    # Export as STEP AP214
    result_shape.exportStep(str(output))
    return output


if __name__ == "__main__":
    spec = ExtrusionSpec(
        dxf_path=Path(sys.argv[1]),
        extrusion_height=float(sys.argv[2]) if len(sys.argv) > 2 else 10.0,
        layer_filter=sys.argv[3] if len(sys.argv) > 3 else None,
    )
    out = extrude_and_export(spec)
    print(f"Exported to {out}")
```

---

## FreeCAD Python Scripting

FreeCAD provides a full Python API for parametric modeling, mesh operations, and format I/O. Scripts can run inside the FreeCAD GUI or headless via `freecad -c script.py`.

### Part Module -- Parametric B-Rep Modeling

Key classes and methods in `Part`:

| API | Purpose |
|---|---|
| `Part.makeBox(l, w, h)` | Create a box primitive |
| `Part.makeCylinder(r, h)` | Create a cylinder primitive |
| `Part.makeSphere(r)` | Create a sphere primitive |
| `Part.makeCone(r1, r2, h)` | Create a cone/frustum |
| `Part.makeTorus(r1, r2)` | Create a torus |
| `Part.makePolygon(points)` | Create a wire from points |
| `Part.Face(wire)` | Create a face from a closed wire |
| `face.extrude(vector)` | Linear extrusion |
| `face.revolve(center, axis, angle)` | Revolution |
| `shape.fuse(other)` | Boolean union |
| `shape.cut(other)` | Boolean subtraction |
| `shape.common(other)` | Boolean intersection |
| `shape.fillet(radius, edges)` | Fillet (round) edges |
| `shape.chamfer(dist, edges)` | Chamfer edges |
| `shape.exportStep(path)` | Export to STEP |
| `shape.exportStl(path)` | Export to STL |
| `shape.exportBrep(path)` | Export to OpenCASCADE BREP |

### Mesh Module -- Triangle Mesh Operations

| API | Purpose |
|---|---|
| `Mesh.Mesh()` | Create empty mesh |
| `Mesh.Mesh(triangles)` | Create mesh from triangle list |
| `mesh.read(path)` | Import STL/OBJ/PLY |
| `mesh.write(path)` | Export to STL/OBJ/PLY |
| `mesh.unite(other)` | Boolean union on meshes |
| `mesh.difference(other)` | Boolean subtraction |
| `mesh.intersect(other)` | Boolean intersection |
| `mesh.decimate(target_faces)` | Reduce face count |
| `mesh.smooth()` | Laplacian smoothing |
| `mesh.removeDuplicatedFacets()` | Clean duplicate triangles |
| `mesh.removeDuplicatedPoints()` | Merge coincident vertices |
| `mesh.fixSelfIntersections()` | Repair self-intersections |
| `mesh.CountFacets` | Number of triangles |
| `mesh.CountPoints` | Number of vertices |
| `mesh.Volume` | Enclosed volume (if watertight) |
| `mesh.Area` | Total surface area |

### Import/Export Modules

| Module | Formats |
|---|---|
| `Import` | STEP, IGES (read/write via OpenCASCADE) |
| `importDXF` | DXF (read/write) |
| `importSVG` | SVG (read) |
| `Mesh` | STL, OBJ, PLY, OFF, AMF, 3MF (read/write) |

---

## ezdxf Library for DXF Reading/Writing

`ezdxf` is the premier Python library for DXF manipulation. It supports DXF R12 through R2018, provides a Pythonic API, and handles the full complexity of the DXF format including layouts, blocks, dimension styles, and hatches.

### Core Concepts

- **`Drawing`**: The top-level document object.
- **`Modelspace`**: The primary drawing space (model tab).
- **`Paperspace`**: Layout tabs for printing.
- **`Layout`**: Base class for Modelspace and Paperspace.
- **`DXFEntity`**: Base class for all DXF entities.
- **`BlockLayout`**: A named collection of entities that can be instanced via INSERT.

### Reading, Querying, and Writing DXF Files

```python
"""Production-quality DXF processing with ezdxf.

Dependencies:
    pip install ezdxf[draw] matplotlib shapely
"""
from __future__ import annotations

import math
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator, Sequence

import ezdxf
from ezdxf import bbox as ezdxf_bbox
from ezdxf.document import Drawing
from ezdxf.entities import DXFGraphic, LWPolyline, Line, Circle, Arc, Spline, Insert
from ezdxf.layouts import Modelspace
from ezdxf.math import Vec3, Matrix44, BoundingBox


@dataclass
class LayerStats:
    """Statistics for a single DXF layer."""

    name: str
    entity_count: int = 0
    entity_types: dict[str, int] = field(default_factory=lambda: defaultdict(int))
    bounding_box: BoundingBox | None = None


@dataclass
class DXFAnalysis:
    """Complete analysis of a DXF file."""

    file_path: Path
    dxf_version: str
    units: int
    units_name: str
    total_entities: int
    layers: dict[str, LayerStats]
    extents: BoundingBox | None


# Map $INSUNITS values to human-readable names
UNITS_MAP: dict[int, str] = {
    0: "Unitless",
    1: "Inches",
    2: "Feet",
    3: "Miles",
    4: "Millimeters",
    5: "Centimeters",
    6: "Meters",
    7: "Kilometers",
    8: "Microinches",
    9: "Mils",
    10: "Yards",
    11: "Angstroms",
    12: "Nanometers",
    13: "Microns",
    14: "Decimeters",
}

# Conversion factors from $INSUNITS to meters
UNITS_TO_METERS: dict[int, float] = {
    0: 1.0,         # Unitless -- treat as meters
    1: 0.0254,      # Inches
    2: 0.3048,      # Feet
    4: 0.001,       # Millimeters
    5: 0.01,        # Centimeters
    6: 1.0,         # Meters
    7: 1000.0,      # Kilometers
    13: 1e-6,       # Microns
    14: 0.1,        # Decimeters
}


def analyze_dxf(file_path: Path) -> DXFAnalysis:
    """Perform comprehensive analysis of a DXF file.

    Args:
        file_path: Path to the DXF file.

    Returns:
        DXFAnalysis with layer stats, units, and extents.

    Raises:
        FileNotFoundError: If the file does not exist.
        ezdxf.DXFError: If the file is not a valid DXF.
    """
    if not file_path.exists():
        raise FileNotFoundError(f"DXF file not found: {file_path}")

    doc: Drawing = ezdxf.readfile(str(file_path))
    msp: Modelspace = doc.modelspace()

    units = doc.header.get("$INSUNITS", 0)
    units_name = UNITS_MAP.get(units, f"Unknown ({units})")

    layers: dict[str, LayerStats] = {}
    total = 0

    for entity in msp:
        total += 1
        layer_name = entity.dxf.get("layer", "0")

        if layer_name not in layers:
            layers[layer_name] = LayerStats(name=layer_name)

        stats = layers[layer_name]
        stats.entity_count += 1
        stats.entity_types[entity.dxftype()] += 1

    # Compute overall bounding box
    extents = ezdxf_bbox.extents(msp)

    return DXFAnalysis(
        file_path=file_path,
        dxf_version=doc.dxfversion,
        units=units,
        units_name=units_name,
        total_entities=total,
        layers=layers,
        extents=extents if extents.has_data else None,
    )


def extract_closed_polylines(
    doc: Drawing,
    layer: str | None = None,
    min_vertices: int = 3,
) -> list[list[Vec3]]:
    """Extract closed polylines as lists of vertices.

    Args:
        doc: The ezdxf Drawing.
        layer: Optional layer filter.
        min_vertices: Minimum vertex count to include.

    Returns:
        List of vertex lists, each representing a closed polygon.
    """
    msp = doc.modelspace()
    result: list[list[Vec3]] = []

    query = msp.query("LWPOLYLINE")
    for entity in query:
        lwp: LWPolyline = entity  # type: ignore[assignment]

        if layer and lwp.dxf.get("layer", "0") != layer:
            continue

        if not lwp.closed:
            continue

        points = list(lwp.get_points(format="xyz"))
        if len(points) >= min_vertices:
            result.append([Vec3(p) for p in points])

    return result


def create_drawing_with_entities(
    output_path: Path,
    units: int = 4,
    dxf_version: str = "R2013",
) -> Drawing:
    """Create a new DXF drawing with standard setup.

    Args:
        output_path: Where to save the DXF file.
        units: $INSUNITS value (default 4 = mm).
        dxf_version: DXF version string.

    Returns:
        The ezdxf Drawing object (call doc.saveas() when done).
    """
    doc = ezdxf.new(dxf_version)
    doc.header["$INSUNITS"] = units

    # Create standard layers
    doc.layers.add("OUTLINE", color=7)       # White
    doc.layers.add("DIMENSIONS", color=1)    # Red
    doc.layers.add("HIDDEN", color=8)        # Dark gray
    doc.layers.add("CENTER", color=2)        # Yellow
    doc.layers.add("HOLES", color=3)         # Green
    doc.layers.add("TEXT", color=4)           # Cyan

    return doc


def write_rectangular_profile(
    doc: Drawing,
    center_x: float,
    center_y: float,
    width: float,
    height: float,
    layer: str = "OUTLINE",
    hole_diameter: float | None = None,
) -> None:
    """Write a rectangular profile with optional center hole.

    Args:
        doc: The ezdxf Drawing.
        center_x: Center X coordinate.
        center_y: Center Y coordinate.
        width: Rectangle width.
        height: Rectangle height.
        layer: Target layer name.
        hole_diameter: If set, add a circular hole at center.
    """
    msp = doc.modelspace()

    half_w = width / 2
    half_h = height / 2

    points = [
        (center_x - half_w, center_y - half_h),
        (center_x + half_w, center_y - half_h),
        (center_x + half_w, center_y + half_h),
        (center_x - half_w, center_y + half_h),
    ]

    msp.add_lwpolyline(
        points,
        close=True,
        dxfattribs={"layer": layer},
    )

    if hole_diameter is not None and hole_diameter > 0:
        msp.add_circle(
            center=(center_x, center_y),
            radius=hole_diameter / 2,
            dxfattribs={"layer": "HOLES"},
        )


def scale_drawing(doc: Drawing, scale_factor: float) -> None:
    """Scale all entities in modelspace by a uniform factor.

    Useful for unit conversion (e.g., inches to mm: scale_factor=25.4).

    Args:
        doc: The ezdxf Drawing.
        scale_factor: Uniform scale multiplier.
    """
    msp = doc.modelspace()
    matrix = Matrix44.scale(scale_factor, scale_factor, scale_factor)

    for entity in msp:
        try:
            entity.transform(matrix)
        except (AttributeError, ezdxf.DXFError):
            pass  # Some entity types do not support transformation


def convert_units(
    doc: Drawing,
    from_units: int,
    to_units: int,
) -> None:
    """Convert all geometry from one unit system to another.

    Args:
        doc: The ezdxf Drawing.
        from_units: Source $INSUNITS value.
        to_units: Target $INSUNITS value.

    Raises:
        ValueError: If either unit system is not in UNITS_TO_METERS.
    """
    if from_units not in UNITS_TO_METERS:
        raise ValueError(f"Unsupported source units: {from_units}")
    if to_units not in UNITS_TO_METERS:
        raise ValueError(f"Unsupported target units: {to_units}")

    factor = UNITS_TO_METERS[from_units] / UNITS_TO_METERS[to_units]

    if abs(factor - 1.0) < 1e-12:
        return  # Same units, nothing to do

    scale_drawing(doc, factor)
    doc.header["$INSUNITS"] = to_units
```

### ezdxf Addons

| Addon | Purpose |
|---|---|
| `ezdxf.addons.drawing` | Render DXF to matplotlib, SVG, or PyQt |
| `ezdxf.addons.geo` | Convert DXF geometry to GeoJSON and Shapely |
| `ezdxf.addons.text2path` | Convert text entities to outline paths |
| `ezdxf.addons.dxf2code` | Generate Python code that recreates a DXF file |
| `ezdxf.addons.odafc` | Wrapper around ODA File Converter for DWG support |
| `ezdxf.addons.meshex` | Export/import mesh data (experimental) |

---

## Best Practices

### Format Selection

1. **Use STEP (AP242) as the canonical exchange format** for B-Rep solids. It preserves topology, units, colors, and assembly structure. Prefer AP242 over AP203/AP214 for new projects.
2. **Use DXF for 2D drawings and laser/CNC profiles.** DXF R2013+ supports all common 2D entity types. Avoid DXF for 3D solids (the 3DSOLID entity contains proprietary ACIS data).
3. **Use STL only as a terminal format** for 3D printing slicer input or FEA meshing. Never use STL as an intermediate exchange format -- it loses topology, units, and metadata.
4. **Use OBJ for visualization meshes** when texture coordinates and material assignments are needed but PBR is not required.
5. **Use glTF 2.0 (.glb) for web/AR/VR delivery.** It is the "JPEG of 3D" -- compact, fast to load, supports PBR materials and animations.

### Tessellation Quality

6. **Set linear deflection relative to part size.** A good starting point is 0.1% of the bounding box diagonal. For a 100mm part, use 0.1mm deflection.
7. **Set angular deflection to 0.5 radians** (about 28 degrees) as a default. Reduce to 0.1-0.2 for parts with small fillets or detailed curvature.
8. **Always verify watertightness** after tessellation. Use `trimesh.is_watertight` or OpenCASCADE shape analysis.

### Unit Handling

9. **Establish a project-wide convention** and document it. Mechanical engineering typically uses millimeters; architecture uses meters or feet; 3D printing uses millimeters.
10. **Always read and respect the source file's unit metadata.** Do not assume units. Parse `$INSUNITS` from DXF, `SI_UNIT` from STEP, and global parameter 14 from IGES.
11. **Convert to the target format's canonical unit early in the pipeline.** For glTF, convert to meters. For 3D printing STL, convert to millimeters.
12. **Include unit conversion validation**: compare bounding box dimensions before and after conversion to catch scaling errors.

### Pipeline Robustness

13. **Validate geometry at each pipeline stage.** Check for degenerate triangles, non-manifold edges, duplicate vertices, and self-intersections.
14. **Log warnings instead of raising exceptions for non-critical geometry issues.** CAD files from the wild are messy -- zero-area faces, tiny gaps, and overlapping geometry are common.
15. **Use deterministic mesh processing.** Avoid algorithms that produce different results on different runs (e.g., randomized decimation). This enables reproducible builds.
16. **Version-pin your CAD libraries.** OpenCASCADE, FreeCAD, and ezdxf can produce subtly different tessellation results across versions.

### FreeCAD Scripting

17. **Always call `doc.recompute()` after modifying geometry.** FreeCAD uses lazy evaluation; shapes are not updated until recompute.
18. **Close documents when done** to free memory: `FreeCAD.closeDocument(doc.Name)`.
19. **Use `Part.Shape.isValid()` to verify solids** after boolean operations. Boolean operations in OpenCASCADE can silently produce invalid geometry.
20. **Prefer `Part.makeCompound` over `Part.fuse` for multi-body exports** when boolean union is not needed. Fuse is expensive and can fail on complex geometry.

### DXF with ezdxf

21. **Always specify `dxf_version` when creating new documents.** Use `R2013` or later for full Unicode and true-color support.
22. **Use `ezdxf.readfile()` for trusted files and `ezdxf.recover.readfile()` for untrusted files.** The recovery mode handles malformed DXF files gracefully.
23. **Work with LWPOLYLINE instead of legacy POLYLINE** for 2D geometry. LWPOLYLINE is more compact and easier to process.
24. **Use `entity.transform(Matrix44)` for coordinate transformations** rather than manually modifying point coordinates. This handles all entity types correctly.

---

## Anti-Patterns

### Losing Precision by Using STL as Interchange

**Wrong**: Converting STEP to STL, then STL to another B-Rep format.
```
STEP -> STL -> back to STEP  (BAD: irreversible precision loss)
```
STL discards all B-Rep topology. Once tessellated, you cannot recover exact cylinder radii, fillet dimensions, or surface tangency. The reverse conversion produces a dense mesh solid, not clean parametric geometry.

**Correct**: Keep B-Rep formats (STEP, IGES, BREP) in the pipeline as long as possible. Only tessellate at the final delivery stage.
```
STEP -> (process as B-Rep) -> STL/glTF for delivery
```

### Ignoring Units

**Wrong**: Assuming all CAD files use millimeters.
```python
# BAD: blind assumption
mesh.apply_scale(0.001)  # "mm to meters" -- but what if the file was in inches?
```

**Correct**: Read units from file metadata and compute the correct conversion factor.
```python
# GOOD: read actual units
insunits = doc.header.get("$INSUNITS", 0)
factor = UNITS_TO_METERS.get(insunits, 1.0) / target_meters_factor
mesh.apply_scale(factor)
```

### Ignoring Coordinate System Conventions

**Wrong**: Importing a Z-up STEP model directly into a Y-up glTF viewer without axis conversion. The model appears lying on its back.

**Correct**: Apply the appropriate rotation matrix during conversion (see Coordinate System Conventions section). Always document which convention your pipeline expects.

### Treating DXF as Simple Geometry

**Wrong**: Parsing only LINE and CIRCLE entities from a DXF file and ignoring everything else.

Many real-world DXF files use LWPOLYLINE with bulge values (arc segments), SPLINE, ELLIPSE, INSERT (block references with transformations), and HATCH. Ignoring these entities produces incomplete geometry.

**Correct**: Handle all common entity types. Use `ezdxf` which provides a complete parser and supports entity queries by type.

### Hardcoding Tessellation Parameters

**Wrong**: Using a single fixed deflection value for all parts.
```python
# BAD: 0.1mm deflection is too coarse for a watch part, too fine for a building
BRepMesh_IncrementalMesh(shape, 0.1, False, 0.5, True)
```

**Correct**: Scale tessellation parameters relative to the part's bounding box diagonal.
```python
bbox = Bnd_Box()
BRepBndLib.Add_s(shape, bbox)
diagonal = bbox.CornerMin().Distance(bbox.CornerMax())
linear_deflection = diagonal * 0.001  # 0.1% of diagonal
```

### Boolean Operations Without Validation

**Wrong**: Chaining boolean operations without checking intermediate results.
```python
# BAD: no validation
result = base.fuse(feature1).cut(hole1).cut(hole2).fillet(1.0, edges)
```

OpenCASCADE boolean operations can fail silently, producing self-intersecting or non-manifold shapes. Subsequent operations on invalid shapes may crash or produce garbage.

**Correct**: Validate after each boolean step.
```python
result = base.fuse(feature1)
if not result.isValid():
    raise RuntimeError("Fuse operation produced invalid geometry")
result = result.cut(hole1)
if not result.isValid():
    raise RuntimeError("Cut operation produced invalid geometry")
```

### Using Legacy POLYLINE Instead of LWPOLYLINE

**Wrong**: Creating 2D polylines with the legacy `POLYLINE`/`VERTEX` entity structure. This is verbose, harder to parse, and not supported by all lightweight DXF readers.

**Correct**: Use `LWPOLYLINE` for all 2D polylines. Reserve `POLYLINE` only for true 3D polylines or polymeshes that LWPOLYLINE cannot represent.

### Fusing Large Assemblies

**Wrong**: Using `Part.fuse()` to combine hundreds of parts into a single solid for export.

This is extremely slow (O(n^2) or worse), prone to failure with complex geometry, and destroys assembly structure.

**Correct**: Use `Part.makeCompound()` to group parts without boolean union. Export assemblies as STEP with proper product structure, not as monolithic solids.

### Ignoring the OCS (Object Coordinate System) in DXF

**Wrong**: Reading X, Y coordinates from DXF entities and assuming they are in the World Coordinate System.

DXF 2D entities can have an extrusion direction (group codes 210/220/230) that defines a local Object Coordinate System. Entities with non-default extrusion directions have their coordinates in OCS, not WCS.

**Correct**: Use `ezdxf`'s built-in OCS-to-WCS transformation. Most ezdxf entity methods already return WCS coordinates, but when working with raw group code data, always apply the arbitrary axis algorithm.

---

## Sources & References

1. **ISO 10303-21 (STEP Physical File Format)**: Official standard defining the STEP file syntax and encoding. Available from ISO at https://www.iso.org/standard/63141.html

2. **ezdxf Documentation**: Comprehensive reference for the ezdxf Python library covering DXF reading, writing, entity manipulation, and addons. https://ezdxf.readthedocs.io/en/stable/

3. **FreeCAD Python Scripting Documentation**: Official FreeCAD wiki covering the Part module, Mesh module, and scripting interface. https://wiki.freecad.org/Power_users_hub

4. **OpenCASCADE Technology Documentation**: Reference for the OCCT kernel used by FreeCAD, PythonOCC, and CadQuery for B-Rep operations, tessellation, and STEP/IGES I/O. https://dev.opencascade.org/doc/overview/html/index.html

5. **Autodesk DXF Reference**: Official Autodesk documentation for the DXF file format, including all group codes, entity types, and header variables. https://help.autodesk.com/view/OARX/2024/ENU/?guid=GUID-235B22E0-A567-4CF6-92D3-38A2306D73F3

6. **Open Design Alliance (ODA) -- DWG/DXF File Format**: The ODA maintains the most complete reverse-engineered DWG specification and provides the ODA File Converter for DWG/DXF conversion. https://www.opendesign.com/guestfiles/oda_file_converter

7. **Khronos glTF 2.0 Specification**: The official specification for glTF, the target format for web/AR delivery of tessellated CAD geometry. https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html

8. **CadQuery Documentation**: Python library built on OCP (OpenCASCADE) providing a fluent API for parametric CAD modeling, used as an alternative to FreeCAD scripting. https://cadquery.readthedocs.io/en/latest/

9. **trimesh Documentation**: Python library for loading, processing, and exporting triangular meshes. Essential for the tessellation-to-delivery stage of CAD conversion pipelines. https://trimesh.org/

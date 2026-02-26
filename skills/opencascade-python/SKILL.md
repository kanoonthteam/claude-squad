---
name: opencascade-python
description: OpenCASCADE Technology via pythonocc-core for 3D CAD engineering — BRep topology, shape analysis, STEP/IGES import/export, mesh triangulation, mass properties, boolean operations, and coordinate transforms
---

# OpenCASCADE Python (pythonocc-core)

Production-quality patterns for 3D CAD engineering with pythonocc-core, the Python binding for OpenCASCADE Technology (OCCT). Covers BRep topology traversal, STEP/IGES file interchange, mesh triangulation, bounding box computation, mass properties (volume, surface area, center of gravity), boolean operations, shape analysis, and coordinate system transforms.

## Table of Contents

1. [Installation & Environment Setup](#installation--environment-setup)
2. [OpenCASCADE Architecture Overview](#opencascade-architecture-overview)
3. [TopoDS_Shape Hierarchy](#topods_shape-hierarchy)
4. [TopExp_Explorer — Topology Traversal](#topexp_explorer--topology-traversal)
5. [BRep_Tool — Geometry Extraction from Topology](#brep_tool--geometry-extraction-from-topology)
6. [STEP File Import & Export](#step-file-import--export)
7. [IGES File Import & Export](#iges-file-import--export)
8. [BRepMesh_IncrementalMesh — Triangulation](#brepmesh_incrementalmesh--triangulation)
9. [Extracting Triangulated Mesh Data](#extracting-triangulated-mesh-data)
10. [Bounding Box Computation](#bounding-box-computation)
11. [GProp — Mass Properties](#gprop--mass-properties)
12. [Shape Analysis](#shape-analysis)
13. [Boolean Operations](#boolean-operations)
14. [Coordinate System Transforms](#coordinate-system-transforms)
15. [Performance: Mesh Quality vs Speed Tradeoffs](#performance-mesh-quality-vs-speed-tradeoffs)
16. [Best Practices](#best-practices)
17. [Anti-Patterns](#anti-patterns)
18. [Sources & References](#sources--references)

---

## Installation & Environment Setup

pythonocc-core wraps the OpenCASCADE Technology (OCCT) C++ library via SWIG-generated bindings. The recommended installation uses conda/mamba because OCCT has complex C++ dependencies that pip cannot resolve reliably.

### Conda Installation (Recommended)

```bash
# Create a dedicated environment — OCCT native libs can conflict with other packages
conda create -n cad python=3.11 -y
conda activate cad

# Install pythonocc-core from conda-forge (includes OCCT 7.7+)
conda install -c conda-forge pythonocc-core=7.8.1

# Optional: visualization backends
conda install -c conda-forge pythonocc-display-simple
pip install numpy trimesh
```

### Mamba Installation (Faster Dependency Resolution)

```bash
mamba create -n cad python=3.11 -y
mamba activate cad
mamba install -c conda-forge pythonocc-core=7.8.1
```

### Verifying the Installation

```python
from OCC.Core.BRepPrimAPI import BRepPrimAPI_MakeBox
from OCC.Core.TopoDS import TopoDS_Shape

box: TopoDS_Shape = BRepPrimAPI_MakeBox(10.0, 20.0, 30.0).Shape()
print(f"Shape type: {box.ShapeType()}")  # TopAbs_SOLID (2)
```

### Docker Setup for CI/CD

```dockerfile
FROM condaforge/mambaforge:latest
RUN mamba install -y -c conda-forge pythonocc-core=7.8.1 python=3.11 numpy
WORKDIR /app
COPY . .
CMD ["python", "process_step.py"]
```

### Key Import Conventions

All OCCT classes live under `OCC.Core.<ModuleName>`. The module name matches the OCCT C++ package name:

| Python Module | OCCT Package | Purpose |
|---|---|---|
| `OCC.Core.TopoDS` | TopoDS | Topological data structures |
| `OCC.Core.TopExp` | TopExp | Topology exploration |
| `OCC.Core.TopAbs` | TopAbs | Topology enumerations |
| `OCC.Core.BRep` | BRep | BRep-specific geometry queries |
| `OCC.Core.BRepTools` | BRepTools | BRep utility operations |
| `OCC.Core.BRepMesh` | BRepMesh | Mesh generation |
| `OCC.Core.BRepPrimAPI` | BRepPrimAPI | Primitive shape creation |
| `OCC.Core.BRepAlgoAPI` | BRepAlgoAPI | Boolean operations |
| `OCC.Core.BRepBndLib` | BRepBndLib | Bounding box from BRep |
| `OCC.Core.BRepGProp` | BRepGProp | Global mass properties |
| `OCC.Core.BRepBuilderAPI` | BRepBuilderAPI | Shape construction |
| `OCC.Core.BRepCheck` | BRepCheck | Shape validity checking |
| `OCC.Core.STEPControl` | STEPControl | STEP file read/write |
| `OCC.Core.IGESControl` | IGESControl | IGES file read/write |
| `OCC.Core.gp` | gp | Geometric primitives (points, vectors, transforms) |
| `OCC.Core.GProp` | GProp | General properties containers |
| `OCC.Core.Bnd` | Bnd | Bounding volumes |
| `OCC.Core.ShapeAnalysis` | ShapeAnalysis | Shape analysis tools |

---

## OpenCASCADE Architecture Overview

OCCT uses a layered architecture where **topology** (combinatorial structure) is separated from **geometry** (mathematical surface/curve definitions). This separation is called Boundary Representation (BRep).

**Topology layer** describes how shapes are connected:
- A Solid is bounded by Shells
- A Shell is a connected set of Faces
- A Face is bounded by Wires
- A Wire is an ordered sequence of Edges
- An Edge is bounded by Vertices

**Geometry layer** describes the mathematical definition:
- A Face references a Surface (plane, cylinder, BSpline, etc.)
- An Edge references a Curve (line, circle, BSpline, etc.)
- A Vertex references a Point (gp_Pnt)

The BRep_Tool class bridges these two layers, letting you extract geometry from topological entities.

### OCCT Memory Management

OCCT uses reference-counted handles (`opencascade::handle<T>`) for geometry objects. In pythonocc-core, these are managed automatically by the Python bindings. However, be aware:

- TopoDS_Shape objects are lightweight wrappers (they share underlying data via `TopoDS_TShape`)
- Copying a TopoDS_Shape does NOT deep-copy the geometry
- Use `BRepBuilderAPI_Copy` for true deep copies when you need independent modification

---

## TopoDS_Shape Hierarchy

The `TopoDS_Shape` class is the base type. Specific sub-types form a strict hierarchy:

```
TopoDS_Shape (abstract base)
├── TopoDS_Compound      — collection of any shapes (TopAbs_COMPOUND)
├── TopoDS_CompSolid     — collection of solids sharing faces (TopAbs_COMPSOLID)
├── TopoDS_Solid         — closed volume bounded by shells (TopAbs_SOLID)
├── TopoDS_Shell         — connected set of faces (TopAbs_SHELL)
├── TopoDS_Face          — bounded portion of a surface (TopAbs_FACE)
├── TopoDS_Wire          — ordered sequence of edges (TopAbs_WIRE)
├── TopoDS_Edge          — bounded portion of a curve (TopAbs_EDGE)
└── TopoDS_Vertex        — point in 3D space (TopAbs_VERTEX)
```

### Shape Type Enumeration

`TopAbs_ShapeEnum` defines the shape type hierarchy order:

| Enum Value | Integer | Description |
|---|---|---|
| `TopAbs_COMPOUND` | 0 | Generic collection |
| `TopAbs_COMPSOLID` | 1 | Composite solid |
| `TopAbs_SOLID` | 2 | Closed volume |
| `TopAbs_SHELL` | 3 | Connected faces |
| `TopAbs_FACE` | 4 | Surface patch |
| `TopAbs_WIRE` | 5 | Edge loop |
| `TopAbs_EDGE` | 6 | Curve segment |
| `TopAbs_VERTEX` | 7 | Point |
| `TopAbs_SHAPE` | 8 | Abstract base |

### Downcasting TopoDS_Shape

OCCT uses explicit downcasting via `topods.Xxx()` functions. You must downcast before accessing sub-type-specific methods:

```python
from OCC.Core.TopoDS import topods, TopoDS_Face, TopoDS_Edge, TopoDS_Vertex
from OCC.Core.TopAbs import TopAbs_FACE

shape: TopoDS_Shape = ...  # some shape from an explorer or reader

# Downcast to specific type
if shape.ShapeType() == TopAbs_FACE:
    face: TopoDS_Face = topods.Face(shape)
```

### Orientation

Every TopoDS_Shape carries an `Orientation` — either `TopAbs_FORWARD` or `TopAbs_REVERSED`. This determines the direction of the surface normal for faces and the parametric direction for edges. Orientation is critical for:

- Boolean operations (defines inside vs outside)
- Mesh normal generation
- Volume calculation sign

---

## TopExp_Explorer — Topology Traversal

`TopExp_Explorer` iterates over sub-shapes of a given type within a shape. It is the primary tool for decomposing any shape into its topological components.

### Constructor Signature

```
TopExp_Explorer(shape: TopoDS_Shape, to_find: TopAbs_ShapeEnum, to_avoid: TopAbs_ShapeEnum = TopAbs_SHAPE)
```

- `to_find`: the type of sub-shape to iterate over
- `to_avoid`: skip sub-shapes contained within this type (default: no avoidance)

### Comprehensive Topology Traversal Example

```python
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from OCC.Core.BRep import BRep_Tool
from OCC.Core.BRepBndLib import brepbndlib
from OCC.Core.BRepGProp import brepgprop
from OCC.Core.Bnd import Bnd_Box
from OCC.Core.GProp import GProp_GProps
from OCC.Core.STEPControl import STEPControl_Reader
from OCC.Core.TopAbs import (
    TopAbs_COMPOUND,
    TopAbs_EDGE,
    TopAbs_FACE,
    TopAbs_SHELL,
    TopAbs_SOLID,
    TopAbs_VERTEX,
    TopAbs_WIRE,
)
from OCC.Core.TopExp import TopExp_Explorer
from OCC.Core.TopoDS import TopoDS_Shape, topods
from OCC.Core.gp import gp_Pnt


@dataclass
class ShapeReport:
    """Topology statistics for a CAD shape."""

    num_compounds: int = 0
    num_solids: int = 0
    num_shells: int = 0
    num_faces: int = 0
    num_wires: int = 0
    num_edges: int = 0
    num_vertices: int = 0
    volume: float = 0.0
    surface_area: float = 0.0
    center_of_gravity: tuple[float, float, float] = (0.0, 0.0, 0.0)
    bounding_box_min: tuple[float, float, float] = (0.0, 0.0, 0.0)
    bounding_box_max: tuple[float, float, float] = (0.0, 0.0, 0.0)
    face_types: dict[str, int] = field(default_factory=dict)


def count_subshapes(shape: TopoDS_Shape, shape_type: int) -> int:
    """Count sub-shapes of a given type using TopExp_Explorer."""
    count: int = 0
    explorer = TopExp_Explorer(shape, shape_type)
    while explorer.More():
        count += 1
        explorer.Next()
    return count


def collect_faces(shape: TopoDS_Shape) -> list[TopoDS_Shape]:
    """Collect all faces from a shape into a list."""
    faces: list[TopoDS_Shape] = []
    explorer = TopExp_Explorer(shape, TopAbs_FACE)
    while explorer.More():
        faces.append(explorer.Current())
        explorer.Next()
    return faces


def collect_vertices(shape: TopoDS_Shape) -> list[gp_Pnt]:
    """Extract all unique vertex positions from a shape."""
    points: list[gp_Pnt] = []
    explorer = TopExp_Explorer(shape, TopAbs_VERTEX)
    while explorer.More():
        vertex = topods.Vertex(explorer.Current())
        pnt: gp_Pnt = BRep_Tool.Pnt(vertex)
        points.append(pnt)
        explorer.Next()
    return points


def analyze_shape(shape: TopoDS_Shape) -> ShapeReport:
    """Produce a full topology and geometry report for a shape."""
    report = ShapeReport()

    # Count all topological entities
    report.num_compounds = count_subshapes(shape, TopAbs_COMPOUND)
    report.num_solids = count_subshapes(shape, TopAbs_SOLID)
    report.num_shells = count_subshapes(shape, TopAbs_SHELL)
    report.num_faces = count_subshapes(shape, TopAbs_FACE)
    report.num_wires = count_subshapes(shape, TopAbs_WIRE)
    report.num_edges = count_subshapes(shape, TopAbs_EDGE)
    report.num_vertices = count_subshapes(shape, TopAbs_VERTEX)

    # Volume and surface area
    vol_props = GProp_GProps()
    brepgprop.VolumeProperties(shape, vol_props)
    report.volume = vol_props.Mass()
    cog: gp_Pnt = vol_props.CentreOfMass()
    report.center_of_gravity = (cog.X(), cog.Y(), cog.Z())

    surf_props = GProp_GProps()
    brepgprop.SurfaceProperties(shape, surf_props)
    report.surface_area = surf_props.Mass()

    # Bounding box
    bbox = Bnd_Box()
    brepbndlib.Add(shape, bbox)
    xmin, ymin, zmin, xmax, ymax, zmax = bbox.Get()
    report.bounding_box_min = (xmin, ymin, zmin)
    report.bounding_box_max = (xmax, ymax, zmax)

    return report


def load_step_and_analyze(step_path: str | Path) -> ShapeReport:
    """Load a STEP file and return a full shape analysis report."""
    reader = STEPControl_Reader()
    status = reader.ReadFile(str(step_path))
    if status != 1:  # IFSelect_RetDone
        raise RuntimeError(f"Failed to read STEP file: {step_path} (status={status})")
    reader.TransferRoots()
    shape: TopoDS_Shape = reader.OneShape()
    return analyze_shape(shape)


if __name__ == "__main__":
    report = load_step_and_analyze("part.step")
    print(f"Faces: {report.num_faces}, Edges: {report.num_edges}")
    print(f"Volume: {report.volume:.4f}")
    print(f"Surface area: {report.surface_area:.4f}")
    print(f"Center of gravity: {report.center_of_gravity}")
    print(f"Bounding box: {report.bounding_box_min} -> {report.bounding_box_max}")
```

### Using `to_avoid` Parameter

The `to_avoid` parameter skips sub-shapes inside a particular topological level. This is useful for getting only the "free" edges not contained in any wire:

```python
# Get edges that are NOT inside any wire (free edges)
explorer = TopExp_Explorer(shape, TopAbs_EDGE, TopAbs_WIRE)
```

### TopExp_MapOfShape for Unique Sub-shapes

`TopExp_Explorer` may visit the same sub-shape multiple times if it appears in multiple parents. Use `TopTools_IndexedMapOfShape` for unique counts:

```python
from OCC.Core.TopExp import topexp
from OCC.Core.TopTools import TopTools_IndexedMapOfShape

face_map = TopTools_IndexedMapOfShape()
topexp.MapShapes(shape, TopAbs_FACE, face_map)
unique_face_count: int = face_map.Extent()
```

---

## BRep_Tool — Geometry Extraction from Topology

`BRep_Tool` is the bridge between topology and geometry. It extracts geometric definitions from topological entities.

### Vertex to Point

```python
from OCC.Core.BRep import BRep_Tool
from OCC.Core.TopoDS import topods
from OCC.Core.gp import gp_Pnt

vertex = topods.Vertex(explorer.Current())
point: gp_Pnt = BRep_Tool.Pnt(vertex)
x, y, z = point.X(), point.Y(), point.Z()
tolerance: float = BRep_Tool.Tolerance(vertex)
```

### Edge to Curve

```python
from OCC.Core.BRep import BRep_Tool
from OCC.Core.TopoDS import topods
from OCC.Core.Geom import Geom_Curve

edge = topods.Edge(explorer.Current())
curve_handle, u_start, u_end = BRep_Tool.Curve(edge)
if curve_handle is not None:
    curve: Geom_Curve = curve_handle
    mid_param: float = (u_start + u_end) / 2.0
    mid_point: gp_Pnt = curve.Value(mid_param)
```

### Face to Surface

```python
from OCC.Core.BRep import BRep_Tool
from OCC.Core.TopoDS import topods
from OCC.Core.Geom import Geom_Surface
from OCC.Core.GeomAbs import GeomAbs_Plane, GeomAbs_Cylinder
from OCC.Core.BRepAdaptor import BRepAdaptor_Surface

face = topods.Face(explorer.Current())
surface_handle = BRep_Tool.Surface(face)

# Use adaptor for surface type classification
adaptor = BRepAdaptor_Surface(face)
surface_type = adaptor.GetType()  # returns GeomAbs_SurfaceType enum

if surface_type == GeomAbs_Plane:
    plane = adaptor.Plane()
    normal = plane.Axis().Direction()
elif surface_type == GeomAbs_Cylinder:
    cylinder = adaptor.Cylinder()
    radius: float = cylinder.Radius()
```

### Face Triangulation Access

After meshing, `BRep_Tool.Triangulation` gives the mesh data for a face:

```python
from OCC.Core.BRep import BRep_Tool
from OCC.Core.TopLoc import TopLoc_Location

face = topods.Face(explorer.Current())
location = TopLoc_Location()
triangulation = BRep_Tool.Triangulation(face, location)

if triangulation is not None:
    nb_nodes: int = triangulation.NbNodes()
    nb_triangles: int = triangulation.NbTriangles()
```

---

## STEP File Import & Export

STEP (ISO 10303) is the most widely used CAD interchange format. OCCT provides `STEPControl_Reader` and `STEPControl_Writer`.

### STEP Import

```python
from __future__ import annotations

from pathlib import Path

from OCC.Core.IFSelect import IFSelect_RetDone
from OCC.Core.STEPControl import STEPControl_Reader
from OCC.Core.TopoDS import TopoDS_Shape


def read_step_file(file_path: str | Path) -> TopoDS_Shape:
    """
    Read a STEP file and return the combined shape.

    Raises:
        FileNotFoundError: If the STEP file does not exist.
        RuntimeError: If the STEP reader fails to parse or transfer.
    """
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"STEP file not found: {path}")

    reader = STEPControl_Reader()

    # ReadFile returns IFSelect_ReturnStatus
    status = reader.ReadFile(str(path))
    if status != IFSelect_RetDone:
        raise RuntimeError(
            f"STEPControl_Reader.ReadFile failed with status {status} "
            f"for file: {path}"
        )

    # Check how many root entities are in the file
    num_roots: int = reader.NbRootsForTransfer()
    if num_roots == 0:
        raise RuntimeError(f"No transferable roots found in STEP file: {path}")

    # Transfer all roots from the STEP model to OCCT shapes
    transfer_count: int = reader.TransferRoots()
    if transfer_count == 0:
        raise RuntimeError(f"Transfer failed — 0 shapes transferred from: {path}")

    # OneShape() returns a compound if multiple roots, single shape otherwise
    shape: TopoDS_Shape = reader.OneShape()
    if shape.IsNull():
        raise RuntimeError(f"Resulting shape is null after transfer from: {path}")

    return shape


def read_step_as_list(file_path: str | Path) -> list[TopoDS_Shape]:
    """
    Read a STEP file and return individual root shapes as a list.
    Useful when a STEP file contains multiple independent bodies.
    """
    path = Path(file_path)
    reader = STEPControl_Reader()
    status = reader.ReadFile(str(path))
    if status != IFSelect_RetDone:
        raise RuntimeError(f"Failed to read STEP file: {path}")

    shapes: list[TopoDS_Shape] = []
    num_roots: int = reader.NbRootsForTransfer()
    for i in range(1, num_roots + 1):
        reader.TransferRoot(i)
    for i in range(1, reader.NbShapes() + 1):
        shapes.append(reader.Shape(i))
    return shapes
```

### STEP Export

```python
from __future__ import annotations

from pathlib import Path

from OCC.Core.IFSelect import IFSelect_RetDone
from OCC.Core.Interface import Interface_Static
from OCC.Core.STEPControl import (
    STEPControl_AsIs,
    STEPControl_ManifoldSolidBrep,
    STEPControl_Writer,
)
from OCC.Core.TopoDS import TopoDS_Shape


def write_step_file(
    shape: TopoDS_Shape,
    file_path: str | Path,
    *,
    application_protocol: str = "AP214",
    author: str = "",
    organization: str = "",
) -> None:
    """
    Write a shape to a STEP file.

    Args:
        shape: The OCCT shape to export.
        file_path: Output STEP file path.
        application_protocol: "AP203" (config control) or "AP214" (automotive).
        author: Optional author metadata.
        organization: Optional organization metadata.

    Raises:
        ValueError: If shape is null.
        RuntimeError: If the write operation fails.
    """
    if shape.IsNull():
        raise ValueError("Cannot write a null shape to STEP file")

    path = Path(file_path)
    path.parent.mkdir(parents=True, exist_ok=True)

    writer = STEPControl_Writer()

    # Set the application protocol
    if application_protocol == "AP203":
        Interface_Static.SetCVal("write.step.schema", "AP203")
    else:
        Interface_Static.SetCVal("write.step.schema", "AP214IS")

    # Set units to millimeters (most common in CAD)
    Interface_Static.SetCVal("write.step.unit", "MM")

    # Set optional metadata
    if author:
        Interface_Static.SetCVal("write.step.author", author)
    if organization:
        Interface_Static.SetCVal("write.step.organization", organization)

    # Transfer the shape — STEPControl_AsIs preserves original type
    transfer_status = writer.Transfer(shape, STEPControl_AsIs)
    if transfer_status != IFSelect_RetDone:
        raise RuntimeError(
            f"STEP transfer failed with status {transfer_status}"
        )

    # Write to disk
    write_status = writer.Write(str(path))
    if write_status != IFSelect_RetDone:
        raise RuntimeError(
            f"STEP write failed with status {write_status} for: {path}"
        )
```

### STEP Transfer Modes

| Mode | Constant | Use Case |
|---|---|---|
| As-Is | `STEPControl_AsIs` | Preserve original shape type (recommended default) |
| Manifold Solid BRep | `STEPControl_ManifoldSolidBrep` | Force solid representation |
| Faceted BRep | `STEPControl_FacetedBrep` | Planar faces only (simplified) |
| Shell Based | `STEPControl_ShellBasedSurfaceModel` | Open shells / surface models |
| Geometric Curve Set | `STEPControl_GeometricCurveSet` | Wireframe / curves only |

---

## IGES File Import & Export

IGES (Initial Graphics Exchange Specification) is an older but still common CAD interchange format, especially in legacy systems and aerospace.

### IGES Import

```python
from __future__ import annotations

from pathlib import Path

from OCC.Core.IGESControl import IGESControl_Reader
from OCC.Core.IFSelect import IFSelect_RetDone
from OCC.Core.TopoDS import TopoDS_Shape


def read_iges_file(file_path: str | Path) -> TopoDS_Shape:
    """
    Read an IGES file and return the combined shape.

    IGES files often contain surfaces rather than solids.
    Use ShapeUpgrade_UnifySameDomain or sewing if you need
    to reconstruct solids from imported surfaces.
    """
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"IGES file not found: {path}")

    reader = IGESControl_Reader()
    status = reader.ReadFile(str(path))
    if status != IFSelect_RetDone:
        raise RuntimeError(f"Failed to read IGES file: {path} (status={status})")

    reader.TransferRoots()
    shape: TopoDS_Shape = reader.OneShape()

    if shape.IsNull():
        raise RuntimeError(f"Null shape after IGES transfer: {path}")

    return shape
```

### IGES Export

```python
from __future__ import annotations

from pathlib import Path

from OCC.Core.IGESControl import IGESControl_Writer
from OCC.Core.Interface import Interface_Static
from OCC.Core.TopoDS import TopoDS_Shape


def write_iges_file(
    shape: TopoDS_Shape,
    file_path: str | Path,
    *,
    brep_mode: int = 1,
) -> None:
    """
    Write a shape to an IGES file.

    Args:
        shape: The shape to export.
        file_path: Output path.
        brep_mode: 0 = faces as trimmed surfaces, 1 = BRep entities (default).
    """
    if shape.IsNull():
        raise ValueError("Cannot export null shape to IGES")

    path = Path(file_path)
    path.parent.mkdir(parents=True, exist_ok=True)

    writer = IGESControl_Writer()
    Interface_Static.SetIVal("write.iges.brep.mode", brep_mode)

    writer.AddShape(shape)
    writer.ComputeModel()
    success: bool = writer.Write(str(path))

    if not success:
        raise RuntimeError(f"IGES write failed for: {path}")
```

### IGES vs STEP Comparison

| Feature | STEP (AP214) | IGES |
|---|---|---|
| Solids | Full support | Limited |
| Surfaces | Full support | Good |
| Colors/Layers | Full support | Basic |
| Assembly structure | Full support | Not supported |
| File size | Smaller | Larger |
| Precision | Higher | Lower (legacy format) |
| Recommendation | Preferred for new projects | Use for legacy interop |

---

## BRepMesh_IncrementalMesh — Triangulation

Before extracting mesh data (vertices, triangles, normals), you must triangulate the shape. `BRepMesh_IncrementalMesh` computes a triangulation for all faces.

### Key Parameters

| Parameter | Type | Description |
|---|---|---|
| `theShape` | `TopoDS_Shape` | Shape to triangulate |
| `theLinDeflection` | `float` | Maximum distance between mesh edge and actual curve (chord height). Smaller = finer mesh. |
| `isRelative` | `bool` | If `True`, `theLinDeflection` is relative to edge length. If `False`, it is an absolute distance in model units. |
| `theAngDeflection` | `float` | Maximum angular deflection in radians (controls curvature approximation). Default: 0.5 rad (~28.6 deg). |
| `isInParallel` | `bool` | Enable multithreaded meshing. Default: `False`. |

### Triangulation Example

```python
from OCC.Core.BRepMesh import BRepMesh_IncrementalMesh
from OCC.Core.TopoDS import TopoDS_Shape


def triangulate_shape(
    shape: TopoDS_Shape,
    linear_deflection: float = 0.1,
    angular_deflection: float = 0.5,
    *,
    relative: bool = False,
    parallel: bool = True,
) -> None:
    """
    Triangulate a shape in-place. After this call, face triangulations
    are accessible via BRep_Tool.Triangulation().

    Args:
        shape: Shape to mesh. Modified in-place (triangulation is stored
               on the BRep faces).
        linear_deflection: Chord height tolerance. For a part measured
                          in mm, 0.1 gives good visual quality.
        angular_deflection: Angular tolerance in radians.
        relative: If True, linear_deflection is relative to edge size.
        parallel: Use multithreaded meshing (recommended for large models).
    """
    mesh = BRepMesh_IncrementalMesh(
        shape,
        linear_deflection,
        relative,
        angular_deflection,
        parallel,
    )
    mesh.Perform()
    if not mesh.IsDone():
        raise RuntimeError("BRepMesh_IncrementalMesh failed to triangulate shape")
```

### Deflection Guidelines

| Use Case | Linear Deflection | Angular Deflection | Notes |
|---|---|---|---|
| Quick preview / thumbnail | 1.0 | 1.0 | Fast, coarse mesh |
| Interactive 3D viewer | 0.1 | 0.5 | Good balance |
| STL export for 3D printing | 0.01 | 0.1 | High quality |
| FEA pre-processing | 0.001 | 0.05 | Very fine, slow |

---

## Extracting Triangulated Mesh Data

After triangulation, extract vertices, triangle indices, and normals per-face.

### Complete Mesh Extraction

```python
from __future__ import annotations

import numpy as np
import numpy.typing as npt

from OCC.Core.BRep import BRep_Tool
from OCC.Core.TopAbs import TopAbs_FACE, TopAbs_Orientation, TopAbs_REVERSED
from OCC.Core.TopExp import TopExp_Explorer
from OCC.Core.TopLoc import TopLoc_Location
from OCC.Core.TopoDS import TopoDS_Shape, topods
from OCC.Core.BRepMesh import BRepMesh_IncrementalMesh
from OCC.Core.gp import gp_Pnt, gp_Vec


def extract_mesh_data(
    shape: TopoDS_Shape,
    linear_deflection: float = 0.1,
    angular_deflection: float = 0.5,
) -> tuple[npt.NDArray[np.float64], npt.NDArray[np.int32], npt.NDArray[np.float64]]:
    """
    Triangulate a shape and extract mesh data as numpy arrays.

    Returns:
        vertices: (N, 3) float64 array of vertex positions.
        triangles: (M, 3) int32 array of vertex indices per triangle.
        normals: (M, 3) float64 array of face normals per triangle.
    """
    # Step 1: Triangulate the shape
    mesh = BRepMesh_IncrementalMesh(shape, linear_deflection, False, angular_deflection, True)
    mesh.Perform()
    if not mesh.IsDone():
        raise RuntimeError("Triangulation failed")

    all_vertices: list[tuple[float, float, float]] = []
    all_triangles: list[tuple[int, int, int]] = []
    all_normals: list[tuple[float, float, float]] = []
    vertex_offset: int = 0

    # Step 2: Iterate over all faces
    explorer = TopExp_Explorer(shape, TopAbs_FACE)
    while explorer.More():
        face = topods.Face(explorer.Current())
        location = TopLoc_Location()
        triangulation = BRep_Tool.Triangulation(face, location)

        if triangulation is None:
            explorer.Next()
            continue

        # Get the transformation from the face location
        trsf = location.Transformation()

        # Extract vertices for this face
        nb_nodes: int = triangulation.NbNodes()
        for i in range(1, nb_nodes + 1):
            pnt: gp_Pnt = triangulation.Node(i)
            # Apply the location transformation
            pnt.Transform(trsf)
            all_vertices.append((pnt.X(), pnt.Y(), pnt.Z()))

        # Extract triangles, adjusting indices by the current vertex offset
        nb_triangles: int = triangulation.NbTriangles()
        orientation: TopAbs_Orientation = face.Orientation()

        for i in range(1, nb_triangles + 1):
            tri = triangulation.Triangle(i)
            n1, n2, n3 = tri.Get()

            # Reverse winding order for reversed faces to get correct normals
            if orientation == TopAbs_REVERSED:
                n1, n2, n3 = n1, n3, n2

            # Convert from 1-based OCCT indexing to 0-based + offset
            idx1: int = vertex_offset + n1 - 1
            idx2: int = vertex_offset + n2 - 1
            idx3: int = vertex_offset + n3 - 1
            all_triangles.append((idx1, idx2, idx3))

            # Compute face normal from triangle vertices
            p1 = all_vertices[idx1]
            p2 = all_vertices[idx2]
            p3 = all_vertices[idx3]

            v1 = gp_Vec(p2[0] - p1[0], p2[1] - p1[1], p2[2] - p1[2])
            v2 = gp_Vec(p3[0] - p1[0], p3[1] - p1[1], p3[2] - p1[2])
            normal: gp_Vec = v1.Crossed(v2)

            mag: float = normal.Magnitude()
            if mag > 1e-10:
                normal.Divide(mag)
                all_normals.append((normal.X(), normal.Y(), normal.Z()))
            else:
                all_normals.append((0.0, 0.0, 1.0))  # degenerate fallback

        vertex_offset += nb_nodes
        explorer.Next()

    vertices = np.array(all_vertices, dtype=np.float64)
    triangles = np.array(all_triangles, dtype=np.int32)
    normals = np.array(all_normals, dtype=np.float64)

    return vertices, triangles, normals


def mesh_to_stl(
    vertices: npt.NDArray[np.float64],
    triangles: npt.NDArray[np.int32],
    normals: npt.NDArray[np.float64],
    output_path: str,
) -> None:
    """Write mesh data to a binary STL file using numpy."""
    import struct

    num_triangles: int = len(triangles)
    with open(output_path, "wb") as f:
        # 80-byte header
        f.write(b"\x00" * 80)
        # Number of triangles (uint32)
        f.write(struct.pack("<I", num_triangles))

        for i in range(num_triangles):
            nx, ny, nz = normals[i]
            i1, i2, i3 = triangles[i]
            v1, v2, v3 = vertices[i1], vertices[i2], vertices[i3]

            # Normal vector
            f.write(struct.pack("<3f", nx, ny, nz))
            # Three vertices
            f.write(struct.pack("<3f", *v1))
            f.write(struct.pack("<3f", *v2))
            f.write(struct.pack("<3f", *v3))
            # Attribute byte count
            f.write(struct.pack("<H", 0))
```

### Alternative: Using StlAPI_Writer for Direct STL Export

```python
from OCC.Core.StlAPI import StlAPI_Writer
from OCC.Core.BRepMesh import BRepMesh_IncrementalMesh
from OCC.Core.TopoDS import TopoDS_Shape


def export_stl(
    shape: TopoDS_Shape,
    output_path: str,
    *,
    linear_deflection: float = 0.1,
    ascii_mode: bool = False,
) -> None:
    """Export a shape directly to STL using the built-in writer."""
    BRepMesh_IncrementalMesh(shape, linear_deflection, False, 0.5, True)

    writer = StlAPI_Writer()
    writer.SetASCIIMode(ascii_mode)
    success: bool = writer.Write(shape, output_path)

    if not success:
        raise RuntimeError(f"STL export failed for: {output_path}")
```

---

## Bounding Box Computation

`Bnd_Box` stores axis-aligned bounding boxes (AABB). `BRepBndLib` computes them from BRep shapes.

### Basic Bounding Box

```python
from __future__ import annotations

from dataclasses import dataclass

from OCC.Core.Bnd import Bnd_Box
from OCC.Core.BRepBndLib import brepbndlib
from OCC.Core.TopoDS import TopoDS_Shape


@dataclass(frozen=True)
class AABB:
    """Axis-Aligned Bounding Box."""

    x_min: float
    y_min: float
    z_min: float
    x_max: float
    y_max: float
    z_max: float

    @property
    def size_x(self) -> float:
        return self.x_max - self.x_min

    @property
    def size_y(self) -> float:
        return self.y_max - self.y_min

    @property
    def size_z(self) -> float:
        return self.z_max - self.z_min

    @property
    def center(self) -> tuple[float, float, float]:
        return (
            (self.x_min + self.x_max) / 2.0,
            (self.y_min + self.y_max) / 2.0,
            (self.z_min + self.z_max) / 2.0,
        )

    @property
    def diagonal(self) -> float:
        return (self.size_x**2 + self.size_y**2 + self.size_z**2) ** 0.5

    @property
    def volume(self) -> float:
        return self.size_x * self.size_y * self.size_z


def compute_bounding_box(
    shape: TopoDS_Shape,
    *,
    use_triangulation: bool = True,
) -> AABB:
    """
    Compute the axis-aligned bounding box of a shape.

    Args:
        shape: The shape to bound.
        use_triangulation: If True, use the mesh triangulation for a tighter
                          box (requires prior triangulation). If False,
                          use BRep geometry directly (may be slightly larger
                          due to control polygon overestimation).
    """
    bbox = Bnd_Box()

    if use_triangulation:
        brepbndlib.Add(shape, bbox, use_triangulation)
    else:
        brepbndlib.Add(shape, bbox)

    if bbox.IsVoid():
        raise RuntimeError("Bounding box is void — shape may be empty or null")

    xmin, ymin, zmin, xmax, ymax, zmax = bbox.Get()
    return AABB(xmin, ymin, zmin, xmax, ymax, zmax)


def compute_oriented_bounding_box(shape: TopoDS_Shape) -> tuple[float, float, float]:
    """
    Compute the minimum-volume oriented bounding box (OBB).
    Returns the three half-dimensions of the OBB.

    Note: OCCT provides Bnd_OBB for oriented bounding boxes.
    """
    from OCC.Core.Bnd import Bnd_OBB
    from OCC.Core.BRepBndLib import brepbndlib

    obb = Bnd_OBB()
    brepbndlib.AddOBB(shape, obb, True, True, False)

    hx: float = obb.XHSize()
    hy: float = obb.YHSize()
    hz: float = obb.ZHSize()
    return (hx * 2.0, hy * 2.0, hz * 2.0)
```

### Bnd_Box Gap

`Bnd_Box` adds a small "gap" (tolerance) around the box by default. For exact bounds:

```python
bbox = Bnd_Box()
bbox.SetGap(0.0)  # Remove the default gap
brepbndlib.Add(shape, bbox)
```

---

## GProp — Mass Properties

`BRepGProp` computes volume, surface area, center of gravity, and moments of inertia.

### Volume Properties

```python
from OCC.Core.BRepGProp import brepgprop
from OCC.Core.GProp import GProp_GProps
from OCC.Core.TopoDS import TopoDS_Shape
from OCC.Core.gp import gp_Pnt


def compute_volume_properties(
    shape: TopoDS_Shape,
    tolerance: float = 1e-6,
) -> dict[str, float | tuple[float, float, float]]:
    """
    Compute volumetric mass properties of a solid shape.

    Args:
        shape: Must be a solid or compound of solids.
        tolerance: Relative tolerance for the computation.

    Returns:
        Dictionary with volume, center_of_gravity, and moments_of_inertia.
    """
    props = GProp_GProps()
    # The optional tolerance parameter controls adaptive integration accuracy
    brepgprop.VolumeProperties(shape, props, tolerance)

    cog: gp_Pnt = props.CentreOfMass()
    volume: float = props.Mass()  # "Mass" in GProp means volume for VolumeProperties

    # Moments of inertia about the center of mass
    ixx: float = props.MomentOfInertia(
        gp_Pnt(cog.X(), cog.Y(), cog.Z()).XYZ()
    )

    return {
        "volume": volume,
        "center_of_gravity": (cog.X(), cog.Y(), cog.Z()),
    }
```

### Surface Area Properties

```python
def compute_surface_area(shape: TopoDS_Shape) -> float:
    """Compute total surface area of a shape."""
    props = GProp_GProps()
    brepgprop.SurfaceProperties(shape, props)
    return props.Mass()  # "Mass" = area for SurfaceProperties
```

### Linear Properties

```python
def compute_linear_properties(shape: TopoDS_Shape) -> float:
    """Compute total edge length of a shape."""
    props = GProp_GProps()
    brepgprop.LinearProperties(shape, props)
    return props.Mass()  # "Mass" = total length for LinearProperties
```

### Understanding GProp_GProps.Mass()

The method name `Mass()` is confusing. Its meaning depends on which `brepgprop` function populated the properties:

| Function | `Mass()` Returns | Unit |
|---|---|---|
| `VolumeProperties` | Volume | length^3 |
| `SurfaceProperties` | Surface area | length^2 |
| `LinearProperties` | Total length | length |

If you need actual mass (with material density), multiply volume by density:

```python
volume: float = compute_volume_properties(shape)["volume"]
density_steel: float = 7.85e-6  # kg/mm^3 (for models in mm)
mass_kg: float = volume * density_steel
```

---

## Shape Analysis

### BRepCheck_Analyzer — Shape Validity

`BRepCheck_Analyzer` checks a shape for topological and geometric validity errors.

```python
from __future__ import annotations

from OCC.Core.BRepCheck import BRepCheck_Analyzer
from OCC.Core.TopoDS import TopoDS_Shape


def validate_shape(shape: TopoDS_Shape) -> tuple[bool, list[str]]:
    """
    Check if a shape is topologically and geometrically valid.

    Returns:
        Tuple of (is_valid, list_of_error_descriptions).
    """
    analyzer = BRepCheck_Analyzer(shape)
    is_valid: bool = analyzer.IsValid()

    errors: list[str] = []
    if not is_valid:
        # Collect detailed error information
        from OCC.Core.TopAbs import TopAbs_FACE, TopAbs_EDGE, TopAbs_VERTEX
        from OCC.Core.TopExp import TopExp_Explorer
        from OCC.Core.BRepCheck import (
            BRepCheck_NoError,
            BRepCheck_InvalidPointOnCurve,
            BRepCheck_InvalidPointOnCurveOnSurface,
            BRepCheck_InvalidPointOnSurface,
            BRepCheck_No3DCurve,
            BRepCheck_Multiple3DCurve,
            BRepCheck_Invalid3DCurve,
            BRepCheck_NoCurveOnSurface,
            BRepCheck_InvalidCurveOnSurface,
            BRepCheck_InvalidCurveOnClosedSurface,
            BRepCheck_InvalidSameRangeFlag,
            BRepCheck_InvalidSameParameterFlag,
            BRepCheck_InvalidDegeneratedFlag,
            BRepCheck_FreeEdge,
            BRepCheck_InvalidMultiConnexity,
            BRepCheck_InvalidRange,
            BRepCheck_EmptyWire,
            BRepCheck_RedundantEdge,
            BRepCheck_SelfIntersectingWire,
            BRepCheck_NoSurface,
            BRepCheck_InvalidWire,
            BRepCheck_RedundantWire,
            BRepCheck_IntersectingWires,
            BRepCheck_InvalidImbricationOfWires,
            BRepCheck_EnclosedRegion,
        )

        error_map: dict[int, str] = {
            BRepCheck_InvalidPointOnCurve: "Invalid point on curve",
            BRepCheck_InvalidPointOnCurveOnSurface: "Invalid point on curve on surface",
            BRepCheck_InvalidPointOnSurface: "Invalid point on surface",
            BRepCheck_No3DCurve: "No 3D curve",
            BRepCheck_Multiple3DCurve: "Multiple 3D curves",
            BRepCheck_Invalid3DCurve: "Invalid 3D curve",
            BRepCheck_NoCurveOnSurface: "No curve on surface",
            BRepCheck_InvalidCurveOnSurface: "Invalid curve on surface",
            BRepCheck_FreeEdge: "Free edge",
            BRepCheck_InvalidMultiConnexity: "Invalid multi-connexity",
            BRepCheck_InvalidRange: "Invalid range",
            BRepCheck_EmptyWire: "Empty wire",
            BRepCheck_SelfIntersectingWire: "Self-intersecting wire",
            BRepCheck_NoSurface: "No surface",
            BRepCheck_InvalidWire: "Invalid wire",
            BRepCheck_IntersectingWires: "Intersecting wires",
        }

        for shape_type in [TopAbs_FACE, TopAbs_EDGE, TopAbs_VERTEX]:
            explorer = TopExp_Explorer(shape, shape_type)
            while explorer.More():
                sub = explorer.Current()
                result = analyzer.Result(sub)
                if result is not None:
                    status_list = result.Status()
                    # Note: status_list iteration depends on OCCT version
                errors.append(f"Shape validation errors detected at {shape_type} level")
                explorer.Next()

    return is_valid, errors
```

### ShapeAnalysis_Surface — Surface Queries

```python
from OCC.Core.ShapeAnalysis import ShapeAnalysis_Surface
from OCC.Core.BRep import BRep_Tool
from OCC.Core.TopoDS import topods, TopoDS_Face
from OCC.Core.gp import gp_Pnt


def analyze_face_surface(face: TopoDS_Face) -> dict[str, float]:
    """Analyze the surface of a face for gaps and degeneracies."""
    surface = BRep_Tool.Surface(face)
    analyzer = ShapeAnalysis_Surface(surface)

    # Check for singularities (degenerate points like poles of a sphere)
    has_singularity: bool = analyzer.HasSingularities(1e-6)

    # Compute the gap between the 3D surface and its UV parametrization
    gap: float = analyzer.Gap()

    return {
        "has_singularity": has_singularity,
        "gap": gap,
    }
```

### Shape Healing

When imported shapes have defects, OCCT provides healing tools:

```python
from OCC.Core.ShapeFix import ShapeFix_Shape
from OCC.Core.TopoDS import TopoDS_Shape


def heal_shape(shape: TopoDS_Shape, tolerance: float = 1e-3) -> TopoDS_Shape:
    """
    Attempt to fix common shape defects (gaps, missing edges, etc.).
    Always validate shapes after import from external files.
    """
    fixer = ShapeFix_Shape(shape)
    fixer.SetPrecision(tolerance)
    fixer.SetMaxTolerance(tolerance * 10.0)
    fixer.Perform()
    return fixer.Shape()
```

### Sewing — Joining Disconnected Faces

IGES imports often produce disconnected faces. Sewing reconnects them:

```python
from OCC.Core.BRepBuilderAPI import BRepBuilderAPI_Sewing
from OCC.Core.TopoDS import TopoDS_Shape
from OCC.Core.TopAbs import TopAbs_FACE
from OCC.Core.TopExp import TopExp_Explorer


def sew_faces(shape: TopoDS_Shape, tolerance: float = 1e-3) -> TopoDS_Shape:
    """Sew disconnected faces into a shell or solid."""
    sewer = BRepBuilderAPI_Sewing(tolerance)

    explorer = TopExp_Explorer(shape, TopAbs_FACE)
    while explorer.More():
        sewer.Add(explorer.Current())
        explorer.Next()

    sewer.Perform()
    return sewer.SewedShape()
```

---

## Boolean Operations

`BRepAlgoAPI` provides CSG (Constructive Solid Geometry) boolean operations: union (fuse), difference (cut), and intersection (common).

### Boolean Operation Functions

```python
from __future__ import annotations

from OCC.Core.BRepAlgoAPI import (
    BRepAlgoAPI_Common,
    BRepAlgoAPI_Cut,
    BRepAlgoAPI_Fuse,
    BRepAlgoAPI_Section,
)
from OCC.Core.BRepCheck import BRepCheck_Analyzer
from OCC.Core.TopoDS import TopoDS_Shape


def boolean_fuse(shape1: TopoDS_Shape, shape2: TopoDS_Shape) -> TopoDS_Shape:
    """
    Boolean union (OR) — combines two shapes into one.
    The result contains the volume of both shapes.
    """
    fuse = BRepAlgoAPI_Fuse(shape1, shape2)
    fuse.Build()
    if not fuse.IsDone():
        raise RuntimeError("Boolean fuse operation failed")

    result: TopoDS_Shape = fuse.Shape()

    # Always validate the result of boolean operations
    analyzer = BRepCheck_Analyzer(result)
    if not analyzer.IsValid():
        raise RuntimeError("Boolean fuse produced an invalid shape")

    return result


def boolean_cut(shape: TopoDS_Shape, tool: TopoDS_Shape) -> TopoDS_Shape:
    """
    Boolean difference (subtraction) — removes tool volume from shape.
    Result = shape AND NOT tool.
    """
    cut = BRepAlgoAPI_Cut(shape, tool)
    cut.Build()
    if not cut.IsDone():
        raise RuntimeError("Boolean cut operation failed")

    result: TopoDS_Shape = cut.Shape()

    analyzer = BRepCheck_Analyzer(result)
    if not analyzer.IsValid():
        raise RuntimeError("Boolean cut produced an invalid shape")

    return result


def boolean_common(shape1: TopoDS_Shape, shape2: TopoDS_Shape) -> TopoDS_Shape:
    """
    Boolean intersection (AND) — keeps only the shared volume.
    Result = shape1 AND shape2.
    """
    common = BRepAlgoAPI_Common(shape1, shape2)
    common.Build()
    if not common.IsDone():
        raise RuntimeError("Boolean common operation failed")

    result: TopoDS_Shape = common.Shape()

    analyzer = BRepCheck_Analyzer(result)
    if not analyzer.IsValid():
        raise RuntimeError("Boolean common produced an invalid shape")

    return result


def boolean_section(shape1: TopoDS_Shape, shape2: TopoDS_Shape) -> TopoDS_Shape:
    """
    Compute the intersection curves/edges between two shapes.
    Returns edges/wires at the intersection, not a solid.
    """
    section = BRepAlgoAPI_Section(shape1, shape2)
    section.Build()
    if not section.IsDone():
        raise RuntimeError("Boolean section operation failed")
    return section.Shape()
```

### Practical Boolean Example — Plate with Holes

```python
from OCC.Core.BRepPrimAPI import BRepPrimAPI_MakeBox, BRepPrimAPI_MakeCylinder
from OCC.Core.gp import gp_Ax2, gp_Dir, gp_Pnt
from OCC.Core.TopoDS import TopoDS_Shape


def create_plate_with_holes(
    width: float = 100.0,
    height: float = 60.0,
    thickness: float = 5.0,
    hole_radius: float = 4.0,
    hole_positions: list[tuple[float, float]] | None = None,
) -> TopoDS_Shape:
    """Create a rectangular plate with cylindrical through-holes."""
    if hole_positions is None:
        hole_positions = [(20.0, 20.0), (50.0, 30.0), (80.0, 20.0)]

    # Create the base plate
    plate: TopoDS_Shape = BRepPrimAPI_MakeBox(width, height, thickness).Shape()

    # Subtract each hole
    for x, y in hole_positions:
        # Cylinder axis points in Z direction, starting below the plate
        axis = gp_Ax2(gp_Pnt(x, y, -1.0), gp_Dir(0, 0, 1))
        cylinder: TopoDS_Shape = BRepPrimAPI_MakeCylinder(
            axis, hole_radius, thickness + 2.0
        ).Shape()
        plate = boolean_cut(plate, cylinder)

    return plate
```

### Boolean Operation Robustness

Boolean operations are the most failure-prone part of OCCT. Common issues:

1. **Tangent/touching faces**: Shapes that barely touch may fail. Add a small offset.
2. **Degenerate results**: Very thin slivers can cause invalid topology.
3. **Tolerance mismatches**: Shapes with different tolerances may not intersect properly.
4. **Non-manifold results**: The result may have non-manifold edges (edge shared by >2 faces).

Mitigations:

```python
from OCC.Core.BRepAlgoAPI import BRepAlgoAPI_Fuse
from OCC.Core.BOPAlgo import BOPAlgo_GlueEnum
from OCC.Core.Message import Message_Report


def robust_fuse(
    shape1: TopoDS_Shape,
    shape2: TopoDS_Shape,
    fuzzy_value: float = 1e-5,
) -> TopoDS_Shape:
    """Fuse with fuzzy tolerance for near-coincident geometry."""
    fuse = BRepAlgoAPI_Fuse()
    fuse.SetArguments([shape1])  # Note: OCCT 7.6+ list-based API
    fuse.SetTools([shape2])
    fuse.SetFuzzyValue(fuzzy_value)
    fuse.SetRunParallel(True)
    fuse.Build()

    if fuse.HasErrors():
        raise RuntimeError("Boolean fuse failed with errors")

    return fuse.Shape()
```

---

## Coordinate System Transforms

OCCT uses `gp_Trsf` for rigid body transformations and `BRepBuilderAPI_Transform` to apply them to shapes.

### Basic Transforms

```python
from __future__ import annotations

import math

from OCC.Core.BRepBuilderAPI import BRepBuilderAPI_Transform
from OCC.Core.TopoDS import TopoDS_Shape
from OCC.Core.gp import gp_Ax1, gp_Dir, gp_Pnt, gp_Trsf, gp_Vec


def translate_shape(
    shape: TopoDS_Shape,
    dx: float = 0.0,
    dy: float = 0.0,
    dz: float = 0.0,
    *,
    copy: bool = True,
) -> TopoDS_Shape:
    """Translate a shape by (dx, dy, dz)."""
    trsf = gp_Trsf()
    trsf.SetTranslation(gp_Vec(dx, dy, dz))
    transformer = BRepBuilderAPI_Transform(shape, trsf, copy)
    return transformer.Shape()


def rotate_shape(
    shape: TopoDS_Shape,
    axis_origin: tuple[float, float, float] = (0.0, 0.0, 0.0),
    axis_direction: tuple[float, float, float] = (0.0, 0.0, 1.0),
    angle_degrees: float = 90.0,
    *,
    copy: bool = True,
) -> TopoDS_Shape:
    """Rotate a shape around an axis by the given angle."""
    ax1 = gp_Ax1(
        gp_Pnt(*axis_origin),
        gp_Dir(*axis_direction),
    )
    trsf = gp_Trsf()
    trsf.SetRotation(ax1, math.radians(angle_degrees))
    transformer = BRepBuilderAPI_Transform(shape, trsf, copy)
    return transformer.Shape()


def scale_shape(
    shape: TopoDS_Shape,
    center: tuple[float, float, float] = (0.0, 0.0, 0.0),
    factor: float = 2.0,
    *,
    copy: bool = True,
) -> TopoDS_Shape:
    """Scale a shape uniformly about a center point."""
    trsf = gp_Trsf()
    trsf.SetScale(gp_Pnt(*center), factor)
    transformer = BRepBuilderAPI_Transform(shape, trsf, copy)
    return transformer.Shape()


def mirror_shape(
    shape: TopoDS_Shape,
    plane_point: tuple[float, float, float] = (0.0, 0.0, 0.0),
    plane_normal: tuple[float, float, float] = (1.0, 0.0, 0.0),
    *,
    copy: bool = True,
) -> TopoDS_Shape:
    """Mirror a shape across a plane defined by point and normal."""
    ax2 = gp_Ax1(gp_Pnt(*plane_point), gp_Dir(*plane_normal))
    trsf = gp_Trsf()
    trsf.SetMirror(ax2)
    transformer = BRepBuilderAPI_Transform(shape, trsf, copy)
    return transformer.Shape()


def compose_transforms(*transforms: gp_Trsf) -> gp_Trsf:
    """Compose multiple transforms left-to-right (first applied first)."""
    result = gp_Trsf()
    for t in transforms:
        result = result.Multiplied(t)
    return result
```

### Coordinate System Conversion

```python
from OCC.Core.gp import gp_Ax3, gp_Dir, gp_Pnt, gp_Trsf


def transform_between_coordinate_systems(
    from_origin: gp_Pnt,
    from_z: gp_Dir,
    from_x: gp_Dir,
    to_origin: gp_Pnt,
    to_z: gp_Dir,
    to_x: gp_Dir,
) -> gp_Trsf:
    """
    Create a transformation from one coordinate system to another.

    Args:
        from_origin, from_z, from_x: Source coordinate system.
        to_origin, to_z, to_x: Target coordinate system.

    Returns:
        gp_Trsf that maps points from the source to the target system.
    """
    from_cs = gp_Ax3(from_origin, from_z, from_x)
    to_cs = gp_Ax3(to_origin, to_z, to_x)

    trsf = gp_Trsf()
    trsf.SetTransformation(from_cs, to_cs)
    return trsf
```

---

## Performance: Mesh Quality vs Speed Tradeoffs

### Deflection Parameter Impact

The `linear_deflection` parameter has the largest impact on mesh density. Here are typical numbers for a 100mm diameter sphere:

| Linear Deflection | Triangles | Vertices | Relative Time | Use Case |
|---|---|---|---|---|
| 5.0 | ~50 | ~30 | 1x (baseline) | Bounding box check |
| 1.0 | ~200 | ~120 | 1.5x | Collision detection |
| 0.1 | ~2,000 | ~1,200 | 3x | Interactive viewer |
| 0.01 | ~20,000 | ~12,000 | 10x | STL for 3D printing |
| 0.001 | ~200,000 | ~120,000 | 50x | FEA mesh seed |

### Angular Deflection Impact

`angular_deflection` controls how well curved regions are approximated. Lower values add more triangles on high-curvature areas. The default of 0.5 radians is adequate for most visualization. Reduce to 0.1 for high-quality exports.

### Parallel Meshing

Set `isInParallel=True` for models with many faces. Speedup is roughly proportional to CPU cores for models with >100 faces. Single-face models see no benefit.

```python
# Parallel meshing — significant speedup for complex assemblies
mesh = BRepMesh_IncrementalMesh(shape, 0.1, False, 0.5, True)  # last param = parallel
```

### Incremental Re-meshing

`BRepMesh_IncrementalMesh` is incremental — if a face already has a triangulation that meets or exceeds the requested deflection, it skips that face. To force re-meshing with different parameters:

```python
from OCC.Core.BRepTools import breptools

# Clear existing triangulations
breptools.Clean(shape)

# Now re-mesh with new parameters
mesh = BRepMesh_IncrementalMesh(shape, 0.01, False, 0.1, True)
mesh.Perform()
```

### Memory Considerations

- Triangulation data is stored on the BRep face itself. Each face holds its own mesh.
- For assemblies with thousands of parts, mesh data can consume significant memory (hundreds of MB).
- Use `breptools.Clean(shape)` to release triangulation memory when no longer needed.
- Consider meshing parts on-demand rather than all at once for large assemblies.

### Profiling Tip

```python
import time
from OCC.Core.BRepMesh import BRepMesh_IncrementalMesh

start = time.perf_counter()
mesh = BRepMesh_IncrementalMesh(shape, linear_deflection, False, angular_deflection, True)
mesh.Perform()
elapsed = time.perf_counter() - start

print(f"Meshing took {elapsed:.3f}s at deflection={linear_deflection}")
```

---

## Best Practices

### 1. Always Validate Imported Shapes

STEP and IGES files from other CAD systems frequently have defects. Always check validity after import:

```python
shape = read_step_file("part.step")
analyzer = BRepCheck_Analyzer(shape)
if not analyzer.IsValid():
    shape = heal_shape(shape)
```

### 2. Use TopExp_Explorer, Not Recursive Descent

`TopExp_Explorer` handles all the subtleties of OCCT topology (shared sub-shapes, orientations). Manual recursion via `TopoDS_Iterator` is error-prone.

### 3. Handle Orientation Correctly

When extracting normals or computing winding order, always check `face.Orientation()`. Reversed faces flip the surface normal.

### 4. Check Return Statuses

Every OCCT operation returns a status. Never assume success:

```python
# BAD: ignoring status
reader.ReadFile("part.step")
reader.TransferRoots()
shape = reader.OneShape()

# GOOD: checking every status
status = reader.ReadFile("part.step")
if status != IFSelect_RetDone:
    raise RuntimeError(f"Read failed: {status}")
```

### 5. Use Absolute Deflection for Known-Size Models

If your model units are known (e.g., millimeters), use absolute deflection (`relative=False`) so mesh quality is consistent across parts of different sizes.

### 6. Triangulate Before Bounding Box Computation

`BRepBndLib.Add` with `useTriangulation=True` gives tighter bounding boxes because it uses the actual mesh vertices rather than BSpline control points:

```python
# Triangulate first
BRepMesh_IncrementalMesh(shape, 0.1, False, 0.5, True)

# Then compute bbox with triangulation
bbox = Bnd_Box()
brepbndlib.Add(shape, bbox, True)  # True = use triangulation
```

### 7. Clean Shapes Before Boolean Operations

Boolean operations are sensitive to shape quality. Heal and simplify shapes before operating:

```python
from OCC.Core.ShapeUpgrade import ShapeUpgrade_UnifySameDomain

def prepare_for_boolean(shape: TopoDS_Shape) -> TopoDS_Shape:
    """Clean up a shape before boolean operations."""
    # Unify same-domain faces/edges to reduce complexity
    unifier = ShapeUpgrade_UnifySameDomain(shape)
    unifier.Build()
    return unifier.Shape()
```

### 8. Use Deep Copy When Modifying Shapes

Since `TopoDS_Shape` copies are shallow:

```python
from OCC.Core.BRepBuilderAPI import BRepBuilderAPI_Copy

original = read_step_file("part.step")
deep_copy: TopoDS_Shape = BRepBuilderAPI_Copy(original).Shape()
# Now safe to modify deep_copy without affecting original
```

### 9. Set Units Consistently

OCCT is unit-agnostic internally. Ensure all shapes use the same unit system. STEP files declare units — check during import:

```python
from OCC.Core.Interface import Interface_Static

# Check what unit the STEP file uses
unit = Interface_Static.CVal("xstep.cascade.unit")
print(f"Model units: {unit}")  # "MM", "INCH", etc.
```

### 10. Prefer STL Writer Over Manual Extraction

For simple STL export, use `StlAPI_Writer` rather than manually extracting triangulation. It handles all the edge cases (orientation, location transforms, degenerate triangles).

---

## Anti-Patterns

### 1. Forgetting to Transfer After ReadFile

```python
# WRONG — shape will be null
reader = STEPControl_Reader()
reader.ReadFile("part.step")
shape = reader.OneShape()  # NULL — no transfer was performed!

# CORRECT
reader = STEPControl_Reader()
reader.ReadFile("part.step")
reader.TransferRoots()      # <-- REQUIRED
shape = reader.OneShape()
```

### 2. Accessing Triangulation Without Meshing

```python
# WRONG — triangulation will be None
face = topods.Face(explorer.Current())
location = TopLoc_Location()
tri = BRep_Tool.Triangulation(face, location)  # None! Never meshed.

# CORRECT — mesh first
BRepMesh_IncrementalMesh(shape, 0.1, False, 0.5, True)
tri = BRep_Tool.Triangulation(face, location)   # Now has data
```

### 3. Ignoring Face Orientation in Mesh Extraction

```python
# WRONG — normals will be flipped for reversed faces
n1, n2, n3 = tri.Get()
# Using n1, n2, n3 directly without checking orientation

# CORRECT — check and swap winding
if face.Orientation() == TopAbs_REVERSED:
    n1, n2, n3 = n1, n3, n2
```

### 4. Using Shallow Copy for Independent Modification

```python
# WRONG — both variables share the same geometry
copy = shape  # This is just another reference to the same data

# CORRECT — make a deep copy
from OCC.Core.BRepBuilderAPI import BRepBuilderAPI_Copy
copy = BRepBuilderAPI_Copy(shape).Shape()
```

### 5. Not Healing Imported Shapes

```python
# WRONG — using imported shapes directly in booleans
shape = read_step_file("external_part.step")
result = boolean_cut(shape, tool)  # May crash or produce garbage

# CORRECT — heal first
shape = read_step_file("external_part.step")
shape = heal_shape(shape)
analyzer = BRepCheck_Analyzer(shape)
if analyzer.IsValid():
    result = boolean_cut(shape, tool)
```

### 6. Hardcoding Deflection Without Considering Model Scale

```python
# WRONG — 0.1mm deflection is too coarse for a 0.5mm watch gear
# and too fine for a 10-meter bridge section
mesh = BRepMesh_IncrementalMesh(shape, 0.1, False, 0.5, True)

# CORRECT — scale deflection to model size
bbox = Bnd_Box()
brepbndlib.Add(shape, bbox)
xmin, ymin, zmin, xmax, ymax, zmax = bbox.Get()
diagonal = ((xmax-xmin)**2 + (ymax-ymin)**2 + (zmax-zmin)**2) ** 0.5
deflection = diagonal * 0.001  # 0.1% of bounding diagonal
mesh = BRepMesh_IncrementalMesh(shape, deflection, False, 0.5, True)
```

### 7. Performing Boolean Operations on Non-Solid Shapes

```python
# WRONG — boolean on shells/faces often fails or gives unexpected results
shell1 = ...  # open shell
shell2 = ...  # open shell
result = boolean_fuse(shell1, shell2)  # Likely to fail

# CORRECT — ensure operands are solids
from OCC.Core.BRepBuilderAPI import BRepBuilderAPI_MakeSolid
solid1 = BRepBuilderAPI_MakeSolid(shell1).Shape()
solid2 = BRepBuilderAPI_MakeSolid(shell2).Shape()
result = boolean_fuse(solid1, solid2)
```

### 8. Not Checking IsDone After Operations

```python
# WRONG — ignoring error state
fuse = BRepAlgoAPI_Fuse(shape1, shape2)
result = fuse.Shape()  # May be null or invalid

# CORRECT
fuse = BRepAlgoAPI_Fuse(shape1, shape2)
fuse.Build()
if not fuse.IsDone():
    raise RuntimeError("Fuse failed")
if fuse.HasErrors():
    raise RuntimeError("Fuse has errors")
result = fuse.Shape()
```

### 9. Blocking the Event Loop with Large Triangulations

```python
# WRONG — meshing a 10,000-face assembly synchronously in a GUI thread
BRepMesh_IncrementalMesh(huge_assembly, 0.01, False, 0.1, True)

# CORRECT — use coarser mesh for preview, fine mesh in background
# Preview mesh (fast)
BRepMesh_IncrementalMesh(huge_assembly, 1.0, False, 1.0, True)
# ... show preview ...
# Then refine in a worker thread with fine parameters
```

### 10. Using 1-Based Indexing Accidentally in Python

```python
# WRONG — OCCT uses 1-based indexing, Python uses 0-based
for i in range(triangulation.NbNodes()):  # Starts at 0, misses last node
    pnt = triangulation.Node(i)  # Node(0) is invalid!

# CORRECT — OCCT indexing starts at 1
for i in range(1, triangulation.NbNodes() + 1):
    pnt = triangulation.Node(i)
```

---

## Sources & References

- [pythonocc-core GitHub Repository](https://github.com/tpaviot/pythonocc-core) — Official Python bindings for OpenCASCADE Technology. Installation guides, API examples, and issue tracker.

- [OpenCASCADE Technology Documentation](https://dev.opencascade.org/doc/overview/html/index.html) — Official OCCT reference documentation covering all modules including BRep, TopExp, Mesh, GProp, and algorithm APIs.

- [OpenCASCADE BRep Format Description](https://dev.opencascade.org/doc/overview/html/specification__brep_format.html) — Detailed specification of the Boundary Representation format used by OCCT, including topology/geometry layering.

- [pythonocc-core Examples Gallery](https://github.com/tpaviot/pythonocc-demos) — Collection of Python example scripts demonstrating STEP/IGES import/export, mesh generation, boolean operations, and visualization.

- [OpenCASCADE Modeling Algorithms Guide](https://dev.opencascade.org/doc/overview/html/occt_user_guides__modeling_algos.html) — Guide to boolean operations, fillets, chamfers, shape healing, and algorithmic shape construction.

- [STEP File Format (ISO 10303) Overview](https://www.steptools.com/stds/step/) — Background on the STEP standard used for CAD data exchange, including AP203 and AP214 application protocols.

- [OpenCASCADE Shape Healing Documentation](https://dev.opencascade.org/doc/overview/html/occt_user_guides__shape_healing.html) — Guide to the ShapeFix, ShapeAnalysis, and ShapeUpgrade packages for repairing defective geometry.

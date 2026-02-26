---
name: computational-geometry
description: Mesh generation, triangulation, face/edge/wire processing, extrusion, boolean operations, surface normals, topology traversal, and spatial indexing for 3D/CAD engineering with Python
---

# Computational Geometry

This skill covers the full spectrum of computational geometry operations required for 3D/CAD
engineering pipelines. It spans mesh representation and generation, triangulation algorithms,
surface normal computation, extrusion and sweep operations, boolean operations on meshes,
BRep-to-mesh conversion, convex hull algorithms, point containment tests, spatial indexing
structures, mesh simplification, coordinate transforms, and topology traversal. All code
examples target Python 3.11+ and rely on numpy, trimesh, scipy.spatial, and related libraries
for production-grade geometry processing.

## Table of Contents

1. Mesh Representation
2. Half-Edge Data Structure
3. Triangulation Algorithms
4. Surface Normal Computation
5. Extrusion Operations
6. Boolean Operations on Meshes
7. BRep to Mesh Conversion Pipeline
8. Convex Hull Algorithms
9. Point-in-Polygon and Point-in-Mesh Tests
10. Spatial Indexing
11. Mesh Simplification and Decimation
12. Coordinate Transforms
13. Topology Traversal
14. Best Practices
15. Anti-Patterns
16. Sources & References

---

## 1. Mesh Representation

A polygonal mesh is the fundamental data structure for representing 3D surfaces in CAD and
computer graphics. At its core, a mesh consists of two arrays: a vertex array storing 3D
coordinates, and an index (face) array describing how those vertices form polygonal faces.
Using numpy arrays for both provides cache-friendly memory layout and enables vectorized
operations that are orders of magnitude faster than per-element Python loops.

### Vertex Arrays

A vertex array is a contiguous block of floating-point coordinates stored as an `(N, 3)`
numpy array where N is the number of vertices. Each row contains the x, y, z coordinates
of a single vertex. For meshes that also carry per-vertex attributes such as normals, UV
coordinates, or colors, these are stored in parallel arrays of matching length.

Always use `np.float64` for vertex positions in CAD workflows where sub-micron precision
matters. For visualization-only meshes, `np.float32` saves memory and bandwidth to the GPU.

### Index Arrays

An index array (also called a face array) is an `(M, K)` numpy array where M is the number
of faces and K is the number of vertices per face (3 for triangles, 4 for quads). Each
element is an integer index into the vertex array. Triangle meshes use `(M, 3)` arrays and
are the most common representation because every polygon can be decomposed into triangles
and GPUs are optimized for triangle rasterization.

For mixed-polygon meshes where faces have varying vertex counts, store faces as a flat
integer array with a separate array of face lengths, or use trimesh's approach of
triangulating everything on load.

### Memory Layout Considerations

Keep vertex and index arrays contiguous in memory (`np.ascontiguousarray`). Many C/C++
geometry kernels and GPU upload paths require contiguous buffers. When slicing or filtering
vertices, the resulting array may not be contiguous, so explicitly ensure contiguity before
passing data to external libraries.

```python
from __future__ import annotations

import numpy as np
import trimesh
from numpy.typing import NDArray


def create_box_mesh(
    width: float,
    height: float,
    depth: float,
    center: NDArray[np.float64] | None = None,
) -> trimesh.Trimesh:
    """Create an axis-aligned box mesh with explicit vertex and face arrays.

    Parameters
    ----------
    width : float
        Extent along the X axis.
    height : float
        Extent along the Y axis.
    depth : float
        Extent along the Z axis.
    center : NDArray[np.float64] | None
        Center point of the box. Defaults to the origin.

    Returns
    -------
    trimesh.Trimesh
        A watertight triangulated box mesh.
    """
    if center is None:
        center = np.zeros(3, dtype=np.float64)

    hw, hh, hd = width / 2.0, height / 2.0, depth / 2.0

    # 8 corner vertices of the axis-aligned box
    vertices: NDArray[np.float64] = np.array(
        [
            [-hw, -hh, -hd],
            [ hw, -hh, -hd],
            [ hw,  hh, -hd],
            [-hw,  hh, -hd],
            [-hw, -hh,  hd],
            [ hw, -hh,  hd],
            [ hw,  hh,  hd],
            [-hw,  hh,  hd],
        ],
        dtype=np.float64,
    ) + center

    # 12 triangles (2 per face, 6 faces), counter-clockwise winding for outward normals
    faces: NDArray[np.int64] = np.array(
        [
            [0, 3, 2], [0, 2, 1],  # back  (-Z)
            [4, 5, 6], [4, 6, 7],  # front (+Z)
            [0, 1, 5], [0, 5, 4],  # bottom (-Y)
            [2, 3, 7], [2, 7, 6],  # top   (+Y)
            [0, 4, 7], [0, 7, 3],  # left  (-X)
            [1, 2, 6], [1, 6, 5],  # right (+X)
        ],
        dtype=np.int64,
    )

    mesh = trimesh.Trimesh(vertices=vertices, faces=faces, process=False)

    # Validate watertightness
    if not mesh.is_watertight:
        raise ValueError("Generated box mesh is not watertight; check winding order.")

    return mesh


def validate_mesh_arrays(
    vertices: NDArray[np.float64],
    faces: NDArray[np.int64],
) -> list[str]:
    """Run basic sanity checks on vertex and face arrays.

    Returns a list of warning strings. An empty list means no issues found.
    """
    warnings: list[str] = []

    if vertices.ndim != 2 or vertices.shape[1] != 3:
        warnings.append(f"Vertices must be (N, 3), got {vertices.shape}")

    if faces.ndim != 2 or faces.shape[1] < 3:
        warnings.append(f"Faces must be (M, K) with K >= 3, got {faces.shape}")

    if not np.issubdtype(faces.dtype, np.integer):
        warnings.append(f"Face indices must be integers, got {faces.dtype}")

    max_idx = faces.max()
    if max_idx >= len(vertices):
        warnings.append(
            f"Face index {max_idx} exceeds vertex count {len(vertices)}"
        )

    if np.any(np.isnan(vertices)) or np.any(np.isinf(vertices)):
        warnings.append("Vertices contain NaN or Inf values")

    # Check for degenerate faces (duplicate vertex indices within a face)
    for i, face in enumerate(faces):
        if len(set(face)) < len(face):
            warnings.append(f"Face {i} has duplicate vertex indices: {face}")

    return warnings
```

---

## 2. Half-Edge Data Structure

The half-edge (or doubly-connected edge list) data structure provides O(1) adjacency
queries that are essential for topology traversal in CAD kernels. Unlike the simple
vertex/face representation, the half-edge structure stores connectivity explicitly, making
operations like finding all faces around a vertex, walking along a boundary loop, or
detecting non-manifold edges efficient.

Each directed half-edge stores:
- **vertex**: the vertex it points to
- **face**: the face it belongs to
- **next**: the next half-edge in the same face loop
- **prev**: the previous half-edge in the same face loop (optional if you walk via next)
- **twin/opposite**: the half-edge going in the opposite direction along the same edge

A full edge consists of two half-edges pointing in opposite directions. Boundary edges
have one half-edge with a null face reference.

### When to Use Half-Edge vs. Index Arrays

Use index arrays (vertex + face arrays) for:
- Rendering and GPU upload
- Mesh I/O (STL, OBJ, PLY)
- Bulk geometry operations (transforms, normal computation)
- Interop with trimesh, Open3D, PyVista

Use half-edge structures for:
- Euler operators (edge split, edge collapse, face split)
- Mesh editing and local remeshing
- Manifold validation and boundary detection
- Topological queries (vertex star, edge ring, face adjacency)
- BRep traversal in CAD kernels (OpenCascade topology)

### Implementation Sketch

A compact half-edge implementation stores all half-edges in a flat numpy array for
performance. Each half-edge is identified by its index. For a triangle mesh with F faces,
there are exactly 3F half-edges (assuming manifold, closed mesh).

```python
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
from numpy.typing import NDArray


@dataclass
class HalfEdgeMesh:
    """Half-edge mesh representation for topology traversal.

    This implementation prioritizes clarity over raw performance. For
    production CAD kernels processing millions of faces, use a compiled
    implementation (e.g., OpenMesh, CGAL, or PMP).
    """

    vertices: NDArray[np.float64]  # (N, 3) vertex positions

    # Per-half-edge connectivity stored in parallel arrays of length H
    he_vertex: NDArray[np.int64] = field(default_factory=lambda: np.empty(0, dtype=np.int64))
    he_face: NDArray[np.int64] = field(default_factory=lambda: np.empty(0, dtype=np.int64))
    he_next: NDArray[np.int64] = field(default_factory=lambda: np.empty(0, dtype=np.int64))
    he_twin: NDArray[np.int64] = field(default_factory=lambda: np.empty(0, dtype=np.int64))

    # face_he[f] = index of one half-edge belonging to face f
    face_he: NDArray[np.int64] = field(default_factory=lambda: np.empty(0, dtype=np.int64))
    # vert_he[v] = index of one outgoing half-edge from vertex v
    vert_he: NDArray[np.int64] = field(default_factory=lambda: np.empty(0, dtype=np.int64))

    @classmethod
    def from_triangle_mesh(
        cls,
        vertices: NDArray[np.float64],
        faces: NDArray[np.int64],
    ) -> HalfEdgeMesh:
        """Build a half-edge structure from a triangle mesh.

        Parameters
        ----------
        vertices : NDArray[np.float64]
            (N, 3) vertex positions.
        faces : NDArray[np.int64]
            (F, 3) triangle face indices.

        Returns
        -------
        HalfEdgeMesh
            The constructed half-edge mesh.
        """
        n_faces = len(faces)
        n_he = 3 * n_faces  # 3 half-edges per triangle

        he_vertex = np.empty(n_he, dtype=np.int64)
        he_face = np.empty(n_he, dtype=np.int64)
        he_next = np.empty(n_he, dtype=np.int64)
        he_twin = np.full(n_he, -1, dtype=np.int64)  # -1 = boundary
        face_he = np.empty(n_faces, dtype=np.int64)
        vert_he = np.full(len(vertices), -1, dtype=np.int64)

        # Map from directed edge (v_from, v_to) -> half-edge index
        edge_map: dict[tuple[int, int], int] = {}

        for fi in range(n_faces):
            base = fi * 3
            face_he[fi] = base
            for local in range(3):
                hi = base + local
                v_from = int(faces[fi, local])
                v_to = int(faces[fi, (local + 1) % 3])

                he_vertex[hi] = v_to
                he_face[hi] = fi
                he_next[hi] = base + (local + 1) % 3

                if vert_he[v_from] == -1:
                    vert_he[v_from] = hi

                # Twin lookup
                twin_key = (v_to, v_from)
                if twin_key in edge_map:
                    twin_hi = edge_map[twin_key]
                    he_twin[hi] = twin_hi
                    he_twin[twin_hi] = hi
                else:
                    edge_map[(v_from, v_to)] = hi

        return cls(
            vertices=vertices,
            he_vertex=he_vertex,
            he_face=he_face,
            he_next=he_next,
            he_twin=he_twin,
            face_he=face_he,
            vert_he=vert_he,
        )

    def vertex_neighbors(self, vertex_idx: int) -> list[int]:
        """Return indices of all vertices adjacent to the given vertex."""
        neighbors: list[int] = []
        start_he = self.vert_he[vertex_idx]
        if start_he == -1:
            return neighbors

        current = start_he
        while True:
            neighbors.append(int(self.he_vertex[current]))
            twin = self.he_twin[current]
            if twin == -1:
                break  # boundary reached
            current = self.he_next[twin]
            if current == start_he:
                break  # full loop

        return neighbors

    def face_vertices(self, face_idx: int) -> NDArray[np.int64]:
        """Return the vertex indices of a face by walking its half-edge loop."""
        result: list[int] = []
        start = self.face_he[face_idx]
        current = start
        while True:
            result.append(int(self.he_vertex[current]))
            current = int(self.he_next[current])
            if current == start:
                break
        return np.array(result, dtype=np.int64)

    def is_boundary_vertex(self, vertex_idx: int) -> bool:
        """Check whether a vertex lies on a mesh boundary."""
        start_he = self.vert_he[vertex_idx]
        if start_he == -1:
            return True
        current = start_he
        while True:
            if self.he_twin[current] == -1:
                return True
            current = self.he_next[self.he_twin[current]]
            if current == start_he:
                break
        return False

    def boundary_loops(self) -> list[list[int]]:
        """Find all boundary loops as lists of vertex indices."""
        visited: set[int] = set()
        loops: list[list[int]] = []

        boundary_hes = np.where(self.he_twin == -1)[0]
        # Build map: vertex -> boundary half-edge starting from that vertex
        # For boundary half-edges, we need the "from" vertex
        # he_vertex stores the "to" vertex, so the "from" vertex is he_vertex[he_prev]
        # We need to walk next pointers on boundary edges

        for he_idx in boundary_hes:
            if he_idx in visited:
                continue
            loop: list[int] = []
            current = int(he_idx)
            while current not in visited:
                visited.add(current)
                loop.append(int(self.he_vertex[current]))
                # Find next boundary half-edge: walk next until we find a boundary
                nxt = int(self.he_next[current])
                while self.he_twin[nxt] != -1:
                    nxt = int(self.he_next[self.he_twin[nxt]])
                current = nxt
            if loop:
                loops.append(loop)

        return loops
```

---

## 3. Triangulation Algorithms

Triangulation converts a polygon or a point set into a set of non-overlapping triangles.
This is a prerequisite for rendering, finite element analysis, and many geometric
operations that assume triangle meshes.

### Delaunay Triangulation

Delaunay triangulation maximizes the minimum angle across all triangles, avoiding skinny
triangles that cause numerical instability in simulations. The key property is that no
point lies inside the circumcircle of any triangle. scipy.spatial provides a robust
implementation based on Qhull.

For 2D point sets, use `scipy.spatial.Delaunay`. The result is a triangulation of the
convex hull of the points. If you need to triangulate a specific polygon (not the convex
hull), use constrained Delaunay triangulation instead.

For 3D point sets, `scipy.spatial.Delaunay` produces a tetrahedralization (3D Delaunay).
The surface triangulation is obtained from the convex hull.

### Ear Clipping

Ear clipping is a simple O(n^2) algorithm for triangulating a simple polygon. An "ear" is
a triangle formed by three consecutive vertices where the triangle contains no other
polygon vertices and the diagonal lies inside the polygon. The algorithm repeatedly finds
and removes ears until only one triangle remains.

Ear clipping handles:
- Simple polygons (no self-intersections)
- Polygons with holes (by creating bridge edges to merge holes with the outer boundary)
- Concave polygons

Use ear clipping when:
- The polygon is small (< 1000 vertices)
- You need a simple, dependency-free implementation
- The polygon may be concave

### Constrained Delaunay Triangulation (CDT)

CDT combines the quality properties of Delaunay triangulation with the ability to preserve
specified edges (constraints). This is essential for meshing polygons with holes, meshing
domains with internal boundaries, and generating meshes that respect feature edges.

The `triangle` library (Python binding for Triangle by J. R. Shewchuk) provides a robust
CDT implementation with options for mesh refinement (adding Steiner points to improve
triangle quality) and area constraints.

Key parameters for `triangle.triangulate`:
- `p`: triangulate a planar straight-line graph (polygon with holes)
- `q`: quality mesh generation (minimum angle constraint, default 20 degrees)
- `a`: maximum triangle area constraint
- `D`: conforming Delaunay (all triangles are Delaunay, not just constrained Delaunay)

```python
from __future__ import annotations

import numpy as np
from numpy.typing import NDArray
from scipy.spatial import Delaunay


def delaunay_2d(points: NDArray[np.float64]) -> NDArray[np.int64]:
    """Compute the 2D Delaunay triangulation of a point set.

    Parameters
    ----------
    points : NDArray[np.float64]
        (N, 2) array of 2D point coordinates.

    Returns
    -------
    NDArray[np.int64]
        (M, 3) array of triangle vertex indices.
    """
    tri = Delaunay(points)
    return tri.simplices.astype(np.int64)


def ear_clip_triangulate(polygon: NDArray[np.float64]) -> NDArray[np.int64]:
    """Triangulate a simple 2D polygon using the ear clipping algorithm.

    Parameters
    ----------
    polygon : NDArray[np.float64]
        (N, 2) ordered polygon vertices. The polygon is assumed to be simple
        (no self-intersections). The last vertex should NOT duplicate the first.

    Returns
    -------
    NDArray[np.int64]
        (N-2, 3) array of triangle vertex indices referencing the input polygon.
    """
    n = len(polygon)
    if n < 3:
        raise ValueError("Polygon must have at least 3 vertices.")

    # Ensure counter-clockwise ordering via signed area
    signed_area = _signed_area_2d(polygon)
    indices = list(range(n))
    if signed_area < 0:
        indices.reverse()

    triangles: list[tuple[int, int, int]] = []

    while len(indices) > 2:
        ear_found = False
        m = len(indices)
        for i in range(m):
            prev_idx = indices[(i - 1) % m]
            curr_idx = indices[i]
            next_idx = indices[(i + 1) % m]

            a = polygon[prev_idx]
            b = polygon[curr_idx]
            c = polygon[next_idx]

            # Check if the vertex is convex (left turn)
            cross = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
            if cross <= 0:
                continue  # reflex vertex, skip

            # Check that no other vertex lies inside triangle (a, b, c)
            is_ear = True
            for j in range(m):
                if j in {(i - 1) % m, i, (i + 1) % m}:
                    continue
                p = polygon[indices[j]]
                if _point_in_triangle_2d(p, a, b, c):
                    is_ear = False
                    break

            if is_ear:
                triangles.append((prev_idx, curr_idx, next_idx))
                indices.pop(i)
                ear_found = True
                break

        if not ear_found:
            raise ValueError(
                "No ear found; polygon may be self-intersecting or degenerate."
            )

    return np.array(triangles, dtype=np.int64)


def _signed_area_2d(polygon: NDArray[np.float64]) -> float:
    """Compute the signed area of a 2D polygon (positive = CCW)."""
    x = polygon[:, 0]
    y = polygon[:, 1]
    return 0.5 * float(np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y))


def _point_in_triangle_2d(
    p: NDArray[np.float64],
    a: NDArray[np.float64],
    b: NDArray[np.float64],
    c: NDArray[np.float64],
) -> bool:
    """Test whether point p lies strictly inside triangle (a, b, c) in 2D."""
    d1 = (p[0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (p[1] - b[1])
    d2 = (p[0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (p[1] - c[1])
    d3 = (p[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (p[1] - a[1])

    has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)

    return not (has_neg and has_pos)
```

---

## 4. Surface Normal Computation

Surface normals are vectors perpendicular to the mesh surface. They are critical for
rendering (lighting), collision detection, inside/outside classification, and mesh
orientation validation.

### Face Normals

A face normal is computed from the cross product of two edge vectors of the triangle. The
direction depends on the winding order of the vertices: counter-clockwise (CCW) winding
produces an outward-facing normal by the right-hand rule.

For a triangle with vertices A, B, C:
- Edge vectors: `e1 = B - A`, `e2 = C - A`
- Face normal (unnormalized): `n = cross(e1, e2)`
- Face normal (unit): `n / |n|`

The magnitude of the cross product equals twice the area of the triangle. Degenerate
triangles (zero area) produce zero-length normals and must be handled explicitly.

### Vertex Normals

Vertex normals are computed by averaging the face normals of all faces that share the
vertex. The two main weighting schemes are:

- **Area-weighted**: Each face normal is weighted by the face area. This is the most
  common approach and produces smooth shading that respects the geometry.
- **Angle-weighted**: Each face normal is weighted by the interior angle at the vertex.
  This gives better results at sharp features.

Trimesh computes area-weighted vertex normals by default via `mesh.vertex_normals`.

### Winding Order Consistency

A mesh has consistent winding order if, for every pair of adjacent triangles, the shared
edge is traversed in opposite directions. This ensures all face normals point in the same
general direction (outward for closed meshes). Inconsistent winding causes rendering
artifacts (flipped faces) and incorrect inside/outside tests.

Trimesh can fix winding order via `mesh.fix_normals()`, which orients all faces
consistently and ensures normals point outward for watertight meshes.

### Vectorized Normal Computation

Always compute normals for the entire mesh in one vectorized operation rather than looping
over faces in Python. Trimesh and numpy make this straightforward:

```python
from __future__ import annotations

import numpy as np
import trimesh
from numpy.typing import NDArray


def compute_face_normals(
    vertices: NDArray[np.float64],
    faces: NDArray[np.int64],
    normalize: bool = True,
) -> NDArray[np.float64]:
    """Compute face normals for a triangle mesh using vectorized numpy operations.

    Parameters
    ----------
    vertices : NDArray[np.float64]
        (N, 3) vertex positions.
    faces : NDArray[np.int64]
        (M, 3) triangle face indices.
    normalize : bool
        If True, return unit normals. If False, return unnormalized normals
        whose magnitude equals twice the triangle area.

    Returns
    -------
    NDArray[np.float64]
        (M, 3) face normal vectors.
    """
    v0 = vertices[faces[:, 0]]
    v1 = vertices[faces[:, 1]]
    v2 = vertices[faces[:, 2]]

    e1 = v1 - v0
    e2 = v2 - v0

    normals = np.cross(e1, e2)

    if normalize:
        lengths = np.linalg.norm(normals, axis=1, keepdims=True)
        # Avoid division by zero for degenerate triangles
        lengths = np.maximum(lengths, np.finfo(np.float64).tiny)
        normals = normals / lengths

    return normals


def compute_vertex_normals_area_weighted(
    vertices: NDArray[np.float64],
    faces: NDArray[np.int64],
) -> NDArray[np.float64]:
    """Compute area-weighted vertex normals.

    Each vertex normal is the normalized sum of the (unnormalized) face normals
    of all faces incident to that vertex. Since unnormalized face normals have
    magnitude proportional to face area, this produces area-weighted averaging.

    Parameters
    ----------
    vertices : NDArray[np.float64]
        (N, 3) vertex positions.
    faces : NDArray[np.int64]
        (M, 3) triangle face indices.

    Returns
    -------
    NDArray[np.float64]
        (N, 3) unit vertex normals.
    """
    face_normals = compute_face_normals(vertices, faces, normalize=False)

    vertex_normals = np.zeros_like(vertices)
    # Accumulate face normals onto each vertex
    for k in range(3):
        np.add.at(vertex_normals, faces[:, k], face_normals)

    lengths = np.linalg.norm(vertex_normals, axis=1, keepdims=True)
    lengths = np.maximum(lengths, np.finfo(np.float64).tiny)

    return vertex_normals / lengths


def check_winding_consistency(mesh: trimesh.Trimesh) -> dict[str, int | bool]:
    """Check winding order consistency and orientation of a mesh.

    Returns
    -------
    dict
        Keys: 'is_watertight', 'is_winding_consistent', 'n_faces',
        'n_flipped_after_fix'.
    """
    original_normals = mesh.face_normals.copy()

    # fix_normals() modifies the mesh in place
    mesh_copy = mesh.copy()
    mesh_copy.fix_normals()

    # Count faces that were flipped
    dots = np.sum(original_normals * mesh_copy.face_normals, axis=1)
    n_flipped = int(np.sum(dots < 0))

    return {
        "is_watertight": bool(mesh.is_watertight),
        "is_winding_consistent": n_flipped == 0,
        "n_faces": len(mesh.faces),
        "n_flipped_after_fix": n_flipped,
    }
```

---

## 5. Extrusion Operations

Extrusion creates a 3D solid by sweeping a 2D profile along a path or direction. This is
one of the most common operations in CAD modeling. The two primary variants are linear
extrusion (sweep along a straight line) and path extrusion (sweep along an arbitrary curve).

### Linear Extrusion

Linear extrusion takes a 2D polygon and extrudes it along a direction vector by a specified
distance. The result is a prismatic solid. The mesh consists of:
- The original polygon face (bottom cap)
- A translated copy of the polygon (top cap)
- Rectangular side faces connecting corresponding edges of the two caps

When the 2D profile is a polygon with holes, the bottom and top caps must be triangulated
using constrained Delaunay triangulation before they can be included in the mesh.

Trimesh provides `trimesh.creation.extrude_polygon` for extruding Shapely polygons. For
manual control, construct the vertex and face arrays directly.

### Path Extrusion (Sweep)

Path extrusion sweeps a 2D cross-section along a 3D curve. At each sample point along the
curve, the cross-section is positioned perpendicular to the curve tangent using a moving
reference frame (typically the Frenet-Serret frame or a parallel transport frame).

The Frenet-Serret frame uses the tangent, normal, and binormal vectors of the curve. This
works well for smooth curves but breaks down at inflection points where the curvature is
zero. The parallel transport frame (Bishop frame) avoids this issue by propagating the
frame along the curve without relying on curvature.

Key considerations for path extrusion:
- Sample the curve densely enough to capture its curvature without creating excessive
  geometry. Adaptive sampling based on curvature gives the best results.
- Handle the start and end caps: close the mesh by adding faces for the first and last
  cross-sections, or leave them open for pipes and tubes.
- Handle self-intersection: tight curves with large cross-sections can cause the swept
  surface to intersect itself. Detect and resolve these cases.

### Taper and Twist

Linear extrusion can be extended with taper (scaling the cross-section along the sweep
direction) and twist (rotating the cross-section). Both are controlled by interpolation
parameters along the sweep path.

For taper, multiply the cross-section coordinates by a scale factor that varies linearly
(or according to a custom curve) from 1.0 at the base to a specified value at the top.

For twist, apply a rotation matrix around the sweep axis at each cross-section. The
rotation angle increases linearly with distance along the sweep direction.

---

## 6. Boolean Operations on Meshes

Boolean operations (union, intersection, difference) combine two solid meshes to produce
a new mesh. These are fundamental to constructive solid geometry (CSG) workflows in CAD.

### Requirements for Boolean Operands

Both input meshes must be:
- **Watertight** (closed, no boundary edges): each edge is shared by exactly two faces
- **Consistently oriented**: all face normals point outward
- **Non-self-intersecting**: no face intersects another face of the same mesh

Violating these requirements leads to undefined behavior, crashes, or incorrect results
in most boolean engines.

### Available Libraries

- **trimesh.boolean**: wraps multiple backends including Blender, OpenSCAD, and Manifold
- **manifold3d**: the Manifold library provides robust, fast boolean operations with
  guaranteed manifold output. It is the recommended backend for production use.
- **pymeshlab**: wraps VCGlib's boolean operations
- **OCP (OpenCascade Python)**: provides BRep-level booleans with exact arithmetic

### Using trimesh with Manifold Backend

Trimesh delegates boolean operations to an available backend. The Manifold backend is
fastest and most robust. Install it with `pip install manifold3d`.

Operations:
- `mesh_a + mesh_b` or `mesh_a.union(mesh_b)`: union
- `mesh_a - mesh_b` or `mesh_a.difference(mesh_b)`: difference (subtract b from a)
- `mesh_a * mesh_b` or `mesh_a.intersection(mesh_b)`: intersection (overlap region)

### Boolean Operation Pipeline

1. Validate both input meshes (watertight, consistent normals)
2. Perform the boolean operation
3. Validate the output mesh
4. Clean up: remove degenerate faces, merge duplicate vertices, fix normals
5. Optionally simplify the result to reduce triangle count

### Robustness Considerations

Exact or near-exact arithmetic is critical for boolean operations. Floating-point errors
cause topology corruption when intersection curves pass near existing vertices or edges.
The Manifold library uses robust predicates internally, making it significantly more
reliable than naive floating-point implementations.

When booleans fail:
- Slightly perturb one operand (translate by a small epsilon in a random direction)
- Remesh both operands to a uniform triangle size before the operation
- Use a different backend (some handle degenerate cases better than others)

---

## 7. BRep to Mesh Conversion Pipeline

Boundary Representation (BRep) is the standard representation in CAD kernels (OpenCascade,
Parasolid, ACIS). A BRep model consists of topological entities (solids, shells, faces,
wires, edges, vertices) linked to geometric entities (surfaces, curves, points).

Converting BRep to a triangle mesh is called tessellation or faceting. The pipeline is:

### Step 1: Topology Traversal

Walk the BRep topology to enumerate all faces. In OpenCascade (via the `OCP` or
`cadquery` Python bindings), use `TopExp_Explorer` to iterate over faces:

```
explorer = TopExp_Explorer(shape, TopAbs_FACE)
while explorer.More():
    face = topods.Face(explorer.Current())
    # Process face
    explorer.Next()
```

### Step 2: Surface Tessellation

Each BRep face is a trimmed parametric surface (NURBS, plane, cylinder, cone, sphere,
torus, or general B-spline). The tessellation algorithm samples the surface in parameter
space (u, v) and produces triangles that approximate the surface within a specified
tolerance.

Key parameters:
- **Linear deflection**: maximum allowed distance between the mesh and the true surface
- **Angular deflection**: maximum allowed angle between adjacent triangle normals
- **Minimum/maximum edge length**: bounds on triangle edge lengths

OpenCascade's `BRepMesh_IncrementalMesh` performs this tessellation. After meshing, extract
the triangulation from each face using `BRep_Tool.Triangulation`.

### Step 3: Stitch and Clean

Individual face tessellations may have gaps at shared edges because each face is
tessellated independently. Stitching merges vertices that are within a tolerance along
shared edges to produce a watertight mesh.

After stitching:
- Remove degenerate triangles (zero area)
- Remove duplicate faces
- Ensure consistent winding order
- Validate watertightness

### Step 4: Export

Export the stitched mesh to STL, OBJ, PLY, or GLTF format. STL is the most common format
for 3D printing and CAM. OBJ and GLTF preserve vertex normals and UV coordinates.

---

## 8. Convex Hull Algorithms

The convex hull of a point set is the smallest convex polytope containing all points. It
is used for collision detection (GJK algorithm uses convex hulls), bounding volume
computation, mesh simplification, and shape analysis.

### 2D Convex Hull

`scipy.spatial.ConvexHull` computes the convex hull using Qhull. For a 2D point set, the
result is a polygon (ordered list of vertex indices).

### 3D Convex Hull

For 3D point sets, `scipy.spatial.ConvexHull` returns a triangulated surface. The
`simplices` attribute contains the triangle indices, and `vertices` contains the indices
of points on the hull.

Trimesh also provides `trimesh.convex.convex_hull(mesh)` which returns a new Trimesh
object representing the convex hull of the input mesh's vertices.

### Performance

Qhull implements the Quickhull algorithm with O(n log n) expected time complexity. For
very large point sets (millions of points), consider:
- Downsampling the point set before computing the hull
- Using approximate convex hull algorithms
- Parallelizing via spatial partitioning

### Convex Decomposition

Many operations (physics simulation, boolean operations, collision detection) work only
on convex meshes or work much faster on convex meshes. Convex decomposition splits a
non-convex mesh into a set of convex parts.

V-HACD (Volumetric Hierarchical Approximate Convex Decomposition) is the standard
algorithm, available via `trimesh.decomposition.convex_decomposition` or the `pyvhacd`
package. Key parameters:
- `maxConvexHulls`: maximum number of convex parts
- `resolution`: voxel resolution for the volumetric step
- `minimumVolumePercentErrorAllowed`: convergence threshold

---

## 9. Point-in-Polygon and Point-in-Mesh Tests

Determining whether a point lies inside a polygon (2D) or inside a mesh (3D) is a
fundamental query in computational geometry.

### 2D: Ray Casting (Crossing Number)

Cast a ray from the test point in any direction (typically +X) and count the number of
times it crosses the polygon boundary. An odd count means inside; even means outside.

Edge cases to handle:
- Ray passes through a vertex: perturb the ray direction slightly
- Ray is collinear with an edge: same treatment
- Point is exactly on the boundary: decide by convention (typically "inside")

`matplotlib.path.Path.contains_point` and `shapely.geometry.Point.within` implement this.

### 3D: Ray Casting for Meshes

The 3D extension casts a ray from the test point and counts intersections with the mesh
surface. For watertight meshes with consistent winding, an odd count means inside.

Trimesh provides `mesh.contains(points)` which uses an optimized ray-based approach with
a BVH acceleration structure. This handles batches of millions of points efficiently.

For non-watertight meshes, generalized winding number provides a robust alternative. The
winding number of a point with respect to a mesh is 1 inside, 0 outside, and fractional
for non-watertight meshes. Threshold at 0.5 for inside/outside classification.

### Performance for Batch Queries

For testing many points against the same mesh:
1. Build a spatial index (BVH) over the mesh triangles once
2. For each query point, cast a ray and use the BVH to find intersections in O(log n)
3. Count intersections to determine inside/outside

Trimesh's `contains` method does this automatically. For custom implementations, use
`trimesh.ray.ray_pyembree.RayMeshIntersector` (requires pyembree) or the built-in
`trimesh.ray.ray_triangle.RayMeshIntersector`.

---

## 10. Spatial Indexing

Spatial indexing structures accelerate geometric queries (nearest neighbor, ray
intersection, range search) from O(n) to O(log n) per query.

### Bounding Volume Hierarchy (BVH)

A BVH is a tree of axis-aligned bounding boxes (AABBs). Each leaf node contains one or a
few primitives (triangles). Each internal node's AABB encloses all primitives in its
subtree.

BVH is the standard acceleration structure for ray tracing and collision detection on
triangle meshes. Trimesh builds a BVH automatically for ray intersection queries.

Construction strategies:
- **Top-down**: recursively split primitives using the spatial median or surface area
  heuristic (SAH). SAH minimizes expected traversal cost.
- **Bottom-up**: agglomerative clustering of primitives.
- **Linear BVH (LBVH)**: sort primitives by Morton code and split at bit boundaries.
  O(n log n) construction, good for GPU construction.

### Octree

An octree recursively subdivides 3D space into eight equal octants. Each node either
contains primitives or has eight children. Octrees provide uniform spatial subdivision and
are well-suited for:
- Point clouds (nearest neighbor, range queries)
- Voxelization
- Level-of-detail rendering
- Sparse volumetric data

Open3D provides `o3d.geometry.Octree` for point cloud operations. For triangle meshes,
BVH is generally preferred over octree.

### k-d Tree

A k-d tree recursively partitions points by alternating coordinate axes. It provides
O(log n) nearest-neighbor queries and is the standard structure for point-based spatial
queries.

`scipy.spatial.KDTree` and `scipy.spatial.cKDTree` (Cython-optimized) provide robust
implementations. Use `cKDTree` for performance-critical applications.

Key operations:
- `query(point, k)`: find k nearest neighbors
- `query_ball_point(point, r)`: find all points within radius r
- `query_pairs(r)`: find all pairs of points within distance r

```python
from __future__ import annotations

import numpy as np
import trimesh
from numpy.typing import NDArray
from scipy.spatial import cKDTree


def find_closest_points_on_mesh(
    mesh: trimesh.Trimesh,
    query_points: NDArray[np.float64],
) -> tuple[NDArray[np.float64], NDArray[np.float64], NDArray[np.int64]]:
    """Find the closest point on a mesh surface for each query point.

    Uses trimesh's proximity query which internally uses a BVH for acceleration.

    Parameters
    ----------
    mesh : trimesh.Trimesh
        The target mesh.
    query_points : NDArray[np.float64]
        (Q, 3) array of query point positions.

    Returns
    -------
    closest_points : NDArray[np.float64]
        (Q, 3) closest points on the mesh surface.
    distances : NDArray[np.float64]
        (Q,) distances from query points to closest surface points.
    face_indices : NDArray[np.int64]
        (Q,) indices of the faces containing the closest points.
    """
    closest_points, distances, face_indices = mesh.nearest.on_surface(query_points)
    return (
        closest_points.astype(np.float64),
        distances.astype(np.float64),
        face_indices.astype(np.int64),
    )


def merge_close_vertices(
    vertices: NDArray[np.float64],
    faces: NDArray[np.int64],
    tolerance: float = 1e-8,
) -> tuple[NDArray[np.float64], NDArray[np.int64]]:
    """Merge vertices that are closer than a specified tolerance.

    Uses a k-d tree to efficiently find vertex clusters within the tolerance
    distance, then remaps face indices to the merged vertices.

    Parameters
    ----------
    vertices : NDArray[np.float64]
        (N, 3) vertex positions.
    faces : NDArray[np.int64]
        (M, 3) face indices.
    tolerance : float
        Maximum distance between vertices to be merged.

    Returns
    -------
    merged_vertices : NDArray[np.float64]
        (K, 3) merged vertex positions, K <= N.
    remapped_faces : NDArray[np.int64]
        (M, 3) face indices referencing merged vertices.
    """
    tree = cKDTree(vertices)

    # Find pairs of vertices within tolerance
    pairs = tree.query_pairs(tolerance, output_type="ndarray")

    # Union-Find to group vertices
    n = len(vertices)
    parent = np.arange(n, dtype=np.int64)

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]  # path compression
            x = parent[x]
        return x

    for i, j in pairs:
        ri, rj = find(int(i)), find(int(j))
        if ri != rj:
            parent[ri] = rj

    # Resolve all parents
    for i in range(n):
        parent[i] = find(i)

    # Create mapping from old to new indices
    unique_roots, inverse = np.unique(parent, return_inverse=True)
    merged_vertices = np.empty((len(unique_roots), 3), dtype=np.float64)

    for new_idx, root in enumerate(unique_roots):
        cluster_mask = parent == root
        merged_vertices[new_idx] = vertices[cluster_mask].mean(axis=0)

    remapped_faces = inverse[faces]

    # Remove degenerate faces (where two or more vertices merged to the same index)
    valid_mask = np.array([
        len(set(face)) == len(face) for face in remapped_faces
    ])
    remapped_faces = remapped_faces[valid_mask]

    return merged_vertices, remapped_faces.astype(np.int64)


def build_point_cloud_kdtree(
    points: NDArray[np.float64],
    leaf_size: int = 16,
) -> cKDTree:
    """Build an optimized k-d tree for a 3D point cloud.

    Parameters
    ----------
    points : NDArray[np.float64]
        (N, 3) point positions.
    leaf_size : int
        Number of points at which to switch to brute-force search.
        Smaller values build deeper trees (better for very localized queries),
        larger values reduce tree construction time.

    Returns
    -------
    cKDTree
        The constructed k-d tree.
    """
    if points.ndim != 2 or points.shape[1] != 3:
        raise ValueError(f"Expected (N, 3) array, got {points.shape}")
    return cKDTree(points, leafsize=leaf_size, balanced_tree=True)
```

---

## 11. Mesh Simplification and Decimation

Mesh simplification reduces the triangle count of a mesh while preserving its shape as
closely as possible. This is essential for level-of-detail rendering, physics simulation,
3D printing slicing, and reducing memory and computation costs.

### Edge Collapse (Quadric Error Metrics)

The most widely used algorithm is edge collapse with quadric error metrics (QEM), introduced
by Garland and Heckbert. Each vertex accumulates a 4x4 quadric matrix representing the sum
of squared distances to its adjacent planes. When collapsing an edge (merging two vertices
into one), the optimal position for the merged vertex minimizes the quadric error.

Key properties:
- Preserves overall shape well, especially planar regions
- O(n log n) time with a priority queue
- Can preserve mesh boundaries by adding penalty quadrics

### Libraries for Mesh Simplification

- **trimesh.simplify**: limited built-in simplification
- **PyMeshLab**: wraps VCGlib's comprehensive simplification algorithms including QEM,
  clustering decimation, and edge-length-based decimation
- **Open3D**: `mesh.simplify_quadric_decimation(target_number_of_triangles)`
- **pyfqmr**: Fast Quadric Mesh Reduction, a Python binding for a fast QEM implementation

### Simplification Parameters

- **Target face count or ratio**: e.g., reduce to 50% of original faces
- **Maximum error threshold**: stop simplifying when the next collapse would exceed this
  geometric error
- **Boundary preservation weight**: higher values prevent boundary edges from collapsing
- **Normal deviation threshold**: prevent collapses that would change normals beyond a
  threshold angle
- **Topology preservation**: prevent collapses that would change the mesh topology (genus)

### Remeshing vs. Decimation

Decimation (simplification) reduces triangle count while preserving the original vertex
positions and connectivity structure. Remeshing creates a new mesh with different
connectivity, typically targeting:
- **Uniform remeshing**: all triangles approximately the same size
- **Isotropic remeshing**: equilateral triangles everywhere
- **Adaptive remeshing**: smaller triangles in high-curvature regions

Use decimation when you need to reduce polygon count. Use remeshing when you need
well-shaped triangles for simulation (FEA, CFD).

---

## 12. Coordinate Transforms

Coordinate transforms are fundamental to positioning, orienting, and scaling geometry in
3D space. Every CAD assembly involves transforming components from local to global
coordinates.

### Homogeneous Coordinates and Affine Transforms

A 4x4 homogeneous transformation matrix combines rotation, translation, and scaling into
a single matrix multiplication. For a point `[x, y, z]`, the homogeneous representation
is `[x, y, z, 1]`. For a direction vector, use `[x, y, z, 0]` (translation does not
affect directions).

The 4x4 matrix has the structure:
```
| R  t |     R = 3x3 rotation/scale matrix
| 0  1 |     t = 3x1 translation vector
```

### Rotation Representations

**Rotation matrices (3x3):** Direct representation, always orthonormal (R^T R = I,
det(R) = 1). Apply via matrix multiplication. Compose rotations by matrix multiplication.
9 parameters with 6 constraints, so 3 degrees of freedom.

**Euler angles:** Three angles (e.g., roll, pitch, yaw) applied in a specific order.
Intuitive but suffer from gimbal lock (loss of a degree of freedom when two axes align).
Avoid for interpolation. Specify the convention (intrinsic/extrinsic, axis order) clearly.

**Axis-angle:** A unit vector (rotation axis) and a scalar (rotation angle). Convert to
rotation matrix via Rodrigues' formula. Natural for specifying rotations around a known
axis.

**Quaternions:** 4-parameter representation (w, x, y, z) with unit constraint (|q| = 1).
No gimbal lock. Efficient interpolation (SLERP). Compose by quaternion multiplication.
Convert to/from rotation matrix via well-known formulas.

Use `scipy.spatial.transform.Rotation` for converting between representations. It supports
all common conventions and provides batch operations.

### Applying Transforms to Meshes

Transform all vertices of a mesh by multiplying them with the transformation matrix. For
trimesh meshes, use `mesh.apply_transform(matrix)`. For raw numpy arrays:

```python
from __future__ import annotations

import numpy as np
from numpy.typing import NDArray
from scipy.spatial.transform import Rotation


def make_transform(
    rotation: Rotation | None = None,
    translation: NDArray[np.float64] | None = None,
    scale: float = 1.0,
) -> NDArray[np.float64]:
    """Construct a 4x4 homogeneous transformation matrix.

    Parameters
    ----------
    rotation : Rotation | None
        A scipy Rotation object. Defaults to identity rotation.
    translation : NDArray[np.float64] | None
        A (3,) translation vector. Defaults to zero translation.
    scale : float
        Uniform scale factor. Defaults to 1.0 (no scaling).

    Returns
    -------
    NDArray[np.float64]
        (4, 4) homogeneous transformation matrix.
    """
    mat = np.eye(4, dtype=np.float64)

    if rotation is not None:
        mat[:3, :3] = rotation.as_matrix() * scale
    elif scale != 1.0:
        mat[:3, :3] *= scale

    if translation is not None:
        mat[:3, 3] = translation

    return mat


def transform_points(
    points: NDArray[np.float64],
    matrix: NDArray[np.float64],
) -> NDArray[np.float64]:
    """Apply a 4x4 homogeneous transform to an array of 3D points.

    Parameters
    ----------
    points : NDArray[np.float64]
        (N, 3) array of 3D points.
    matrix : NDArray[np.float64]
        (4, 4) homogeneous transformation matrix.

    Returns
    -------
    NDArray[np.float64]
        (N, 3) transformed points.
    """
    n = len(points)
    # Convert to homogeneous coordinates: (N, 4)
    ones = np.ones((n, 1), dtype=np.float64)
    homogeneous = np.hstack([points, ones])

    # Apply transform: (N, 4) @ (4, 4)^T = (N, 4)
    transformed = homogeneous @ matrix.T

    return transformed[:, :3]


def transform_normals(
    normals: NDArray[np.float64],
    matrix: NDArray[np.float64],
) -> NDArray[np.float64]:
    """Transform normal vectors by the inverse-transpose of the upper-left 3x3.

    Normals must be transformed by (M^{-1})^T, not by M itself, to remain
    perpendicular to the surface after non-uniform scaling.

    Parameters
    ----------
    normals : NDArray[np.float64]
        (N, 3) normal vectors.
    matrix : NDArray[np.float64]
        (4, 4) homogeneous transformation matrix.

    Returns
    -------
    NDArray[np.float64]
        (N, 3) transformed and re-normalized normal vectors.
    """
    # Extract upper-left 3x3 and compute inverse-transpose
    upper_3x3 = matrix[:3, :3]
    normal_matrix = np.linalg.inv(upper_3x3).T

    transformed = normals @ normal_matrix.T

    # Re-normalize
    lengths = np.linalg.norm(transformed, axis=1, keepdims=True)
    lengths = np.maximum(lengths, np.finfo(np.float64).tiny)

    return transformed / lengths


def quaternion_slerp(
    q0: NDArray[np.float64],
    q1: NDArray[np.float64],
    t: float,
) -> NDArray[np.float64]:
    """Spherical linear interpolation between two unit quaternions.

    Parameters
    ----------
    q0 : NDArray[np.float64]
        (4,) start quaternion [w, x, y, z].
    q1 : NDArray[np.float64]
        (4,) end quaternion [w, x, y, z].
    t : float
        Interpolation parameter in [0, 1].

    Returns
    -------
    NDArray[np.float64]
        (4,) interpolated unit quaternion.
    """
    dot = np.dot(q0, q1)

    # Ensure shortest path (negate if dot product is negative)
    if dot < 0.0:
        q1 = -q1
        dot = -dot

    # Clamp to avoid numerical issues with arccos
    dot = np.clip(dot, -1.0, 1.0)

    # If quaternions are very close, use linear interpolation
    if dot > 0.9995:
        result = q0 + t * (q1 - q0)
        return result / np.linalg.norm(result)

    theta = np.arccos(dot)
    sin_theta = np.sin(theta)

    w0 = np.sin((1.0 - t) * theta) / sin_theta
    w1 = np.sin(t * theta) / sin_theta

    return w0 * q0 + w1 * q1
```

---

## 13. Topology Traversal

Topology traversal refers to navigating the relationships between topological entities
in a BRep or mesh data structure. In OpenCascade-based CAD kernels, the topological
hierarchy is:

```
Compound > CompSolid > Solid > Shell > Face > Wire > Edge > Vertex
```

Each entity at a higher level contains entities at lower levels. A Solid contains Shells,
each Shell contains Faces, each Face is bounded by one or more Wires (outer boundary and
inner holes), and each Wire is a sequence of connected Edges.

### Traversal Patterns in OpenCascade (OCP/CadQuery)

Use `TopExp_Explorer` to iterate over sub-shapes of a specific type within a parent shape.
Use `TopTools_IndexedMapOfShape` to build a map of unique sub-shapes for counting and
deduplication (since the same edge may be shared by two faces).

Common traversal operations:
- **All faces of a solid**: `TopExp_Explorer(solid, TopAbs_FACE)`
- **All edges of a face**: `TopExp_Explorer(face, TopAbs_EDGE)`
- **All wires of a face**: `TopExp_Explorer(face, TopAbs_WIRE)`
- **Adjacent faces sharing an edge**: use `TopTools_IndexedDataMapOfShapeListOfShape`

### Mesh Topology Traversal

For triangle meshes without a half-edge structure, trimesh provides adjacency information:
- `mesh.face_adjacency`: pairs of face indices that share an edge
- `mesh.face_adjacency_edges`: the vertex indices of the shared edge for each pair
- `mesh.vertex_faces`: for each vertex, the list of face indices that contain it
- `mesh.edges_unique`: all unique edges in the mesh
- `mesh.edges_face`: mapping from edges to adjacent faces

### Feature Edge Detection

Feature edges are edges where adjacent face normals differ by more than a threshold angle.
These correspond to sharp edges, creases, or corners of the model and are important for:
- Rendering (smooth vs. flat shading boundaries)
- Mesh segmentation (splitting a mesh into smooth patches)
- CAD feature recognition

Compute the dihedral angle between adjacent faces:
```
cos_angle = dot(normal_face_a, normal_face_b)
angle = arccos(clamp(cos_angle, -1, 1))
```

Edges where `angle > threshold` (typically 30-45 degrees) are feature edges.

---

## Best Practices

### Numerical Robustness

- Use `np.float64` for all geometric computations. `float32` accumulates errors that
  corrupt topology in boolean operations and intersection tests.
- When comparing floating-point values, always use a tolerance: `np.isclose(a, b, atol=1e-10)`
  rather than exact equality.
- Normalize vectors explicitly after every operation that could change their length
  (rotation, addition, interpolation). Do not assume vectors remain normalized after
  multiple operations.
- Use robust geometric predicates (exact arithmetic) for orientation and incircle tests
  when implementing Delaunay triangulation or boolean operations. The `robustpredicates`
  package provides Python bindings to Shewchuk's predicates.
- Avoid computing cross products of nearly parallel vectors; the result is numerically
  unstable. Check the magnitude of the cross product and handle the degenerate case.

### Memory and Performance

- Vectorize all per-vertex and per-face operations using numpy. A Python loop over 100k
  triangles is roughly 100x slower than the equivalent numpy operation.
- Use contiguous arrays (`np.ascontiguousarray`) before passing data to C extensions or
  GPU upload paths. Non-contiguous arrays trigger silent copies in some libraries and
  segfaults in others.
- For large meshes (> 1M triangles), use `np.float32` for vertex positions if the
  application tolerates it (visualization, approximate physics). This halves memory usage
  and improves cache utilization.
- Build spatial indices (BVH, k-d tree) once and reuse for multiple queries. Rebuilding
  per query negates the speedup.
- Use `trimesh.util.concatenate` to merge multiple meshes into one before performing batch
  operations. Operating on one large mesh is faster than iterating over many small meshes.

### Mesh Quality

- Always validate mesh watertightness after constructing or modifying a mesh:
  `mesh.is_watertight`. Non-watertight meshes cause incorrect boolean operations, volume
  computations, and ray-based inside/outside tests.
- Fix winding order before exporting: `mesh.fix_normals()`. Inconsistent winding causes
  rendering artifacts and incorrect normal-based computations.
- Remove degenerate triangles (zero area) after any operation that modifies vertex positions
  (simplification, smoothing, boolean operations). Degenerate triangles cause NaN normals
  and division-by-zero errors.
- Merge duplicate vertices after importing meshes from STL (which stores vertices per-face
  with no sharing) using `mesh.merge_vertices()`.
- Check for non-manifold edges (shared by more than two faces) and non-manifold vertices
  (whose removal would disconnect the mesh). Non-manifold geometry breaks most geometry
  processing algorithms.

### API Design

- Accept `NDArray[np.float64]` and return `NDArray[np.float64]` for all geometry functions.
  Convert from other types at the API boundary, not deep inside computation.
- Separate topology (connectivity) from geometry (positions). Functions that modify
  connectivity should not also transform positions, and vice versa.
- Return validation results as structured data (dataclasses or typed dicts), not as print
  statements or exceptions. Let the caller decide how to handle issues.
- Prefer immutable mesh operations (return a new mesh) over in-place mutation. This avoids
  subtle bugs from shared references and makes it easier to implement undo/redo.

---

## Anti-Patterns

### Using Python Loops for Per-Element Geometry Operations

```python
# WRONG: Python loop over triangles
normals = []
for i in range(len(faces)):
    v0 = vertices[faces[i, 0]]
    v1 = vertices[faces[i, 1]]
    v2 = vertices[faces[i, 2]]
    e1 = v1 - v0
    e2 = v2 - v0
    normals.append(np.cross(e1, e2))
normals = np.array(normals)

# RIGHT: Vectorized numpy operation
v0 = vertices[faces[:, 0]]
v1 = vertices[faces[:, 1]]
v2 = vertices[faces[:, 2]]
normals = np.cross(v1 - v0, v2 - v0)
```

The vectorized version is typically 50-200x faster for meshes with > 10k faces.

### Ignoring Winding Order

Constructing meshes without consistent winding order and assuming normals will be correct
is a common source of bugs. Always enforce CCW winding for outward-facing normals and
validate with `mesh.fix_normals()` after construction.

### Using float32 for CAD Geometry

Using `np.float32` for vertex positions in CAD workflows leads to precision loss at
distances far from the origin. A float32 value at 1000.0 has a precision of about 0.06mm,
which is unacceptable for machining tolerances. Always use `np.float64` for CAD.

### Performing Booleans on Non-Watertight Meshes

Boolean operations require watertight, consistently oriented input meshes. Performing
booleans on open meshes or meshes with inconsistent normals produces garbage output or
crashes. Always validate inputs before boolean operations.

### Rebuilding Spatial Indices Per Query

```python
# WRONG: Building k-d tree inside a loop
for point in query_points:
    tree = cKDTree(mesh_vertices)  # rebuilt every iteration
    dist, idx = tree.query(point)

# RIGHT: Build once, query many times
tree = cKDTree(mesh_vertices)
distances, indices = tree.query(query_points)  # batch query
```

### Ignoring Degenerate Triangles

Degenerate triangles (zero area, collinear vertices) produce NaN normals and division-by-zero
errors in downstream operations. Always filter them after mesh modification operations:

```python
# Remove degenerate faces
areas = mesh.area_faces
valid = areas > np.finfo(np.float64).tiny
mesh.update_faces(valid)
```

### Mixing Coordinate Frames Without Tracking

Performing geometric operations on points from different coordinate frames (e.g., local
part coordinates vs. assembly coordinates) without explicit frame tracking produces
incorrect results. Always transform all geometry into a common frame before computation,
and document the frame convention (right-handed, Z-up vs Y-up, units).

### Not Handling Non-Manifold Geometry

Assuming all input meshes are manifold (each edge shared by exactly two faces, each vertex
has a disc-like neighborhood) causes crashes in algorithms that rely on manifold topology
(half-edge construction, subdivision, boolean operations). Always check:

```python
# Check for non-manifold conditions
edges = mesh.edges_sorted
unique_edges, edge_counts = np.unique(edges, axis=0, return_counts=True)
non_manifold_edges = unique_edges[edge_counts > 2]
if len(non_manifold_edges) > 0:
    raise ValueError(f"Mesh has {len(non_manifold_edges)} non-manifold edges")
```

---

## Sources & References

- **trimesh documentation** -- comprehensive mesh processing library for Python:
  https://trimesh.org/
- **scipy.spatial reference** -- Delaunay triangulation, convex hull, k-d tree, Voronoi:
  https://docs.scipy.org/doc/scipy/reference/spatial.html
- **Computational Geometry: Algorithms and Applications (de Berg et al.)** -- textbook
  covering fundamental algorithms including Delaunay, convex hull, and spatial indexing:
  https://link.springer.com/book/10.1007/978-3-540-77974-2
- **OpenCascade Technology documentation** -- BRep topology, tessellation, and boolean
  operations in the standard open-source CAD kernel:
  https://dev.opencascade.org/doc/overview/html/index.html
- **Garland & Heckbert, Surface Simplification Using Quadric Error Metrics (SIGGRAPH 1997)** --
  foundational paper on QEM-based mesh decimation:
  https://www.cs.cmu.edu/~garland/Papers/quadrics.pdf
- **Manifold library** -- robust boolean operations with guaranteed manifold output:
  https://github.com/elalish/manifold
- **Open3D documentation** -- point cloud and mesh processing with spatial indexing:
  https://www.open3d.org/docs/release/

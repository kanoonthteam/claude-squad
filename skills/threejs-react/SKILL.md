---
name: threejs-react
description: Three.js with React Three Fiber and Drei for declarative 3D scene setup, mesh rendering, materials, lighting, camera controls, model loading, animation, raycasting, and performance optimization
---

# Three.js with React Three Fiber

Production-ready patterns for building 3D scenes and CAD-style applications using React Three Fiber (`@react-three/fiber`), React Three Drei (`@react-three/drei`), and the Three.js ecosystem. Covers the full stack of 3D web development: Canvas setup, scene graphs, geometries, materials, lighting, cameras, model loading with DRACO compression, animation, interaction, post-processing, and performance optimization.

## Table of Contents

1. [Canvas Setup & Scene Graph](#canvas-setup--scene-graph)
2. [Declarative Mesh Creation](#declarative-mesh-creation)
3. [Geometries](#geometries)
4. [Materials](#materials)
5. [Lighting](#lighting)
6. [Camera Setup & Controls](#camera-setup--controls)
7. [Drei Helpers](#drei-helpers)
8. [Model Loading](#model-loading)
9. [DRACO Compression & Mesh Optimization](#draco-compression--mesh-optimization)
10. [Animation with useFrame](#animation-with-useframe)
11. [Raycasting & Interaction](#raycasting--interaction)
12. [Post-Processing Effects](#post-processing-effects)
13. [Responsive Canvas & Window Resize](#responsive-canvas--window-resize)
14. [Performance Optimization](#performance-optimization)
15. [Memory Management](#memory-management)
16. [Best Practices](#best-practices)
17. [Anti-Patterns](#anti-patterns)
18. [Sources & References](#sources--references)

---

## Canvas Setup & Scene Graph

The `<Canvas>` component from `@react-three/fiber` is the root of every R3F application. It creates a WebGL renderer, a default scene, and a default camera. Every child of `<Canvas>` is added to the Three.js scene graph.

### Basic Canvas

```tsx
// components/Scene.tsx
import { Canvas } from '@react-three/fiber';
import type { FC } from 'react';

interface SceneProps {
  children: React.ReactNode;
}

export const Scene: FC<SceneProps> = ({ children }) => {
  return (
    <Canvas
      gl={{
        antialias: true,
        alpha: false,
        powerPreference: 'high-performance',
        stencil: false,
        depth: true,
      }}
      dpr={[1, 2]}
      shadows
      camera={{ position: [5, 5, 5], fov: 50, near: 0.1, far: 1000 }}
      style={{ width: '100%', height: '100vh' }}
      onCreated={({ gl }) => {
        gl.setClearColor('#1a1a2e');
      }}
    >
      {children}
    </Canvas>
  );
};
```

Key `<Canvas>` props:

| Prop | Type | Description |
|------|------|-------------|
| `gl` | `WebGLRendererParameters` | WebGL renderer options (antialias, alpha, precision) |
| `dpr` | `number \| [min, max]` | Device pixel ratio, clamp with array for performance |
| `shadows` | `boolean \| ShadowMapType` | Enable shadow maps on the renderer |
| `camera` | `CameraProps` | Default camera position, fov, near, far |
| `frameloop` | `'always' \| 'demand' \| 'never'` | Controls render loop behavior |
| `flat` | `boolean` | Disables tone mapping (use for UI overlays) |
| `linear` | `boolean` | Disables sRGB color space conversion |
| `orthographic` | `boolean` | Use an orthographic camera by default |

### Scene Graph Hierarchy

R3F maps JSX to Three.js objects. Every lowercase JSX element corresponds to a Three.js class:

- `<mesh>` creates a `THREE.Mesh`
- `<group>` creates a `THREE.Group`
- `<ambientLight>` creates a `THREE.AmbientLight`
- `<boxGeometry>` creates a `THREE.BoxGeometry`

Nesting JSX elements mirrors the Three.js parent-child scene graph. The `attach` prop controls how a child attaches to its parent (e.g., `attach="geometry"` or `attach="material"`).

---

## Declarative Mesh Creation

A mesh in Three.js requires two things: a geometry (the shape) and a material (the appearance). In R3F, these are declared as children of the `<mesh>` element.

```tsx
// components/BasicShapes.tsx
import { useRef } from 'react';
import { Mesh } from 'three';

export function BasicShapes() {
  const cubeRef = useRef<Mesh>(null);

  return (
    <group>
      {/* Box */}
      <mesh position={[-2, 0, 0]} castShadow receiveShadow>
        <boxGeometry args={[1, 1, 1]} />
        <meshStandardMaterial color="#e63946" roughness={0.4} metalness={0.6} />
      </mesh>

      {/* Sphere */}
      <mesh position={[0, 0, 0]} castShadow>
        <sphereGeometry args={[0.7, 64, 64]} />
        <meshStandardMaterial color="#457b9d" roughness={0.2} metalness={0.8} />
      </mesh>

      {/* Torus Knot */}
      <mesh ref={cubeRef} position={[2, 0, 0]} castShadow>
        <torusKnotGeometry args={[0.5, 0.15, 128, 32]} />
        <meshPhysicalMaterial
          color="#2a9d8f"
          roughness={0.1}
          metalness={1.0}
          clearcoat={1.0}
          clearcoatRoughness={0.1}
        />
      </mesh>

      {/* Ground plane */}
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, -1, 0]} receiveShadow>
        <planeGeometry args={[20, 20]} />
        <meshStandardMaterial color="#f1faee" />
      </mesh>
    </group>
  );
}
```

Common mesh props:

- `position={[x, y, z]}` -- world-space position
- `rotation={[x, y, z]}` -- Euler rotation in radians
- `scale={[x, y, z]}` or `scale={uniformScale}` -- object scaling
- `castShadow` / `receiveShadow` -- shadow participation
- `visible={boolean}` -- toggle visibility without removing from scene graph
- `frustumCulled={boolean}` -- whether the renderer skips this if outside the camera frustum

---

## Geometries

R3F exposes all Three.js geometries as lowercase JSX elements. The `args` prop maps to the constructor arguments.

### Built-in Geometries

| JSX Element | Constructor Args | Description |
|-------------|-----------------|-------------|
| `<boxGeometry>` | `[width, height, depth, wSeg, hSeg, dSeg]` | Rectangular cuboid |
| `<sphereGeometry>` | `[radius, widthSeg, heightSeg]` | UV sphere |
| `<cylinderGeometry>` | `[radiusTop, radiusBottom, height, radialSeg]` | Cylinder / cone |
| `<coneGeometry>` | `[radius, height, radialSeg]` | Cone |
| `<torusGeometry>` | `[radius, tube, radialSeg, tubularSeg]` | Torus (donut) |
| `<torusKnotGeometry>` | `[radius, tube, tubularSeg, radialSeg, p, q]` | Torus knot |
| `<planeGeometry>` | `[width, height, wSeg, hSeg]` | Flat plane |
| `<ringGeometry>` | `[innerRadius, outerRadius, thetaSeg]` | Ring / annulus |
| `<circleGeometry>` | `[radius, segments]` | Filled circle |
| `<extrudeGeometry>` | `[shapes, options]` | Extruded 2D shape |
| `<latheGeometry>` | `[points, segments]` | Lathed revolution surface |
| `<tubeGeometry>` | `[path, tubularSeg, radius, radialSeg, closed]` | Tube along a curve |

### Custom Buffer Geometry

For procedural or CAD-style geometry, create `BufferGeometry` manually:

```tsx
// components/CustomGeometry.tsx
import { useMemo } from 'react';
import { BufferGeometry, Float32BufferAttribute, Vector3 } from 'three';

interface CustomPlaneProps {
  width: number;
  height: number;
  resolution: number;
  displaceFn?: (x: number, z: number) => number;
}

export function CustomPlane({
  width,
  height,
  resolution,
  displaceFn = (x, z) => Math.sin(x * 2) * Math.cos(z * 2) * 0.3,
}: CustomPlaneProps) {
  const geometry = useMemo(() => {
    const geo = new BufferGeometry();
    const vertices: number[] = [];
    const normals: number[] = [];
    const uvs: number[] = [];
    const indices: number[] = [];

    const stepX = width / resolution;
    const stepZ = height / resolution;

    for (let iz = 0; iz <= resolution; iz++) {
      for (let ix = 0; ix <= resolution; ix++) {
        const x = ix * stepX - width / 2;
        const z = iz * stepZ - height / 2;
        const y = displaceFn(x, z);

        vertices.push(x, y, z);
        normals.push(0, 1, 0); // Simplified; recompute for accuracy
        uvs.push(ix / resolution, iz / resolution);
      }
    }

    for (let iz = 0; iz < resolution; iz++) {
      for (let ix = 0; ix < resolution; ix++) {
        const a = iz * (resolution + 1) + ix;
        const b = a + 1;
        const c = a + (resolution + 1);
        const d = c + 1;
        indices.push(a, c, b, b, c, d);
      }
    }

    geo.setIndex(indices);
    geo.setAttribute('position', new Float32BufferAttribute(vertices, 3));
    geo.setAttribute('normal', new Float32BufferAttribute(normals, 3));
    geo.setAttribute('uv', new Float32BufferAttribute(uvs, 2));
    geo.computeVertexNormals();

    return geo;
  }, [width, height, resolution, displaceFn]);

  return (
    <mesh geometry={geometry} receiveShadow>
      <meshStandardMaterial color="#a8dadc" wireframe={false} side={2} />
    </mesh>
  );
}
```

---

## Materials

### MeshStandardMaterial (PBR)

The workhorse material for physically-based rendering. Uses the metallic-roughness workflow.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `color` | `string \| Color` | `#ffffff` | Base color (albedo) |
| `roughness` | `number` | `1.0` | Surface roughness (0 = mirror, 1 = diffuse) |
| `metalness` | `number` | `0.0` | Metallicity (0 = dielectric, 1 = metal) |
| `map` | `Texture` | `null` | Albedo texture map |
| `normalMap` | `Texture` | `null` | Normal map for surface detail |
| `roughnessMap` | `Texture` | `null` | Per-pixel roughness |
| `metalnessMap` | `Texture` | `null` | Per-pixel metalness |
| `aoMap` | `Texture` | `null` | Ambient occlusion map |
| `envMapIntensity` | `number` | `1.0` | Environment map reflection intensity |
| `emissive` | `string \| Color` | `#000000` | Emissive (glow) color |
| `emissiveIntensity` | `number` | `1.0` | Emissive brightness |

### MeshPhysicalMaterial (Advanced PBR)

Extends `MeshStandardMaterial` with additional physical properties:

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `clearcoat` | `number` | `0.0` | Clearcoat layer intensity (car paint, lacquer) |
| `clearcoatRoughness` | `number` | `0.0` | Clearcoat layer roughness |
| `transmission` | `number` | `0.0` | Optical transmission (0 = opaque, 1 = transparent) |
| `thickness` | `number` | `0.0` | Volume thickness for transmission |
| `ior` | `number` | `1.5` | Index of refraction |
| `sheen` | `number` | `0.0` | Sheen layer intensity (fabric) |
| `sheenRoughness` | `number` | `1.0` | Sheen layer roughness |
| `sheenColor` | `string \| Color` | `#000000` | Sheen tint color |
| `iridescence` | `number` | `0.0` | Thin-film iridescence intensity |
| `iridescenceIOR` | `number` | `1.3` | Iridescence index of refraction |

### Custom Shader Material

For effects beyond PBR, use `shaderMaterial` from Drei or raw `<shaderMaterial>`:

```tsx
// components/GradientMaterial.tsx
import { shaderMaterial } from '@react-three/drei';
import { extend, type ReactThreeFiber } from '@react-three/fiber';
import { Color } from 'three';

const GradientShaderMaterial = shaderMaterial(
  {
    uColorA: new Color('#1a1a2e'),
    uColorB: new Color('#e94560'),
    uTime: 0,
  },
  // Vertex shader
  /* glsl */ `
    varying vec2 vUv;
    void main() {
      vUv = uv;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }
  `,
  // Fragment shader
  /* glsl */ `
    uniform vec3 uColorA;
    uniform vec3 uColorB;
    uniform float uTime;
    varying vec2 vUv;
    void main() {
      float mixFactor = vUv.y + sin(vUv.x * 6.2831 + uTime) * 0.1;
      vec3 color = mix(uColorA, uColorB, mixFactor);
      gl_FragColor = vec4(color, 1.0);
    }
  `
);

extend({ GradientShaderMaterial });

declare module '@react-three/fiber' {
  interface ThreeElements {
    gradientShaderMaterial: ReactThreeFiber.MaterialNode<
      InstanceType<typeof GradientShaderMaterial>,
      typeof GradientShaderMaterial
    >;
  }
}

export { GradientShaderMaterial };
```

Usage with the `useFrame` hook to animate uniforms:

```tsx
import { useRef } from 'react';
import { useFrame } from '@react-three/fiber';
import type { ShaderMaterial } from 'three';

export function GradientSphere() {
  const materialRef = useRef<ShaderMaterial>(null);

  useFrame((state) => {
    if (materialRef.current) {
      materialRef.current.uniforms.uTime.value = state.clock.elapsedTime;
    }
  });

  return (
    <mesh>
      <sphereGeometry args={[1, 64, 64]} />
      <gradientShaderMaterial ref={materialRef} />
    </mesh>
  );
}
```

### Texture Loading

Use `useTexture` from Drei for loading texture maps:

```tsx
import { useTexture } from '@react-three/drei';

export function TexturedBox() {
  const [colorMap, normalMap, roughnessMap, aoMap] = useTexture([
    '/textures/brick_color.jpg',
    '/textures/brick_normal.jpg',
    '/textures/brick_roughness.jpg',
    '/textures/brick_ao.jpg',
  ]);

  return (
    <mesh castShadow>
      <boxGeometry args={[2, 2, 2]} />
      <meshStandardMaterial
        map={colorMap}
        normalMap={normalMap}
        roughnessMap={roughnessMap}
        aoMap={aoMap}
      />
    </mesh>
  );
}
```

---

## Lighting

### Light Types

| Light | JSX | Key Props | Use Case |
|-------|-----|-----------|----------|
| Ambient | `<ambientLight>` | `intensity`, `color` | Base fill light, no shadows |
| Directional | `<directionalLight>` | `intensity`, `position`, `castShadow` | Sun-like parallel light |
| Point | `<pointLight>` | `intensity`, `position`, `distance`, `decay` | Omnidirectional light source |
| Spot | `<spotLight>` | `intensity`, `position`, `angle`, `penumbra` | Cone-shaped focused light |
| Hemisphere | `<hemisphereLight>` | `skyColor`, `groundColor`, `intensity` | Sky + ground ambient |
| Rect Area | `<rectAreaLight>` | `width`, `height`, `intensity` | Soft area light (no shadow) |

### Shadow Configuration

Directional light shadows require configuring the shadow camera frustum for quality:

```tsx
<directionalLight
  position={[10, 15, 10]}
  intensity={1.5}
  castShadow
  shadow-mapSize-width={2048}
  shadow-mapSize-height={2048}
  shadow-camera-near={0.5}
  shadow-camera-far={50}
  shadow-camera-left={-10}
  shadow-camera-right={10}
  shadow-camera-top={10}
  shadow-camera-bottom={-10}
  shadow-bias={-0.0001}
/>
```

### Environment Maps with Drei

Environment maps provide image-based lighting (IBL) for realistic reflections:

```tsx
import { Environment } from '@react-three/drei';

// Using an HDRI preset
<Environment preset="sunset" background blur={0.5} />

// Using a custom HDR file
<Environment files="/hdri/warehouse.hdr" background />

// Generating environment from scene content
<Environment ground={{ height: 15, radius: 60, scale: 1000 }}>
  <mesh scale={100}>
    <sphereGeometry args={[1, 64, 64]} />
    <meshBasicMaterial color="#839681" side={1} />
  </mesh>
</Environment>
```

Available `Environment` presets: `apartment`, `city`, `dawn`, `forest`, `lobby`, `night`, `park`, `studio`, `sunset`, `warehouse`.

---

## Camera Setup & Controls

### PerspectiveCamera

The default camera type. Set it declaratively or via Drei:

```tsx
import { PerspectiveCamera, OrbitControls } from '@react-three/drei';

export function CameraRig() {
  return (
    <>
      <PerspectiveCamera
        makeDefault
        position={[5, 5, 5]}
        fov={50}
        near={0.1}
        far={1000}
      />
      <OrbitControls
        enableDamping
        dampingFactor={0.05}
        minDistance={2}
        maxDistance={20}
        maxPolarAngle={Math.PI / 2}
        target={[0, 0, 0]}
      />
    </>
  );
}
```

### OrthographicCamera

Used for CAD/engineering views where perspective distortion is undesirable:

```tsx
import { OrthographicCamera, OrbitControls } from '@react-three/drei';

export function OrthoView() {
  return (
    <>
      <OrthographicCamera
        makeDefault
        position={[0, 10, 0]}
        zoom={50}
        near={0.1}
        far={1000}
      />
      <OrbitControls enableRotate={false} />
    </>
  );
}
```

### Camera Controls Comparison

| Control | Import | Features |
|---------|--------|----------|
| `OrbitControls` | `@react-three/drei` | Orbit around target; damping; zoom/pan limits |
| `MapControls` | `@react-three/drei` | Like OrbitControls but screen-space panning |
| `TrackballControls` | `@react-three/drei` | Full trackball rotation without gimbal lock |
| `FlyControls` | `@react-three/drei` | Free-flying first-person camera |
| `CameraControls` | `@react-three/drei` | Feature-rich, camera-controls library wrapper |
| `ScrollControls` | `@react-three/drei` | Scroll-driven camera animation |

### Programmatic Camera Animation

```tsx
import { useRef } from 'react';
import { useFrame, useThree } from '@react-three/fiber';
import { Vector3 } from 'three';

export function AnimatedCamera() {
  const { camera } = useThree();
  const target = useRef(new Vector3(0, 0, 0));

  useFrame((state) => {
    const t = state.clock.elapsedTime * 0.3;
    camera.position.lerp(
      new Vector3(Math.sin(t) * 8, 5, Math.cos(t) * 8),
      0.02
    );
    camera.lookAt(target.current);
  });

  return null;
}
```

---

## Drei Helpers

`@react-three/drei` provides a rich collection of helpers that simplify common 3D tasks.

### Stage

Automatic centering, shadows, and lighting for showcasing objects:

```tsx
import { Stage } from '@react-three/drei';

<Stage adjustCamera intensity={0.5} shadows="contact" environment="city">
  <MyModel />
</Stage>
```

### Html

Embed HTML/CSS inside the 3D scene, positioned in world space:

```tsx
import { Html } from '@react-three/drei';

export function Label({ position, text }: { position: [number, number, number]; text: string }) {
  return (
    <Html
      position={position}
      center
      distanceFactor={10}
      occlude
      style={{
        background: 'rgba(0,0,0,0.8)',
        color: 'white',
        padding: '4px 8px',
        borderRadius: '4px',
        fontSize: '12px',
        whiteSpace: 'nowrap',
        pointerEvents: 'none',
      }}
    >
      {text}
    </Html>
  );
}
```

### Other Useful Drei Components

| Component | Purpose |
|-----------|---------|
| `Center` | Automatically center children at the origin |
| `Float` | Animate children with a gentle floating motion |
| `Text` / `Text3D` | Render text in 3D (SDF / geometry-based) |
| `Line` / `QuadraticBezierLine` | Draw lines and curves |
| `Edges` | Render wireframe edges on geometry |
| `Outlines` | Render outlines around meshes (toon/CAD style) |
| `MeshReflectorMaterial` | Reflective floor material |
| `MeshTransmissionMaterial` | Physically accurate glass/transmission |
| `ContactShadows` | Baked contact shadows on a plane |
| `AccumulativeShadows` | Soft accumulated shadows from multiple samples |
| `Sky` / `Stars` | Procedural sky and starfield |
| `Grid` | Infinite-style grid plane (CAD/engineering) |
| `GizmoHelper` / `GizmoViewport` | Navigation gizmo (axis orientation cube) |
| `TransformControls` | Interactive translate/rotate/scale gizmo |
| `Bounds` / `useBounds` | Fit camera to selection bounds |
| `ScreenSpace` | Render children in screen space |
| `Sparkles` / `Cloud` | Particle effects |
| `useHelper` | Attach Three.js helpers (box, skeleton, etc.) |

### Grid for CAD-Style Views

```tsx
import { Grid, GizmoHelper, GizmoViewport } from '@react-three/drei';

export function CadScene() {
  return (
    <>
      <Grid
        infiniteGrid
        cellSize={1}
        cellThickness={0.5}
        sectionSize={5}
        sectionThickness={1.5}
        sectionColor="#6f6f6f"
        cellColor="#444444"
        fadeDistance={30}
        fadeStrength={1}
      />
      <GizmoHelper alignment="bottom-right" margin={[80, 80]}>
        <GizmoViewport axisColors={['#e63946', '#2a9d8f', '#457b9d']} labelColor="white" />
      </GizmoHelper>
    </>
  );
}
```

---

## Model Loading

### useGLTF (Recommended)

`useGLTF` from Drei wraps Three.js `GLTFLoader` with caching and Suspense support:

```tsx
// components/Model.tsx
import { Suspense, useRef } from 'react';
import { useGLTF } from '@react-three/drei';
import { Group } from 'three';
import type { GLTF } from 'three-stdlib';

type ModelGLTF = GLTF & {
  nodes: {
    Body: THREE.Mesh;
    Wheels: THREE.Mesh;
    Glass: THREE.Mesh;
  };
  materials: {
    CarPaint: THREE.MeshStandardMaterial;
    Chrome: THREE.MeshStandardMaterial;
    Glass: THREE.MeshPhysicalMaterial;
  };
};

interface CarModelProps {
  position?: [number, number, number];
  color?: string;
}

export function CarModel({ position = [0, 0, 0], color = '#e63946' }: CarModelProps) {
  const groupRef = useRef<Group>(null);
  const { nodes, materials } = useGLTF('/models/car.glb') as ModelGLTF;

  return (
    <group ref={groupRef} position={position} dispose={null}>
      <mesh
        geometry={nodes.Body.geometry}
        castShadow
        receiveShadow
      >
        <meshPhysicalMaterial
          {...materials.CarPaint}
          color={color}
          clearcoat={1}
          clearcoatRoughness={0.1}
          metalness={0.9}
          roughness={0.2}
        />
      </mesh>
      <mesh
        geometry={nodes.Wheels.geometry}
        material={materials.Chrome}
        castShadow
      />
      <mesh geometry={nodes.Glass.geometry}>
        <meshPhysicalMaterial
          {...materials.Glass}
          transmission={0.95}
          thickness={0.5}
          roughness={0}
          ior={1.5}
        />
      </mesh>
    </group>
  );
}

// Preload for faster initial render
useGLTF.preload('/models/car.glb');
```

Always wrap model components in `<Suspense>`:

```tsx
import { Suspense } from 'react';
import { Canvas } from '@react-three/fiber';
import { CarModel } from './Model';

export function App() {
  return (
    <Canvas shadows>
      <Suspense fallback={null}>
        <CarModel position={[0, 0, 0]} color="#457b9d" />
      </Suspense>
      <ambientLight intensity={0.4} />
      <directionalLight position={[10, 10, 5]} intensity={1} castShadow />
    </Canvas>
  );
}
```

### useLoader (Generic)

For non-GLTF formats or custom loaders:

```tsx
import { useLoader } from '@react-three/fiber';
import { OBJLoader } from 'three-stdlib';
import { STLLoader } from 'three-stdlib';

// OBJ
export function ObjModel() {
  const obj = useLoader(OBJLoader, '/models/part.obj');
  return <primitive object={obj} scale={0.01} />;
}

// STL (common in CAD/3D printing)
export function StlModel() {
  const geometry = useLoader(STLLoader, '/models/bracket.stl');
  return (
    <mesh geometry={geometry} castShadow>
      <meshStandardMaterial color="#a8dadc" roughness={0.5} metalness={0.3} />
    </mesh>
  );
}
```

### Generating Typed Models with gltfjsx

Use the `gltfjsx` CLI to auto-generate typed React components from `.glb`/`.gltf` files:

```bash
npx gltfjsx model.glb --types --transform
```

This produces a ready-to-use TypeScript component with all nodes and materials typed, plus it can apply DRACO compression and mesh optimization via the `--transform` flag.

---

## DRACO Compression & Mesh Optimization

### DRACO Compression

DRACO reduces `.glb` file sizes by 80-90% for geometry data. Enable it in `useGLTF`:

```tsx
import { useGLTF } from '@react-three/drei';

export function CompressedModel() {
  const { scene } = useGLTF('/models/building.glb', '/draco/');
  return <primitive object={scene} />;
}

// The second arg is the DRACO decoder path.
// Host the decoder files from node_modules/three/examples/jsm/libs/draco/
// or use the CDN: 'https://www.gstatic.com/draco/versioned/decoders/1.5.6/'
```

### Mesh Optimization Pipeline

1. **gltf-transform** -- CLI for compressing and optimizing glTF/glb assets:

```bash
# Install
pnpm add -D @gltf-transform/cli

# Compress with DRACO
npx gltf-transform draco input.glb output.glb

# Optimize (dedup, weld, simplify)
npx gltf-transform optimize input.glb output.glb

# Texture compression with KTX2 (basis universal)
npx gltf-transform ktx2 input.glb output.glb --slots "baseColor"

# Full pipeline
npx gltf-transform optimize input.glb temp.glb && \
npx gltf-transform draco temp.glb output.glb
```

2. **Mesh simplification** -- Reduce polygon count while preserving visual quality:

```bash
npx gltf-transform simplify input.glb output.glb --ratio 0.5 --error 0.001
```

3. **Texture optimization** -- Resize and compress textures:

```bash
npx gltf-transform resize input.glb output.glb --width 1024 --height 1024
```

---

## Animation with useFrame

The `useFrame` hook runs every frame (typically 60fps). Use it for procedural animations, physics updates, and uniform updates.

```tsx
// components/AnimatedScene.tsx
import { useRef } from 'react';
import { useFrame } from '@react-three/fiber';
import { Mesh, MathUtils } from 'three';

interface SpinningCubeProps {
  speed?: number;
  floatAmplitude?: number;
}

export function SpinningCube({ speed = 1, floatAmplitude = 0.5 }: SpinningCubeProps) {
  const meshRef = useRef<Mesh>(null);

  useFrame((state, delta) => {
    if (!meshRef.current) return;

    // Rotate based on delta time (frame-rate independent)
    meshRef.current.rotation.y += delta * speed;
    meshRef.current.rotation.x += delta * speed * 0.3;

    // Float up and down with sine wave
    meshRef.current.position.y =
      Math.sin(state.clock.elapsedTime * speed) * floatAmplitude;
  });

  return (
    <mesh ref={meshRef} castShadow>
      <boxGeometry args={[1, 1, 1]} />
      <meshStandardMaterial color="#e63946" />
    </mesh>
  );
}
```

### useFrame Priority

When multiple `useFrame` callbacks need ordering, use the priority parameter. Lower values run first:

```tsx
// Physics update (runs first)
useFrame((state, delta) => {
  // Update physics world
}, -1);

// Render update (runs after physics)
useFrame((state, delta) => {
  // Update visual positions from physics bodies
}, 0);
```

### Conditional Rendering with useFrame

Avoid running `useFrame` when not needed. Use R3F's `frameloop="demand"` on Canvas and call `invalidate()` when changes occur:

```tsx
import { useThree } from '@react-three/fiber';

export function OnDemandUpdater() {
  const invalidate = useThree((state) => state.invalidate);

  const handleChange = () => {
    // Trigger a re-render only when something changes
    invalidate();
  };

  return <mesh onClick={handleChange}>...</mesh>;
}
```

---

## Raycasting & Interaction

R3F provides built-in event handling on mesh elements. Under the hood, it uses Three.js `Raycaster` for mouse/pointer intersection testing.

### Pointer Events

```tsx
// components/InteractiveMesh.tsx
import { useState, useCallback, useRef } from 'react';
import { useFrame } from '@react-three/fiber';
import { Mesh, Color } from 'three';
import type { ThreeEvent } from '@react-three/fiber';

export function InteractiveMesh() {
  const meshRef = useRef<Mesh>(null);
  const [hovered, setHovered] = useState(false);
  const [clicked, setClicked] = useState(false);

  // Scale animation on hover/click
  useFrame(() => {
    if (!meshRef.current) return;
    const targetScale = clicked ? 1.5 : hovered ? 1.2 : 1;
    meshRef.current.scale.lerp(
      { x: targetScale, y: targetScale, z: targetScale } as any,
      0.1
    );
  });

  const handleClick = useCallback((event: ThreeEvent<MouseEvent>) => {
    event.stopPropagation(); // Prevent click from propagating to parent meshes
    setClicked((prev) => !prev);
    console.log('Hit point:', event.point);
    console.log('Face normal:', event.face?.normal);
    console.log('Distance:', event.distance);
  }, []);

  const handlePointerOver = useCallback((event: ThreeEvent<PointerEvent>) => {
    event.stopPropagation();
    setHovered(true);
    document.body.style.cursor = 'pointer';
  }, []);

  const handlePointerOut = useCallback(() => {
    setHovered(false);
    document.body.style.cursor = 'auto';
  }, []);

  return (
    <mesh
      ref={meshRef}
      onClick={handleClick}
      onPointerOver={handlePointerOver}
      onPointerOut={handlePointerOut}
      onPointerMove={(e) => {
        // Access UV coordinates for texture painting, etc.
        console.log('UV:', e.uv);
      }}
    >
      <boxGeometry args={[1, 1, 1]} />
      <meshStandardMaterial
        color={clicked ? '#e63946' : hovered ? '#f4a261' : '#457b9d'}
      />
    </mesh>
  );
}
```

### Available Pointer Events

| Event | Fires When |
|-------|-----------|
| `onClick` | Click on mesh (pointer down + up) |
| `onDoubleClick` | Double-click on mesh |
| `onPointerUp` | Pointer released on mesh |
| `onPointerDown` | Pointer pressed on mesh |
| `onPointerOver` | Pointer enters mesh (like mouseenter) |
| `onPointerOut` | Pointer leaves mesh (like mouseleave) |
| `onPointerMove` | Pointer moves over mesh |
| `onPointerMissed` | Click misses all meshes in the scene |
| `onContextMenu` | Right-click on mesh |

### ThreeEvent Properties

All pointer events provide a `ThreeEvent` with:

- `event.point` -- `Vector3` world-space intersection point
- `event.distance` -- Distance from camera to hit point
- `event.face` -- The intersected face (with normal)
- `event.faceIndex` -- Index of the intersected face
- `event.uv` -- UV coordinates at the intersection
- `event.object` -- The intersected Three.js object
- `event.ray` -- The `Ray` used for intersection
- `event.stopPropagation()` -- Stop event from bubbling to parent objects
- `event.delta` -- Distance traveled since pointer down (useful for distinguishing click vs. drag)

---

## Post-Processing Effects

Use `@react-three/postprocessing` (wraps `postprocessing` library) for GPU-accelerated effects:

```bash
pnpm add @react-three/postprocessing postprocessing
```

```tsx
// components/Effects.tsx
import { EffectComposer, Bloom, SSAO, ToneMapping, Vignette } from '@react-three/postprocessing';
import { BlendFunction, ToneMappingMode } from 'postprocessing';

export function Effects() {
  return (
    <EffectComposer multisampling={4}>
      <Bloom
        intensity={0.5}
        luminanceThreshold={0.8}
        luminanceSmoothing={0.3}
        mipmapBlur
      />
      <SSAO
        radius={0.05}
        intensity={30}
        luminanceInfluence={0.5}
        color="#000000"
      />
      <ToneMapping mode={ToneMappingMode.ACES_FILMIC} />
      <Vignette
        offset={0.3}
        darkness={0.7}
        blendFunction={BlendFunction.NORMAL}
      />
    </EffectComposer>
  );
}
```

Common post-processing effects:

| Effect | Purpose |
|--------|---------|
| `Bloom` | Glow/bloom on bright areas |
| `SSAO` | Screen-space ambient occlusion (depth-based shadows) |
| `DepthOfField` | Camera-like focus blur |
| `ToneMapping` | HDR to LDR color mapping (ACES, Reinhard, etc.) |
| `Vignette` | Darkened edges |
| `ChromaticAberration` | Color fringing at edges |
| `Noise` / `DotScreen` | Film grain and halftone effects |
| `Outline` | Selection outline around objects |
| `SMAA` / `FXAA` | Anti-aliasing (use instead of Canvas `antialias` for better quality) |
| `N8AO` | Improved AO from N8 (better than default SSAO) |

### Selection-Based Outline

```tsx
import { useState } from 'react';
import { EffectComposer, Outline, Selection, Select } from '@react-three/postprocessing';

export function SelectableScene() {
  const [selected, setSelected] = useState<string | null>(null);

  return (
    <Selection>
      <EffectComposer autoClear={false}>
        <Outline
          blur
          edgeStrength={5}
          width={1024}
          visibleEdgeColor={0xe63946}
          hiddenEdgeColor={0x457b9d}
        />
      </EffectComposer>

      <Select enabled={selected === 'box'}>
        <mesh onClick={() => setSelected('box')}>
          <boxGeometry />
          <meshStandardMaterial color="#a8dadc" />
        </mesh>
      </Select>

      <Select enabled={selected === 'sphere'}>
        <mesh position={[2, 0, 0]} onClick={() => setSelected('sphere')}>
          <sphereGeometry />
          <meshStandardMaterial color="#457b9d" />
        </mesh>
      </Select>
    </Selection>
  );
}
```

---

## Responsive Canvas & Window Resize

R3F automatically handles canvas resizing when the parent container dimensions change. The renderer and camera aspect ratio are updated automatically.

### Full-Viewport Canvas

```tsx
// Ensure the parent fills the viewport
export function FullscreenScene() {
  return (
    <div style={{ width: '100vw', height: '100vh' }}>
      <Canvas>
        {/* Scene content */}
      </Canvas>
    </div>
  );
}
```

### Responsive Container

```tsx
export function ResponsiveScene() {
  return (
    <div style={{ width: '100%', height: '100%', minHeight: '400px' }}>
      <Canvas
        resize={{ scroll: false, debounce: { scroll: 50, resize: 50 } }}
      >
        {/* Scene content */}
      </Canvas>
    </div>
  );
}
```

### Accessing Viewport Size in Components

```tsx
import { useThree } from '@react-three/fiber';

export function ResponsiveObject() {
  const { viewport, size } = useThree();

  // viewport.width / viewport.height = world-space dimensions at z=0
  // size.width / size.height = pixel dimensions of the canvas

  return (
    <mesh scale={[viewport.width / 4, viewport.height / 4, 1]}>
      <planeGeometry />
      <meshBasicMaterial color="#e63946" />
    </mesh>
  );
}
```

### useAspect for Responsive Scaling

```tsx
import { useAspect } from '@react-three/drei';

export function ResponsiveImage() {
  const scale = useAspect(1920, 1080, 1); // [width, height, factor]

  return (
    <mesh scale={scale}>
      <planeGeometry />
      <meshBasicMaterial map={/* texture */} />
    </mesh>
  );
}
```

---

## Performance Optimization

### Instanced Meshes

For rendering thousands of identical geometries (e.g., trees, particles, screws in a CAD model):

```tsx
// components/InstancedBoxes.tsx
import { useRef, useMemo } from 'react';
import { useFrame } from '@react-three/fiber';
import { InstancedMesh, Object3D, MathUtils } from 'three';

interface InstancedBoxesProps {
  count: number;
}

export function InstancedBoxes({ count = 1000 }: InstancedBoxesProps) {
  const meshRef = useRef<InstancedMesh>(null);

  const transforms = useMemo(() => {
    const temp = new Object3D();
    const data: { position: [number, number, number]; scale: number }[] = [];

    for (let i = 0; i < count; i++) {
      data.push({
        position: [
          MathUtils.randFloatSpread(20),
          MathUtils.randFloatSpread(20),
          MathUtils.randFloatSpread(20),
        ],
        scale: MathUtils.randFloat(0.1, 0.5),
      });
    }

    return data;
  }, [count]);

  // Set initial transforms
  useMemo(() => {
    if (!meshRef.current) return;
    const temp = new Object3D();

    transforms.forEach((t, i) => {
      temp.position.set(...t.position);
      temp.scale.setScalar(t.scale);
      temp.updateMatrix();
      meshRef.current!.setMatrixAt(i, temp.matrix);
    });

    meshRef.current.instanceMatrix.needsUpdate = true;
  }, [transforms]);

  return (
    <instancedMesh ref={meshRef} args={[undefined, undefined, count]} castShadow>
      <boxGeometry args={[1, 1, 1]} />
      <meshStandardMaterial color="#a8dadc" />
    </instancedMesh>
  );
}
```

### Drei Instances (Simplified)

```tsx
import { Instances, Instance } from '@react-three/drei';

export function DreInstances() {
  return (
    <Instances limit={1000} range={1000}>
      <boxGeometry />
      <meshStandardMaterial />
      {Array.from({ length: 1000 }, (_, i) => (
        <Instance
          key={i}
          position={[Math.random() * 20 - 10, Math.random() * 20 - 10, Math.random() * 20 - 10]}
          scale={Math.random() * 0.5}
          color={`hsl(${Math.random() * 360}, 70%, 60%)`}
        />
      ))}
    </Instances>
  );
}
```

### Level of Detail (LOD)

Switch between high-poly and low-poly versions based on camera distance:

```tsx
import { Detailed } from '@react-three/drei';

export function LodModel() {
  return (
    <Detailed distances={[0, 15, 30]}>
      {/* High detail: 0-15 units from camera */}
      <mesh>
        <sphereGeometry args={[1, 64, 64]} />
        <meshStandardMaterial color="#e63946" />
      </mesh>
      {/* Medium detail: 15-30 units */}
      <mesh>
        <sphereGeometry args={[1, 16, 16]} />
        <meshStandardMaterial color="#e63946" />
      </mesh>
      {/* Low detail: 30+ units */}
      <mesh>
        <sphereGeometry args={[1, 8, 8]} />
        <meshStandardMaterial color="#e63946" />
      </mesh>
    </Detailed>
  );
}
```

### BVH for Raycasting Performance

Drei's `Bvh` component builds a bounding volume hierarchy for fast raycasting on complex meshes:

```tsx
import { Bvh } from '@react-three/drei';

export function OptimizedScene() {
  return (
    <Bvh firstHitOnly>
      {/* All meshes inside Bvh get accelerated raycasting */}
      <ComplexModel />
      <AnotherComplexModel />
    </Bvh>
  );
}
```

### Frustum Culling

Frustum culling is enabled by default on all objects (`frustumCulled={true}`). For large scenes:

- Ensure bounding spheres/boxes are correct (`geometry.computeBoundingSphere()`)
- For objects that should always render (skyboxes, backgrounds), set `frustumCulled={false}`
- Use `<AdaptiveDpr>` from Drei to reduce resolution under load

### Performance Monitoring

```tsx
import { Perf } from 'r3f-perf';

export function DebugScene() {
  return (
    <>
      {process.env.NODE_ENV === 'development' && (
        <Perf position="top-left" />
      )}
      {/* Scene content */}
    </>
  );
}
```

### Additional Performance Tips

- **Merge geometries** -- Use `mergeBufferGeometries` for static objects that share a material
- **Freeze transforms** -- Call `object.matrixAutoUpdate = false` for static objects and manually update with `object.updateMatrix()` only when needed
- **Shared materials** -- Reuse material instances across meshes; define once and pass by reference
- **Texture atlases** -- Combine multiple textures into a single atlas to reduce draw calls
- **Web Workers** -- Offload heavy geometry computations to workers
- **frameloop="demand"** -- Only render when something changes (ideal for CAD viewers)
- **`<AdaptiveDpr>`** -- Dynamically lower pixel ratio when framerate drops
- **`<AdaptiveEvents>`** -- Throttle pointer events when framerate drops

---

## Memory Management

Three.js objects (geometries, materials, textures, render targets) allocate GPU memory that is NOT automatically freed by JavaScript garbage collection. You must explicitly dispose of them.

### Automatic Disposal with R3F

R3F automatically calls `dispose()` on objects when they are removed from the scene graph (unmounted). The `dispose={null}` prop on a `<group>` or `<primitive>` prevents automatic disposal (useful for shared/cached assets).

### Manual Disposal Pattern

```tsx
import { useEffect, useRef } from 'react';
import { useThree } from '@react-three/fiber';
import { Mesh, TextureLoader } from 'three';

export function DisposableModel() {
  const meshRef = useRef<Mesh>(null);
  const { gl } = useThree();

  useEffect(() => {
    return () => {
      // Cleanup on unmount
      if (meshRef.current) {
        meshRef.current.geometry.dispose();
        const material = meshRef.current.material;
        if (Array.isArray(material)) {
          material.forEach((m) => {
            m.map?.dispose();
            m.normalMap?.dispose();
            m.roughnessMap?.dispose();
            m.dispose();
          });
        } else {
          material.map?.dispose();
          material.normalMap?.dispose();
          material.roughnessMap?.dispose();
          material.dispose();
        }
      }
    };
  }, []);

  return (
    <mesh ref={meshRef}>
      <boxGeometry args={[1, 1, 1]} />
      <meshStandardMaterial color="#e63946" />
    </mesh>
  );
}
```

### Scene-Level Cleanup

For full scene teardown (e.g., navigating away from a 3D page):

```tsx
import { useThree } from '@react-three/fiber';
import { useEffect } from 'react';

export function SceneCleanup() {
  const { scene, gl } = useThree();

  useEffect(() => {
    return () => {
      scene.traverse((object) => {
        if ('geometry' in object && object.geometry) {
          (object as any).geometry.dispose();
        }
        if ('material' in object && object.material) {
          const materials = Array.isArray(object.material)
            ? object.material
            : [object.material];
          materials.forEach((mat: any) => {
            Object.keys(mat).forEach((key) => {
              const value = mat[key];
              if (value && typeof value.dispose === 'function') {
                value.dispose();
              }
            });
            mat.dispose();
          });
        }
      });
      gl.renderLists.dispose();
      gl.dispose();
    };
  }, [scene, gl]);

  return null;
}
```

### Memory Leak Checklist

- Always dispose geometries, materials, and textures on unmount
- Use `useGLTF.preload()` for caching; don't load the same model in multiple components without caching
- Remove event listeners attached to the DOM in `useEffect` cleanup
- Clear `useFrame` callbacks by unmounting the component (R3F handles this automatically)
- Call `gl.forceContextLoss()` and `gl.dispose()` when permanently leaving the 3D view
- Monitor GPU memory in Chrome DevTools > Performance > GPU or with `gl.info.memory`

---

## Best Practices

1. **Always use Suspense** around components that load async resources (models, textures, HDRIs)
2. **Preload assets** with `useGLTF.preload()`, `useTexture.preload()` to avoid loading jank
3. **Use delta time** in `useFrame` for frame-rate independent animation: `rotation += delta * speed` not `rotation += 0.01`
4. **Clamp device pixel ratio** with `dpr={[1, 2]}` to prevent performance issues on 4K displays
5. **Prefer `meshStandardMaterial`** over `meshPhysicalMaterial` unless you need clearcoat, transmission, or sheen -- physical material is significantly more expensive
6. **Use `instancedMesh`** for any repeated geometry (more than ~10 copies) to reduce draw calls
7. **Enable shadows selectively** -- only on objects that need them; use `ContactShadows` for cheaper soft shadows
8. **Use DRACO compression** for all production `.glb` files to reduce download size
9. **Type your GLTF models** using the output from `gltfjsx --types` for full TypeScript safety
10. **Use `stopPropagation()`** on pointer events to prevent unintended interactions on parent objects
11. **Prefer `frameloop="demand"`** for CAD/engineering viewers where the scene is mostly static
12. **Keep the scene graph shallow** -- deeply nested groups add traversal overhead
13. **Use `drei/Bvh`** for complex scenes with raycasting to avoid O(n) intersection tests
14. **Separate static and dynamic content** -- static meshes can skip matrix auto-update
15. **Compress textures** with KTX2/Basis Universal for significantly smaller downloads and GPU memory usage
16. **Use environment maps** for realistic reflections rather than adding more lights
17. **Profile with r3f-perf** during development to catch performance regressions early
18. **Dispose resources** explicitly when removing objects from the scene dynamically

---

## Anti-Patterns

- **Creating new objects in `useFrame`** -- Allocating `new Vector3()`, `new Color()`, etc. every frame causes GC pressure. Create refs outside the loop and reuse them.
- **Inline arrow functions as event handlers** -- `onClick={() => handleClick()}` creates a new function every render. Use `useCallback` for stable references.
- **Loading the same model multiple times** -- Without caching, each `useGLTF` call fetches the file again. Use `useGLTF.preload()` and let Drei's cache handle deduplication.
- **Using `meshPhysicalMaterial` everywhere** -- Physical material is 2-3x more expensive than standard. Reserve it for hero objects (glass, car paint, water).
- **Forgetting `stopPropagation`** on nested clickable meshes -- Events bubble up through the scene graph, triggering parent handlers unexpectedly.
- **Setting `castShadow` on every object** -- Each shadow-casting object requires an extra render pass from the light's perspective. Be selective.
- **Not using `dispose={null}` on shared geometry** -- If multiple components reference the same loaded model, the first to unmount disposes the shared resource, breaking others.
- **Running expensive computations in `useFrame`** -- The frame callback blocks the render loop. Offload heavy work to Web Workers or compute asynchronously.
- **Ignoring the `args` pattern** -- Passing props directly to geometry constructors instead of using `args={[...]}` causes the geometry to be recreated on every render.
- **Using CSS transforms on the Canvas element** -- CSS transforms on the canvas container cause misalignment between the visual position and the internal raycaster coordinates.
- **Not setting `near`/`far` on the camera** -- Default values (`0.1` to `2000`) cause z-fighting. Set them as tight as possible for your scene.
- **Adding lights inside components that render multiple times** -- Each instance adds another light, quickly exceeding GPU limits. Define lights at the scene level.
- **Using `<primitive>` without `clone()`** -- If the same loaded scene is used in multiple `<primitive>` elements, they share the same Three.js object. Use `scene.clone()` for independent instances.
- **Skipping `computeVertexNormals()`** on custom geometry -- Without normals, lighting calculations produce flat black surfaces.
- **Not handling WebGL context loss** -- On mobile and GPU-constrained devices, the browser may reclaim the WebGL context. Listen for `webglcontextlost` and `webglcontextrestored` events.

---

## Sources & References

- [React Three Fiber Official Documentation](https://r3f.docs.pmnd.rs/getting-started/introduction)
- [React Three Drei Documentation](https://drei.docs.pmnd.rs/getting-started/introduction)
- [Three.js Official Documentation](https://threejs.org/docs/)
- [React Three Fiber GitHub Repository](https://github.com/pmndrs/react-three-fiber)
- [Drei GitHub Repository -- Full Component List](https://github.com/pmndrs/drei)
- [gltfjsx -- Auto-Generate R3F Components from GLTF Models](https://github.com/pmndrs/gltfjsx)
- [React Three Postprocessing Documentation](https://react-three.github.io/postprocessing/)
- [glTF-Transform CLI for Mesh Optimization](https://gltf-transform.dev/cli)
- [Three.js Fundamentals -- How to Dispose of Objects](https://threejs.org/docs/#manual/en/introduction/How-to-dispose-of-objects)
- [Three.js Journey -- Comprehensive Three.js Course](https://threejs-journey.com/)

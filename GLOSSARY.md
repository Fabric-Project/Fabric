# Fabric Glossary

A reference for Fabric's domain terminology, covering core concepts, known inconsistencies, and concepts that would benefit from naming.

## Core Concepts

### Graph
A complete Fabric document: the set of all Nodes and their Connections. A Graph is serialisable (`Codable`), versioned, and supports undo. When saved to disk, a Graph is sometimes referred to as a **Composition** (Quartz Composer heritage), though the codebase uses `Graph` exclusively.

### Node
The fundamental processing unit. A Node has typed input and output Ports, an Execution Mode, a Time Mode, and an `execute(context:)` method. Fabric ships 165+ built-in Nodes; new ones are added by subclassing.

### Port
A typed data connection point on a Node. Ports are either **Inlets** (inputs) or **Outlets** (outputs). Two flavours exist:

| Kind | Description | UI colour |
|------|-------------|-----------|
| **Parameter Port** | Wraps a `Parameter`; carries value types (Bool, Number, Vector, Color, String, etc.) and auto-generates a UI control | Grey |
| **Object Port** | Carries reference types (Geometry, Material, Shader, Image) | Coloured per type |

### Connection
A link from one Node's Outlet to another Node's Inlet. An Outlet may feed many Inlets; an Inlet accepts one Connection.

### Parameter
A user-configurable value attached to a Parameter Port. Parameters surface as UI controls (sliders, number fields, colour pickers, dropdowns, etc.) in the Editor's inspector.

## Execution Model

### Execution Mode
Determines *when* a Node executes. Three modes exist:

| Mode | Behaviour | Typical use |
|------|-----------|-------------|
| **Provider** | Executes on demand, at most once per frame | Camera input, noise generator, constants |
| **Processor** | Executes when its inputs change or time advances | Image effects, math, transforms |
| **Consumer** | Always executes (when its Enable port is true); performs an external side-effect | Renderer, file writer, network output |

### Pull-based Evaluation
The Graph is evaluated starting from Consumer Nodes. Each Consumer recursively requests data from its upstream Nodes, which are added to an ordered execution list. Evaluation order is: Providers, then Processors, then Consumers.

### Dirty Flag
The `isDirty` property on a Node. Set `true` when inputs change; cleared after execution. A Node only re-evaluates when dirty (Consumers and Providers are special-cased to always execute).

### Time Mode
Controls a Node's relationship with time:

| Mode | Meaning |
|------|---------|
| **None** | No time dependency |
| **Idle** | Does not depend on time but needs periodic execution (e.g. hardware polling) |
| **TimeBase** | Explicitly time-dependent; uses the execution context's time parameter |

### Graph Execution Context
A `GraphExecutionContext` value passed to every Node's `execute()`. Carries timing information, iteration state (inside an Iterator), events, and user data.

## Port Data Types

### Parameter types (value semantics, grey)
`Bool`, `Index` (integer), `Number` (float), `String`, `Vector2`, `Vector3`, `Vector4`, `Color` (RGBA Vector4 wrapper), `Quaternion`, `Transform`, `Matrix` (planned).

### Object types (reference semantics, coloured)
`Geometry`, `Material`, `Shader`, `Image`.

### Array
A typed array of any of the above. Fabric arrays are homogeneously typed.

## 3D / Scene Graph

### Satin
The underlying Swift/Metal 3D rendering engine. Fabric builds its scene graph and GPU pipeline on top of Satin's abstractions (`Satin.Object`, `Satin.Mesh`, `Satin.Material`, `Satin.Geometry`).

### Object (Scene Graph)
A `Satin.Object`: a node in the 3D scene hierarchy with position, scale, and orientation (quaternion). Parent-child relationships form a transform tree. *Note: "Object" is also used for Object Ports and `ObjectType`; see Inconsistencies below.*

### Geometry
GPU buffer data (vertices, normals, UVs, indices) defining a 3D shape. In the Node type system, Geometry Nodes output a `Satin.Geometry` value.

### Material
A GPU program (vertex + fragment shader pair) applied to a Geometry to produce a rendered surface. Variants include PBR, Diffuse, Displacement, Depth, UV, Skybox.

### Mesh
A Renderable 3D object: a Geometry combined with a Material, ready to draw. Can be instanced for performance.

### Renderable
Anything that can be drawn in a scene: Meshes, Lights, Cameras. The Satin `Object` base class provides the common interface.

### Scene
The root `Satin.Object` whose children are all Renderables in a Graph. The GraphRenderer builds a Scene from the Graph's Object Nodes.

### Render Pass / Render Order
Render Pass is an index enabling multi-pass techniques (e.g. shadow mapping). Render Order is an integer controlling draw order within a pass.

## Image Processing

### FabricImage
A wrapper around `MTLTexture` for GPU image data. Can be **managed** (allocated from the Texture Cache, automatically recycled) or **unmanaged** (caller-owned lifetime).

### Texture Cache
GPU texture memory pool managed by `GraphRendererTextureCache`. Comes in Private (GPU-only) and Shared (CPU-readable) variants. Managed FabricImages are vended from here and recycled when released.

### Effect Node
An image-processing Node backed by a Metal fragment shader. Base classes are named by how many input images (channels) they accept:

| Base class | Input images |
|------------|-------------|
| `BaseEffectNode` | 1 |
| `BaseEffectTwoChannelNode` | 2 |
| `BaseEffectThreeChannelNode` | 3 |

### Generator
A Node that produces an image procedurally (noise, patterns) with no image input.

### Image Provider
A Node that sources image data from outside Fabric: file, camera, video, screen capture, Syphon.

## Subgraph System

### SubgraphNode
A Node whose implementation is an entire Graph. Enables composition and reuse.

### Published Port
A Port on a Node inside a Subgraph that is marked `published = true`, exposing it as an Inlet or Outlet on the parent SubgraphNode's interface.

### Deferred Subgraph
A SubgraphNode variant that renders its content to textures (colour + depth) rather than contributing objects to the parent scene. Useful for post-processing pipelines.

### Iterator
A SubgraphNode variant that executes its contained Graph multiple times per frame, providing iteration index, progress, and count via an Iterator Info Node.

### Environment
A SubgraphNode providing Image-Based Lighting (IBL) via Satin's `IBLScene`. Contains an Environment Skybox for HDRI maps.

## Feedback

### Feedback Cache
`GraphRendererFeedbackCache`: detects and manages feedback loops where a downstream Node's output feeds back into an upstream Node. Prevents infinite recursion by caching the previous frame's value.

## Node Type Groups (UI)

The Node browser organises Nodes into groups for discovery:

| Group | Contains |
|-------|----------|
| **All** | Every Node |
| **SceneGraph** | Renderer, Camera, Light, Mesh, Loader, Subgraph |
| **Mesh** | Geometry, Material |
| **Image** | All image-processing Nodes, Shaders |
| **Parameter** | Bool, Number, Vector, Quaternion, Transform, Color, String, Array, IO |
| **Utility** | Cursor, Keyboard, Log, Render Info, etc. |

---

## Terminology Inconsistencies

Issues found in the current codebase where the same concept goes by different names, or naming is ambiguous.

### "Producer" vs "Provider"
`ARCHITECTURE.md` line 14 calls them "Producer nodes" and the Execution Mode discussion uses "Producers". The code enum is `ExecutionMode.Provider`. The codebase should settle on one term. The enum wins — **Provider** is the canonical name.

### "Patch" vs "Node"
Quartz Composer called processing units "Patches". Fabric calls them "Nodes", but QC language persists:
- `CurrentTimeNode` is named **"Patch Time"** in the UI and its description says "time since patch execution started".
- `NodeTimeMode.swift` comments reference "the custom patch" throughout.
- `NodeRegistry.swift` has the comment `// Sub Patch Iterator, Replicate etc`.
- `NODES.md` has a section titled **"Macro Patches"**.

**Recommendation:** replace "patch" with "node" in user-facing strings and comments.

### "Geometery" typo
`NodeType.Geometery` is misspelt throughout the codebase (missing the 'r' swap — should be "Geometry"). It propagates via the enum case into `BaseGeometryNode`, `NodeTypeGroups`, and deprecated nodes. Because it's a serialised enum value, fixing it requires a migration path.

### "Inlet/Outlet" vs "input/output" in API names
The `PortKind` enum uses `.Inlet` / `.Outlet`, but the `Node` API exposes `inputPorts()` / `outputPorts()` and properties like `inputNodes` / `outputNodes`. Both naming conventions coexist without a clear rule for when to use which.

### "Image" vs "Texture" in UI colour naming
Object Ports of type Image are coloured with `Color.nodeTexture` (in `NodeType.swift`), while everywhere else the user-facing term is "Image". The internal colour name leaks the implementation concept ("texture") into the domain model.

### "Object" is overloaded
"Object" simultaneously refers to:
1. `Satin.Object` — a 3D scene-graph node
2. `ObjectType` — the Node type enum case for scene-graph Nodes
3. **Object Port** — the port kind for reference types (Geometry, Material, Shader, Image)

These are three distinct concepts sharing one word.

### "Composition" vs "Graph"
External documentation and QC heritage use "Composition" for a saved document. The codebase uses `Graph` exclusively. `NODES.md` section "Macro Patches" implies the QC framing. The terms are never explicitly distinguished.

---

## Unnamed Concepts

Patterns and mechanisms that exist in the codebase but lack an explicit, documented name.

### Value propagation
The mechanism by which data flows from an Outlet to connected Inlets during evaluation. It is implicit in the pull-based model — there is no named "signal", "message", or "propagation" abstraction.

### Dirty cascade / invalidation propagation
When a Node becomes dirty, all downstream dependents must re-evaluate. This cascade is implicit in the pull-based evaluation rather than being an explicit, named invalidation pass.

### Port interface (of a Subgraph)
The set of Published Ports that define a SubgraphNode's external contract. There is no protocol, type, or named concept for "the interface of a Subgraph" — it is simply the ports where `published == true`.

### Channel count (of an Effect)
The number of input images an Effect Node accepts (1, 2, or 3). This is encoded in class names (`BaseEffectNode`, `BaseEffectTwoChannelNode`, `BaseEffectThreeChannelNode`) but never named as a first-class concept.

### Execution lifecycle
The sequence `startExecution()` → (per frame: `execute(context:)`) → `stopExecution()` plus `enableExecution()` / `disableExecution()` / `teardown()`. This lifecycle is convention-based rather than documented as a named state machine.

### Scene proxy
The `Satin.Object` that the GraphRenderer builds from a Graph's Object Nodes to serve as the renderable scene root. It exists in code but has no domain name beyond being "the scene".

### Default camera
When no Camera Node is present, the GraphRenderer uses a default camera at `(0, 0, 2)` looking at the origin. This fallback is not named or documented.

### Managed vs unmanaged image lifetime
`FabricImage` instances are either vended by the Texture Cache (managed — automatically recycled) or created directly (unmanaged — caller-owned). The distinction is important for performance but is not surfaced as a named concept in documentation.

# Fabric Engineering Specification

**Read [PRINCIPLES.md](PRINCIPLES.md) first. It overrides everything in this file.**

Review README.md, Architecture.md, Glossary.md, Nodes.md, 

## Engineering Guidelines

For all development:

### General
- Do not introduce third-party frameworks without asking first.
- Avoid UIKit / AppKit unless requested.
- We use Swift 5.9 for now
- We use SwiftUI
- We target macOS 15 + , iOS 18 +, visionOS 2.0 +
- We priortize clean code, with variable and function names optimized for legibility and self documentation - we can be verbose to avoid ambiguity
- We avoid single, acronym style variable or function names
- We do not violate D.R.Y.
- We keep separation of responsibilities.

### Swift
- Always mark @Observable classes with @MainActor.
- Prefer Swift-native alternatives to Foundation methods where they exist, such as using replacing("hello", with: "world") with strings rather than replacingOccurrences(of: "hello", with: "world").
- Prefer modern Foundation API, for example URL.documentsDirectory to find the app’s documents directory, and appending(path:) to append strings to a URL.
- Never use C-style number formatting such as Text(String(format: "%.2f", abs(myNumber))); always use Text(abs(change), format: .number.precision(.fractionLength(2))) instead.
- Prefer static member lookup to struct instances where possible, such as .circle rather than Circle(), and .borderedProminent rather than BorderedProminentButtonStyle().
- Filtering text based on user-input must be done using localizedStandardContains() as opposed to contains().
- Avoid force unwraps and force try unless it is unrecoverable.

### SwiftUI instructions

- Always use foregroundStyle() instead of foregroundColor().
- Always use clipShape(.rect(cornerRadius:)) instead of cornerRadius().
- Always use the Tab API instead of tabItem().
- Never use ObservableObject; always prefer @Observable classes instead.
- Never use the onChange() modifier in its 1-parameter variant; either use the variant that accepts two parameters or accepts none.
- Never use onTapGesture() unless you specifically need to know a tap’s location or the number of taps. All other usages should use Button.
- Never use Task.sleep(nanoseconds:); always use Task.sleep(for:) instead.
- Never use UIScreen.main.bounds to read the size of the available space.
- Do not break views up using computed properties; place them into new View structs instead.
- Do not force specific font sizes; prefer using Dynamic Type instead.
- Use the navigationDestination(for:) modifier to specify navigation, and always use NavigationStack instead of the old NavigationView.
- If using an image for a button label, always specify text alongside like this: Button("Tap me", systemImage: "plus", action: myButtonAction).
- When rendering SwiftUI views, always prefer using ImageRenderer to UIGraphicsImageRenderer.
- Don’t apply the fontWeight() modifier unless there is good reason. If you want to make some text bold, always use bold() instead of fontWeight(.bold).
- Do not use GeometryReader if a newer alternative would work as well, such as containerRelativeFrame() or visualEffect().
- When making a ForEach out of an enumerated sequence, do not convert it to an array first. So, prefer ForEach(x.enumerated(), id: \.element.id) instead of ForEach(Array(x.enumerated()), id: \.element.id).
- When hiding scroll view indicators, use the .scrollIndicators(.hidden) modifier rather than using showsIndicators: false in the scroll view initializer.
- Place view logic into view models or similar, so it can be tested.
- Avoid AnyView unless it is absolutely required.
- Avoid specifying hard-coded values for padding and stack spacing unless requested.
- Avoid using UIKit / AppKit colors in SwiftUI code.

### Best Practices
- While we dont prematurely optmize, we avoid some patterns:
    - We avoid dispatching via DispatchGroup or MainActor on the main thread as a way to 'skip' a runloop invokation and get UI stuff to work - this is considered a hack
    - We avoid running single shot `.task { }` calls on SwiftUI Views
    - We mark properties on models which are @Observable with @ObservationIgnored for any public variables that
    - We avoid leaning heavily on @Environment as it can cause views to redraw


---

## 1. Vision & Guardrails
- Spiritually Quartz Composer, architecturally modern Swift + Metal + Satin.
- **Typed**, predictable node system; stable contracts and execution semantics - see `ARCHITECTURE.md` for types.
- **Performance over cleverness:** zero redundant work, stable identities.
- **Ergonomics:** readable APIs, minimal boilerplate, 3rd-party-friendly.
- **Surgical change policy:** reversible, minimal churn, backward-compatible until explicit migration.

**Current Pragmatic Conceccions:**
- **Typed ports only** for now; “virtual” types postponed.
- **Vec4 proxies pure Vec4, Orientation (Quaternion) and Color. This can be revisited in the future. 

---

## 2. Non-Negotiable Design Patterns & Contracts

### 2.1  Nodes & Execution
- Nodes define immutable static metadata:  `nodeType`, `nodeExecutionMode`, `nodeTimeMode`,  `name`, `nodeDescription`.
- A node is named from four sources, three of them overridden by the subclass:
  - `class var name` — override: the stable name the type is registered and listed under, and the default instance title.
  - `func deriveTitle() -> String` — override only when an instance has a more specific authoritative title, such as a shader-backed `BaseImageNode`; defaults to `Self.name`.
  - `func deriveSubtitle() -> String?` — override where the node describes itself, nil otherwise: Math Expression's expression, StrategyNode's strategy.
  - `func deriveStatuses() -> [NodeStatus]` — override where the node has something to report: Math Expression's parse error. The most severe (`NodeStatus` orders error over warning) picks the glyph at the trailing edge of the title row, and every status's message shows on hover; the view layer draws them. Empty otherwise.
  - `var userName: String?` — final: the user's rename, serialized and public for rename-specific callers.
  - An empty name is no name: `userName` normalizes "" to nil at set and decode.
- From those it composes, both final:
  - `var title` — the normalized result of `deriveTitle()`, falling back to `Self.name` when empty.
  - `var subtitle` — `userName ?? deriveSubtitle()`, normalized so empty values and values equal to `title` read as nil. General consumers read this rather than `userName`.
  - `var debugDescription` — the title plus resolved subtitle, e.g. `Math Expression (My Rename)`. `print(node)` and `"\(node)"` give it; diagnostic labels and traces use it when they need both values.
- Call `namingDidChange()` whenever state feeding `deriveTitle()`, `deriveSubtitle()` or `deriveStatuses()` changes, from any thread; `NodeViewModel` mirrors the node's `title` / `subtitle` / `status` observably and keeps `userName` only for rename editing, clearing, and undo.
- Execution is **pull-based**; one execute per node per pass.
- `GraphRenderer` (executor and scheduler) today does not use `nodeExecutionMode` or `nodeTimeMode` but will in the future.
- **Iterator (QC-style)** remains the multi-evaluation macro; refinements allowed, paradigm fixed.
- One file per Node Class
- `Node.executionState` (`ExecutionState`: `.disabled`, `.enabled`, `.started`, `.stopped`) is runtime-only and never serialized. Overrides of `enableExecution`, `startExecution`, `stopExecution` and `disableExecution` **must call `super` after their own work succeeds**; that call records the state.
- `Graph` owns topology: it records the nodes each edit touches (added, removed, connected, disconnected, published). `GraphRenderer` owns execution of exactly one graph: each frame it reconciles those nodes against its own `executionState`. Added nodes enable; nodes that are connected, published or Consumers start; fully disconnected nodes stop; removed nodes stop and disable. Only started nodes execute. Subgraph nodes carry their state into their inner graph; Iterator starts every inner node. Lifecycle failures go to the renderer's `errorDelegate`. Editing code never calls node lifecycle methods.

- Node Settings:
  - Nodes may opt into a QC like ’Settings View’
  - Any Node whose execution logic would change the  type, or number of ports should have only have that logic fire via changing a Setting, NOT at runtime
  - Settings should have a custom Init override, and be exposed as a enum or struct that can be set via the procedural Node / Graph API. This avoids UI only configuration.
  - The settings are one `NodeSettings` value: what the settings view edits and the ports do not hold. Two node types share a value type only where each can take the other's value. A node gives it through `settings`, takes it through `apply(_:)`, and offers `init(context:settings:)`. A `StrategyNode` subclass's value conforms to `StrategySettings`.
  - Override `apply(_:)`; never call it. `setSettings(_:)` is the final entry for views, the procedural API and undo. A public setter is a wrapper over it that changes part of a value of several fields, as `setStrategy` and `setRouteCount` are. The value's initialiser takes no default arguments, so a caller cannot reset a field by leaving it out. In `apply`, cast the existential to your own type and return on any other, change what `declaredPorts()` reads, call `reconcilePorts()`, then call super.
  - The value saves flattened into the node's container, so its coding keys must not be `Node.CodingKeys`. Decode it in `init(from:)`, before `super.init` where the ports depend on it. What the view does not edit, such as a device's reconnect record, stays out of the value.
  - A setting's side effects live in the stored property's observer, or in `apply` where several settings share them, so they run once: the reconcile, `namingDidChange()`, and `settingsDidChange()`, which refreshes an open settings model. Settings models are `@MainActor`.
  - `apply` runs on the thread that edits the graph, which a host can keep off main, never from `execute`: a `NumericTypeAgnosticNode` specialises inside the connect, from `inletDidConnect(_:from:)`, through `setStrategy`. A node whose settings reach main-thread state is applied from main only.
  - `NodeSettingsTests` checks every registered node with settings at its default value. A new node also needs a case with non-default values in `nonDefaultSettingsSaveAndOpen`, as a misnamed key falls back to the default and passes unseen otherwise.

- Important Node subclasses
  - StrategyNode / TypeAgnosticNode - useful for Nodes that can change their port type on demand
    

### 2.2  Ports & Registration
- **Declarations are the source of truth.** A node's interface is `declaredPorts() -> [PortDeclaration]`, a function of its settings and what it reads at runtime (a shader, a script, a device), never of the document. A port the node always has is a stored property (`public let x = ParameterPort(…)`, made at property initialisation, before `Node.init`) declared as `PortDeclaration(key: "x", port: x)`; overrides call `super` and preserve order.
- A declaration names a `PortKey` (the node's own `.own(String)`; a subgraph proxy's `.proxy(node:inner:)`), its kind, type, name, description, and a `control` for a parameter inlet. The key is the port's identity across saves and settings changes: give a dynamic port a key that names it stably.
- **Ports change only through `reconcilePorts()`.** It brings the registry to the declarations: a port kept under its key and type keeps its wires and value; a retyped one is replaced under the same runtime id and keeps the wires that fit; an undeclared one is retired, wires and publishing removed as graph edits. There is no imperative add, remove, replace or reorder. Call it when settings or a runtime read change the interface, never from `execute`.
- `prepareDeclarations()` runs before every reconcile (resolve strategy-derived state there); `bindPorts()` runs after. A node whose ports are all stored properties does not override it; a node with dynamic ports (a strategy, a source, a device, records) assigns its references to them there, the one place a node looks its ports up by key.
- **No port lookup by name, key or cast in `execute`** (#449). Execute reads stored ports through their properties and dynamic ones through references bound in `bindPorts()`; nodes with data-driven ports hold arrays aligned with their records. The same holds for `respondToPull`.
- UI and serialization order derive from the declarations' order.
- **Structure changes only on the editing thread, inside an edit.** Nodes, wires, publishing and a node's ports change through edits made on the thread that edits the graph. Execute reads and writes port values, nothing else. A node that learns during execute that its interface should change records that, and the change is applied as an edit; a node whose interface follows its wires changes it in `inletDidConnect(_:from:)`, which the graph calls inside the connect (Numeric type-agnostic nodes specialise there). The one notification that starts on the render thread is `namingDidChange()`'s hop to main, which changes a label, not structure.
- `NodeRegistry` should support this as it’s the single source of truth for nodes.
- **Typed ports only** (for now).  
  Any “virtual” or generic ports must remain type-safe and backward-compatible.

### 2.3  Parameters & ParameterPort
- Input Ports should be backed by Parameters as a Parameter Port if the type is a Parameter
     - ie avoid raw Ports unless type demands it. 
- **The port's value is canonical; the parameter mirrors it, one way.** A value change writes the parameter through its setter; nothing reads the parameter to learn the value, and writing a parameter does not reach its port. The parameter gives a control its range, options and label, and for a material-backed port it is the uniform the material uploads.
- A port starts at its parameter's value, the declaration's default; a document restores its saved value by key.
- Controls write a port through `Graph.setControlValue(_:on:)` and follow it through `Port.addValueObserver(_:)`, hopping to main once per turn. Nodes observe no parameters.
- Value changes mark dirty only; heavy work deferred to `execute`.
- Published parameter surface mirrors published ports; inlets auto-unpublish on connect.

### 2.4  Graph, Subgraphs & Rendering
- Graph owns nodes, connections and publishing, each naming ports by `PortAddress` (node id and port key). Publishing is a graph relation from address to name; ports do not know whether they are published.
- A subgraph node's proxies are declarations from what its sub graph publishes, in publishing order; a publishing change inside reconciles the subgraph node.
- **Subgraphs** inherit `BaseObjectNode`, expose an Satin object.
- `GraphRenderer` handles traversal, caching, single-execute per frame, resize propagation. 
- `GraphRenderer` handles discovery of cameras (only one supported now), and if none are found, leverages its own cached camera.
- `GraphRenderer`’s default camera is set up for the default QC coordinate system.
- We must manage pixel/unit conversions when a camera has non-default values.

### 2.5  Helper Base Node Families
- BaseEffectNode.swift 
- BaseEffectThreeChannelNode.swift
- BaseEffectTwoChannelNode.swift 
- BaseGeneratorNode.swift 
- BaseGeometryNode.swift 
- BaseMaterialNode.swift
- BaseObjectNode.swift 
- BaseRenderableNode.swift 
- BaseTextureComputeProcessorNode.swift

### 2.6 Type-Agnostic Nodes

Some nodes operate identically regardless of what data flows through them (e.g. Sample and Hold, Queue). Because ports are typed, these nodes use a Settings picker to declare which type they carry — but the picker is a practical requirement of the type system, not a semantic choice. The node's behavior does not change.

- Default to `PortType.Virtual`, which accepts any connection and requires no configuration.
- Virtual appears first in the type picker, separated from concrete types.
- Switching type reconciles the dynamic ports to the declarations for it; their order is the declarations'.
- When a concrete type is active, the node's display name reflects it (e.g. `"Sample and Hold Float"`).
- `snapshotValue()` / `sendBoxed()` are the runtime-polymorphic read/write API for ports whose type is only known at runtime.

**Base class:** `TypeAgnosticNode`. **Reference implementation:** `SampleAndHoldNode`.

---

## 3. Best-Practice Rules

### 3.1  Performance & Invalidation
- Cache topology (`inputNodes`, `outputNodes`); recompute only on connect/disconnect.
- One execute per frame per node; track executed set (`GraphRenderer` has cache now, and Node has `isDirty` `markDirty` `markClean` - which may go away).
- Zero-work steady state: skip execute if unchanged.
- Avoid allocations; reuse materials, geometry, textures.

### 3.2  Ports & Publishing
- Publish through `Graph.setPublished(_:port:name:)` and `setPublishedName(_:port:)`; read with `isPublished(_:)` and `publishedName(of:)`.

### 3.3  Serialization
- A node saves only its parameter inlets' values, by key (`"ports": {key: PortValue}`); its interface comes from its declarations on open. Graphs save wires and publishing by address. Port and connection ids are runtime-only.
- A node whose ports come from compiling a source (JavaScript, Live Image, a user's shader file, Math Expression, Parametric Geometry) sets `lastCompiledSource` on each compile that succeeds; `Node` saves it when it differs from `compilableSource`. When the source does not compile on open (or a shader file has not resolved), the node declares its ports from the last compiled source, read for its interface only and never run. The document carries no port structure.
- Older documents are read through `GraphFormatMigration`, once at open; keep decode shims until an official migration step.

### 3.4  Subgraph Behavior
- Iterator applies per-iteration params before subgraph execute.
- Render-to-Image-with-Depth sizes to inputs, attaches depth, outputs typed textures.

---

## 4. Common Pitfalls & Preventions
| Issue | Root Cause | Prevention |
|-------|-------------|------------|
| Nothing renders until tweak | Port not given its declared default | Declare the default on the parameter; the port starts at it |
| Iterator/Processor slow | Excess publisher churn | Dirty-flag only; do heavy work in execute |
| Topology recomputed each frame | No caching | Recompute only on connect/disconnect |
| Type-erasure confusion | Mixing `any` with Equatable generics | Stay typed; use Utility/Log node for debug |
| Serialization drift | Ad-hoc encoders | Ports save only their values, by key; the interface comes from declarations |
| Stale node title on canvas/inspector | `subtitle` input changed without notifying | Call `namingDidChange()` in the `didSet` of any state `subtitle` derives from |
| Port lookup in `execute` | Finding ports by name or cast per frame | Hold the port in a stored property; bind dynamic ones in `bindPorts()` |

---

## 5. Developer & Plugin Ergonomics
- Registration API must be readable and deterministic.
- Typed port access is the stored property itself; a node needs no lookup helpers for the ports it always has.
- Extend `PortType` centrally for new types.
- Lifecycle: `init → declaredPorts → reconcilePorts → bindPorts → (decode: values by key) → execute → send`.

---

## 6. Code Review Checklist
- [ ] Node has semantically correct type, execution mode, and time mode. 
- [ ] Node metadata present and stable  
- [ ] Fixed ports are stored properties; `declaredPorts()` calls `super`, order intentional, keys stable  
- [ ] Execute reads ports through stored properties or references bound in `bindPorts()`, never by name, key or cast
- [ ] Lifecycle overrides call `super` after their own work; editing code never calls them
- [ ] `execute` idempotent per frame, no allocations  
- [ ] Outputs use `send(force:true)` appropriately  
- [ ] No recursive topology recompute
- [ ] Subgraph nodes discover cameras and apply state before execute
- [ ] Serialization by port key and address, no port ids
- [ ] If Node dynamically changes port count or type, we should only trigger via Setting in Settings View, not within the graph
- [ ] If we have a Settings View, we should have a custom initializer so procedural graph creation has an entry to settings.
- [ ] A node with settings exposes them as one `NodeSettings` value through `settings` and `apply(_:)`, and offers `init(context:settings:)` (`NodeSettingsTests` checks that every core node applies and gives back its own value with its ports, and saves and opens it unchanged)
- [ ] If the Node overrides `deriveSubtitle()`, every mutation of the state it derives from calls `namingDidChange()` (StrategyNode’s `strategy` already does)
- [ ] New Nodes should live in an appropriate spot in the NodeRegistry

---

## 7. Commit messages
Do not hard-wrap. Do not include a co-authorship signature, instead append a final `Via <model>` line.

---

## Historical Context
This specification incorporates prior engineering discussions and decisions.
The chat history should be retained for design rationale and provenance,
while this file serves as the canonical, version-controlled contract
for future development of Fabric.

---

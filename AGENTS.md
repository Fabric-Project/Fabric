# Fabric Engineering Specification

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
- Fire `subtitleSubject.send()` whenever state feeding `deriveTitle()`, `deriveSubtitle()` or `deriveStatuses()` changes; `NodeViewModel` mirrors the node's `title` / `subtitle` / `status` observably and keeps `userName` only for rename editing, clearing, and undo.
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
  - A node with settings exposes them as one `NodeSettings` value through `settings` and `apply(_:)`, and offers `init(context:settings:)`. `apply` brings the node, its ports included, to the value; a port whose registry key survives keeps its identity. A subclass takes its own type out of the existential and calls super; a base class reads its part through a protocol on the value, as `StrategySettings` carries the strategy. `Node.encode(to:)` writes the value flattened into the node's own container; `init(from:)` decodes it before `super.init`. State saved with the node that the settings view does not edit, such as a device's reconnect record, stays in `encode(to:)`.
  - A settings view commits a draft through `Graph.setSettings`: on each change for pickers, steppers and buttons, after a pause and when editing ends for text and code (`NodeSettingsDraft`). The node is not written until the commit. A draft takes the node's value when `settingsChangedSubject` fires.
  - Every edit registers, through the graph it was made in. A compound edit is an undo group; nothing inside it is suppressed.
  - Undo and redo are driven through `Graph.undo()` / `redo()`, which commit pending drafts first; an app provides its Undo and Redo commands on them.
  - A handler re-applies through the public API. What it registers goes to the redo stack. Registration is suspended only around construction, decode and the primitives a handler has no API for.
  - A step holds ids and values and finds what it acts on by id. It does not hold wires, proxies or other steps' work: a settings step holds the settings either side and the states of the ports the change touched, and the wires and proxies those ports take register steps of their own in the same group.

- Important Node subclasses
  - StrategyNode / TypeAgnosticNode - useful for Nodes that can change their port type on demand
    

### 2.2  Ports & Registration
- **Registry = source of truth.**  
- Subclasses implement `class func registerPorts(context:)`, call `super`, preserve order.
- **A node's port set and order are a function of its fixed declarations and its current settings value.** Equal settings give equal ports, in equal order, under equal ids for surviving keys, however the node got there. Order is not document-owned: a document's ports match by registry key and the code decides their order. Three responsibilities, kept apart:
  - **The node declares.** `open func declaredPorts() -> [PortDeclaration]` returns the node's whole interface as an ordered list: registry key, kind, port type, display name, description, and how to make the port. It defaults to `registerPorts(context:)`. A node whose ports follow its settings, or a source or device it reads at runtime, overrides it and computes from that state; fixed and derived ports interleave freely, and the list is the order. It makes no ports it does not return and changes nothing.
  - **The registry reconciles.** `PortRegistry.reconcile(to:owner:hydrating:)` keeps a port whose key, kind and type match (the same object, wires and value), replaces a retyped one in place under its id, makes a missing key with the state undo or decode holds for it, removes an undeclared one, and leaves the list's order. It returns what changed and does not touch the graph.
  - **The node hands the change to the graph.** `Node.reconcilePorts()` runs the reconcile and applies it through the graph as edits: unpublish and disconnect for removed ports, rebind and the replaced event for retyped ones, publish for added published ones; then rebuilds the parameter group from port order. Every edit registers; nothing suspends registration around it.
- The base `apply(_:)` reconciles once, after every level has set its part of the settings; init and decode reconcile once the settings are set, before `super.init` where the node can read them there. A node whose interface changes outside its settings, a script recompiling or a controller connecting, calls `reconcilePorts()` once it has changed what `declaredPorts()` reads.
- An expression, script or shader that does not compile declares the interface of the last that did, so a half-typed edit keeps its ports and wires. Ports a document holds that a node cannot yet declare at all (an unparseable script, a shader that does not compile, on open) are kept, declared after the node's own, until it can (`adoptRemainingSnapshotPortsAsFallback`, `discardUndeclaredSnapshotPorts`).
- `addDynamicPort` is deprecated: a port it adds is declared after the node's own for the rest of the node's life.
- `NodeRegistry` should support this as it’s the single source of truth for nodes.
- **Typed ports only** (for now).  
  Any “virtual” or generic ports must remain type-safe and backward-compatible.

### 2.3  Parameters & ParameterPort
- Input Ports should be backed by Parameters as a Parameter Port if the type is a Parameter
     - ie avoid raw Ports unless type demands it. 
- Always seed `value` from the backing parameter on init/decode (hydration).
- Maintain bi-directional sync: parameter ↔ port.
- Parameter changes mark dirty only; heavy work deferred to `execute`.
- Published parameter surface mirrors published ports; inlets auto-unpublish on connect.
- A port's publishing changes through `Graph.setPublished` and `setPublishedName` only. `Port.published` and `publishedName` are read-only outside Fabric; inside it, `setPublishing(_:name:)` is for a port no graph has to hear of: one being built, decoded or hydrated, or a proxy its subgraph node makes.

### 2.4  Graph, Subgraphs & Rendering
- Graph owns nodes, connections (by port UUID), and published params.
- A node id names one object in a graph at a time: Node's equality is its id, and the lifecycle review, view models and undo steps find a node by it.
- **Subgraphs** inherit `BaseObjectNode`, expose an Satin object.
- A `SubgraphNode` owns the proxies standing for its sub graph's published ports. The sub graph tells it of each change as the change it is, through four events: `portDidPublish`, `portWillUnpublish`, `port(_:wasReplacedBy:)` and `portDidRename`, raised by the graph's publish API, `addNode`, `delete(node:)` and `Node`'s port edits, whether or not undo registration is on. Nothing else changes proxies after decode. A proxy published further up is an ordinary published port of the graph it is in, so each level follows by the same events.
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
- Switching type changes the ports `declaredPorts()` gives for the strategy; a port that survives keeps its id, and its position is the declaration's.
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
- Initialize `ParameterPorts` on init/decode and subscribe once.

### 3.3  Serialization
- Serialize via registry snapshots; connections by UUID; reconstruct types through `PortType`.
- Keep decode shims until an official migration step.

### 3.4  Subgraph Behavior
- Iterator applies per-iteration params before subgraph execute.
- Render-to-Image-with-Depth sizes to inputs, attaches depth, outputs typed textures.
- Clone sets (`CloneSet`, `Graph+CloneSet.swift`, `Graph+ClonePatch.swift`): a set holds one stored graph, and its members are instances of it under the same inner ids. A sync encodes the member whose design moved on as the stored graph and patches each sibling to it: the two encodings are compared by id, node entry by node entry, wire by wire, note by note, and only what differs is changed, in place: a node whose entry differs in more than placement, port state or a nested sub graph takes its settings from the stored entry through `Graph.setSettings`. Every node keeps what it holds at runtime; published inlet values are the per-member exception the comparison leaves out. Sets sync as the document's undo group closes, and every change the sync makes registers its own step in that group; undo and redo replay them and sync nothing. See `CloneSetCoordinator`. An edit that registers no undo syncs only when `syncCloneSets(editedIn:)` is called for it, and a sync with no undo group open registers nothing. Nothing clone-specific belongs on Node. `SubgraphNode.proxyID(for:)` carries one piece of clone-specific code: a member's proxies take ids of their own, since its siblings wrap inner ports under the same ids in one parent graph.

---

## 4. Common Pitfalls & Preventions
| Issue | Root Cause | Prevention |
|-------|-------------|------------|
| Nothing renders until tweak | Ports not seeded from params | Always set `self.value = param.value` on init/decode |
| Iterator/Processor slow | Excess publisher churn | Dirty-flag only; do heavy work in execute |
| Topology recomputed each frame | No caching | Recompute only on connect/disconnect |
| Type-erasure confusion | Mixing `any` with Equatable generics | Stay typed; use Utility/Log node for debug |
| Serialization drift | Ad-hoc encoders | Always through registry + `PortType` |
| Stale node title on canvas/inspector | `subtitle` input changed without notifying | Fire `subtitleSubject.send()` in the `didSet` of any state `subtitle` derives from |

---

## 5. Developer & Plugin Ergonomics
- Registration API must be readable and deterministic.
- Provide var-proxy helpers (`port<Value>("Color")`, `portOrDefault("Scale",1.0)`).
- Extend `PortType` centrally for new types.
- Lifecycle: `init → registerPorts → attachParams → decode → subscribe → execute → send`.

---

## 6. Code Review Checklist
- [ ] Node has semantically correct type, execution mode, and time mode. 
- [ ] Node metadata present and stable  
- [ ] `registerPorts(context:)` calls `super`, order intentional  
- [ ] A node with dynamic ports declares them in `declaredPorts()` and never adds, removes, replaces or orders ports itself; it calls `reconcilePorts()` only when its interface changes outside its settings
- [ ] Lifecycle overrides call `super` after their own work; editing code never calls them
- [ ] Every edit registers, through the graph it was made in; a compound edit is an undo group, and nothing inside it suspends registration. `withoutUndoRegistration` is only for construction, decode and the primitives an undo handler has no API for
- [ ] Undo steps register through `Graph.registerUndo(_:)` (or `registerUndo(on:_:)` for a node) on the graph the edit was made in, never on the undo manager directly: the graph is the one place that sees every edit (`UndoRegistrationTests` checks core code). A step holds ids and values and finds what it acts on in the graph it is handed, never holding the graph's nodes, ports, wires or notes: something may have put another object under the same id by the time it runs
- [ ] ParameterPorts seed and subscribe once  
- [ ] `execute` idempotent per frame, no allocations  
- [ ] Outputs use `send(force:true)` appropriately  
- [ ] No recursive topology recompute
- [ ] Subgraph nodes discover cameras and apply state before execute
- [ ] Serialization via registry + UUID
- [ ] If Node dynamically changes port count or type, we should only trigger via Setting in Settings View, not within the graph (`DeclaredPortsInvariantTests` checks every core node's ports against a node opened from its current settings, through edits, undo and redo)
- [ ] If we have a Settings View, we should have a custom initializer so procedural graph creation has an entry to settings.
- [ ] A node with settings exposes them as one `NodeSettings` value through `settings` and `apply(_:)`, and offers `init(context:settings:)` (`SettingsUndoTests` checks that every core node applies and gives back its own value with its ports, and saves and opens it unchanged)
- [ ] A settings view commits a draft through `Graph.setSettings`, never writing the node as it edits
- [ ] If the Node overrides `deriveSubtitle()`, every mutation of the state it derives from fires `subtitleSubject.send()` (StrategyNode’s `strategy` already does)
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

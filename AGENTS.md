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
- Instances of a node's `name` may be user-editable in the future, but for now reflect the static class `name`.
- Execution is **pull-based**; one execute per node per pass.
- `GraphRenderer` (executor and scheduler) today does not use `nodeExecutionMode` or `nodeTimeMode` but will in the future.
- **Iterator (QC-style)** remains the multi-evaluation macro; refinements allowed, paradigm fixed.
- One file per Node Class

- Node Settings:
  - Nodes may opt into a QC like ’Settings View’
  - Any Node whose execution logic would change the  type, or number of ports should have only have that logic fire via changing a Setting, NOT at runtime
  - Settings should have a custom Init override, and be exposed as a enum or struct that can be set via the procedural Node / Graph API. This avoids UI only configuration.

- Important Node subclasses
  - StrategyNode / TypeAgnosticNode - useful for Nodes that can change their port type on demand
    

### 2.2  Ports & Registration
- **Registry = source of truth.**  
- Subclasses implement `class func registerPorts(context:)`, call `super`, preserve order.
- **Dynamic ports are supported through the Registry.** See TypeAgnosticNode
- UI and serialization order derive from registration.
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

### 2.4  Graph, Subgraphs & Rendering
- Graph owns nodes, connections (by port UUID), and published params.
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
- Switching type rebuilds the dynamic ports; port order must be explicit and stable.
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

---

## 4. Common Pitfalls & Preventions
| Issue | Root Cause | Prevention |
|-------|-------------|------------|
| Nothing renders until tweak | Ports not seeded from params | Always set `self.value = param.value` on init/decode |
| Iterator/Processor slow | Excess publisher churn | Dirty-flag only; do heavy work in execute |
| Topology recomputed each frame | No caching | Recompute only on connect/disconnect |
| Type-erasure confusion | Mixing `any` with Equatable generics | Stay typed; use Utility/Log node for debug |
| Serialization drift | Ad-hoc encoders | Always through registry + `PortType` |

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
- [ ] ParameterPorts seed and subscribe once  
- [ ] `execute` idempotent per frame, no allocations  
- [ ] Outputs use `send(force:true)` appropriately  
- [ ] No recursive topology recompute
- [ ] Subgraph nodes discover cameras and apply state before execute
- [ ] Serialization via registry + UUID
- [ ] If Node dynamically changes port count or type, we should only trigger via Setting in Settings View, not within the graph
- [ ] If we have a Settings View, we should have a custom initializer so procedural graph creation has an entry to settings.
- [ ] If we have a Settings View and a custom initializer, use a custom struct or enum for the settings
- [ ] New Nodes should live in an appropriate spot in the NodeRegistry
---

## Historical Context
This specification incorporates prior engineering discussions and decisions.
The chat history should be retained for design rationale and provenance,
while this file serves as the canonical, version-controlled contract
for future development of Fabric.

---

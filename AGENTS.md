# Fabric Engineering Specification

**Revision B — 2025-12-22**

> This document supersedes transient chat discussions and supplements
> the public documentation (`README.md`, `ARCHITECTURE.md`, `NODES.md`, etc.) - which you should consult.
> It defines the architectural contracts, design patterns, and coding guidelines
> that all Fabric contributors (human or AI) must follow.
> 
> the public code base exists at https://github.com/Fabric-Project/Fabric and should be consulted
> 
> **Purpose:** This spec exists to guide consistent, high-performance, ergonomic development
> of the Fabric node-based runtime. It is intended for internal engineering and AI-assisted development,
> not public distribution.

## Immediate Next Goals

Major Effort:

We need deterministic, non-recursive evaluation of graphs that contain feedback loops (cycles). The current pull-eval recursion breaks on cycles unless we short-circuit, but short-circuiting without defined semantics breaks outputs. The correct semantics for most Fabric feedback graphs are “temporal feedback” (cycle reads previous-frame values), which requires a stable previous-frame snapshot per output port.

Separate concerns:
- PortType - schema/editor-time contract (connectability, UI, serialization, declared type).
- PortValue - runtime value container (optional in Step 1, useful for cache/inspection later).
- NodePort<T> - remains strongly typed for node authors.
- Feedback - should be an execution/renderer caching details and not baked into ports/nodes for 3rd party devs to reason about.
- Update Classes that vend `FabricImages` to always output a new image per frame using our `GraphRenderers` helper method `newImage(withWidth width:Int, height:Int) -> FabricImage?`

## Engineering Guidelines

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
- Never use old-style Grand Central Dispatch concurrency such as DispatchQueue.main.async(). If behavior like this is needed, always use modern Swift concurrency.
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

## 0. Revision Summary

**Locked decisions:**
- **Typed ports only** for now; “virtual” types postponed.
- **Current publish/unpublish** behavior retained pending UX feedback.

---

## 1. Vision & Guardrails
- Spiritually Quartz Composer, architecturally modern Swift + Metal + Satin.
- **Typed**, predictable node system; stable contracts and execution semantics - see `ARCHITECTURE.md` for types.
- **Performance over cleverness:** zero redundant work, stable identities.
- **Ergonomics:** readable APIs, minimal boilerplate, 3rd-party-friendly.
- **Surgical change policy:** reversible, minimal churn, backward-compatible until explicit migration.

---

## 2. Non-Negotiable Design Patterns & Contracts

### 2.1  Nodes & Execution
- Nodes define immutable static metadata:  `nodeType`, `nodeExecutionMode`, `nodeTimeMode`,  `name`, `nodeDescription`.
- Instances of a node's `name` may be user-editable in the future, but for now reflect the static class `name`.
- Execution is **pull-based**; one execute per node per pass.
- `GraphRenderer` (executor and scheduler) today does not use `nodeExecutionMode` or `nodeTimeMode` but will in the future.
- **Iterator (QC-style)** remains the multi-evaluation macro; refinements allowed, paradigm fixed.

### 2.2  Ports & Registration
- **Registry = source of truth.**  
- Subclasses implement `class func registerPorts(context:)`, call `super`, preserve order.
- **Dynamic ports are supported through the Registry.**  
- UI and serialization order derive from registration.
- Dynamic ports aren’t implemented yet, but will be in the future.
- `NodeRegistry` should support this as it’s the single source of truth for nodes.
- **Typed ports only** (for now).  
  Any “virtual” or generic ports must remain type-safe and backward-compatible.

### 2.3  Parameters & ParameterPort
- Always seed `value` from the backing parameter on init/decode (hydration).
- Maintain bi-directional sync: parameter ↔ port.
- Parameter changes mark dirty only; heavy work deferred to `execute`.
- Published parameter surface mirrors published ports; inlets auto-unpublish on connect.

### 2.4  Graph, Subgraphs & Rendering
- Graph owns nodes, connections (by port UUID), and published params.
- **Subgraphs** inherit `BaseObjectNode`, expose an object.
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

## 6. Immediate Next Steps

### A. Port Registration Ergonomics
- Design a lightweight DSL/macro for registration.  
  - Preserve type safety and runtime structure.  
  - Explicit order and super-extension.
- Implement var-proxy helpers for typed port access.

### B. Migration Pass
- Pilot migration on one node per family (Geometry, Material, Effect, Object, Utility).
- Validate registration readability, serialization, UI order, dirty propagation.

### C. Iterator Refinements
- Optimize per-iteration state apply.  
- Add max iteration and early exit guards.  
- Add profiling hooks (time, count).

---

## 7. Non-Goals (for now)
- Virtual port type with type casting.  
- Push-based global scheduler. 
- Non-Apple platform targets.

---

## 8. Code Review Checklist
- [ ] Node metadata present and stable  
- [ ] `registerPorts(context:)` calls `super`, order intentional  
- [ ] ParameterPorts seed and subscribe once  
- [ ] `execute` idempotent per frame, no allocations  
- [ ] Outputs use `send(force:true)` appropriately  
- [ ] No recursive topology recompute  
- [ ] Serialization via registry + UUID  
- [ ] Subgraph nodes discover cameras and apply state before execute

---

## 9. Open Items / Parking Lot
- Ensure
- Extend Utility/Log node for safe “virtual” debugging.  
- Plan one-time save-migration once registration API stabilizes.

---

## 10. Historical Context
This specification incorporates prior engineering discussions and decisions.
The chat history should be retained for design rationale and provenance,
while this file serves as the canonical, version-controlled contract
for future development of Fabric.

---

# Fabric Engineering Specification

**Revision A — 2025-10-23**

> This document supersedes transient chat discussions and supplements
> the public documentation (`README.md`, `ARCHITECTURE.md`, `NODES.md`, etc.).
> It defines the architectural contracts, design patterns, and coding guidelines
> that all Fabric contributors (human or AI) must follow.
> 
> **Purpose:** This spec exists to guide consistent, high-performance, ergonomic development
> of the Fabric node-based runtime. It is intended for internal engineering and AI-assisted development,
> not public distribution.

---

## 0. Revision Summary
This revision consolidates the state of Fabric as of October 2025, integrating lessons from recent development.

**Locked decisions:**
- **QC-style Iterator** is the canonical paradigm.
- **Subgraph evaluation** is working (Iterator, Render-to-Image-with-Depth, Subgraph Node).
- **Typed ports only** for now; “virtual” types postponed.
- **Current publish/unpublish** behavior retained pending UX feedback.
- **Next focus:** improve port registration ergonomics and var-proxy API; migrate nodes once finalized.

---

## 1. Vision & Guardrails
- Spiritually Quartz Composer, architecturally modern Swift + Metal + Satin.
- **Typed**, predictable node system; stable contracts and execution semantics.
- **Performance over cleverness:** zero redundant work, stable identities, `send(force:)` on mutation.
- **Ergonomics:** readable APIs, minimal boilerplate, 3rd-party-friendly.
- **Surgical change policy:** reversible, minimal churn, backward-compatible until explicit migration.

---

## 2. Non-Negotiable Design Patterns & Contracts

### 2.1  Nodes & Execution
- Nodes define immutable static metadata: `nodeType`, `nodeExecutionMode`, `nodeDescription`.
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

### 2.5  Base Node Families
- **BaseEffect (1/2/3 channel):** mutate internal state, render, `send(force:true)`.
- **BaseGeometry/Material/Object:** mutate Satin instances, retain identity.

---

## 3. Best-Practice Rules

### 3.1  Performance & Invalidation
- Cache topology (`inputNodes`, `outputNodes`); recompute only on connect/disconnect.
- One execute per frame per node; track executed set.
- Zero-work steady state: skip execute if unchanged.
- Avoid allocations; reuse materials, geometry, textures.

### 3.2  Ports & Publishing
- Initialize `ParameterPorts` on init/decode and subscribe once.
- Use `send(force:true)` when identity is stable.
- Respect publish rules (inlets auto-unpublish on connect).

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
- Decide macro implementation (Swift macro vs build-time codegen).  
- Extend Utility/Log node for safe “virtual” debugging.  
- Plan one-time save-migration once registration API stabilizes.

---

## 10. Historical Context
This specification incorporates prior engineering discussions and decisions.
The chat history should be retained for design rationale and provenance,
while this file serves as the canonical, version-controlled contract
for future development of Fabric.

---

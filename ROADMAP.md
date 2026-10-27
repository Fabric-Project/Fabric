
# Roadmap

## Alpha Goals:

* Fabric exposes Satin's scene graph and parameter system in a node based metaphor.
- Scene Graph `Objects` and `Parameters`:
  - Cameras
    - Perspective / Orthographic   
  - Renderers
    - To views / Texture    
  - Mesh
    - Geometry
    - Materials
    - Shaders
  - Textures

- `Object` nodes have Parameters which can be adjusted, such as
  - Parameters
    - Boolean      
    - Numbers
    - Vectors
    - Quarternions
    - Colors
    - String
    - Arrays of parameters

In Fabric, like Quartz Composer, `Objects` and `Parameters` run left to right:

A simple Fabric Scene rendering a Cube:

<img width="2056" height="1329" alt="A simple Fabric Scene rendering a Cube" src="https://github.com/user-attachments/assets/cae9afca-6a99-4fa1-85d0-0dfddf55d58b" />

<!-- <img width="800" alt="image" src="https://github.com/user-attachments/assets/cbc39e56-d9e5-4c42-888a-f6bf696028c8" /> -->

## Beta Goals
* Expand on available Nodes and expose features of Satin in a thoughtful way. There is a *lot* of ground to cover. 
* UI Improvements
* Determine how to handle 'Structure' like nodes, and casting nodes. 
* Optimize the run time and enable basic features like Undo / Redo
* Collect community feedback

## 1.0 Goals
* Make a public plugin API and ensure the existing nodes are implemented via dog-fooding (no private api)
* Create a Fabric framework that allows for rendering Fabric documents into a host application in a standard way.
* Allow procedural building of Fabric graphs via API
* Support rendering of Fabric content on macOS, iOS, visionOS, just like its underlying engine, Satin
* Find opportunities to expand Satin engine to support new features.

## Follow-up: Fabric execution performance

After completing and validating the current single-threaded Iterator correctness and frame-contract branch, profile and optimize Fabric using the lessons from Satin. Keep this separate from the correctness work.

The 2026-10-23 profile shows substantial Swift reference-counting slow-path activity: `doDecrementSlow` accounts for 59 ms (4.2%) in the supplied sample. Callers include `GraphFrameImageUses.retainImages(in:)`, port/parameter setters and Combine sinks, `Node.markClean()` / `SubgraphNode.markClean()`, and `GraphRenderer.executionPlanExtension(forcing:alreadyScheduledNodeIDs:)`. `objc_msgSend` also accounts for 47 ms (3.3%). These are investigation leads, not proof that every caller or weak reference needs replacement; sampled costs overlap and should not be summed.

Review repeated traversal, temporary arrays and ownership churn, parameter/port notification cascades, weak-reference and delegate accesses, and hashing or synchronization reached during steady-state execution. Reuse existing identities and cached execution information, invalidate on actual changes, and preserve Iterator behavior, image lifetimes, and the public node contract. Measure representative graphs before and after each focused change; avoid example-specific paths and unrelated API redesigns.

Specific leads from subsequent 2026-10-23 profiles:

- **Iterator execution-plan extension:** `GraphRenderer.executionPlanExtension(forcing:alreadyScheduledNodeIDs:)` accounts for 74 ms (47.4%) in a supplied 156 ms sample, under nested `GraphRenderer.execute` / `IteratorNode.execute`. Dictionary reads account for 26 ms, writes for 19 ms, and `reserveCapacity` / resizing for 12 ms; UUID hashing and `pullNodeForExecutionPlan` also appear. Investigate why forced execution plans are rebuilt during iteration, whether unchanged topology and forced-node selections can reuse plans, and how to avoid repeated UUID hashing, traversal-state dictionaries, and allocation in steady state. Preserve pull semantics, requested-output behavior, forced evaluation, and topology invalidation. This is the larger lead in this particular sample; inclusive costs overlap.
- **Compose Vector and similar strategy nodes:** `ComposeVectorNode.execute` constructs `"inputComponent\(i)"` for change checks and again for component reads, then looks up ports through the registry dictionary. It also resolves its typed strategy from a string on execution. One sample attributes 39 ms (0.7%) to `comp(_:)`, including string interpolation/allocation; another attributes 5 ms to the change-check closure's named port lookups. Investigate retaining typed component/output port references and the resolved strategy when `rebuildPorts(forStrategy:)` runs, refreshing them on rebuild/decode, so execution reads references directly. Audit sibling strategy nodes for the same pattern without redesigning their public API.

The earlier `GraphFrameImageUses` port-scanning mechanism has since been replaced by texture-recycling scopes. Reprofile the current implementation before treating that older stack as remaining work.

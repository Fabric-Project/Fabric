# Fabric and Satin: Principles

> Kept identical in Fabric (`PRINCIPLES.md`) and Satin (`PRINCIPLES.md`). Change both together.

These principles are sacrosanct. They describe what Fabric and Satin must be, not how to build them, so they hold no matter which technical solution we pick. If a request or a design would break one of them, say so before doing anything: name the principle, explain the conflict, and propose an alternative that keeps it. Only proceed if a maintainer explicitly decides to make the exception.

## The goal

A coherent architecture (it makes sense to humans), an elegant one (people and agents can work with it easily), and a performant, responsive one: it reacts immediately to input and doesn't drop frames.

Satin and Fabric are creative coding toolkits. People will use them in strange, weird and unconventional ways, so they need to be flexible, composable and elegantly designed. Prefer one clear way to do something over many clever ones.

## What they are

**Satin** is a Metal rendering engine for all Apple platforms (macOS, iOS, visionOS). It supplies a scene graph, materials, geometry and rendering techniques that compose together in a high-performance, high-fidelity engine. It's designed to get things on screen fast: think openFrameworks or Processing, with a setup, update, draw style API built for Swift and Metal.

**Fabric** is a framework for authoring and rendering node graphs, built on Satin. Through its API, a program builds or loads a graph document, edits it and renders it; no UI is required. It follows Quartz Composer conventions and has a pull-based execution model. It exposes Satin types (cameras, lights, meshes, geometry, materials), uses Satin Parameters, and lets nodes do CPU work as well as submit GPU work. Some nodes read results back from the GPU to fill their output ports. Fabric supports plugins, loaded dynamically, each of which can provide many nodes.

**A host** is whatever drives Fabric or Satin. It owns a document's lifecycle, submits edits and input, provides the place output goes, and receives results. A host may have a UI or none.

**Fabric Editor** is the exemplar host: it gives a graph document an editing UI and a view of its output. It uses only API available to every host.

## 1. Host and rendering never block each other

- The host never waits on rendering.
- Rendering never waits on the host.

The host decides what the graph should be: edits, settings, parameter changes, input events, resizing, opening and saving. With a UI, that includes mouse, keyboard and touch, node settings panels, node parameter UI and graph editing.

Rendering carries it out:
- Satin setup: creating pipelines and GPU resources from what has been loaded.
- Satin update: streaming data to the GPU, uniforms and so on.
- Satin draw: submitting work, through Satin or raw Metal.
- Fabric graph rendering: enabling, disabling, starting, stopping and executing nodes.

The host produces intent and rendering consumes it. At a handoff, ownership moves: the host no longer touches that memory. Every piece of mutable state has one owner at a time.

Results flow the other way, for example parameters driven by the graph. Rendering never waits for the host to receive them.

## 2. Slow work blocks neither

Loading files, listing directories, decoding images and models, compiling shaders and allocating large resources take as long as they take. Neither the host nor rendering waits for them. A finished result is handed to its owner like any other handoff.

## 3. Main-only APIs get an escape hatch, not a general path

Main is a platform constraint, not a role. A host with a UI usually runs on main, but the principles above are about host and rendering, wherever they run.

Some APIs outside our control must run on main: certain device access, permissions, some framework setup. Nodes that depend on them need a dedicated, consistent way to do that work on main, either waiting for the result or not. A host that uses such nodes must keep main serviced, even a host with no UI.

This is an escape hatch for those APIs only. It is not a general way to run work, it is not part of rendering, and it must not become a habit. Everything else a node does happens where rendering happens. Device input has its own nuances and is handled case by case.

Keep the entry points consistent, so the implementation can change without touching every caller.

## 4. Raw Metal is first-class

Satin has opinions about its engine architecture, but it must support custom workloads alongside its own. Fabric has nodes that use Metal Performance Shaders and MPSGraph, custom rendering, post-processing, and shader libraries such as Lygia, and plugins can render whatever they want.

- A node gets a real command buffer to work with. Raw Metal, MPS and Satin work in a frame happen in the order the graph asks for them.
- Plugins get exactly the same contract as Fabric's own nodes: no capability flags, no reduced modes.
- If a design only works when node or plugin authors follow a "don't do that" rule, it breaks this principle.

## 5. Satin supports Fabric's execution model, including Iterator

Fabric supports Iterator-style rendering (as in Quartz Composer): one subgraph drawn many times a frame. That needs care with Metal buffers and command submission, and Satin must support it.

- Each iteration's values and GPU work stay independent and in order, for Satin objects (meshes, geometry, materials) and raw-Metal nodes alike.
- That holds when iterating inside Render to Image, and when rendering to an image inside an Iterator.
- Ideally a node doesn't need to know it's inside an Iterator.

## 6. Results from the GPU can arrive now or later

Some nodes read results back from the GPU. A node may need them in the same frame, keeping its output in step with that frame's data, or may take them a frame later so it never waits on the GPU. Which one can be a user's choice, and it can change while the graph is running.

Designs must leave room for both, and for switching between them. This is a capability to keep in mind, not a fixed contract.

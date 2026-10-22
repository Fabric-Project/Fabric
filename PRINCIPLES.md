# Fabric and Satin: Principles

> Kept identical in Fabric (`PRINCIPLES.md`) and Satin (`PRINCIPLES.md`). Change both together.

These principles are sacrosanct. They describe what Fabric and Satin must be, not how to build them, so they hold no matter which technical solution we pick. If a request or a design would break one of them, say so before doing anything: name the principle, explain the conflict, and propose an alternative that keeps it. Only proceed if a maintainer explicitly decides to make the exception.

## The goal

A coherent architecture (it makes sense to humans), an elegant one (people and agents can work with it easily), and a performant, responsive one: it reacts immediately to input and doesn't drop frames.

Satin and Fabric are creative coding toolkits. People will use them in strange, weird and unconventional ways, so they need to be flexible, composable and elegantly designed. Prefer one clear way to do something over many clever ones.

## What they are

**Satin** is a Metal rendering engine for all Apple platforms (macOS, iOS, visionOS). It supplies a scene graph, materials, geometry and rendering techniques that compose together in a high-performance, high-fidelity engine. It's designed to get things on screen fast: think openFrameworks or Processing, with a setup, update, draw style API built for Swift and Metal.

**Fabric** is a node-based creative coding framework built on Satin. It follows Quartz Composer conventions and has a pull-based execution model. It exposes Satin types (cameras, lights, meshes, geometry, materials), uses Satin Parameters, and lets nodes do CPU work as well as submit GPU work. Some nodes read results back from the GPU to fill their output ports. Fabric supports plugins, loaded dynamically, each of which can provide many nodes.

## 1. Main and rendering never block each other

- Main never blocks rendering.
- Rendering never blocks main.

Rendering means all of:
- Satin setup: allocating GPU resources, loading.
- Satin update: streaming data to the GPU, uniforms and so on.
- Satin draw: submitting work, through Satin or raw Metal.
- Fabric graph rendering: enabling, disabling, starting, stopping and executing nodes.

Think of main as a producer of user intent (input, edits, settings) and rendering as its consumer. When something is handed from the UI to rendering, the handoff is clear: main no longer touches that memory. Every piece of mutable state has one owner at a time.

Rendering needs a way to send results back to the UI, for example parameters driven by the graph, without waiting on main to receive them.

Consider:
- Generic UI events: mouse, keyboard, touch.
- Window resizing.
- File loading and access: directory listings, open dialogs, loading images and models. Ideally none of these stall rendering.
- Fabric's UI: node settings panels, node parameter UI, graph edits.

## 2. Main-only APIs get an escape hatch, not a general path

Some APIs outside our control must run on main: certain device access, permissions, some framework setup. Nodes that depend on them need a dedicated, consistent way to do that work on main, either waiting for the result or not.

This is an escape hatch for those APIs only. It is not a general way to run work, it is not part of rendering, and it must not become a habit. Everything else a node does happens where rendering happens. Device input has its own nuances and is handled case by case.

Keep the entry points consistent, so the implementation can change without touching every caller.

## 3. Raw Metal is first-class

Satin has opinions about its engine architecture, but it must support custom workloads alongside its own. Fabric has nodes that use Metal Performance Shaders and MPSGraph, custom rendering, post-processing, and shader libraries such as Lygia, and plugins can render whatever they want.

- A node gets a real command buffer to work with. Raw Metal, MPS and Satin work in a frame happen in the order the graph asks for them.
- Plugins get exactly the same contract as Fabric's own nodes: no capability flags, no reduced modes.
- If a design only works when node or plugin authors follow a "don't do that" rule, it breaks this principle.

## 4. Satin supports Fabric's execution model, including Iterator

Fabric supports Iterator-style rendering (as in Quartz Composer): one subgraph drawn many times a frame. That needs care with Metal buffers and command submission, and Satin must support it.

- Each iteration's values and GPU work stay independent and in order, for Satin objects (meshes, geometry, materials) and raw-Metal nodes alike.
- That holds when iterating inside Render to Image, and when rendering to an image inside an Iterator.
- Ideally a node doesn't need to know it's inside an Iterator.

## 5. Results from the GPU can arrive now or later

Some nodes read results back from the GPU. A node may need them in the same frame, keeping its output in step with that frame's data, or may take them a frame later so it never waits on the GPU. Which one can be a user's choice, and it can change while the graph is running.

Designs must leave room for both, and for switching between them. This is a capability to keep in mind, not a fixed contract.

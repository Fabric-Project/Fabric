# Overview

Fabric is built on top of Satin, a metal rendering engine that supports scene graphs of meshes, composed of materials and geometry. 

As such, Nodes in Fabric consist of "Objects" (think Meshes, Materials, Cameras) and "Parameters" (Numbers, Vectors, Strings) - roughly reference and value semantics.

Nodes may have Objects or Parameter ports, and are typically outputting a single type.

* Object ports are denoted by colors
* Parameter ports are gray

Fabric executes nodes in similar fashion to Quartz Composer, with a 'pull' based invocation, traversing the graph and executing nodes upstream prior to themselves. 

# Differences to Quartz Composer

* Image Processing - does not use Core Image - images have fixed extent, and are all presumed to be linear for GPU processing. Loading nodes are responsible for linearizing textures, and output rendering is responsible for color matching.
* No virtual types just yet - Fabric arrays are typed (for now?) and thus require connecting to equivalent input and output types.
* Additional types - Fabric introduces a few useful types, such a Vectors, Quaternions, and Matrices which are helpful for graphics programming.
  
# WIP
* Port Publishing - not yet done
* Type Casting - not yet done
* Macro patches - right now WIP, but the goal is to be able to author and load sub-patches at a minimum. Not sure if we will follow for rendering environments just yet.
* Iteration paradigm - unclear at the moment - we could use an iterator macro patch like QC, or enable a flat multi execution paradigm like Max with a aggregation node.
* Rendering - today we manually create a flat graph which requires a camera node and a set of meshes as a scenes. We could unravel to a more QC paradigm where a base renderer renders meshes at the root level, however this would imply nesting much like Quartz Composer used to do (Render In Image > Camera > Fog) etc, which is cumbersome. Suggestions welcome.

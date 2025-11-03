# Overview

### Nodes

In Fabric, you primarily work with `Nodes`. 

A `Node` is a visual representation of doing something useful (a function), like taking an input, processing it, and outputting it as a result. 

Nodes come in 3 flavors - or `Execution Modes`:

For example, a `Node` may compute a `Number` (Processor), load an `Image` (Provider), configure a `Material` and  `Geometry` (Processors) or render as a `Mesh` (Consumer).


* `Producer` nodes - they output data, maybe an `Image` from a camera, a random `Number`, a `Color` etc.
* `Processor` nodes, they both input and output data, doings something useful like Integrating a `Number` or smoothing a an `Array of Points`. 
* `Consumer` nodes - they input data, and do something with it external to Fabric, like render a `Mesh` to the screen, putput `Strings` to the network, or save it `Images` disk  as a movie (etc).

Below is an example of a `Graph` of `Nodes` (Nodes connected to one another) of 

<img width="960" height="614" alt="Fabric" src="https://github.com/user-attachments/assets/44a51357-8209-44cf-920a-d33f92eb8f1a" />

As you can see in the image above, `Nodes` have inputs and ouputs depending on what they do, and these are called `Ports`, and ports of the same type can be connected to one another to form a `Graph` and compute useful things. 

You can peruse the complete set of Nodes Fabric supports in the code base, or get an overview via our [Nodes Reference](https://github.com/Fabric-Project/Fabric/blob/main/NODES.md)

### Ports

Ports in Fabric represent specific types of data a node can Produce, Process or Consume. 

These ports are split into 2 types

* Parameter Ports (Booleans, Indexes, Numbers, Vectors, Strings, Colors, Arrays)
* Object Ports (Meshes, Materials, Geometry, Cameras, Lights, Environments)

If you are a developer, this maps roughly value and reference semantics.

Parameter Ports are named such because they also provide a user interface to configure the values, perhaps a number entry, a slider, a text entry field, etc. 

* Parameter ports are gray
* Object ports are denoted by colors

Fabic supports an evolving set of data that a `Node` can output 

## Port Data Types. 

Parameters:
- Bool (True False values)
- Index (Integer values),
- Number (Floating point values)
- String (String values)
- Vector 2, Vector 3, Vector 4 (Sets of 
- Color (A wrapper for Vector 4, RGBA) 

Objects:
- Geometry (A set of buffers that work together to define how 
- Material (a Vertex and Fragment Program that work with the graphcis engine)
- Shader (A custom Fragment or Shader Program) used with a custom Material. 
- Image (A Texture)


* 


# Evaluation / Execution

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

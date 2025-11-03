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

`Ports` in Fabric represent specific types of data a `Node` can `Produce`, `Process` or `Consume`. 

These ports are split into 2 types

* Parameter Ports
* Object Ports 

and can be 
* Inlets ( takes data in )
* Outlets ( outputs data )

If you are a developer, this maps roughly value and reference semantics.

Parameter Ports are named such because they also provide a user interface to configure the values, perhaps a number entry, a slider, a text entry field, in the Editor GUI. 

* Parameter ports are gray
* Object ports are denoted by colors

Fabic supports an evolving set of data that a `Node` can output 

## Port Data Types. 

Parameters (Grey):
- Bool (True False values)
- Index (Integer values),
- Number (Floating point values)
- String (String values)
- Vector 2, Vector 3, Vector 4 (Sets of 
- Color (A wrapper for Vector 4, RGBA) 

Objects (Colored):
- Geometry (A set of buffers that work together to define how 
- Material (a Vertex and Fragment Program that work with the graphcis engine)
- Shader (A custom Fragment or Shader Program) used with a custom Material. 
- Image (A Texture)

A `Node` can have many different `Ports` of differing type, allowing you to connect and process data in many useful ways. 

<img width="1394" height="972" alt="image" src="https://github.com/user-attachments/assets/55514951-9682-438a-8c9c-ce45b7cd28ab" />

The above image illustrates a set of `Nodes` with different types of `Ports` - can you see how they might get connected? 

# Evaluation / Execution

Fabric executes nodes in similar fashion to Quartz Composer, with 'pull' based evaluation and added to a list of ordered `Nodes` to execute

`Consumer` `Nodes` are first are identified, and then any `Node` connected to its input `Ports` it is recursively is evaluated. Once we find the top most `Nodes`, we then evaluate those first, sending data down stream. 

Generally speaking this means `Consumers` are connected to `Processors`, which are connected to `Providers`. 

We then evaluate the `Providers`, then the `Processors`, and finally the `Consumers` , ensuring they have the data they need to execute correctly.

# Differences to Quartz Composer

* Image Processing - does not use Core Image - images have fixed extent, and are all presumed to be linear for GPU processing. Loading nodes are responsible for linearizing textures, and output rendering is responsible for color matching.
* No virtual types just yet - Fabric arrays are typed (for now?) and thus require connecting to equivalent input and output types.
* Additional types - Fabric introduces a few useful types, such a Vectors, Quaternions, and Matrices which are helpful for graphics programming.

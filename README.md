# Fabric

Fabric is a Node based 3D content authoring environment written by [Anton Marini](https://github.com/vade).

Fabric uses Satin 3D engine [Satin rendering engine](https://github.com/Fabric-Project/Satin) written by @[Reza Ali](https://github.com/rezaali). 

Please note Fabric is heavily under construction.

Fabric is inspired by Apple's deprecated Quartz Composer ecosystem, and its design philosophy.

Fabric  and aims to
* Provide a Visual Node based content authoring environent
* Provide an SDK to load an common interchange format
* Provide an SDK to add nodes via a plugin architecture

Fabric is intended to be used as 
* A Creative coding tool requires little to no programming experience.
* Pro User tool to create reusable documents (similar to Quartz Composer Compositions) that can be loaded in the Fabric runtime and embedded into 3rd party applications.
* Developer environment built on Satin that can render high fidelity visual output in a procedural way, using modern rendering techniques.

An early alpha of Satin rendering a Super Shape with an HDRI environment and a PBR Shader at 120Hz:
 
<img width="800" alt="image" src="https://github.com/user-attachments/assets/b1d707b3-dcfe-48e7-88e1-324950842be3" />
<img width="800" alt="image" src="https://github.com/user-attachments/assets/1cd56919-e110-4ff1-bb06-37e7509525a9" />

Fabric supports, thanks to Satin, high fidelity modern rendering techniques including

- Physically based rendering
- Scene graph
- Lighting and Shadow casting
- Realtime shader editing (live coding, hot reloading)


## Roadmap

### Today:

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
    - Numbers
    - Vectors
    - Quarternions
    - Colors
    - String

In Fabric, unlike Quartz Composer, `Objects` run top to bottom, and `Parameters` left to right. We think this helps with organization and legibility, but to be honest, we're shooting from the proverbial hip here. 

A simple Fabric Scene rendering a Cube:

<img width="800" alt="image" src="https://github.com/user-attachments/assets/cbc39e56-d9e5-4c42-888a-f6bf696028c8" />



### Tomorrow
* Expand on available Nodes and expose features of Satin in a thoughtful way. There is a *lot* of ground to cover. 
* UI Improvements
* Determine how to handle 'Structure' like nodes, and casting nodes. 
* Optimize the run time and enable basic features like Undo / Redo
* Collect community feedback

### The Future
* Make a public plugin API and ensure the existing nodes are implemented via dog-fooding (no private api)
* Create a Fabric framework that allows for rendering Fabric documents into a host application in a standard way.
* Allow procedural building of Fabric graphs via API
* Support rendering of Fabric content on macOS, iOS, visionOS, just like its underlying engine, Satin
* Find opportunities to expand Satin engine to support new features.

# Community

I (vade / aka Anton Marini) are looking to build a community of developers who long for the ease of use and interoperabilty of Quartz Composer, its ecosystem and plugin comminity. 

If you are interested in contributing, please do not hesitate to reach out / comment in the git repository.

# FAQ

- Will Fabric ever be cross platform?
  - No. Fabric is purpose built on top of Satin and aims to provide a best in class Apple platform experience using Metal.

- What languages are used?
  - Fabric Editor is written in Swift and SwiftUI. Satin is written in Swift and C++

- Why not just use Vuo or Touch Designer or some other node based tool?
  - I do not like them.
  - Don't get me wrong, they are incredible tools, but they are not for me. 
  - They do not think the way I think.
  - They do not expose the layers of abstraction I want to work with.
  - They do not provide the user experience I want.












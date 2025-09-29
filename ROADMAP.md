
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

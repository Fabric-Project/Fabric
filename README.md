# Fabric

Fabric is inspired by Apple's deprecated Quartz Composer ecosystem, and its design philosophy.

Fabric  and aims to
* Provide a Visual Node based content authoring environment
* Provide an SDK to load an common interchange format
* Provide an SDK to add nodes via a plugin architecture

Fabric is intended to be used as 
* A Creative coding tool requires little to no programming experience.
* Pro User tool to create reusable documents (similar to Quartz Composer Compositions) that can be loaded in the Fabric runtime and embedded into 3rd party applications.
* Developer environment built on Satin that can render high fidelity visual output in a procedural way, using modern rendering techniques.

An early alpha of Satin rendering a instances of a sphere geometry, along with an HDRI environment and a PBR Shader at 120Hz:

<img width="2056" height="1329" alt="An early alpha of Satin rendering a instances of a sphere geometry, along with an HDRI environment and a PBR Shader at 120Hz" src="https://github.com/user-attachments/assets/17d86aab-9995-4ace-b627-ec69c5e7875b" />

<!-- <img width="800" alt="Fabric" src="https://github.com/user-attachments/assets/0c0f3a88-5c22-4ad5-88cb-c05602b548a5" />
<img width="800" alt="Fabric" src="https://github.com/user-attachments/assets/a649647a-a948-460c-827f-09b3fa6b1eee" /> -->


## Credits

Fabric is authored by by [Anton Marini](https://github.com/vade).

Fabric uses Satin 3D engine [Satin rendering engine](https://github.com/Fabric-Project/Satin) written by @[Reza Ali](https://github.com/rezaali). 

Fabric includes a licensed Metal port of [Lygia](https://lygia.xyz) shader library, powering Image effects and more, written by @[Patricio Gonzalez Vivo](https://github.com/patriciogonzalezvivo/) and contributors.

Fabric supports, thanks to Satin and Lygia, high fidelity modern rendering techniques including

- Physically based rendering
- Scene graph
- Lighting and Shadow casting
- Realtime shader editing (live coding, hot reloading)
- GPU Compute
- Image Based Lighting
- 3D Model Loading
- Material System
- ML based realtime segmentation and keypoint detection
- Shader based Image Processing and Mixing



## Requirements

> [!WARNING]
> Please note Fabric is heavily under construction.

- macOS 14 +
- XCode 15 +

Please See [Releases](https://github.com/Fabric-Project/Fabric/releases) for code signed App downloads.

For Developers:
1. Checkout Fabric and ensure you check out with submodules enabled, as Satin is a dependency.
2. Open the XCode project
3. Ensure that `Fabric Editor` is the active target.
4. Build and run. 

# Getting Started

Checkout our [Architecture Document ](ARCHITECTURE.md) to understand the underlying paradigms of working with Fabric's Nodes and execution model, learn what a node and a port is, and how Fabric executes your compositions.

We also provide a set of evolving tutorial / getting started and sample Fabric compositions along with a readme walk through.

You can use the sample compositions to learn and build off of:

[Sample Compositions](https://github.com/Fabric-Project/Fabric/tree/main/Samples) 

You can view a comprehensive list of [Nodes](NODES.md) here to explore and learn how to compose more advanced and custom setups with Fabric. 

# Roadmap

Checkout our [Roadmap Document](ROADMAP.md)

# Community

I ( [Anton Marini](https://github.com/vade) ) are looking to build a community of developers who long for the ease of use and interoperability of Quartz Composer, its ecosystem and plugin community. 

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











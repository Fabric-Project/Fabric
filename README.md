# Fabric

![Swift](https://img.shields.io/badge/swift-F54A2A?style=flat&logo=swift&logoColor=white) 
![Metal](https://img.shields.io/badge/metal-3-lime.svg?logo=data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPHN2ZyB3aWR0aD0iNzIwcHgiIGhlaWdodD0iNzIwcHgiIHZpZXdCb3g9IjAgMCA3MjAgNzIwIiB2ZXJzaW9uPSIxLjEiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgeG1sbnM6eGxpbms9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkveGxpbmsiPgogICAgPGRlZnM+CiAgICAgICAgPGxpbmVhckdyYWRpZW50IHgxPSI1MCUiIHkxPSIwJSIgeDI9IjUwJSIgeTI9IjEwMCUiIGlkPSJsaW1lR3JhZGllbnQiPgogICAgICAgICAgICA8c3RvcCBzdG9wLWNvbG9yPSIjMEVGRkREIiBvZmZzZXQ9IjAlIj48L3N0b3A+CiAgICAgICAgICAgIDxzdG9wIHN0b3AtY29sb3I9IiMyNEZGNzQiIG9mZnNldD0iMTAwJSI+PC9zdG9wPgogICAgICAgIDwvbGluZWFyR3JhZGllbnQ+CiAgICA8L2RlZnM+CiAgICA8Zz4KICAgICAgICA8Zz4KICAgICAgICAgICAgPHBhdGggZD0iTTU3Niw3MjAgTDE0NCw3MjAgQzY0LjUsNzIwIDAsNjU1LjUgMCw1NzYgTDAsMTQ0IEMwLDY0LjUgNjQuNSwwIDE0NCwwIEw1NzYsMCBDNjU1LjUsMCA3MjAsNjQuNSA3MjAsMTQ0IEw3MjAsNTc2IEM3MjAsNjU1LjUgNjU1LjUsNzIwIDU3Niw3MjAgWiIgaWQ9ImFwcC1iYWNrcGxhdGUiIGZpbGw9InVybCgjbGltZUdyYWRpZW50KSI+PC9wYXRoPgogICAgICAgICAgICA8cG9seWdvbiBpZD0iUGF0aCIgZmlsbD0iIzAwMDAwMCIgcG9pbnRzPSIxNDEgMTMyIDMzNCAzNjggMzM0IDE5NSA2NTEgNTQ1IDU2OSA1NDUgMzk4IDM2NCAzOTYgNTQ1IDIwNSAzMDkgMjA1IDU0NSAxNDEgNTQ1Ij48L3BvbHlnb24+CiAgICAgICAgPC9nPgogICAgPC9nPgo8L3N2Zz4=)
![Xcode](https://img.shields.io/badge/Xcode-007ACC?style=flat&logo=Xcode&logoColor=white)
![Discord](https://img.shields.io/discord/1443372127427366933?logo=Discord&label=Discord&color=blue)

Fabric is a creative code and rapid prototyping environment focusing on interactive visuals, image and video processing and analysis and 3D content authoring.

Fabric
* Provides an intuitive Visual Node based content authoring environment
* Provides an SDK to load an common interchange file format
* Provides an SDK to extend Fabric by creating custom nodes via a plugin architecture

Fabric is inspired by Apple's deprecated Quartz Composer ecosystem, and its design philosophy.

Fabric is intended to be used as 
* A Creative coding tool requires little to no programming experience.
* Pro User tool to create reusable documents (similar to Quartz Composer Compositions) that can be loaded in the Fabric runtime and embedded into 3rd party applications.
* Developer environment built on Satin that can render high fidelity visual output in a procedural way, using modern rendering techniques.

An early alpha of Satin rendering a instances of a sphere geometry, along with an HDRI environment and a PBR Shader at 120Hz:

<img width="2056" height="1329" alt="An early alpha of Satin rendering a instances of a sphere geometry, along with an HDRI environment and a PBR Shader at 120Hz" src="https://github.com/user-attachments/assets/17d86aab-9995-4ace-b627-ec69c5e7875b" />

<!-- <img width="800" alt="Fabric" src="https://github.com/user-attachments/assets/0c0f3a88-5c22-4ad5-88cb-c05602b548a5" />
<img width="800" alt="Fabric" src="https://github.com/user-attachments/assets/a649647a-a948-460c-827f-09b3fa6b1eee" /> -->

## What can I do with Fabric?

Think of Fabric as a playground of visual capabilies you can combine together.

Author
* Interacive 3D graphics
* Image processing and effects
* Audio reactive scenes
* images and video analysis pipelines
* embed your scenes into your own apps

Check out the [Samples](https://github.com/Fabric-Project/Fabric/tree/main/Samples) 

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
- Local LLM calling

## Credits

Fabric is authored by by [Anton Marini](https://github.com/vade).

Fabric uses Satin 3D engine [Satin rendering engine](https://github.com/Fabric-Project/Satin) written by @[Reza Ali](https://github.com/rezaali). 

Fabric includes a licensed Metal port of [Lygia](https://lygia.xyz) shader library, powering Image effects and more, written by @[Patricio Gonzalez Vivo](https://github.com/patriciogonzalezvivo/) and contributors.

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

Checkout our [Architecture Document ](ARCHITECTURE.md) to understand the underlying paradigms of working with Fabric's Nodes and execution model, learn what a `Node` and a `Port` is, the types of data Fabric can generate and process, and how Fabric executes your compositions.

We also provide a set of evolving tutorial / getting started and sample Fabric compositions along with a readme walk through. You can use the [Sample Compositions](https://github.com/Fabric-Project/Fabric/tree/main/Samples) 
to learn and build off of.

You can view a comprehensive list of available and planned [Nodes](NODES.md) here to explore and learn how to compose more advanced and custom setups with Fabric. 

Don't hesitate to file a feature request if a Node is missing!

# Roadmap

Checkout our [Roadmap Document](ROADMAP.md)

# Community

I ( [Anton Marini](https://github.com/vade) ) are looking to build a community of developers who long for the ease of use and interoperability of Quartz Composer, its ecosystem and plugin community. 

If you are interested in contributing, please do not hesitate to reach out / comment in the git repository, or [join our discord via invite](https://discord.gg/CrG92BG7xp) 

![Discord](https://img.shields.io/discord/1443372127427366933?logo=Discord&label=Discord&color=blue)


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











A list of Nodes (planned and implemented) for Fabric.

<img width="1568" height="1110" alt="image" src="https://github.com/user-attachments/assets/f6425c2c-e44d-4fda-bc93-3bb94c3978a9" />


# Material

<img width="1415" height="839" alt="image" src="https://github.com/user-attachments/assets/8960eecc-0025-4cd4-b21a-64dcc44984d8" />

- [x] Basic Color (no lighting)
- [x] Basic Diffuse (lighting)
- [x] Basic Texture (no lighting)
- [x] Standard (Physical Based Rendering)
- [x] PBR (Advanced Physical Based Rendering)
- [x] Depth (Visualize Depth)
- [x] UV (Visual texture coordinates)
- [x] Displace (Luminosity / RGB Based Displacement shader)

# Geometry

<img width="1184" height="671" alt="image" src="https://github.com/user-attachments/assets/345dab62-c203-418b-ac5a-24fb6f6f9b6d" />

### Primitives
- [ ] Line
- [x] Plane
- [x] Perspective Quad
- [x] Rounded Rect
- [x] Triangle
- [x] Circle
- [x] Arc
- [x] Cone
- [x] Box
- [x] Rounded Box
- [ ] Squircle
- [x] Capsule
- [x] IcoSphere
- [ ] Octasphere
- [x] Sphere
- [x] Tube
- [x] Torus
- [x] Cyclorama
- [x] Tesselated Text (2D)
- [x] Extruded Text (3D)
- [x] Super Shape (3D Supershape formula)
- [x] Geometry Compose (Pixel Array → Geometry)
- [x] Parametric Expression Geometry

### Parametric Surfaces
- [x] Möbius Strip
- [x] Helicoid
- [x] Superellipsoid
- [x] Klein Bottle
- [x] Catenoid
- [x] Paraboloid
- [x] Enneper Surface
- [x] Pseudosphere
- [x] Dupin Cyclide
- [x] Roman Surface
- [x] Cross Cap
- [x] Bour Surface
- [x] Breather Surface
- [x] Dini Surface

# Object

<img width="1334" height="821" alt="image" src="https://github.com/user-attachments/assets/363949de-847f-4f79-8a9a-3702e7a5c4a4" />

- [x] Mesh
- [x] Instanced Mesh
- [x] Model Mesh (3D Model Loader)
- [x] Instanced Model Mesh
- [x] Image Mesh
- [x] Orthographic Camera
- [x] Perspective Camera
- [x] Directional Light
- [x] Point Light
- [x] Spot Light

# Macro Patches

- [x] Sub Graph
- [x] Render in Image with Depth (Outputs Image / Depth Image)
- [x] Environment (Image Based Lighting)
- [x] Environment Skybox (used within Env Node)
- [x] Iterator Node
- [x] Iterator Info (used within Iterator)
- [ ] Replicate in Space
- [ ] Replicate in Time

# Image Processing

<img width="1334" height="821" alt="image" src="https://github.com/user-attachments/assets/86b33241-d619-499e-8f79-f1613ab12b66" />

### Loading
- [x] Image Provider
- [x] Movie Provider (AVFoundation)
- [x] Camera Provider (AVFoundation)
- [x] Screen Capture Provider
- [x] Syphon Client
- [x] Syphon Server
- [x] Test Card
- [x] Live Image

### Generator

- [x] Classic FBM Noise
- [x] Constant Color
- [x] Domain Warp Simplex Noise
- [x] Gradient FBM Noise
- [x] Linear Gradient
- [x] Simplex FBM Noise
- [x] Simplex Ridge Noise
- [x] Simplex Turbulence Noise
- [x] UV
- [x] Voronoi Cells Noise
- [x] Voronoise Noise
- [x] Wavelet FBM Noise
- [x] Worley Noise

### Color Adjust

- [x] Brightness / Contrast / Saturation
- [x] Hue
- [ ] Color Polynomial
- [x] White Balance
- [x] Vibrance
- [x] Levels
- [x] Gamma
- [x] RGB Linear to SRGB
- [x] sRGB to RGB Linear
- [x] Exposure
- [x] Channel Mixer
- [x] Posterize
- [ ] Channel Combine

### Color Effect

- [x] Color LUT
- [x] Invert
- [x] Duo Tone
- [x] Threshold
- [ ] False Color

### Color Space

- [x] CMYK <-> RGB
- [x] Color Clamp
- [x] HSV <-> RGB
- [x] LAB <-> RGB
- [x] YIQ <-> RGB
- [x] YPbPr <-> RGB
- [x] YUV <-> RGB
- [x] XYZ <-> RGB
- [x] XYZ <-> LAB
- [x] Channel Subsample

### Color Tone Mapping

HDR -> SDR conversion
- [x] Aces
- [x] Filmic
- [x] Reinhard
- [x] Reinhard Jodie
- [x] Uncharted
- [x] Uncharted 2

### Film Emulation

- [x] Grain
- [x] Light Leak
- [x] Technicolor 1
- [x] Technicolor 2
- [x] Technicolor 3
- [x] Technicolor 3w
- [x] Vignetting
- [x] White Diffusion
- [x] Cine Grain
- [x] Fast Grain
- [x] Halation
- [x] Halation Extract

### Lens

- [x] Barrel Distortion
- [ ] Chromatic Aberration
- [ ] Prism / Kaliedoscope

### Mixing

- [x] Standard Mixing Modes 
    - Additive
    - Average
    - Color Burn
    - Color Dodge
    - Color
    - Darken
    - Difference
    - Exclusion
    - Glow
    - Hard Light
    - Hard Mix
    - Hue
    - Lighten
    - Linear Burn
    - Linear Dodge
    - Linear Light
    - Luminosity
    - MixTemplate.msl
    - Multiply
    - Negation
    - Overlay
    - Phoenix
    - Pin Light
    - Reflect
    - Saturation
    - Screen
    - Soft Light
    - Source Over
    - Subtract
    - Vivid Light

- [ ] Mix modes with Masking
- [x] Fade Curve
- [x] SPK MXR

### Compositing

- [x] Porter Duff compositing
    - Atop
    - In
    - Out
    - Over
    - Xor

### Masking
- [x] Apply Mask
- [x] Foreground Mask (ML)
- [x] Person Mask (ML)

### Tiling

- [ ] Lygia Tiling Ops
- [x] Kaleidoscope
- [ ] Mirror

### Shape Generation

- [x] Circle
- [x] Cross
- [x] Triangle

### Shape Operators

- [x] SDF Blend
- [x] SDF Intersect
- [x] SDF Onion
- [x] SDF Render
- [x] SDF Subtract
- [x] SDF Tile
- [x] SDF Union

### Decimation

- [ ] Dither
- [x] Pixelate
- [x] Hexagonal Pixelate
- [x] Polar Pixelate
- [x] Triangular Pixelate
- [x] CMYK Dot Screen
- [x] Cross Hatch

### Distortion

- [ ] Warp
- [ ] Bump
- [x] Displacement
- [x] Displacement w Mask
- [x] Pinch
- [x] Dent
- [x] Twirl
- [x] Wobble
- [x] Key Point Displacement

### Blur

- [x] Gaussian
- [x] Gaussian Blur Channels
- [x] Gaussian Blur with Mask
- [x] Motion Blur
- [x] Post Process Motion Blur
- [x] Zoom Blur
- [x] Depth of Field 
- [x] Linearize Depth
- [ ] Bloom
- [ ] Gloom
- [ ] Variable Versions of above

### Morphology

- [ ] Sharpen
- [ ] Unsharpen
- [x] Sobel
- [x] Dilation
- [ ] Erode
- [ ] Open
- [ ] Close

### Analysis

- [x] Marching Squares Contour (needs better stability at edges)
- [x] Contour Path
- [ ] Blob Detection (requires nested array support)
- [ ] Segmentation
- [x] Lucas-Kanade Optical Flow
- [x] Gradient Flow
- [x] Gradient Flow Offset
- [ ] Classification
- [x] Face Pose Analysis / Landmark
- [x] Hand Pose Detection / Landmark
- [ ] Body Pose Detection / Landmark
- [ ] Depth Map Prediction
- [x] Metal FX 2x Upsampler (ML based)  
- [x] FXAA Antialiasing  
- [ ] Image Embedding Vector( via fast Clip like model or Vision Feature Print? whats most useful - careful do we want to stray into comfy ui bullshit? )

### ML / AI

- [x] Local LLM (on-device language model)
- [x] Vision Language Model (on-device VLM)


### Info 
- [x] Image Dimensions
- [x] Texture Crop
- [x] Image Resample (Linear / Bilinear / Lancos)
- [ ] Image Pixel to Color (sample at XY -> XYZ)

# Parameters

### Boolean

- [x] Bool
- [x] True
- [x] False
- [x] Logic Operator
- [x] Signal

### Index

- [x] Index
- [x] Index Generator

### Number

- [x] Number
- [x] Graph Time
- [x] System Time
- [x] Timestamp
- [x] Integrator (accrues every frame for now)
- [ ] Derivator
- [x] Single Operator Math
- [x] Binary Operator Math
- [x] Gradient Noise (FBM)
- [x] Remap
- [x] Tween / Easing
- [x] Clamp
- [x] Round
- [ ] Counter
- [x] LFO
- [x] Pulse
- [x] Trigger
- [x] Number Generator
- [x] Smooth (Kalman or 1 Euro Filter?)
- [x] Math Expression
- [x] Number Logic (Comparison)

### Numeric

- [x] Distance
- [x] Easing
- [x] Tween
- [x] Repeat
- [x] Ripple Repeat
- [x] Pairwise Distance Array

### Vector

- [x] Vector 2
- [x] Vector 3
- [x] Vector 4
- [x] Vector Compose
- [x] Vector Decompose
- [x] Vector 2 Distance
- [x] Vector 3 Distance
- [x] Vector 4 Distance
- [x] Vector Tween
- [x] Vector Array Compose
- [x] Vector Array Decompose
- [x] Vector Array Tween
- [ ] Vector Ops (Cross / Dot / etc)

### Color

- [x] Color
- [x] Color From RGBA
- [x] Color Tween

### Orientation

- [x] Orientation
- [x] Orientation Compose
- [x] Orientation Decompose
- [x] Orientation Tween
- [x] Orientation Array Compose
- [x] Orientation Array Decompose
- [x] Orientation Array Tween

### Transform (Float4x4 Matrix)

- [x] Identity Transform
- [x] Transform Compose
- [x] Rotate Transform
- [x] Scale Transform
- [x] Translate Transform
- [x] Transpose Transform
- [x] Invert Transform
- [x] Decompose Transform
- [x] Transform Array Compose
- [x] Transform Array Decompose
- [x] Geometry to Transform Array

### String

- [x] String
- [x] String Loader (Text file loader)
- [x] String Components
- [x] String Length
- [x] String Range
- [x] String Case
- [x] String Formatter
- [x] String Scanner
- [x] String Join
- [x] String Wrap
- [x] String Remove Whitespace
- [x] String Difference
- [x] String Split
- [x] String Compare
- [x] Convert to String ( type convert )
- [x] Timestamp Formatter
- [x] Directory Scanner
- [x] String to Timecode Format
- [x] Local LLM Node

### Dictionary

- [x] Dictionary
- [x] Typed Dictionary pass-through nodes
- [x] Compose Dictionary
- [x] Decompose Dictionary
- [x] Dictionary Set Value For Key
- [x] Dictionary Value For Key
- [x] Dictionary Count
- [x] Dictionary Has Key
- [x] Dictionary Remove Key
- [x] Dictionary Merge
- [x] Dictionary From JSON String

### Array

Array nodes are type-agnostic and can work with any compatible Fabric port type selected in Settings.

- [x] Array Queue Value
- [x] Array Count
- [x] Array First Value
- [x] Array Last Value
- [x] Array Value at Index
- [x] Array Append
- [x] Array Replace Value At Index
- [x] Array Split at Index
- [x] Array Subarray
- [x] Array Reverse
- [x] Array Shuffle
- [x] Array Range Interpolate
- [x] Array Resample
- [x] Line Points
- [x] Ring Points
- [x] Grid Points
- [x] Repeat Value
- [x] Simplify Polyline (Simplification of Array of Vector 2 Points via Ramer-Douglas-Peucker algo)
- [ ] Multiplexer
- [ ] Demultiplexer
- [ ] Sort (? what does this mean for some types ?)

### Signaling Nodes

- [x] Sample and Hold
- [x] Pulse
- [x] Signal
- [x] Timeline (Multi-track keyframe animation with bezier interpolation)

# Other Nodes

###  I / O

- [x] Audio Input Spectrum
- [x] Keyboard
- [x] Mouse / Touch / Cursor (macOS)
- [x] OSC Input (OSCKit)
- [ ] OSC Output
- [x] MIDI Input (MIDIKit, learn mode)
- [ ] MIDI Output
- [x] HID Input (IOKit)
- [x] Game Controller Input (GameController.framework)
- [ ] HID Output
- [ ] NDI Input
- [ ] NDI Output
- [x] Syphon Input
- [x] Syphon Output
- [ ] Artnet Input
- [ ] Artnet Output
- [ ] Depth Camera Input (Orbec / Kinect)

###  Info Nodes
 - [x] Rendering Destination Dimensions
 - [x] Units to Pixels
 - [x] Pixels to Units
 - [ ] Mesh Hit Test
 - [x] Frame Rate
 - [x] Frame Counter
 - [x] Log
 - [x] Visualize
 - [x] JavaScript
 - [x] Switch
 - [x] Gate
 - [x] Matrix Switch

 
 

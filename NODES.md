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
- [ ] UV (Visual texture coordinates)
- [x] Skybox (HDRI Environment Map)
- [x] Displace (Luminosity / RGB Based Displacement shader)

# Geometry

<img width="1184" height="671" alt="image" src="https://github.com/user-attachments/assets/345dab62-c203-418b-ac5a-24fb6f6f9b6d" />

- [ ] Line
- [x] Plane
- [ ] Billboard
- [x] Point Plane (Temp until #15 is fixed)
- [x] Rounded Rect
- [x] Triangle
- [x] Circle
- [ ] Arc
- [ ] Cone
- [x] Box
- [ ] Rounded Box
- [ ] Squircle
- [x] Capsule
- [x] IcoSphere
- [ ] Octasphere
- [x] Sphere
- [ ] Tube
- [ ] Torus
- [x] Tesselated Text
- [x] Extruded Text
- [x] Supershape
- [x] Skybox
- [ ] Parametric

# Object

<img width="1334" height="821" alt="image" src="https://github.com/user-attachments/assets/363949de-847f-4f79-8a9a-3702e7a5c4a4" />

- [x] Mesh
- [x] Instanced Mesh
- [x] 3D Model Loader
- [x] Orthographic Camera
- [x] Perspective Camera
- [x] Directional Light
- [x] Point Light
- [ ] Spot Light

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
- [x] Video Provider (AVFoundation)
- [x] Camera Provider (AVFoundation)

### Color Adjust

- [x] Brightness / Contrast / Saturation
- [x] Hue
- [ ] Color Polynomial
- [x] White Balance
- [x] Vibrance
- [ ] Levels
- [ ] Gamma
- [ ] Exposure
- [ ] Channel Mixer
- [ ] Channel Combine
- [ ] Color Space To / From

### Color Effect

- [ ] Color LUT
- [x] Invert
- [x] Duo Tone
- [ ] False Color

### Lens

- [ ] Lens Distortion
- [ ] Chromatic Abberation
- [ ] Grain
- [x] Vignetting
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

### Compositing

- [x] Porter Duff compositing
    - Atop
    - In
    - Out
    - Over
    - Xor

### Masking
- [ ] Image to Mask
- [x] Foreground Mask (ML)
- [x] Person Mask (ML)

### Tiling

- [ ] Lygia Tiling Ops
- [x] Kaleidoscope
- [ ] Mirror

### Decimation

- [ ] Threshold
- [ ] Dither
- [x] Pixelate
- [ ] Half Tone

### Distortion

- [ ] Warp
- [ ] Bump
- [ ] Displacement
- [ ] Twirl
- [ ] Pinch

### Blur

- [ ] Gaussian (Kawase)
- [ ] Directional (Motion)
- [x] Depth of Field 
- [ ] Bloom
- [ ] Gloom
- [ ] Variable Versions of above

### Morphology

- [ ] Sharpen
- [ ] Unsharpen
- [x] Sobel
- [ ] Dilate
- [ ] Erode
- [ ] Open
- [ ] Close

### Info 
- [x] Image Dimensions
- [ ] Image Crop
- [ ] Image Resize (Linear / Bilinear / Lancos)
- [ ] Image Pixel to Color (sample at XY -> XYZ)

# Parameters

### Boolean

- [x] True
- [x] False
- [ ] Logic Operator
- [ ] Signal

### Index

Have yet to work on Index (integer only) numeric nodes 

### Number

- [x] Number
- [x] Current Time (AKA Patch Time)
- [x] System Time
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
- [ ] LFO
- [ ] Smooth (Kalman or 1 Euro Filter?)
- [ ] Math Expression
- [ ] Audio Spectrum

### Vector

- [x] Make Vec 2
- [x] Make Vec 3
- [x] Make Vec 4
- [x] Vec 2 to Float
- [x] Vec 3 to Float
- [x] Vec 4 to Float
- [ ] Vector Ops (Cross / Dot / etc)

### Color

Have yet to work on Color nodes, ideally all color spaces / images are linear / aces linear internally, we'll see!

### Quaternion

Have yet to work on Quaternion nodes, unclear if we def want these types??

### Matrix

Have yet to work on Matrix nodes, unclear if we def want these types?

### String

- [x] String Loader (Text file loader)
- [x] String Components
- [x] String Length
- [x] String Range
- [ ] String Case
- [ ] String Formatter
- [ ] String Join
- [ ] String Separator
- [ ] String Compare
- [x] Convert to String ( type convert )
- [ ] Date Formatter
- [ ] Current Date
- [ ] Directory Scanner
- [ ] String to Timecode Format

### Array

Array nodes are implemented as Swift Generics, and can work with any of the above types

- [x] Queue
- [x] Array Count
- [x] Item at Index (Number for now)
- [ ] Multiplexer
- [ ] Demultiplexer
- [ ] Sort (? what does this mean for some types ?)
- [ ] Reverse
- [ ] Range / Slice

### Signaling Nodes

- [x] Sample and Hold
- [ ] Pulse
- [ ] Signal
- [ ] Timeline

# Other Nodes

###  I / O

- [ ] Keyboard
- [x] Mouse / Touch / Cursor (macOS)
- [ ] OSC Input
- [ ] OSC Output
- [ ] Midi Input
- [ ] Midi Output
- [ ] HID Input
- [ ] HID Output
- [ ] NDI Input
- [ ] NDI Output
- [ ] Syphon Input
- [ ] Syphon Output
- [ ] Artnet Input
- [ ] Artnet Output

###  Info Nodes
 - [x] Rendering Destination Dimensions
 - [x] Units to Pixels
 - [x] Pixels to Units
 - [ ] Mesh Hit Test
 - [ ] Frame Rate
 - [x] Frame Counter
 - [ ] Log

 
 


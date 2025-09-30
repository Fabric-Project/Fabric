<img width="1568" height="1110" alt="image" src="https://github.com/user-attachments/assets/f6425c2c-e44d-4fda-bc93-3bb94c3978a9" />


A list of Nodes (planned and implemented) for Fabric.

# Material

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
- [ ] Line
- [x] Plane
- [x] Point Plane (Temp until #15 is fixed)
- [ ] Rounded Rect
- [ ] Triangle
- [ ] Circle
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
- [x] Mesh
- [x] Instanced Mesh
- [x] 3D Model Loader
- [x] Scene (Environment and Scene Graph)
- [x] Orthographic Camera
- [x] Perspective Camera
- [x] Directional Light
- [x] Point Light
- [ ] Spot Light
- [x] Render Node
- [x] Deferred Render Node (Outputs Depth / Texture)
- [ ] Sub-Graph Node 

# Image Processing

### Loading
- [x] Image Loader
- [ ] Video Loader (AVFoundation)
- [ ] Camera Loader (AVFoundation)

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

- [ ] Standard Mixing Modes
- [ ] Mix modes with Masking

### Compositing

- [ ] Porter Duff compositing

### Masking
- [ ] Image to Mask
- [ ] Subject Mask (ML)
- [ ] Person Mask (ML)

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
- [x] Sobel
- [ ] Dilate
- [ ] Erode
- [ ] Open
- [ ] Close

### Info 
- [ ] Image Dimensions

# Parameters

### Boolean

- [x] True
- [x] False
- [ ] Logic Operator

### Index

Have yet to work on Index (integer only) numeric nodes 

### Number

- [x] Number
- [x] Current Time
- [x] Integrator (accrues every frame for now)
- [ ] Derivator
- [x] Single Operator Math
- [x] Binary Operator Math
- [x] Gradient Noise (FBM)
- [x] Remap
- [x] Tween / Easing
- [ ] Clamp
- [ ] Round
- [ ] Counter
- [ ] LFO
- [ ] Smooth (Kalman or 1 Euro Filter?)
- [ ] Audio Spectrum

### Vector

- [x] Make Vec 2
- [x] Make Vec 3
- [x] Make Vec 4
- [ ] Vector Ops (Cross / Dot / etc)

### Quaternion

Have yet to work on Quaternion nodes, unclear if we def want these types??

### Matrix

Have yet to work on Matrix nodes, unclear if we def want these types?

### String

- [x] String Loader (Text file loader)
- [x] String Components
- [x] String Length
- [x] String Range
- [ ] String Formatter
- [ ] String Join
- [ ] String Separator
- [ ] String Compare
- [ ] Date Formatter
- [ ] Current Date

### Array

Array nodes are implemented as Swift Generics, and can work with any of the above types

- [x] Queue
- [x] Array Count
- [x] Item at Index (Number for now)
- [ ] Multiplexer
- [ ] Demultiplexer
- [ ] Sort (? what does this mean for some types ?)


# Other Nodes

###  I / O

- [ ] Keyboard
- [ ] Mouse / Touch / Cursor 
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
 - [ ] Rendering Destination Dimensions


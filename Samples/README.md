
# Getting Started with Fabric:

Included in the Sample folder is an evolving set of tutorial and sample Fabric files, each of which is documented below. 

Feel free to download these samples to use as references for learning, or starting templates for your own work with Fabric.

## 1 - Basic Color Plane

<img width="2056" height="1329" alt="image" src="https://github.com/user-attachments/assets/4a9840c4-d5cd-440b-a4d9-3e42c4228b64" />

This example explores the simplest setup.

* A `Geometry` node provides data for the 'shape' of geometry to draw
* A `Material` node provides data for the 'color' of material to draw
* A `Mesh` node consumes both a `Geometry` and a `Material` and positions, scales and orients it in the 3D world

A standard composition like this uses the default coordinate system, and provides a default `Camera` on your behalf.  

Explore available `Geometry` nodes available in the left hand Sidebar and try connecting them to the `Mesh` node!

## 2 - Animated Color Plane

<img width="2056" height="1329" alt="image" src="https://github.com/user-attachments/assets/723ab6fe-4235-42c1-8759-60e192f9fc7a" />

This examples explore our first adventure with time, and introduces animation principles in Fabric:

* A `Number Integrator` node will accrue a value over one second. Integrating at a rate of 1, will mean that every second, the value will increase by 1. 
* `Gradient Noise` node provides a smooth landscape of random values - allowing us to create continuous random values between -1 and 1. 
* `Number Remap` node allows us to scale a number that lies between one range to another. 
* `Vector 4` node allows us to combine 4 Number values into a single piece of data - known as a vector. This vector has 4 values.

Combining the above nodes lets us produce 3 smoothly changing random values which we intepret the 4 vector values as red, green, blue and a constant alpha (transparency) color. Because our color's red, green and blue values are driven by independent changing random numbers, it animates over time. 

* Play with the `Number Integrators` value to adjust how quickly our color animates. 
* Play with the individual `Number Remap` output range values to adjust how much Red, Green or Blue you want in your final color.

## 3 - Animation Easing

<img width="2056" height="1329" alt="image" src="https://github.com/user-attachments/assets/67f2b057-b604-470c-a59c-474d5d4f482e" />

This example expands on our Animation example above, using our `Number Integrator` to drive animation. 

Because we are drawing multiple objects, we create one `Mesh` node for each object we wish to draw. 

We introduce:

* `Number Binary Math` node which does math on 2 numerical values. You can chose addition, subtraction, etc. In our case, we chose the modulo operation.
* `Number Ease` node which changes how a number moves through the range of 0 to 1

This example shows how different easing values change the position of a sphere over the same time. 

> [!Important]
> Note we can re-use `Geometry` nodes across multiple `Mesh` nodes.
> This saves memory and is more efficient.
> Because we want different colors, we use multiple `Color Material` nodes.


* Play with the `Integrator Node` to adjust the animation speed like before.
* Play with the `Number Ease` values to get an intuition for the types of easing curves and how they change the feeling of the movement.

## 4 - 3D Scene

<img width="2056" height="1329" alt="image" src="https://github.com/user-attachments/assets/717e6dd1-0c5a-41ed-8eb6-6053b94764ea" />

This example expands on our concept of our composition and introduces a sense of space to our animation.

We introduce

* A `Perspective Camera` to control our view of the scene.
* A `Directional Light` to provide lighting to our scene.

We are familiar with `Geometry` , `Material` and `Mesh` nodes by now, but take note as to how each `Mesh` is positioned, and how different `Material` nodes respond to different lighting  and tranparency settings. 

* Play with the position of the `Camera Node` to get a sense for space. 
* Try animating the `Camera` position! You know how!
* Play with the `Directional Lighting` node to get a sense for how different materials respond to lighting setups.
* Try animating the `Directional Lighting` color or position for fun. 


## 5 - Camera and Image Processing

<img width="2056" height="1329" alt="image" src="https://github.com/user-attachments/assets/4346ed1d-6193-4484-ae1e-7eebedb7104b" />

This examples introduces image processing with Fabric.

We introduce the `Image` data type and nodes which process images. 

* A `Camera Node` produces a steady stream of `Image` data from a camera available (and even your iPhone's camera if paired)
* Various `Image` processing nodes
   * `Duo Tone` node adjusts the color for a two tone image effect
   * `Fade Curve` mixes between two `Images`
   * `Kaliedoscope` creates a geometric kaliedoscope image effect.


We leverage a `Image Material` to draw the processed image on to a plane geometry. 

* Play with the value and order of the `Image` effects to produce different resulting images. 
* Explore the available `Image` processing nodes available in the side bar.
* Try animating the `Image` processing values using your knowledge of Fabric.
* Try loading a movie file via the `Movie Provider` node, or an image file via the `Image Provider` node.

## 6 - Determinant Of Hessians

<img width="1526" height="1060" alt="image" src="https://github.com/user-attachments/assets/a72a045b-5ff3-4170-98b4-5e00f2ae83b5" />

This is a fancy name for a tye of edge detector (sorry it sounds cool!).

This graph demonstrains chaining image filter operations  - a set sobel filters in a very specific way to help identify edges.

However, this graph is pretty complex, and it might be nice to organize it so that it acts like other image processing nodes - inputting an image and ouputting an image. 

Lets see if we can do that:

## 7 -  Determinant Of Hessians with a Subgraph

<img width="1293" height="695" alt="image" src="https://github.com/user-attachments/assets/2169d9d3-b864-4568-a40c-d49055d81ce9" />

To clean up our custom filter - we can use a Subgraph - which you can think of as a second set of nodes, which can expose inputs and outputs.

<img width="550" height="257" alt="image" src="https://github.com/user-attachments/assets/e34b7f0b-962b-4c09-b2c2-e3576cdb7f4d" />

Select the `Subtract` (the last `Image` processing node in the chain), right click/control click, and choose `Selection -> Select all Upstream Nodes`

This will select all nodes that `Subtract` has as inputs.

<img width="711" height="296" alt="image" src="https://github.com/user-attachments/assets/921e25bd-c06f-4648-9187-ffc462ae764c" />

Shift click to de-select the `Camera Provider` node, and then right click/control click on `Subtract` and chose `Selection -> Embed Selection In...  -> Subgraph`

This wlll embed the selected nodes into a new `Subgraph` Node. Double click the `Subgraph` Node and you can see the `Image` processing filter chain.

In order to expose the inputs (2 images, and a number) and the resulting image to the parent graph, we need to `Publish` some ports

`Publishing` a port makes it available as an input or output to the graph above the current graph. Select the final `Subtract` Node, right click/control click and `Publish` the Image output port.

<img width="479" height="264" alt="image" src="https://github.com/user-attachments/assets/89a297c3-7249-46f9-950f-e8716fdb57b8" />

You can do the same for the 2 input images and the number port.

> [!Warning]
> As of Alpha 5 - Embedding into any subgraphs nodes do not yet auto-publish ports.
> Please manually publish ports to maintain connections to the parent graph.
> Stay tuned for fixes!

## Render In Image

<img width="2628" height="1807" alt="image" src="https://github.com/user-attachments/assets/85971e38-875b-43a4-9277-86a8cb4e2570" />

<img width="1444" height="792" alt="image" src="https://github.com/user-attachments/assets/05f34be1-fef7-47a3-bee3-347dd5361bc8" />

This graph introduces `Render In Image` node, a special kind of `Subgragh` node that allows 3D scenes to rendered off screen be post processed by `Image` nodes.

* `Render In Image` has its own `Subgraph` which can host 3D rendering
* `Render In Image` has a resolution, the width and height of the resulting image.
* `Render In Image` has 2 `Image` Outlet `Ports` -  one for color render, and one for depth, which we use in this graph.

We also introduce anew `Image` filters which used together can leverage both the Color and Depth `Images` from `Render In Image` to produce a depth of field effect.









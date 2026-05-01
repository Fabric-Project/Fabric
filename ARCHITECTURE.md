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

As you can see in the image above, `Nodes` have inputs and outputs depending on what they do, and these are called `Ports`, and ports of the same type can be connected to one another to form a `Graph` and compute useful things. 

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
- Matrix ( Not yet integrated )

Objects (Colored):
- Geometry (A set of buffers that work together to define how 
- Material (a Vertex and Fragment Program that work with the graphics engine)
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

# Numeric Hygiene — Never Emit Non-Finite Values

`Float` and `Double` outputs from a node must be **finite**. Emitting `NaN` or `±Inf` from a `Number` (or any `Float`/`Double` array) outlet is a serious bug: it can crash the application.

### Why

A `NaN` value that lands in a downstream `FloatParameter` triggers an unbounded recursion between `ParameterPort.value.didSet` and the underlying Satin `GenericParameter`'s publisher. The cycle is fundamental to how Swift compares floats: `NaN != NaN` is **always true**, so the equality guard at each end of the cycle (`if oldValue != self.value`) never short-circuits. Each iteration republishes the same `NaN`, the next subscriber writes it back, and the stack overflows in milliseconds. The crash surfaces as `EXC_BAD_ACCESS (code=2)` with a thread stack of repeating `send` / `didset` / `closure` frames.

`Inf` is less catastrophic but causes its own problems (e.g., when downstream maps a value into a finite range, or when the value is later combined arithmetically and produces `NaN`).

### Where non-finite values come from

Common sources, none of them exotic:

* **Math edge cases** — `0/0`, `log(x)` for `x ≤ 0`, `asin(x)` for `|x| > 1`, `sqrt(x)` for `x < 0`, division by a value that may be zero.
* **Uninitialized inputs at load time** — during graph decode, an upstream port's value may briefly be `nil`. If your node substitutes `Double.nan` as a default in that case, you've armed the cycle.
* **Bad audio / device data** — capture buffers from misbehaving devices can contain `NaN` samples.
* **Sticky internal state** — a one-pole filter's state, an envelope follower, or any feedback variable, once contaminated, stays `NaN` forever (`x + α(input - x)` is `NaN` when `x` is `NaN`, regardless of `input`).

### The two valid strategies

When your node *might* produce a non-finite value, pick one of:

#### 1. Don't emit (preferred when the output is meaningless without all inputs)

If the result depends on inputs that haven't propagated yet, or on conditions that aren't met, **skip the `send` entirely**. Downstream keeps its last known good value. This is what `Math Expression` and `Array Math Expression` do when an input variable hasn't received a value yet:

```swift
var sawUnresolvedVariable = false
let result = evaluator.eval(variables: { variable in
    if let port = self.findPort(named: variable) as? NodePort<Float>,
       let portValue = port.value {
        return Double(portValue)
    }
    sawUnresolvedVariable = true
    return 0  // not NaN — keeps the in-progress math finite
})

let output = Float(result)
guard !sawUnresolvedVariable, output.isFinite else { return }
self.outputNumber.send(output)
```

The fallback inside the evaluator is `0`, not `NaN`, so the in-progress math doesn't get poisoned even before the guard runs.

#### 2. Scrub to 0 (preferred when partial output is acceptable)

For per-element array outputs, dropping the entire emit because of one bad element is heavy-handed. Validate per-element and substitute `0`:

```swift
let f = Float(result)
output.append(f.isFinite ? f : 0)
```

`Array Math Expression` does this for legitimate per-element math NaN, and combines it with strategy (1) for unresolved-variable failures.

#### 3. Self-heal sticky state

If your node holds internal floating-point state that feeds itself (envelope followers, IIR filters, accumulators), validate the state on read and reset to `0` if it's gone non-finite, so a one-time bad input can't poison the node forever:

```swift
let prev = state[k].isFinite ? state[k] : 0
let next = prev + alpha * (input - prev)
state[k] = next.isFinite ? next : 0
```

`AudioSpectrum`'s `SimpleFilterBank` envelope follower uses this pattern.

### What not to do

* **Don't** silently `0.0`-fallback at port reads while still emitting the result — if the math then produces `NaN` from another path, you've moved the failure, not fixed it. Pair the read-time fallback with an emit-time `isFinite` guard.
* **Don't** rely on downstream nodes to scrub. Every node-author is responsible for the validity of its own outputs. Once a `NaN` reaches a `FloatParameter`, it's already too late.
* **Don't** assume "this can't happen" — load-time and device-edge cases produce non-finite values in practice.

### Rule of thumb

> A `Number` outlet should only ever `send` a value for which `isFinite == true`. If you can't guarantee that, either skip the `send` or scrub to `0` first.

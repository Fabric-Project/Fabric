# JavaScript Node

Processes Fabric data with a JavaScript function. The function's signature
declares the node's ports, and running it moves values through them.

## The signature

```typescript
function main(a: Number, b: Number): { sum: Number, over: Bool } {
  const total = a + b
  return { sum: total, over: total > 1 }
}
```

The parameters are the node's inputs, the return type its outputs, and both take
the port's name from the declaration. The function **must return** an object with
a key per declared output; a script that returns something else, or throws, has
its error reported on the node and at the line it happened.

A script with nothing to send declares no return type.

## Types

| Signature type | Arrives as | Return as |
| --- | --- | --- |
| `Bool` | `boolean` | `boolean` |
| `Int` | `number` | `number`, truncated to a 32-bit integer |
| `Number` | `number` | `number` |
| `String` | `string` | `string` |
| `Vector2` | `[x, y]` | two numbers |
| `Vector3` | `[x, y, z]` | three numbers |
| `Vector4` | `[x, y, z, w]` | four numbers |
| `Color` | `[r, g, b, a]` | four numbers |
| `Quaternion` | `[x, y, z, w]` | four numbers, `w` last |
| `Transform` | sixteen numbers | sixteen numbers, column-major |
| `Geometry` | `{ type, handleID, vertexCount, indexCount, boundsMin, boundsMax }` | the object it arrived as |
| `Material` | `{ type, handleID, label, hasShader, parameterCount, blending }` | the object it arrived as |
| `Image` | `{ type, handleID, width, height, textureTransform, pixelFormat }` | the object it arrived as |

An array of any of them is `Type[]`, and a dictionary keyed by string is
`Record<string, Type>`. Both nest: `Record<string, Transform[]>` is a
dictionary of arrays.

`Value` is any value at all, and is what the dictionary nodes and the JSON
parser hand out, so `Record<string, Value>` is how a script takes one of
those. It can only be an input, in any of its forms: a signature that returns a
`Value` is refused, because there is no way to say what a value is on the
way back out.

A transform's sixteen numbers are four columns of four, so `m[12]`, `m[13]` and
`m[14]` are its translation.

## What is in scope

`context`, describing the frame being run:

| | |
| --- | --- |
| `time` | seconds since the graph started |
| `deltaTime` | seconds since the last frame |
| `displayTime` | when the frame is for, where a source knows |
| `systemTime` | seconds since the reference date |
| `frameNumber` | frames since the graph started |
| `iterationIndex` | which pass, inside an Iterator |
| `iterationCount` | how many passes, inside an Iterator |

`console.log` prints to the app's output. `import`, `export`, `require` and
dynamic `import` are rejected: a script is the document's, and reaches nothing
the document does not carry.

## Worth knowing

**Geometry, material and image are handles.** Their properties read, but nothing
written to them is kept, and an output of one of those types has to be an object
that arrived as an input. An object merely shaped like one sends nothing.

**A collection is all or nothing.** One element that cannot be converted discards
the whole array or dictionary rather than that element, so a single stray value
costs the lot.

**Colour is a vector4.** Fabric holds no separate colour value, so the two are
interchangeable in both directions.

**An input with nothing on it is `null`.** Returning `null` or `undefined` for an
output sends nothing rather than a zero.

## The annotated form

Scripts written for this node before it took a TypeScript signature declared
their ports as `function (__type name) main(__type name)`, outputs first. Those
still parse, and are rewritten to the signature above as they are read — the
signature only, leaving the body as its author wrote it.

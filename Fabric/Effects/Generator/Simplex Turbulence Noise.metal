//
//  Simplex Turbulence Noise.metal
//  Fabric
//
// description: Generates turbulence from simplex noise

#include "../../lygia/generative/snoise.msl"

#define FABRIC_NOISE_FUNC(position, uniforms) snoise(position)
#define FABRIC_NOISE_COMBINER(position, uniforms) fabricNoiseTurbulence(position, uniforms)
#define FABRIC_NOISE_UNSIGNED_OUTPUT 1

#include "Noise/Library/NoiseTemplateFractal.msl"

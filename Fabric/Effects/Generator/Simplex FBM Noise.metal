//
//  Simplex FBM Noise.metal
//  Fabric
//
// description: Generates fractal Brownian motion from simplex noise

#include "../../lygia/generative/snoise.msl"

#define FABRIC_NOISE_FUNC(position, uniforms) snoise(position)
#define FABRIC_NOISE_COMBINER(position, uniforms) fabricNoiseFBM(position, uniforms)

#include "Noise/Library/NoiseTemplateFractal.msl"

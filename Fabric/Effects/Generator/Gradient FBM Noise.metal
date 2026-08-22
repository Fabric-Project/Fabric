//
//  Gradient FBM Noise.metal
//  Fabric
//
// description: Generates fractal Brownian motion from gradient noise

#include "../../lygia/generative/gnoise.msl"

#define FABRIC_NOISE_FUNC(position, uniforms) gnoise(position)
#define FABRIC_NOISE_COMBINER(position, uniforms) fabricNoiseFBM(position, uniforms)

#include "Noise/Library/NoiseTemplateFractal.msl"

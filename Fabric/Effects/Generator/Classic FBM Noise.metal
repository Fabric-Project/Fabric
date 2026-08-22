//
//  Classic FBM Noise.metal
//  Fabric
//
// description: Generates fractal Brownian motion from classic Perlin noise

#include "../../lygia/generative/cnoise.msl"

#define FABRIC_NOISE_FUNC(position, uniforms) cnoise(position)
#define FABRIC_NOISE_COMBINER(position, uniforms) fabricNoiseFBM(position, uniforms)

#include "Noise/Library/NoiseTemplateFractal.msl"

//
//  Wavelet FBM Noise.metal
//  Fabric
//
// description: Generates fractal Brownian motion from wavelet noise

#include "../../lygia/generative/wavelet.msl"

#define FABRIC_NOISE_FUNC(position, uniforms) wavelet(position)
#define FABRIC_NOISE_COMBINER(position, uniforms) fabricNoiseFBM(position, uniforms)

#include "Noise/Library/NoiseTemplateFractal.msl"

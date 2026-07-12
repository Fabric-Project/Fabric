//
//  Worley Noise.metal
//  Fabric
//
// description: Generates cellular Worley noise

#define FABRIC_NOISE_FUNC(position, uniforms) fabricNoiseWorley(position, uniforms)
#define FABRIC_NOISE_COMBINER(position, uniforms) fabricNoiseSingle(position, uniforms)
#define FABRIC_NOISE_UNSIGNED_OUTPUT 1

#include "Noise/Library/NoiseTemplateCellular.msl"

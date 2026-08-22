//
//  Voronoise Noise.metal
//  Fabric
//
// description: Generates smooth Voronoi value noise

#include "../../lygia/generative/voronoise.msl"

#define FABRIC_NOISE_FUNC(position, uniforms) voronoise(position, uniforms.cellularJitter, uniforms.smoothness)
#define FABRIC_NOISE_COMBINER(position, uniforms) fabricNoiseSingle(position, uniforms)
#define FABRIC_NOISE_UNSIGNED_OUTPUT 1

#include "Noise/Library/NoiseTemplateVoronoise.msl"

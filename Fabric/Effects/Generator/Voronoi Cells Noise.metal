//
//  Voronoi Cells Noise.metal
//  Fabric
//
// description: Generates Voronoi cell distance noise

#define FABRIC_NOISE_FUNC(position, uniforms) fabricNoiseVoronoiDistance(position, uniforms)
#define FABRIC_NOISE_COMBINER(position, uniforms) fabricNoiseSingle(position, uniforms)
#define FABRIC_NOISE_UNSIGNED_OUTPUT 1

#include "Noise/Library/NoiseTemplateCellular.msl"

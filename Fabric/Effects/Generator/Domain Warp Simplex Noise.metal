//
//  Domain Warp Simplex Noise.metal
//  Fabric
//
// description: Generates domain-warped simplex fractal Brownian motion noise

#include "../../lygia/generative/snoise.msl"

#define FABRIC_NOISE_DOMAIN_WARP_AMOUNT(uniforms) uniforms.domainWarpAmount
#define FABRIC_NOISE_FUNC(position, uniforms) snoise(position)
#define FABRIC_NOISE_COMBINER(position, uniforms) fabricNoiseDomainWarpFBM(position, uniforms)

#include "Noise/Library/NoiseTemplateDomainWarp.msl"

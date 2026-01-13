//
//  TestPostProcessor.metal
//  v
//
//  Created by Anton Marini on 7/15/24.
//


#define SAMPLER_PRECISION half4
#define SAMPLER_TYPE texture2d<half>

#include "../../lygia/sampler.msl"
#include "../../lygia/math.msl"
//#include "../lygia/math/atan2.msl"
#include "../../lygia/color/brightnessContrast.msl"
#include "../../lygia/space/sqTile.msl"
// From Satin, not Lygia FWIW
#include "Library/Repeat.metal"


typedef struct {
    float amount; // slider, 0.0, 1.0, 0.0, Amount
    float angle; // slider, 0.0, 1.0, 0.0, Angle 
    float2 origin; // xypad 0.0, 1.0, 0.5, Origin
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<half, access::sample> renderTex [[texture( FragmentTextureCustom0 )]] )
{
	
	float2 texSize = float2(renderTex.get_width(), renderTex.get_height());
    float2 aspect  = float2(texSize.x / texSize.y, 1.0);

    // origin in normalized UV (0..1). If you don’t have it yet, use center:
    float2 originUV = uniforms.origin;

    // 1) center + aspect-correct to metric space
    float2 p = (in.texcoord - originUV);
    p *= aspect;                // now distance uses correct metric

    // 2) polar
    float r   = length(p);
    float phi = atan2(p.y, p.x); // <-- important

    // 3) quantize (your repeat scheme, keeping your semantics)
    float2 polar  = float2(r, phi);
    float2 polar2 = polar;
    float2 polar3 = polar;

    int2 cellAmount = repeat(polar2, uniforms.amount);
    polar.y = float(cellAmount.y) * uniforms.amount;

    int2 cellAngle = repeat(polar3, uniforms.angle);
    polar.x = float(cellAngle.x) * uniforms.angle;

    // 4) back to cartesian in metric space
    float2 q;
    q.x = polar.x * cos(polar.y);
    q.y = polar.x * sin(polar.y);

    // 5) undo aspect + re-center back to UV space
    q /= aspect;
    float2 uv = q + originUV;

    // (optional) clamp to avoid sampling outside
    uv = clamp(uv, 0.0, 1.0);

    half4 color = SAMPLER_FNC(renderTex, uv);
    return color;

}

//
//  DisplacementMaterial.metal
//  
//
//  Created by Anton Marini on 7/4/25.
//

#include <metal_stdlib>
using namespace metal;

typedef struct {
    float pointSize;
    float amount; // slider, 0.0, 2.0, 0.0, Amount
    float minPointSize; // slider, 0.5, 128.0, 1.0, Min Point Size
    float maxPointSize; // slider, 0.5, 128.0, 1.0, Max Point Size
    float brightness; // slider, 0.0, 2.0, 1.0, Brightness
    float lumaVPosMix; // slider, 0.0, 1.0, 0.0, Luma vs RGB
    float4x4 displacementTextureTransform;
    float4x4 colorTextureTransform;
} DisplacementUniforms;

constexpr sampler s( min_filter::linear, mag_filter::linear);

constant half4 lumcoeff = half4(0.299,0.587,0.114,0.);

typedef struct {
    float pointSize [[point_size]];
    float4 position [[position]];
    float2 uv;
} CustomVertexData;

vertex CustomVertexData displacementVertex(Vertex in [[stage_in]],
                                           ushort amp_id [[amplification_id]],
                                           constant VertexUniforms *vertexUniforms [[buffer( VertexBufferVertexUniforms )]],
                                           constant DisplacementUniforms &uniforms [[buffer( VertexBufferMaterialUniforms )]],
                                           texture2d<half, access::sample> rdTex [[texture( VertexTextureCustom0 )]] )
{
    CustomVertexData out;

    const float2 displacementUV =
        (uniforms.displacementTextureTransform * float4(in.texcoord, 0.0, 1.0)).xy;
    const half4 sample = rdTex.sample(s, displacementUV);
    const half luma = dot(lumcoeff, sample);

    const float3 position = mix(in.position, float3(sample.rgb), uniforms.amount);
    const float3 lumaPos = in.position + normalize(in.normal) * float(luma) * uniforms.amount;
    const float3 final = mix(lumaPos, position, uniforms.lumaVPosMix);

#if INSTANCING
    out.position = vertexUniforms[amp_id].viewProjectionMatrix * instanceUniforms[instanceID].modelMatrix * float4( final, 1.0 );
#else
    out.position = vertexUniforms[amp_id].modelViewProjectionMatrix * float4( final, 1.0 );
#endif
    
    out.pointSize = uniforms.pointSize * mix(uniforms.minPointSize, uniforms.maxPointSize, float(luma));
    out.uv = in.texcoord;
    
    return out;
}

// The material's Point Sprite setting shapes each point (SATIN_POINT_SPRITE); meshes of
// triangles draw unshaped.
fragment half4 displacementFragment( CustomVertexData in [[stage_in]],
                                     constant DisplacementUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
                                     texture2d<half, access::sample> colorTex [[texture( FragmentTextureCustom0 )]]
                                     SATIN_POINT_SPRITE_FRAGMENT_DATA )
{
    const float2 colorUV =
        (uniforms.colorTextureTransform * float4(in.uv, 0.0, 1.0)).xy;
    const half4 color = colorTex.sample(s, colorUV);
    return SATIN_POINT_SPRITE(color * half(uniforms.brightness));
}

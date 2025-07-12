//
//  DisplacementMaterial.metal
//  
//
//  Created by Anton Marini on 7/4/25.
//

#include <metal_stdlib>
using namespace metal;

typedef struct {
    float amount;
    float minPointSize;
    float maxPointSize;
    float brightness;
    float lumaVPosMix;
} DisplacementUniforms;

constexpr sampler s( min_filter::linear, mag_filter::linear);
constexpr sampler p( min_filter::linear, mag_filter::linear, mip_filter::linear );

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

    const half4 sample = rdTex.sample( s, in.texcoord );
    const half luma = dot(lumcoeff, sample);

    const float3 position = mix(in.position, float3(sample.rgb), uniforms.amount);
    const float3 lumaPos = mix(in.position, in.position + float3(0.0, 0.0, luma), uniforms.amount);
    const float3 final = mix(lumaPos, position, uniforms.lumaVPosMix);

#if INSTANCING
    out.position = vertexUniforms[amp_id].viewProjectionMatrix * instanceUniforms[instanceID].modelMatrix * float4( final, 1.0 );
#else
    out.position = vertexUniforms[amp_id].modelViewProjectionMatrix * float4( final, 1.0 );
#endif
    
    out.pointSize =  mix(uniforms.minPointSize, uniforms.maxPointSize, float(luma));
    out.uv = in.texcoord;
    
    return out;
}

[[early_fragment_tests]]
fragment half4 displacementFragment( CustomVertexData in [[stage_in]],
                                                             const float2 puv [[point_coord]],
//                                                                uint stencilValue [[stencil_value]],
//                                                                uint refValue [[stencil_ref_value]],

                                                             //                                     const half4 existingColor [[color(0)]],
                                                             
                                                             constant DisplacementUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
                                                             texture2d<half, access::sample> colorTex [[texture( FragmentTextureCustom0 )]],
                                                             texture2d<half, access::sample> pointSpriteTex [[texture( FragmentTextureCustom1 )]] )
{
    
//    if (length(puv - float2(0.5)) > 0.5)
//    {
//        discard_fragment();
//    }
    
//    const uint width = colorTex.get_width();
//    const uint height = colorTex.get_height();
//    const float2 reslution = float2(width, height);
//
//    const half4 color = colorTex.read( uint2(in.uv * reslution) );
    
//    if ( length(existingColor) > 1.0 )
//          discard_fragment();
//    
    
//    const half4 blendFactor = 1.0 - half4(stencilValue) / half4(refValue); // fade out at limit

    const half4 color = colorTex.sample( s, in.uv );
    const half4 sprite = pointSpriteTex.sample( p, puv ) ;
        
    return sprite;// * color * uniforms.brightness;
}

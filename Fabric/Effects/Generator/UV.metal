//
//  BasicColorTexture.metal
//  Fabric
//
//  Created by Anton Marini on 6/29/25.
//


typedef struct {
} PostUniforms;

fragment half4 postFragment( VertexData in [[stage_in]],
                            constant PostUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]])
{
    return half4(in.texcoord.x, in.texcoord.y, 0.0, 1.0);
}

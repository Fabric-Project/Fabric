//
//  Constant Color.metal
//  Fabric
//
// description: Generates a constant signed four-channel image
//

typedef struct {
    float4 value; // slider, -1.0, 1.0, 0.0, Value
} PostUniforms;

fragment half4 postFragment(
    VertexData in [[stage_in]],
    constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]]
)
{
    return half4(uniforms.value);
}

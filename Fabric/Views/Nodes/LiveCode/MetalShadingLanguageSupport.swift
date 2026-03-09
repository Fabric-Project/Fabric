//
//  MetalShadingLanguageSupport.swift
//  Fabric
//
//  Created by Codex on 3/4/26.
//

import LanguageSupport

private let metalReservedOperators = [
    ".", ",", ";", ":", "::", "?", "->", "->*", ".*",
    "=", "+", "-", "*", "/", "%", "++", "--",
    "+=", "-=", "*=", "/=", "%=",
    "==", "!=", "<", ">", "<=", ">=",
    "&&", "||", "!",
    "&", "|", "^", "~", "<<", ">>",
    "&=", "|=", "^=", "<<=", ">>=",
]

private let metalReservedIdentifiers = [
    // C/C++ and MSL language keywords and qualifiers.
    "alignas", "alignof", "asm", "auto", "bool", "break", "case", "catch", "char",
    "class", "const", "constexpr", "consteval", "constinit", "const_cast", "continue",
    "decltype", "default", "delete", "do", "double", "dynamic_cast", "else", "enum",
    "explicit", "export", "extern", "false", "float", "for", "friend", "goto", "if",
    "inline", "int", "long", "mutable", "namespace", "new", "noexcept", "nullptr",
    "operator", "private", "protected", "public", "register", "reinterpret_cast",
    "return", "short", "signed", "sizeof", "static", "static_assert", "static_cast",
    "struct", "switch", "template", "this", "thread_local", "throw", "true", "try",
    "typedef", "typeid", "typename", "union", "unsigned", "using", "virtual", "void",
    "volatile", "wchar_t", "while",
    "device", "constant", "thread", "threadgroup", "ray_data", "object_data", "mesh",
    "vertex", "fragment", "kernel", "compute", "visible", "extern_constant",
    "packed", "precise", "restrict", "__restrict", "__restrict__",
    // Attributes and qualifiers used in parameter/entry point declarations.
    "[[stage_in]]", "[[position]]", "[[point_size]]", "[[render_target_array_index]]",
    "[[viewport_array_index]]", "[[front_facing]]", "[[sample_id]]", "[[sample_mask]]",
    "[[thread_position_in_grid]]", "[[thread_position_in_threadgroup]]",
    "[[thread_index_in_threadgroup]]", "[[threads_per_threadgroup]]",
    "[[threadgroup_position_in_grid]]", "[[simdgroup_index_in_threadgroup]]",
    "[[thread_index_in_simdgroup]]", "[[grid_origin]]", "[[grid_size]]", "[[user(locn0)]]",
    "[[buffer(0)]]", "[[texture(0)]]", "[[sampler(0)]]", "[[color(0)]]", "[[depth(any)]]",
    // Access and sampler related terms.
    "access", "sample", "read", "write", "read_write", "sampler",
    "coord", "filter", "mip_filter", "address", "compare_func", "max_anisotropy",
    "normalized", "clamp_to_edge", "repeat", "mirrored_repeat", "clamp_to_zero",
    "nearest", "linear",
    // Core scalar and vector types.
    "half", "float", "double", "bool", "char", "uchar", "short", "ushort", "int", "uint",
    "long", "ulong",
    "half2", "half3", "half4", "float2", "float3", "float4", "double2", "double3", "double4",
    "bool2", "bool3", "bool4", "char2", "char3", "char4", "uchar2", "uchar3", "uchar4",
    "short2", "short3", "short4", "ushort2", "ushort3", "ushort4",
    "int2", "int3", "int4", "uint2", "uint3", "uint4", "long2", "long3", "long4",
    "ulong2", "ulong3", "ulong4",
    // Matrix types.
    "half2x2", "half2x3", "half2x4", "half3x2", "half3x3", "half3x4", "half4x2", "half4x3", "half4x4",
    "float2x2", "float2x3", "float2x4", "float3x2", "float3x3", "float3x4", "float4x2", "float4x3", "float4x4",
    "double2x2", "double2x3", "double2x4", "double3x2", "double3x3", "double3x4", "double4x2", "double4x3", "double4x4",
    // Texture and depth texture families.
    "texture1d", "texture1d_array", "texture2d", "texture2d_array", "texture2d_ms", "texture2d_ms_array",
    "texture2d_array_ref", "texturecube", "texturecube_array", "texture3d", "texture_buffer",
    "depth2d", "depth2d_array", "depth2d_ms", "depth2d_ms_array", "depthcube", "depthcube_array",
    // Other common MSL objects and builtins.
    "atomic", "array", "pair", "tuple", "metal", "simd", "complex", "imaginary",
    "radians", "degrees", "sin", "cos", "tan", "asin", "acos", "atan", "pow", "exp", "exp2",
    "log", "log2", "sqrt", "rsqrt", "abs", "min", "max", "clamp", "mix", "step", "smoothstep",
    "dot", "cross", "length", "distance", "normalize", "reflect", "refract", "faceforward",
    "floor", "ceil", "round", "trunc", "fract", "fmod", "modf", "isnan", "isinf",
]

extension LanguageConfiguration
{
    public static func metalShaderLanguage(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        let stringRegex = try? Regex<Substring>("\"(?:\\\\\"|[^\"])*+\"")
        let characterRegex = try? Regex<Substring>("'(?:\\\\.|[^'\\\\])'")
        let numberRegex = try? Regex<Substring>("-?(?:0[xX][0-9A-Fa-f]+|\\d+\\.\\d+(?:[eE][+-]?\\d+)?|\\d+[eE][+-]?\\d+|\\d+)")
        let identifierRegex = try? Regex<Substring>("[a-zA-Z_][a-zA-Z0-9_]*")
        let operatorRegex = try? Regex<Substring>("[+\\-*/%=!<>|&^~?:.,;]+")

        return LanguageConfiguration(
            name: "Metal Shader Language",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            stringRegex: stringRegex,
            characterRegex: characterRegex,
            numberRegex: numberRegex,
            singleLineComment: "//",
            nestedComment: (open: "/*", close: "*/"),
            identifierRegex: identifierRegex,
            operatorRegex: operatorRegex,
            reservedIdentifiers: metalReservedIdentifiers,
            reservedOperators: metalReservedOperators,
            languageService: languageService
        )
    }
}

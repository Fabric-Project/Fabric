//
//  PortValue+Codable.swift
//  Fabric
//

import Foundation
import simd

/// A value as a document holds it: one key naming the case, its payload in
/// that case's own form, `{"Float": 0.5}`, `{"Vector3": [0, 1, 0]}`. Vectors
/// are arrays of components; a Transform is its four columns, as Satin's
/// matrix parameter writes it. Geometry, Material and Image are runtime
/// objects with no document form: encoding one throws.
extension PortValue: Codable
{
    private enum CaseKey: String, CodingKey
    {
        case Bool, Int, Float, String, Vector2, Vector3, Vector4, Quaternion, Transform, Array, Dictionary
    }

    public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CaseKey.self)
        guard let key = container.allKeys.first, container.allKeys.count == 1 else
        {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "A port value is one key naming its case"))
        }

        switch key
        {
        case .Bool: self = .Bool(try container.decode(Swift.Bool.self, forKey: key))
        case .Int: self = .Int(try container.decode(Swift.Int.self, forKey: key))
        case .Float: self = .Float(try container.decode(Swift.Float.self, forKey: key))
        case .String: self = .String(try container.decode(Swift.String.self, forKey: key))
        case .Vector2: self = .Vector2(try container.decode(simd_float2.self, forKey: key))
        case .Vector3: self = .Vector3(try container.decode(simd_float3.self, forKey: key))
        case .Vector4: self = .Vector4(try container.decode(simd_float4.self, forKey: key))
        case .Quaternion: self = .Quaternion(simd_quatf(vector: try container.decode(simd_float4.self, forKey: key)))
        case .Transform:
            let columns = try container.decode([simd_float4].self, forKey: key)
            guard columns.count == 4 else
            {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "A Transform is four columns")
            }
            self = .Transform(simd_float4x4(columns: (columns[0], columns[1], columns[2], columns[3])))
        case .Array: self = .Array(ContiguousArray(try container.decode([PortValue].self, forKey: key)))
        case .Dictionary: self = .Dictionary(try container.decode([Swift.String: PortValue].self, forKey: key))
        }
    }

    public func encode(to encoder: any Encoder) throws
    {
        var container = encoder.container(keyedBy: CaseKey.self)

        switch self
        {
        case .Bool(let value): try container.encode(value, forKey: .Bool)
        case .Int(let value): try container.encode(value, forKey: .Int)
        case .Float(let value): try container.encode(value, forKey: .Float)
        case .String(let value): try container.encode(value, forKey: .String)
        case .Vector2(let value): try container.encode(value, forKey: .Vector2)
        case .Vector3(let value): try container.encode(value, forKey: .Vector3)
        case .Vector4(let value): try container.encode(value, forKey: .Vector4)
        case .Quaternion(let value): try container.encode(value.vector, forKey: .Quaternion)
        case .Transform(let value): try container.encode([value.columns.0, value.columns.1, value.columns.2, value.columns.3], forKey: .Transform)
        case .Array(let values): try container.encode(Swift.Array(values), forKey: .Array)
        case .Dictionary(let values): try container.encode(values, forKey: .Dictionary)
        case .Geometry, .Material, .Image:
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                                                         debugDescription: "A runtime object has no document form"))
        }
    }
}

extension PortValue
{
    /// Whether the value can be written to a document: no runtime object in it.
    var hasDocumentForm: Bool
    {
        switch self
        {
        case .Geometry, .Material, .Image: return false
        case .Array(let values): return values.allSatisfy(\.hasDocumentForm)
        case .Dictionary(let values): return values.values.allSatisfy(\.hasDocumentForm)
        default: return true
        }
    }
}

/// An own key is its string; a proxy key is the inner node's id then the
/// inner key, `["<node>", "inputNumber1"]`, which nests for a proxy of a proxy.
extension PortKey: Codable
{
    public init(from decoder: any Decoder) throws
    {
        if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self)
        {
            self = .own(name)
            return
        }

        var container = try decoder.unkeyedContainer()
        let node = try container.decode(UUID.self)
        let inner = try container.decode(PortKey.self)
        self = .proxy(node: node, inner: inner)
    }

    public func encode(to encoder: any Encoder) throws
    {
        switch self
        {
        case .own(let name):
            var container = encoder.singleValueContainer()
            try container.encode(name)
        case .proxy(let node, let inner):
            var container = encoder.unkeyedContainer()
            try container.encode(node)
            try container.encode(inner)
        }
    }
}

/// `["<node>", <key>]`.
extension PortAddress: Codable
{
    public init(from decoder: any Decoder) throws
    {
        var container = try decoder.unkeyedContainer()
        self.init(node: try container.decode(UUID.self), key: try container.decode(PortKey.self))
    }

    public func encode(to encoder: any Encoder) throws
    {
        var container = encoder.unkeyedContainer()
        try container.encode(node)
        try container.encode(key)
    }
}


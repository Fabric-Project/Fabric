//
//  simd+hashable.swift
//  Fabric
//
//  Created by Anton Marini on 5/5/25.
//

import Foundation
import simd

extension float2x2 : @retroactive Hashable
{
    public func hash(into hasher: inout Hasher) {
        hasher.combine(columns.0.hashValue ^ columns.1.hashValue)
    }
}

extension float3x3 : @retroactive Hashable
{
    public func hash(into hasher: inout Hasher) {
        hasher.combine(columns.0.hashValue ^ columns.1.hashValue ^ columns.2.hashValue)
    }

}

extension float4x4 : @retroactive Hashable
{
    public func hash(into hasher: inout Hasher) {
        hasher.combine(columns.0.hashValue ^ columns.1.hashValue ^ columns.2.hashValue ^ columns.3.hashValue)
    }
}

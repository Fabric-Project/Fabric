//
//  MTLTexture+Equatable.swift
//  Fabric
//
//  Created by Anton Marini on 5/5/25.
//
import Metal


public struct EquatableTexture: Equatable
{
    public let texture: MTLTexture

    public static func == (lhs: EquatableTexture, rhs: EquatableTexture) -> Bool {
        return lhs.texture === rhs.texture // reference identity
    }
}

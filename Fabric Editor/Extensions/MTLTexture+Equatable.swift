//
//  MTLTexture+Equatable.swift
//  Fabric
//
//  Created by Anton Marini on 5/5/25.
//
import Metal


struct EquatableTexture: Equatable
{
    let texture: MTLTexture

    static func == (lhs: EquatableTexture, rhs: EquatableTexture) -> Bool {
        return lhs.texture === rhs.texture // reference identity
    }
}

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
    public var isFlipped:Bool = false
    
    // TODO: Until we get a texture pool where we vend texture for effects
    // this should be true?
    // https://github.com/Fabric-Project/Fabric/issues/34

    public var force: Bool = false

    public static func == (lhs: EquatableTexture, rhs: EquatableTexture) -> Bool {
//        return false
        return lhs.texture === rhs.texture
        && (lhs.force || rhs.force) // reference identity
    }
}

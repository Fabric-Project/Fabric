//
//  MTLTexture+Equatable.swift
//  Fabric
//
//  Created by Anton Marini on 5/5/25.
//
import Metal

//
//public struct FabricImage: Equatable, Identifiable
//{
//    public let id = UUID()
//    public let texture: MTLTexture
//    public var isFlipped:Bool = false
//    
//    // TODO: Until we get a texture pool where we vend texture for effects
//    // this should be true?
//    // https://github.com/Fabric-Project/Fabric/issues/34
//
//    public var force: Bool = false
//
//    public static func == (lhs: FabricImage, rhs: FabricImage) -> Bool {
////        return false
//        return lhs.texture === rhs.texture && lhs.id == rhs.id
//        && (lhs.force || rhs.force) // reference identity
//    }
//}

import Metal

public final class FabricImage: Identifiable, Equatable
{
    public let id = UUID()
    public let texture: MTLTexture
    public var isFlipped: Bool = false

    // MARK: - Managed/unmanaged
    private var commandBuffer:MTLCommandBuffer?
    private var onRelease: ((MTLTexture, MTLCommandBuffer) -> Void)?
    private var didRelease = false

    // Factory-only
    private init(texture: MTLTexture, commandBuffer:MTLCommandBuffer?, onRelease: ((MTLTexture, MTLCommandBuffer) -> Void)?)
    {
        self.texture = texture
        self.commandBuffer = commandBuffer
        self.onRelease = onRelease
    }

    /// Created by GraphRenderer (or other pool owner). Returned to pool on `release()` / `deinit`.
    internal static func managed(texture: MTLTexture,commandBuffer:MTLCommandBuffer, onRelease: @escaping (MTLTexture, MTLCommandBuffer) -> Void) -> FabricImage
    {
        FabricImage(texture: texture, commandBuffer: commandBuffer, onRelease: onRelease)
    }

    /// Asset / external ownership. No pooling.
    public static func unmanaged(texture: MTLTexture) -> FabricImage
    {
        FabricImage(texture: texture, commandBuffer: nil, onRelease: nil)
    }

    deinit
    {
        release()
    }

    /// Optional explicit release for deterministic reuse (recommended in hot paths).
    public func release()
    {
        guard !didRelease else { return }
        didRelease = true
        // Should not happen?
        if let commandBuffer
        {
            onRelease?(texture, commandBuffer)
        }
        onRelease = nil
        commandBuffer = nil
    }

    // MARK: - Equatable

    public static func == (lhs: FabricImage, rhs: FabricImage) -> Bool
    {
//        return lhs === rhs

        // 2) OR if you want texture identity:
        return lhs.texture === rhs.texture && lhs.id == rhs.id
    }
}

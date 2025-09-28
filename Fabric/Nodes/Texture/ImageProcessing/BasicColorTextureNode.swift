
//
//  BaseTextureComputeNode.swift
//  Fabric
//
//  Created by Anton Marini on 6/28/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

class BrightnessContrastImageNode : BaseEffectNode
{
    override class var name:String { "Brightness Contrast" }
    override class var sourceShaderName: String { "BrightnessContrastImageNode" }
}

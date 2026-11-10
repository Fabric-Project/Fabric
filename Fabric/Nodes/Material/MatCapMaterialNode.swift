//
//  MatCapMaterialNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

/// Shades a surface from a matcap: an image of a lit sphere, read by the direction each point of the
/// surface faces the camera. Lighting, reflections and color all come from the image, so it needs
/// no lights.
public class MatCapMaterialNode : BasicTextureMaterialNode
{
    public override class var name:String {  "MatCap Material" }
    override public class var nodeDescription: String { "Shades a surface from a matcap image, a lit sphere, by the direction each point faces the camera. Needs no lights." }

    public override var material: MatCapMaterial {
        return _material
    }

    private lazy var _material = MatCapMaterial(context: self.context)
}

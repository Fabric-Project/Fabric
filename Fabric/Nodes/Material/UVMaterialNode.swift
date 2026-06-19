//
//  UVMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 11/17/25.
//

import Foundation
import Satin
import simd
import Metal

public class UVMaterialNode : BaseMaterialNode
{
    public override class var name:String {  "UV Material" }
    override public class var nodeDescription: String { "Provides visualization of underlying geometry UV coordinates."}

    public override var material: UVColorMaterial {
        return _material
    }
    
    private var _material = UVColorMaterial()
}

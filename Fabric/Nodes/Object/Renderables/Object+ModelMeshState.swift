//
//  Object+ModelMeshState.swift
//  Fabric
//
//  Created by Toby Harris on 10/13/26.
//

import Satin
import Metal

extension Object
{
    /// Sets every mesh under a loaded model to Model Mesh's or Instanced Model
    /// Mesh's Enable Shadows, Culling Mode and Double Sided.
    func setModelMeshState(castsShadow: Bool, cullMode: MTLCullMode, doubleSided: Bool)
    {
        for case let mesh as Mesh in self.getChildren(true)
        {
            mesh.material?.lighting = true
            mesh.castShadow = castsShadow
            mesh.receiveShadow = castsShadow
            mesh.cullMode = cullMode
            mesh.doubleSided = doubleSided
        }
    }
}

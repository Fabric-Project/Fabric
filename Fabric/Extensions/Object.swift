//
//  Object.swift
//  Fabric
//
//  Created by Anton Marini on 10/15/25.
//

import Foundation
import Satin
import simd

public extension Object {
    /// Flattens an object hierarchy so that only meshes remain as direct
    /// children of a new top-level container, with transforms baked in.
    ///
    /// - Parameter object: The root of the hierarchy to flatten.
    /// - Returns: A new `Object` whose direct children are the meshes from the
    ///   original hierarchy, each with `localMatrix` set to its original world transform.
    static func flatten(_ object: Object) -> Object {
        // New top-level container; reuse source label and context
        let flatRoot = Object(label: object.label)
        flatRoot.context = object.context

        // Collect meshes first (avoid mutating while traversing)
        var meshes: [Mesh] = []
        object.apply(recursive: true) { obj in
            if let mesh = obj as? Mesh {
                meshes.append(mesh)
            }
        }

        // Reparent each mesh and bake its world transform into its local transform
        for mesh in meshes {
            let originalWorld = mesh.worldMatrix
            mesh.removeFromParent()            // detach from original hierarchy
            flatRoot.add(mesh)                 // re-parent under flat root
            mesh.localMatrix = originalWorld   // bake world -> local (flatRoot is identity)
        }

        return flatRoot
    }
}


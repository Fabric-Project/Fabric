//
//  Color+Node.swift
//  Fabric
//
//  Node color extensions for SwiftUI Color
//

import SwiftUI

extension Color {
    /// Color for texture/image nodes
    public static var nodeTexture: Color {
        Color("NodeTextureColor", bundle: Bundle.module)
    }

    /// Color for geometry nodes
    public static var nodeGeometry: Color {
        Color("NodeGeometryColor", bundle: Bundle.module)
    }

    /// Color for camera nodes
    public static var nodeCamera: Color {
        Color("NodeCameraColor", bundle: Bundle.module)
    }

    /// Color for material nodes
    public static var nodeMaterial: Color {
        Color("NodeMaterialColor", bundle: Bundle.module)
    }

    /// Color for mesh nodes
    public static var nodeMesh: Color {
        Color("NodeMeshColor", bundle: Bundle.module)
    }

    /// Color for render nodes
    public static var nodeRender: Color {
        Color("NodeRenderColor", bundle: Bundle.module)
    }

    /// Color for shader nodes
    public static var nodeShader: Color {
        Color("NodeShaderColor", bundle: Bundle.module)
    }

    /// Color for object nodes
    public static var nodeObject: Color {
        Color("NodeObjectColor", bundle: Bundle.module)
    }
}

//
//  NodeType.swift
//  Fabric
//
//  Created by Anton Marini on 6/21/25.
//

import Foundation
import SwiftUI

extension Node
{
    // Only really used in the UI
    public enum NodeTypeGroups: String, CaseIterable
    {
        case All
        case SceneGraph // Renderer, Object, Camera, Light, Mesh
        case Mesh
        case Image // Texture / Shader
        case Parameter
            
        func nodeTypes() -> [Node.NodeType]
        {
            switch self
            {
            case .All: return Node.NodeType.allCases
            case .SceneGraph: return [.Renderer, .Object, .Camera, .Light]
            case .Mesh: return [.Mesh, .Geometery, .Material]
            case .Image: return Node.NodeType.ImageType.nodeTypes() + [.Shader]
            case .Parameter: return Node.NodeType.ParameterType.nodeTypes()
            }
        }
        
        func imageName() -> String
        {
            switch self
            {
            case .All: return "circle.dotted.circle"
            case .SceneGraph: return "scale.3d"
            case .Mesh: return "cube.transparent"
            case .Image: return "camera.filters"
            case .Parameter: return "beziercurve"
            }
        }
        
        func image() -> Image
        {
            return SwiftUI.Image(systemName: imageName())
        }
    }
    
    public enum NodeType : CustomStringConvertible, CaseIterable, Equatable, Hashable
    {
        public enum ParameterType : String, CaseIterable, Equatable, Hashable
        {
            case Boolean
            case Number
            case Vector
            case Quaternion
            case Matrix
            case Color
            case String
            case Array
            
            static func nodeTypes() -> [Node.NodeType] {
                return Self.allCases.map{ Node.NodeType.Parameter(parameterType:$0) }
            }
        }
        
        // Inspired by CIFilter Categories, but uh, different!
        public enum ImageType : String, CaseIterable, Equatable, Hashable
        {
            case BaseEffect
            case Loader
            case Generator
            case ColorAdjust
            case ColorEffect
            case Lens
            case Composite
            case Mix
            case Mixers
            case Mask
            case Tile
            case Blur
            case Descimate
            case Distort
            case Geometry
            case Morphology
            
            static func nodeTypes() -> [Node.NodeType] {
                return Self.allCases.map{ Node.NodeType.Image(imageType:$0) }
            }
        }
        
        case Subgraph // A graph with exposed published ports
        case Renderer // Renders a scene graph
        case Object // Scene graph, owns transforms
        case Camera // Scene graph object
        case Light // Scene graph object
        case Mesh // Scene graph object
        case Geometery
        case Material
        case Shader
        case Image(imageType:ImageType)
        case Parameter(parameterType:ParameterType)
        
        public static var allCases: [Node.NodeType] { return [.Renderer, .Subgraph, .Object, .Camera, .Light, .Mesh, .Geometery, .Material, .Shader,  ] + ImageType.nodeTypes() + ParameterType.nodeTypes() }
        
        public var description: String
        {
            switch self
            {
            case .Subgraph: return "Subgraph"
            case .Renderer: return "Renderer"
            case .Object: return "Object"
            case .Camera: return "Camera"
            case .Light: return "Light"
            case .Mesh: return "Mesh"
            case .Geometery: return "Geometery"
            case .Material: return "Material"
            case .Shader: return "Shader"
            case .Image(imageType: let imageType): return "Image \(imageType.rawValue.titleCase)"
            case .Parameter(let paramType): return "\(paramType.rawValue) Parameter"
            }
        }
        
        public func color() -> Color
        {
//            return [Color.red, .blue, .green, .yellow, .orange, .pink, .purple, .gray].randomElement( ) ?? .gray
            
            switch self
            {
            case .Image:
                return Color.nodeTexture

            case .Geometery:
                return Color.nodeGeometry

            case .Camera:
                return Color.nodeCamera
                
            case .Light:
                return Color.nodeObject

            case .Material:
                return Color.nodeMaterial

            case .Mesh:
                return Color.nodeMesh
                
            case .Renderer:
                return Color.nodeRender

            case .Subgraph:
                return Color.nodeRender
                
            case .Shader:
                return Color.nodeShader
                
            case .Object:
                return Color.nodeObject
                
            case .Parameter(_):
                return Color(hue: 0, saturation: 0, brightness: 0.3)
            }
        }
        
        public func backgroundColor() -> Color
        {
            return self.color().opacity(0.6)
        }
    }
}

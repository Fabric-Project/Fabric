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
        case Utility
            
        func nodeTypes() -> [Node.NodeType]
        {
            switch self
            {
            case .All: return Node.NodeType.allCases
            case .SceneGraph: return Node.NodeType.ObjectType.nodeTypes() + [.Subgraph]
            case .Mesh: return [.Geometery, .Material]
            case .Image: return Node.NodeType.ImageType.nodeTypes() + [.Shader]
            case .Parameter: return Node.NodeType.ParameterType.nodeTypes()
            case .Utility: return [Node.NodeType.Utility]
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
            case .Utility: return "gear"
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
            case Tile
            case Blur
            case Descimate
            case Distort
            case Geometry
            case Morphology
            case Mask
            case Analysis

            static func nodeTypes() -> [Node.NodeType] {
                return Self.allCases.map{ Node.NodeType.Image(imageType:$0) }
            }
        }
        
        // Anything renderable in a Satin scene graph
        public enum ObjectType:String, CaseIterable, Equatable, Hashable
        {
            case Camera
            case Light
            case Mesh // Renderable ?
            case Loader
//            case Scene
            static func nodeTypes() -> [Node.NodeType] {
                return Self.allCases.map{ Node.NodeType.Object(objectType:$0) }
            }
        }
        
        case Renderer // Renders a scene graph
        case Subgraph
        case Object(objectType:ObjectType) // Scene graph, owns transforms
        case Geometery
        case Material
        case Shader
        case Image(imageType:ImageType)
        case Parameter(parameterType:ParameterType)
        case Utility
        
        public static var allCases: [Node.NodeType] { return
            [.Renderer ]
            + ObjectType.nodeTypes()
            + [ .Geometery, .Material, .Shader, ]
            + ImageType.nodeTypes()
            + ParameterType.nodeTypes()
            + [ .Utility ]
        }
        
        public var description: String
        {
            switch self
            {
            case .Subgraph: return "Sub Graph"
            case .Renderer: return "Renderer"
            case .Object(let objectType): return objectType.rawValue
            case .Geometery: return "Geometery"
            case .Material: return "Material"
            case .Shader: return "Shader"
            case .Image(imageType: let imageType): return "Image \(imageType.rawValue.titleCase)"
            case .Parameter(let paramType): return "\(paramType.rawValue) Parameter"
            case .Utility: return "Utility"
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

            case .Object(let objectType):
                
                    switch objectType
                    {
                    case .Camera:
                        return Color.nodeCamera
                        
                    case .Light:
                        return Color.nodeObject
                        
                    case .Mesh:
                        return Color.nodeMesh
                        
                    case .Loader:
                        return Color.nodeMesh
//
//                    case .Scene:
//                        return Color.nodeObject
                    }
                
            
            case .Material:
                return Color.nodeMaterial

            case .Subgraph:
                return Color.nodeRender
           
            case .Renderer:
                return Color.nodeRender

            case .Shader:
                return Color.nodeShader
                                
            case .Parameter(_):
                return Color(hue: 0, saturation: 0, brightness: 0.3)
        
            case .Utility:
                return Color(hue: 0, saturation: 0, brightness: 0.3)
            }
            
        }
        
        public func backgroundColor() -> Color
        {
            return self.color().opacity(0.6)
        }
    }
}

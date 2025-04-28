//
//  NodeProtocol.swift
//  v
//
//  Created by Anton Marini on 4/27/24.
//

import SwiftUI
import Metal
import Satin

protocol NodeDelegate : AnyObject
{
    func willUpdate(node:Node)
    func didUpdate(node:Node)
    func shouldDelete(node:Node)
}

protocol NodeProtocol
{
    init(context:Context)
    
    static var name:String { get }
    static var nodeType:Node.NodeType { get }
    var nodeType:Node.NodeType { get }

    var ports: [any AnyPort] { get }
    func evaluate(atTime:TimeInterval,
                  renderPassDescriptor: MTLRenderPassDescriptor,
                  commandBuffer: MTLCommandBuffer)
    
//    func update()
    func resize(size: (width: Float, height: Float), scaleFactor: Float)
    

}

@Observable class Node: Equatable, Identifiable, Hashable
{
    enum NodeType : String, CaseIterable
    {
        case Texture // Rendered output of a Renderer
        case Renderer // Renders a scene graph
        case Object // Scene graph, owns transforms
        case Camera // Scene graph object
        case Light // Scene graph object
        case Mesh // Scene graph object
        case Geometery
        case Material
        case Shader
        
        case Parameter
        
        func color() -> Color
        {
            switch self
            {
            case .Texture:
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

            case .Shader:
                return Color.nodeShader
                
            case .Object:
                return Color.nodeObject
                
            case .Parameter:
                return Color(hue: 0, saturation: 0, brightness: 0.3)
            }
        }
        
        func backgroundColor() -> Color
        {
            return self.color().opacity(0.6)
        }
    }
    
    
    let id = UUID()
    var ports:[any AnyPort] { [ ] }
    
    var nodeSize:CGSize = CGSizeMake(150, 100)

    @ObservationIgnored var context:Context
    
    @ObservationIgnored weak var delegate:(any NodeDelegate)? = nil

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
    }
    
    var isSelected:Bool = false
    var isDragging:Bool = false
    var showParams:Bool = false
    //    var parameterGroup:ParameterGroup

    public var nodeType:NodeType {
        let myType = type(of: self) as! (any NodeProtocol.Type)
        return  myType.nodeType
    }
    
    var name : String {
        let myType = type(of: self) as! (any NodeProtocol.Type)
        return  myType.name
    }
    
    var offset: CGSize = .zero
    {
        willSet
        {
            if let delegate = self.delegate
            {
                delegate.willUpdate(node: self)
            }
        }
        
        didSet
        {
            if let delegate = self.delegate
            {
                delegate.didUpdate(node: self)
            }
        }
    }
    
    
    required init (context:Context)
    {
        self.context = context
       
        
        for var port in self.ports
        {
            port.node = self
        }
        
        self.nodeSize = self.computeNodeSize()
        
        
    }
    
    
    
    deinit
    {
        print("Deleted node \(id)")
    }
    
    public static func == (lhs: Node, rhs: Node) -> Bool
    {
        return lhs.id == rhs.id
    }
             
    public func evaluate(atTime:TimeInterval,
                         renderPassDescriptor: MTLRenderPassDescriptor,
                         commandBuffer: MTLCommandBuffer)
    {
     
    }
    
    public func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        
    }
   
    private func computeNodeSize() -> CGSize
    {
        let horizontalInputsCount = self.ports.filter { $0.direction == .Horizontal && $0.kind != .Inlet  }.count
        let horizontalOutputsCount = self.ports.filter { $0.direction == .Horizontal && $0.kind != .Outlet  }.count

        let verticalInputsCount = self.ports.filter { $0.direction == .Vertical && $0.kind != .Inlet  }.count
        let verticalOutputsCount = self.ports.filter { $0.direction == .Vertical && $0.kind != .Outlet  }.count

        let horizontalMax = max(horizontalInputsCount, horizontalOutputsCount)
        let verticalMax = max(verticalInputsCount, verticalOutputsCount)
        
        let height:CGFloat = 20 + (CGFloat(horizontalMax) * 25)
        let width:CGFloat = 20 + (CGFloat(verticalMax) * 25)
        
        return CGSize(width: max(width, 150), height: max(height, 60) )
    }
}

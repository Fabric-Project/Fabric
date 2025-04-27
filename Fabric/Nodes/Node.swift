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
    static var type:Node.NodeType { get }
    
    var ports: [any AnyPort] { get }
    func evaluate(atTime:TimeInterval,
                  renderPassDescriptor: MTLRenderPassDescriptor,
                  commandBuffer: MTLCommandBuffer)
    
//    func update()
    func resize(size: (width: Float, height: Float), scaleFactor: Float)
    

}

@Observable class Node: Equatable, Identifiable, Hashable
{
    enum NodeType : CaseIterable
    {
        case Texture // Rendered output of a Renderer
        case Renderer // Renders a scene graph
        case Object // Scene graph, owns transforms
        case Camera // Scene graph object
        case Mesh // Scene graph object
        case Geometery
        case Material
        case Shader
        
        
        case Parameter
    }
    
    
    static let nodeSize = CGSizeMake(150, 100)
    
    let id = UUID()
    let type:NodeType
    let name:String
    var ports:[any AnyPort] { [ ] }
    
    @ObservationIgnored var context:Context
    
    @ObservationIgnored weak var delegate:(any NodeDelegate)? = nil

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
    }
    
    var isSelected:Bool = false
    var isDragging:Bool = false
    var showParams:Bool = false
    var parameterGroup:ParameterGroup
    
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
    
    init (context:Context,
          type: NodeType,
          name:String,
          parameterGroup:ParameterGroup = ParameterGroup() )
    {
        self.context = context
        self.type = type
        self.name = name
        self.parameterGroup = parameterGroup
        
        for var port in self.ports
        {
            port.node = self
        }
        
//        self.cacheInletPoints()
//        self.cacheOutletPoints()
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
   
    
//    // MARK: - Node Drawing
//    
//    private func cacheInletPoints()
//    {
//        let rangeOfInputs = 0 ..< self.numberOfInputs
//        let indexOfLastInput = self.numberOfInputs - 1
//        
//        let halfWidth:Double = Self.nodeSize.width/2.0
//        
//        self.localInletPositions = rangeOfInputs.map( {
//            
//            var x = remap(input: Double($0),
//                          inMin: 0,
//                          inMax: Double(indexOfLastInput),
//                          outMin: halfWidth - Double(indexOfLastInput * 15),
//                          outMax: halfWidth + Double(indexOfLastInput * 15) )
//            
//            x = x.isNaN ? halfWidth : x
//            
//            return CGPoint(x:x , y: 0.0)
//        } )
//        
//    }
//    
//    private func cacheOutletPoints()
//    {
//        let rangeOfOutputs = 0 ..< self.numberOfOutputs
//        let indexOfLastOutput = self.numberOfOutputs - 1
//        
//        let halfWidth:Double = Self.nodeSize.width/2.0
//
//        self.localOutletPositions = rangeOfOutputs.map( {
//            
//            var x = remap(input: Double($0),
//                          inMin: 0,
//                          inMax: Double(indexOfLastOutput),
//                          outMin: halfWidth - Double(indexOfLastOutput * 15) ,
//                          outMax: halfWidth + Double(indexOfLastOutput * 15) )
//            
//            x = x.isNaN ? halfWidth : x
//            
//            return CGPoint(x:x , y: Self.nodeSize.height)
//        } )
//        
//    }
}

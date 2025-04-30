//
//  BoxGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/25/25.
//
import Satin
import Foundation
import simd
import Metal

class BoxGeometryNode : Node, NodeProtocol
{    
    static let name = "Box Geometry"
    static var nodeType = Node.NodeType.Geometery

    // Ports
    let inputWidth = NodePort<Float>(name: "Width", kind: .Inlet)
    let inputHeight = NodePort<Float>(name: "Height", kind: .Inlet)
    let inputDepth = NodePort<Float>(name: "Depth", kind: .Inlet)
    let inputResolution = NodePort<simd_int3>(name: "Resolution", kind: .Inlet)
    
    let outputGeometry = NodePort<Geometry>(name: BoxGeometryNode.name, kind: .Outlet)

    private let geometry = BoxGeometry(width: 1, height: 1, depth: 1)
    
    override var ports:[any AnyPort] { [inputWidth,
                               inputHeight,
                               inputDepth,
                               inputResolution,
                               outputGeometry] }
    
  
    
    override func evaluate(atTime:TimeInterval,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if let width = self.inputWidth.value
        {
            self.geometry.width = width
        }
        
        if let height = self.inputHeight.value
        {
            self.geometry.height = height
        }
        
        if let depth = self.inputDepth.value
        {
            self.geometry.depth = depth
        }
        
        if let resolution = self.inputResolution.value
        {
            self.geometry.resolution = resolution
        }
                
        self.outputGeometry.send(self.geometry)
     }
}

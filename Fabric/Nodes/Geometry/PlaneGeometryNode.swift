//
//  PlaneGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Satin
import Foundation
import simd
import Metal

class PlaneGeometryNode : Node, NodeProtocol
{
    static let name = "Plane Geometry"
    static var type = Node.NodeType.Geometery

    // Ports
    let inputWidth = NodePort<Float>(name: "Width", kind: .Inlet)
    let inputHeight = NodePort<Float>(name: "Height", kind: .Inlet)
    let inputResolution = NodePort<simd_int2>(name: "Resolution", kind: .Inlet)
    
    let outputGeometry = NodePort<Geometry>(name: PlaneGeometryNode.name, kind: .Outlet)

    private let geometry = PlaneGeometry(width: 1, height: 1)
    
    override var ports:[any AnyPort] { [inputWidth,
                               inputHeight,
                               inputResolution,
                               outputGeometry] }

    required init(context:Context)
    {
        super.init(context: context, type: .Geometery, name: PlaneGeometryNode.name)
    }
    
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
               
        if let resolution = self.inputResolution.value
        {
            self.geometry.resolution = resolution
        }
                
        self.outputGeometry.send(self.geometry)
     }
}

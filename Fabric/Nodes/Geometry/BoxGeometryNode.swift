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

    // Params

    let inputWidthParam = GenericParameter<Float>("Width", 1.0, .inputfield)
    let inputHeightParam = GenericParameter<Float>("Height", 1.0, .inputfield)
    let inputDepthParam = GenericParameter<Float>("Depth", 1.0, .inputfield)
    let inputResolutionParam = GenericParameter<simd_int3>("Resolution", simd_int3(repeating: 5), .inputfield)

    
    let outputGeometry = NodePort<Geometry>(name: BoxGeometryNode.name, kind: .Outlet)

    private let geometry = BoxGeometry(width: 1, height: 1, depth: 1)
    
    override var inputParameters: [any Parameter] { [inputWidthParam, inputHeightParam, inputDepthParam, inputResolutionParam] }
    override var ports:[any AnyPort] { super.ports + [outputGeometry] }
    
    
    override func evaluate(atTime:TimeInterval,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        self.geometry.width = self.inputWidthParam.value
        
        self.geometry.height =  self.inputHeightParam.value
        
        self.geometry.depth = self.inputDepthParam.value
        
        self.geometry.resolution =  self.inputResolutionParam.value
                
        self.outputGeometry.send(self.geometry)
     }
}

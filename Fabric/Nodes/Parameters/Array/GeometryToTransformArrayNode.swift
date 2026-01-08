//
//  ArrayCountNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//


import Foundation
import Satin
import simd
import Metal
import MetalKit

public class GeometryToTransformArrayNode : Node
{
    public override class var name:String { "Geometry To Array of Transforms" }
    public override class var nodeType:Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Convert Geometry Vertices an array of Translation Transforms"}

    // TODO: add character set menu to choose component separation strategy
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort", NodePort<SatinGeometry>(name: "Geometry", kind: .Inlet)),
            ("inputTransform", NodePort<simd_float4x4>(name: "Transform", kind: .Inlet)),
            ("outputPort", NodePort<ContiguousArray<simd_float4x4>>(name: "Array of Transforms", kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<SatinGeometry> { port(named: "inputPort") }
    public var inputTransform:NodePort<simd_float4x4> { port(named: "inputTransform") }
    public var outputPort:NodePort<ContiguousArray<simd_float4x4>> { port(named: "outputPort") }
 
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        // So this is subtle and annoying
        // Because the POINTER value of our Geom hasnt changed, but the buffer may have
        // We really do need to re-calc every frame.
        
        // Ideally theres some mechanism to account for this? 
        
//        if self.inputPort.valueDidChange
//        {
            if let geometry = self.inputPort.value
            {
//                let stride = MemoryLayout<SatinVertex>.stride
                var output = ContiguousArray<simd_float4x4>()
                let inputTransform = self.inputTransform.value ?? matrix_identity_float4x4

                if geometry.geometryData.vertexCount > 0
                {
                    output.reserveCapacity( Int(geometry.geometryData.vertexCount) ) 
                    
                    for i in 0 ..< Int(geometry.geometryData.vertexCount)
                    {
                        let vertex = geometry.geometryData.vertexData.advanced(by: i )
                        
                        output.append( simd_mul( translationMatrix3f(vertex.pointee.position), inputTransform) )
                    }
                }

                self.outputPort.send(output)
            }
            
            else
            {
                self.outputPort.send( nil )
            }
//        }
    }
}

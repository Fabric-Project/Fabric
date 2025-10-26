//
//  EnvironmentNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/14/25.
//

import Foundation
import Satin
import simd
import Metal

public class EnvironmentNode: SubgraphNode
{
    override public class var name:String { "Environment Node" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Subgraph }
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputEnvironmentTexture", NodePort<EquatableTexture>(name: "Environment Texture", kind: .Inlet)),
            ("inputEnvironmentIntensity", ParameterPort(parameter: FloatParameter("Environment Intensity", 1.0, 0.0, 1.0, .slider))),
//            ("inputBlur", ParameterPort(parameter: FloatParameter("Blur", 0.0, 0.0, 5.0, .slider))),
        ]
    }
    
    // Port Proxy
    public var inputEnvironmentTexture:NodePort<EquatableTexture> { port(named: "inputEnvironmentTexture") }
    public var inputEnvironmentIntensity:ParameterPort<Float> { port(named: "inputEnvironmentIntensity") }
//    public var inputBlur:ParameterPort<Float> { port(named: "inputBlur") }
    
    
    public required init(context: Context)
    {
        super.init(context: context)
        
        self.subGraph.scene = IBLScene()
    }
    
    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        
        self.subGraph.scene = IBLScene()
    }
    
    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: any MTLCommandBuffer)
    {
        if self.inputEnvironmentTexture.valueDidChange,
           let environmentTexture = self.inputEnvironmentTexture.value,
           let iblScene = self.subGraph.scene as? IBLScene
        {
            iblScene.setEnvironment(texture: environmentTexture.texture, cubemapSize: 2048, reflectionSize:2048, irradianceSize: 32)
        }
        
        if self.inputEnvironmentIntensity.valueDidChange,
           let iblScene = self.subGraph.scene as? IBLScene,
           let inputEnvironmentIntensity = self.inputEnvironmentIntensity.value
        {
            iblScene.environmentIntensity = inputEnvironmentIntensity
        }
        
//        if self.inputBlur.valueDidChange,
//           let iblScene = self.subGraph.scene as? IBLScene,
//           let inputBlur = self.inputBlur.value
//        {
//            iblScene.cubemapGenerator?.blur = inputEnvironmentIntensity
//        }
        
        super.execute(context: context, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }
}

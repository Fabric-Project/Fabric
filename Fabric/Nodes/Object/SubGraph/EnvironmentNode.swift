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
    override public class var nodeDescription: String { "Subgraph that provides an environment for 3D rendering" }
    
    // Ports
    public let inputEnvironmentTexture = NodePort<FabricImage>(name: "Environment Texture", kind: .Inlet, description: "HDR environment map for image-based lighting")
    public let inputEnvironmentIntensity = ParameterPort(parameter: FloatParameter("Environment Intensity", 1.0, 0.0, 1.0, .slider, "Brightness multiplier for the environment lighting"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputEnvironmentTexture", port: self.inputEnvironmentTexture),
            PortDeclaration(key: "inputEnvironmentIntensity", port: self.inputEnvironmentIntensity),
        ]
    }

//    public var inputBlur:ParameterPort<Float> { port(named: "inputBlur") }
    
    
    public required init(context: Context)
    {
        super.init(context: context)
        
        self.subGraph.scene = IBLScene(context: context)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        guard let context = decoder.context?.documentContext as? Context else {
            fatalError("Failed to decode Context from decoder")
        }
        
        try super.init(from: decoder)
        
        self.subGraph.scene = IBLScene(context: context)
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        if self.inputEnvironmentTexture.valueDidChange,
           let environmentTexture = self.inputEnvironmentTexture.value,
           let iblScene = self.subGraph.scene as? IBLScene
        {
            iblScene.setEnvironment(texture: environmentTexture.texture, cubemapSize: 2048, reflectionSize:2048, irradianceSize: 32) { result in
                if case let .failure(error) = result {
                    print("Environment lighting failed: \(error)")
                }
            }
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
        
        // This calls forward for us...
        try super.execute(renderer: renderer, executionInfo: executionInfo, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }
}

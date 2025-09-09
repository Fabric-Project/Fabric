//
//  SceneBuilder.swift
//  Fabric
//
//  Created by Anton Marini on 4/28/25.
//

import Foundation
import Satin
import simd
import Metal

public class SceneBuilderNode : BaseObjectNode, NodeProtocol
{
    public static let name = "Scene Builder"
    public static var nodeType = Node.NodeType.Object

    // Params
    public let inputEnvironmentIntensity: FloatParameter

    public override var inputParameters: [any Parameter] { super.inputParameters + [inputEnvironmentIntensity,] }

    // Ports
    public let inputEnvironment:NodePort<EquatableTexture>
    public let inputObject1:NodePort<Object>
    public let inputObject2:NodePort<Object>
    public let inputObject3:NodePort<Object>
    public let inputObject4:NodePort<Object>
    public let inputObject5:NodePort<Object>
    public let inputObject6:NodePort<Object>
    public let inputObject7:NodePort<Object>
    public let inputObject8:NodePort<Object>
    public let inputObject9:NodePort<Object>
    public let inputObject10:NodePort<Object>
    public let outputScene:NodePort<Object>
    
    public override var ports: [any NodePortProtocol] {  [ inputEnvironment,
                                                           inputObject1,
                                                           inputObject2,
                                                           inputObject3,
                                                           inputObject4,
                                                           inputObject5,
                                                           inputObject6,
                                                           inputObject7,
                                                           inputObject8,
                                                           inputObject9,
                                                           inputObject10,
                                                           outputScene] + super.ports}
    
    private var object = IBLScene()

    public required init(context: Context)
    {
        self.inputEnvironmentIntensity = FloatParameter("Environment Intensity", 1.0, 0.0, 1.0, .slider)
        self.inputEnvironment = NodePort<EquatableTexture>(name: "Environment", kind: .Inlet)
        self.inputObject1 = NodePort<Object>(name: "Input 1", kind: .Inlet)
        self.inputObject2 = NodePort<Object>(name: "Input 2", kind: .Inlet)
        self.inputObject3 = NodePort<Object>(name: "Input 3", kind: .Inlet)
        self.inputObject4 = NodePort<Object>(name: "Input 4", kind: .Inlet)
        self.inputObject5 = NodePort<Object>(name: "Input 5", kind: .Inlet)
        self.inputObject6 = NodePort<Object>(name: "Input 6", kind: .Inlet)
        self.inputObject7 = NodePort<Object>(name: "Input 7", kind: .Inlet)
        self.inputObject8 = NodePort<Object>(name: "Input 8", kind: .Inlet)
        self.inputObject9 = NodePort<Object>(name: "Input 9", kind: .Inlet)
        self.inputObject10 = NodePort<Object>(name: "Input 10", kind: .Inlet)
        self.outputScene = NodePort<Object>(name: SceneBuilderNode.name, kind: .Outlet)
                
        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputEnvironmentIntensityParameter
        case inputEnvironmentParameter
        case inputObject1Parameter
        case inputObject2Parameter
        case inputObject3Parameter
        case inputObject4Parameter
        case inputObject5Parameter
        case inputObject6Parameter
        case inputObject7Parameter
        case inputObject8Parameter
        case inputObject9Parameter
        case inputObject10Parameter
        
        case outputScenePort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputEnvironmentIntensity, forKey: .inputEnvironmentIntensityParameter)
        try container.encode(self.inputEnvironment, forKey: .inputEnvironmentParameter)
        try container.encode(self.inputObject1, forKey: .inputObject1Parameter)
        try container.encode(self.inputObject2, forKey: .inputObject2Parameter)
        try container.encode(self.inputObject3, forKey: .inputObject3Parameter)
        try container.encode(self.inputObject4, forKey: .inputObject4Parameter)
        try container.encode(self.inputObject5, forKey: .inputObject5Parameter)
        try container.encode(self.inputObject6, forKey: .inputObject6Parameter)
        try container.encode(self.inputObject7, forKey: .inputObject7Parameter)
        try container.encode(self.inputObject8, forKey: .inputObject8Parameter)
        try container.encode(self.inputObject9, forKey: .inputObject9Parameter)
        try container.encode(self.inputObject10, forKey: .inputObject10Parameter)
        try container.encode(self.outputScene, forKey: .outputScenePort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputEnvironmentIntensity = try container.decode(FloatParameter.self, forKey: .inputEnvironmentIntensityParameter)

        self.inputEnvironment = try container.decode(NodePort<EquatableTexture>.self, forKey: .inputEnvironmentParameter)

        self.inputObject1 = try container.decode(NodePort<Object>.self, forKey: .inputObject1Parameter)
        self.inputObject2 = try container.decode(NodePort<Object>.self, forKey: .inputObject2Parameter)
        self.inputObject3 = try container.decode(NodePort<Object>.self, forKey: .inputObject3Parameter)
        self.inputObject4 = try container.decode(NodePort<Object>.self, forKey: .inputObject4Parameter)
        self.inputObject5 = try container.decode(NodePort<Object>.self, forKey: .inputObject5Parameter)
        self.inputObject6 = try container.decode(NodePort<Object>.self, forKey: .inputObject6Parameter)
        self.inputObject7 = try container.decode(NodePort<Object>.self, forKey: .inputObject7Parameter)
        self.inputObject8 = try container.decode(NodePort<Object>.self, forKey: .inputObject8Parameter)
        self.inputObject9 = try container.decode(NodePort<Object>.self, forKey: .inputObject9Parameter)
        self.inputObject10 = try container.decode(NodePort<Object>.self, forKey: .inputObject10Parameter)

        self.outputScene = try container.decode(NodePort<Object>.self, forKey: .outputScenePort)
        
        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        var scene:[Object] = []
        if let v = inputEnvironment.value {
            
            if let _ = object.environment
            {
            }
            else
            {
                object.setEnvironment(texture: v.texture, cubemapSize: 2048, reflectionSize:2048, irradianceSize:1024)
            }
        }
        
        self.object.environmentIntensity = self.inputEnvironmentIntensity.value

        if let v = inputObject1.value { scene.append(v) }
        if let v = inputObject2.value { scene.append(v) }
        if let v = inputObject3.value { scene.append(v) }
        if let v = inputObject4.value { scene.append(v) }
        if let v = inputObject5.value { scene.append(v) }
        if let v = inputObject6.value { scene.append(v) }
        if let v = inputObject7.value { scene.append(v) }
        if let v = inputObject8.value { scene.append(v) }
        if let v = inputObject9.value { scene.append(v) }
        if let v = inputObject10.value { scene.append(v) }

        self.object.children = scene
        
        self.evaluate(object: self.object, atTime: context.timing.time)
        
        outputScene.send(self.object)
    }
}

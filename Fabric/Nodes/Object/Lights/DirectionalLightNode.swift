//
//  DirectionalLightNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//


import Foundation
import Satin
import simd
import Metal

class DirectionalLightNode : BaseObjectNode, NodeProtocol
{
    static let name = "Directional Light"
    static var nodeType = Node.NodeType.Light

    public var inputLookAt = GenericParameter<simd_float3>("Look At", simd_float3(repeating:0), .inputfield )
    public var inputColor = GenericParameter<simd_float3>("Color", simd_float3(repeating:1), .inputfield )
    public var inputIntensity = FloatParameter("Intensity", 1.0, 0.0, 10.0, .slider)
    public var inputShadowStrength = FloatParameter("Shadow Strength", 0.5, 0.0, 1.0, .slider)
    public var inputShadowRadius = FloatParameter("Shadow Radius", 2.0, 0.0, 10.0, .slider)
    public var inputShadowBias = FloatParameter("Shadow Bias", 0.005, 0.0, 1.0, .slider)
    
    override var inputParameters: [any Parameter] { super.inputParameters + [inputLookAt, inputColor, inputIntensity, inputShadowStrength, inputShadowRadius, inputShadowBias] }
    
    // Ports
    let outputLight = NodePort<Object>(name: MeshNode.name, kind: .Outlet)
    
    private var light: DirectionalLight =  DirectionalLight(color: [1.0, 1.0, 1.0], intensity: 1.0)
    
    override var ports: [any AnyPort] { super.ports +  [outputLight] }
    
    let lightHelperGeo = BoxGeometry(width: 0.1, height: 0.1, depth: 0.5)
    let lightHelperMat = BasicDiffuseMaterial(hardness: 0.7)

//    lazy var lightHelperMesh0 = Mesh(geometry: lightHelperGeo, material: lightHelperMat)

    required init(context:Context)
    {
        super.init(context: context)
        
        light.castShadow = true
        light.shadow.resolution = (1024, 1024)
        light.shadow.bias = 0.0005
        light.shadow.strength = 0.5
        light.shadow.radius = 2
        light.position.y = 5.0

//        if let shadowCamera = light.shadow.camera as? OrthographicCamera {
//            shadowCamera.update(left: -2, right: 2, bottom: -2, top: 2)
//        }

        light.lookAt(target: .zero, up: Satin.worldUpDirection)
//        light.add(lightHelperMesh0)

    }
    
    required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
    }

    
    
    override func evaluate(atTime:TimeInterval,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        self.light.color = self.inputColor.value
        self.light.intensity = self.inputIntensity.value
        self.light.shadow.strength = self.inputShadowStrength.value
        self.light.shadow.radius = self.inputShadowRadius.value
        self.light.shadow.bias = self.inputShadowBias.value

        self.evaluate(object: self.light, atTime: atTime)
        
        self.light.lookAt(target: self.inputLookAt.value)
        
        self.outputLight.send(light)
    }
}

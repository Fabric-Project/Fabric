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

class DirectionalLightNode : Node, NodeProtocol
{
    static let name = "Directional Light"
    static var nodeType = Node.NodeType.Light

    // Ports
    let inputPosition = NodePort<simd_float3>(name: "Position", kind: .Inlet)
    let inputOrientation = NodePort<simd_quatf>(name: "Orientation", kind: .Inlet)

    let outputLight = NodePort<Object>(name: MeshNode.name, kind: .Outlet)
    
    private var light: DirectionalLight =  DirectionalLight(color: [1.0, 1.0, 1.0], intensity: 1.0)
    
    override var ports: [any AnyPort] { super.ports +  [
                                         inputPosition,
                                         inputOrientation,
                                                        outputLight] }
    
    let lightHelperGeo = BoxGeometry(width: 0.1, height: 0.1, depth: 0.5)
    let lightHelperMat = BasicDiffuseMaterial(hardness: 0.7)

//    lazy var lightHelperMesh0 = Mesh(geometry: lightHelperGeo, material: lightHelperMat)

    required init(context:Context)
    {
        super.init(context: context)
        
        light.castShadow = true
        light.shadow.resolution = (2048, 2048)
        light.shadow.bias = 0.0005
        light.shadow.strength = 0.5
        light.shadow.radius = 2
        light.position.y = 5.0

        light.lookAt(target: .zero, up: Satin.worldUpDirection)
//        light.add(lightHelperMesh0)

    }
    
    override func evaluate(atTime:TimeInterval,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        
        let radius: Float = 5.0

        let time = atTime + .pi * 0.5
        self.light.position = simd_make_float3(radius * Float(sin(time)), 5.0, radius * cos(Float(time)))
        self.light.lookAt(target: .zero, up: Satin.worldUpDirection)

        
//        if let v = self.inputPosition.value
//        {
//            light.position = v
//        }
        
        self.outputLight.send(light)
        
    }
}

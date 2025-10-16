//
//  EnvironmentSkyboxNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/15/25.
//

import Foundation
import Satin

class EnvironmentSkyboxNode: MeshNode
{
    public override class var name:String {  "Skybox" }

    // Parameters
    public let inputEnvironmentIntensity:FloatParameter
    public let inputBlur:FloatParameter
    public override var inputParameters: [any Parameter] { [inputEnvironmentIntensity, inputBlur] + super.inputParameters }

        
    override public var object:Mesh? {
        return self.mesh
    }

    
    
    private let mesh: Mesh
    
    private let geometry = SkyboxGeometry(size: 450)
    private let material = SkyboxMaterial()
    
    
    public required init(context:Context)
    {
        // self.inputTexture =  NodePort<EquatableTexture>(name: "Texture", kind: .Inlet)
        self.inputEnvironmentIntensity = FloatParameter("Environment Intensity", 1.0, 0.0, 1.0, .slider)
        self.inputBlur = FloatParameter("Blur", 0.0, 0.0, 5.0, .slider)

        self.mesh = Mesh(geometry: self.geometry, material: self.material)
        
        super.init(context: context)
        
        self.material.setup()

    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputEnvironmentIntensityParameter
        case inputBlurParameter
    }

    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputEnvironmentIntensity, forKey: .inputEnvironmentIntensityParameter)
        try container.encode(self.inputBlur, forKey: .inputBlurParameter)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.inputEnvironmentIntensity = try container.decode(FloatParameter.self, forKey: .inputEnvironmentIntensityParameter)
        self.inputBlur = try container.decode(FloatParameter.self, forKey: .inputBlurParameter)
        
        self.mesh = Mesh(geometry: SkyboxGeometry(size: 450), material: self.material)
        
        try super.init(from: decoder)
        
        self.material.setup()

    }
    
    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool {
        
        var shouldOutput = super.evaluate(object: self.mesh, atTime: atTime)
        
        if self.inputEnvironmentIntensity.valueDidChange
        {
            self.material.environmentIntensity = self.inputEnvironmentIntensity.value
            shouldOutput = true
        }
        
        if  self.inputBlur.valueDidChange
        {
            self.material.blur = self.inputBlur.value
            shouldOutput = true
        }
        
        
        return shouldOutput
    }
}

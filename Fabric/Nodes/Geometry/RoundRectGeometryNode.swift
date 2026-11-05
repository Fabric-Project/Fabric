//
//  RoundRectGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/3/25.
//

import Satin
import Foundation
import simd
import Metal

public class RoundRectGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Round Rect Geometry" }
    public override class var nodeDescription: String { "Generates rounded rectangle geometry" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
        ("inputWidth", ParameterPort(parameter:FloatParameter("Width", 1.0, .inputfield, "Width of the rectangle in world units"))),
        ("inputHeight", ParameterPort(parameter:FloatParameter("Height", 1.0, .inputfield, "Height of the rectangle in world units"))),
        ("inputRadius", ParameterPort(parameter:FloatParameter("Radius", 1.0, .inputfield, "Corner radius for the rounded edges in world units"))),
        ("inputResolutionWidth", ParameterPort(parameter:IntParameter("Angular Segments", 1, .inputfield, "Number of segments for the corner curves"))),
        ("inputResolutionHeight", ParameterPort(parameter:IntParameter("Radial Segments", 1, .inputfield, "Number of radial segments from center to edge"))),

        ] + ports
    }
    
    // Proxy Port
    public var inputWidth: ParameterPort<Float> { _inputWidth }
    private var _inputWidth: ParameterPort<Float>!
    public var inputHeight: ParameterPort<Float> { _inputHeight }
    private var _inputHeight: ParameterPort<Float>!
    public var inputRadius: ParameterPort<Float> { _inputRadius }
    private var _inputRadius: ParameterPort<Float>!
    public var inputResolutionWidth: ParameterPort<Int> { _inputResolutionWidth }
    private var _inputResolutionWidth: ParameterPort<Int>!
    public var inputResolutionHeight: ParameterPort<Int> { _inputResolutionHeight }
    private var _inputResolutionHeight: ParameterPort<Int>!

    override public func bindPorts()
    {
        super.bindPorts()
        self._inputWidth = findPort(named: "inputWidth")
        self._inputHeight = findPort(named: "inputHeight")
        self._inputRadius = findPort(named: "inputRadius")
        self._inputResolutionWidth = findPort(named: "inputResolutionWidth")
        self._inputResolutionHeight = findPort(named: "inputResolutionHeight")
    }
    
   
    public override var geometry: RoundedRectGeometry { _geometry }

    private lazy var _geometry = RoundedRectGeometry(context:self.context, width: 1, height: 1, radius: 0.2, angularResolution: 32, radialResolution: 32)
    
    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputWidth.valueDidChange || self.inputHeight.valueDidChange,
           let inputWidth = self.inputWidth.value,
           let inputHeight = self.inputHeight.value
        {
            self.geometry.size = simd_float2( inputWidth, inputHeight)
            shouldOutputGeometry = true
        }
        
        if self.inputRadius.valueDidChange,
           let inputRadius = self.inputRadius.value
        {
            self.geometry.radius = max(0.0001, inputRadius)
            shouldOutputGeometry = true
        }
        
        if  self.inputResolutionWidth.valueDidChange || self.inputResolutionHeight.valueDidChange,
            let inputResolutionWidth = self.inputResolutionWidth.value,
            let inputResolutionHeight = self.inputResolutionHeight.value
        {
            self.geometry.angularResolution = inputResolutionWidth
            self.geometry.radialResolution = inputResolutionHeight
            
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}

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

public class TubeGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Tube Geometry" }
    public override class var nodeDescription: String { "Generates tube geometry" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
            ("inputRadius",  ParameterPort(parameter:FloatParameter("Radius", 0.25, .inputfield, "Radius of the tube in world units"))),
            ("inputHeight",  ParameterPort(parameter:FloatParameter("Height", 0.75, .inputfield, "Height of the tube in world units"))),
            ("inputStartAngle",  ParameterPort(parameter:FloatParameter("Start Angle", 0.0, .inputfield, "Starting angle of the tube arc in degrees"))),
            ("inputEndAngle",  ParameterPort(parameter:FloatParameter("End Angle", 90.0, .inputfield, "Ending angle of the tube arc in degrees"))),
            ("inputAngularResolution",  ParameterPort(parameter:IntParameter("Angular Segments", 20, .inputfield, "Number of segments around the tube circumference"))),
            ("inputVerticalResolution",  ParameterPort(parameter:IntParameter("Vertical Segments", 5, .inputfield, "Number of segments along the tube height"))),

        ] + ports
    }
    
    // Proxy Port
    public var inputRadius: ParameterPort<Float> { _inputRadius }
    private var _inputRadius: ParameterPort<Float>!
    public var inputHeight: ParameterPort<Float> { _inputHeight }
    private var _inputHeight: ParameterPort<Float>!
    public var inputStartAngle: ParameterPort<Float> { _inputStartAngle }
    private var _inputStartAngle: ParameterPort<Float>!
    public var inputEndAngle: ParameterPort<Float> { _inputEndAngle }
    private var _inputEndAngle: ParameterPort<Float>!
    public var inputAngularResolution: ParameterPort<Int> { _inputAngularResolution }
    private var _inputAngularResolution: ParameterPort<Int>!
    public var inputVerticalResolution: ParameterPort<Int> { _inputVerticalResolution }
    private var _inputVerticalResolution: ParameterPort<Int>!

    override public func bindPorts()
    {
        super.bindPorts()
        self._inputRadius = findPort(named: "inputRadius")
        self._inputHeight = findPort(named: "inputHeight")
        self._inputStartAngle = findPort(named: "inputStartAngle")
        self._inputEndAngle = findPort(named: "inputEndAngle")
        self._inputAngularResolution = findPort(named: "inputAngularResolution")
        self._inputVerticalResolution = findPort(named: "inputVerticalResolution")
    }

    public override var geometry: TubeGeometry { _geometry }

    private lazy var _geometry = TubeGeometry(context:self.context, radius: 0.25, height: 0.75, startAngle: 0.0, endAngle: degToRad(90.0), angularResolution: 20, verticalResolution: 5)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputRadius.valueDidChange,
           let inputRadius = self.inputRadius.value
        {
            self.geometry.radius = degToRad(inputRadius)
            shouldOutputGeometry = true
        }
        
        if self.inputHeight.valueDidChange,
           let inputHeight = self.inputHeight.value
        {
            self.geometry.height = inputHeight
            shouldOutputGeometry = true
        }
        
        if self.inputStartAngle.valueDidChange,
           let inputAngle = self.inputStartAngle.value
        {
            self.geometry.startAngle = degToRad(inputAngle)
            shouldOutputGeometry = true
        }
        
        if self.inputEndAngle.valueDidChange,
           let inputAngle = self.inputEndAngle.value
        {
            self.geometry.endAngle = degToRad(inputAngle)
            shouldOutputGeometry = true
        }
        
        if self.inputAngularResolution.valueDidChange,
            let inputAngularResolution = self.inputAngularResolution.value
        {
            self.geometry.angularResolution = inputAngularResolution
            shouldOutputGeometry = true
        }
        
        if self.inputVerticalResolution.valueDidChange,
           let inputVerticalResolution = self.inputVerticalResolution.value
        {
            self.geometry.verticalResolution = inputVerticalResolution
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}

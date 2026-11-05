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

public class ArcGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Arc Geometry" }
    public override class var nodeDescription: String { "Generates arc geometry" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
            ("inputInnerRadius",  ParameterPort(parameter:FloatParameter("Inner Radius", 0.25, .inputfield, "Inner radius of the arc ring in world units"))),
            ("inputOuteradius",  ParameterPort(parameter:FloatParameter("Outer Radius", 0.75, .inputfield, "Outer radius of the arc ring in world units"))),
            ("inputStartAngle",  ParameterPort(parameter:FloatParameter("Start Angle", 0.0, .inputfield, "Starting angle of the arc in degrees"))),
            ("inputEndAngle",  ParameterPort(parameter:FloatParameter("End Angle", 90.0, .inputfield, "Ending angle of the arc in degrees"))),
        ("inputAngularResolution",  ParameterPort(parameter:IntParameter("Angular Segments", 20, .inputfield, "Number of segments along the arc curve"))),
        ("inputRadialResolution",  ParameterPort(parameter:IntParameter("Radial Segments", 5, .inputfield, "Number of segments from inner to outer radius"))),

        ] + ports
    }
    
    // Proxy Port
    public var inputInnerRadius: ParameterPort<Float> { _inputInnerRadius }
    private var _inputInnerRadius: ParameterPort<Float>!
    public var inputOuteradius: ParameterPort<Float> { _inputOuteradius }
    private var _inputOuteradius: ParameterPort<Float>!
    public var inputStartAngle: ParameterPort<Float> { _inputStartAngle }
    private var _inputStartAngle: ParameterPort<Float>!
    public var inputEndAngle: ParameterPort<Float> { _inputEndAngle }
    private var _inputEndAngle: ParameterPort<Float>!
    public var inputAngularResolution: ParameterPort<Int> { _inputAngularResolution }
    private var _inputAngularResolution: ParameterPort<Int>!
    public var inputRadialResolution: ParameterPort<Int> { _inputRadialResolution }
    private var _inputRadialResolution: ParameterPort<Int>!

    override public func bindPorts()
    {
        super.bindPorts()
        self._inputInnerRadius = findPort(named: "inputInnerRadius")
        self._inputOuteradius = findPort(named: "inputOuteradius")
        self._inputStartAngle = findPort(named: "inputStartAngle")
        self._inputEndAngle = findPort(named: "inputEndAngle")
        self._inputAngularResolution = findPort(named: "inputAngularResolution")
        self._inputRadialResolution = findPort(named: "inputRadialResolution")
    }

    public override var geometry: ArcGeometry { _geometry }

    private lazy var _geometry = ArcGeometry(context:self.context, radius: (inner: 0.25, outer:0.75),
                                        angle: (start:0.0, end:degToRad(90.0)), res: (angular:20, radial:5))

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputInnerRadius.valueDidChange,
           let inputRadius = self.inputInnerRadius.value
        {
            self.geometry.innerRadius = inputRadius
            shouldOutputGeometry = true
        }
        
        if self.inputOuteradius.valueDidChange,
           let inputRadius = self.inputOuteradius.value
        {
            self.geometry.outerRadius = inputRadius
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
        
        if self.inputRadialResolution.valueDidChange,
           let inputRadialResolution = self.inputRadialResolution.value
        {
            self.geometry.radialResolution = inputRadialResolution
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}

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

public class TorusGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Torus Geometry" }
    public override class var nodeDescription: String { "Generates torus geometry" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
            ("inputMinorRadius",  ParameterPort(parameter:FloatParameter("Minor Radius", 5.0, .inputfield, "Radius of the tube cross-section in world units"))),
            ("inputMajorRadius",  ParameterPort(parameter:FloatParameter("Major Radius", 0.25, .inputfield, "Distance from center to tube center in world units"))),
            ("inputMinorResolution",  ParameterPort(parameter:IntParameter("Minor Segments", 20, .inputfield, "Number of segments around the tube cross-section"))),
            ("inputMajorResolution",  ParameterPort(parameter:IntParameter("Major Segments", 20, .inputfield, "Number of segments around the torus ring"))),

        ] + ports
    }
    
    // Proxy Port
    public var inputMinorRadius: ParameterPort<Float> { _inputMinorRadius }
    private var _inputMinorRadius: ParameterPort<Float>!
    public var inputMajorRadius: ParameterPort<Float> { _inputMajorRadius }
    private var _inputMajorRadius: ParameterPort<Float>!
    public var inputMinorResolution: ParameterPort<Int> { _inputMinorResolution }
    private var _inputMinorResolution: ParameterPort<Int>!
    public var inputMajorResolution: ParameterPort<Int> { _inputMajorResolution }
    private var _inputMajorResolution: ParameterPort<Int>!

    override public func bindPorts()
    {
        super.bindPorts()
        self._inputMinorRadius = findPort(named: "inputMinorRadius")
        self._inputMajorRadius = findPort(named: "inputMajorRadius")
        self._inputMinorResolution = findPort(named: "inputMinorResolution")
        self._inputMajorResolution = findPort(named: "inputMajorResolution")
    }

    public override var geometry: TorusGeometry { _geometry }

    private lazy var _geometry = TorusGeometry(context:self.context, minorRadius: 5.0, majorRadius: 0.25, minorResolution: 20, majorResolution: 20)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputMinorRadius.valueDidChange,
           let inputRadius = self.inputMinorRadius.value
        {
            self.geometry.minorRadius = degToRad(inputRadius)
            shouldOutputGeometry = true
        }
        
        if self.inputMajorRadius.valueDidChange,
           let inputMajorRadius = self.inputMajorRadius.value
        {
            self.geometry.majorRadius = inputMajorRadius
            shouldOutputGeometry = true
        }
                
        if self.inputMajorResolution.valueDidChange,
            let inputMajorResolution = self.inputMajorResolution.value
        {
            self.geometry.majorResolution = inputMajorResolution
            shouldOutputGeometry = true
        }
        
        if self.inputMinorResolution.valueDidChange,
            let inputMinorResolution = self.inputMinorResolution.value
        {
            self.geometry.minorResolution = inputMinorResolution
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}

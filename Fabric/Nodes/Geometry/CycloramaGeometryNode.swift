//
//  CycloramaGeometryNode.swift
//  Fabric
//

import Satin
import Foundation
import simd
import Metal

public class CycloramaGeometryNode: BaseGeometryNode
{
    public override class var name: String { "Cyclorama Geometry" }
    public override class var nodeDescription: String { "Generates a cyclorama — a seamless sweep geometry with a flat floor, curved transition, and vertical back wall, like a photography studio infinity cove." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return [
            ("inputWidth",             ParameterPort(parameter: FloatParameter("Width",           4.0, .inputfield, "Width of the cyclorama along the X axis in world units"))),
            ("inputLength",            ParameterPort(parameter: FloatParameter("Length",          4.0, .inputfield, "Length of the floor section along the Z axis in world units"))),
            ("inputDepth",             ParameterPort(parameter: FloatParameter("Depth",           4.0, .inputfield, "Height of the back wall in world units"))),
            ("inputRadius",            ParameterPort(parameter: FloatParameter("Radius",          1.0, .inputfield, "Radius of the curved transition between floor and wall"))),
            ("inputWidthResolution",   ParameterPort(parameter: IntParameter("Width Segments",     1,  .inputfield, "Subdivisions along the width"))),
            ("inputLengthResolution",  ParameterPort(parameter: IntParameter("Length Segments",    1,  .inputfield, "Subdivisions along the floor length"))),
            ("inputDepthResolution",   ParameterPort(parameter: IntParameter("Depth Segments",     1,  .inputfield, "Subdivisions along the back wall height"))),
            ("inputAngularResolution", ParameterPort(parameter: IntParameter("Angular Segments",  24,  .inputfield, "Subdivisions around the curved transition arc"))),
        ] + ports
    }

    public var inputWidth:             ParameterPort<Float> { port(named: "inputWidth") }
    public var inputLength:            ParameterPort<Float> { port(named: "inputLength") }
    public var inputDepth:             ParameterPort<Float> { port(named: "inputDepth") }
    public var inputRadius:            ParameterPort<Float> { port(named: "inputRadius") }
    public var inputWidthResolution:   ParameterPort<Int>   { port(named: "inputWidthResolution") }
    public var inputLengthResolution:  ParameterPort<Int>   { port(named: "inputLengthResolution") }
    public var inputDepthResolution:   ParameterPort<Int>   { port(named: "inputDepthResolution") }
    public var inputAngularResolution: ParameterPort<Int>   { port(named: "inputAngularResolution") }

    public override var geometry: CycloramaGeometry { _geometry }

    private lazy var _geometry = CycloramaGeometry(
        context: self.context,
        width: 4.0,
        length: 4.0,
        depth: 4.0,
        radius: 1.0,
        widthResolution: 1,
        lengthResolution: 1,
        depthResolution: 1,
        angularResolution: 24
    )

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputWidth.valueDidChange,
           let v = self.inputWidth.value
        {
            self.geometry.width = v
            shouldOutputGeometry = true
        }

        if self.inputLength.valueDidChange,
           let v = self.inputLength.value
        {
            self.geometry.length = v
            shouldOutputGeometry = true
        }

        if self.inputDepth.valueDidChange,
           let v = self.inputDepth.value
        {
            self.geometry.depth = v
            shouldOutputGeometry = true
        }

        if self.inputRadius.valueDidChange,
           let v = self.inputRadius.value
        {
            self.geometry.radius = v
            shouldOutputGeometry = true
        }

        if self.inputWidthResolution.valueDidChange,
           let v = self.inputWidthResolution.value
        {
            self.geometry.widthResolution = v
            shouldOutputGeometry = true
        }

        if self.inputLengthResolution.valueDidChange,
           let v = self.inputLengthResolution.value
        {
            self.geometry.lengthResolution = v
            shouldOutputGeometry = true
        }

        if self.inputDepthResolution.valueDidChange,
           let v = self.inputDepthResolution.value
        {
            self.geometry.depthResolution = v
            shouldOutputGeometry = true
        }

        if self.inputAngularResolution.valueDidChange,
           let v = self.inputAngularResolution.value
        {
            self.geometry.angularResolution = v
            shouldOutputGeometry = true
        }

        return shouldOutputGeometry
    }
}

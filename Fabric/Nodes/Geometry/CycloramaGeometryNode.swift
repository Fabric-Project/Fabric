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

    public let inputWidth = ParameterPort(parameter: FloatParameter("Width",           4.0, .inputfield, "Width of the cyclorama along the X axis in world units"))
    public let inputLength = ParameterPort(parameter: FloatParameter("Length",          4.0, .inputfield, "Length of the floor section along the Z axis in world units"))
    public let inputDepth = ParameterPort(parameter: FloatParameter("Depth",           4.0, .inputfield, "Height of the back wall in world units"))
    public let inputRadius = ParameterPort(parameter: FloatParameter("Radius",          1.0, .inputfield, "Radius of the curved transition between floor and wall"))
    public let inputWidthResolution = ParameterPort(parameter: IntParameter("Width Segments",     1,  .inputfield, "Subdivisions along the width"))
    public let inputLengthResolution = ParameterPort(parameter: IntParameter("Length Segments",    1,  .inputfield, "Subdivisions along the floor length"))
    public let inputDepthResolution = ParameterPort(parameter: IntParameter("Depth Segments",     1,  .inputfield, "Subdivisions along the back wall height"))
    public let inputAngularResolution = ParameterPort(parameter: IntParameter("Angular Segments",  24,  .inputfield, "Subdivisions around the curved transition arc"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputWidth", port: self.inputWidth),
            PortDeclaration(key: "inputLength", port: self.inputLength),
            PortDeclaration(key: "inputDepth", port: self.inputDepth),
            PortDeclaration(key: "inputRadius", port: self.inputRadius),
            PortDeclaration(key: "inputWidthResolution", port: self.inputWidthResolution),
            PortDeclaration(key: "inputLengthResolution", port: self.inputLengthResolution),
            PortDeclaration(key: "inputDepthResolution", port: self.inputDepthResolution),
            PortDeclaration(key: "inputAngularResolution", port: self.inputAngularResolution),
        ] + super.declaredPorts()
    }

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

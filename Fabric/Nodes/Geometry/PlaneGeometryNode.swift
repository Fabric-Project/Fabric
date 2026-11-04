//
//  PlaneGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Satin
import Foundation
import simd
import Metal

public class PlaneGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Plane Geometry" }
    public override class var nodeDescription: String { "Generates plane geometry" }

    public let inputPlane = ParameterPort(parameter:StringParameter("Plane", "XY", ["XY", "YX", "XZ", "ZX", "YZ", "ZY"], .dropdown, "Orientation plane defining which axes the plane spans"))
    public let inputWidth = ParameterPort(parameter:FloatParameter("Width", 1.0, .inputfield, "Width of the plane in world units"))
    public let inputHeight = ParameterPort(parameter:FloatParameter("Height", 1.0, .inputfield, "Height of the plane in world units"))
    public let inputResolutionWidth = ParameterPort(parameter:IntParameter("Width Segments", 1, .inputfield, "Number of segments along the width"))
    public let inputResolutionHeight = ParameterPort(parameter:IntParameter("Height Segments", 1, .inputfield, "Number of segments along the height"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputPlane", port: self.inputPlane),
            PortDeclaration(key: "inputWidth", port: self.inputWidth),
            PortDeclaration(key: "inputHeight", port: self.inputHeight),
            PortDeclaration(key: "inputResolutionWidth", port: self.inputResolutionWidth),
            PortDeclaration(key: "inputResolutionHeight", port: self.inputResolutionHeight),
        ] + super.declaredPorts()
    }

    public override var geometry: PlaneGeometry { _geometry }

    private lazy var _geometry = PlaneGeometry(context:self.context, width: 1, height: 1, orientation: .xy)
    
    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputPlane.valueDidChange,
           let planeName = self.inputPlane.value
        {
          switch planeName {
          case "XY":
              self.geometry.orientation = .xy
          case "YX":
              self.geometry.orientation = .yx
          case "XZ":
              self.geometry.orientation = .xz
          case "ZX":
              self.geometry.orientation = .zx
          case "YZ":
              self.geometry.orientation = .yz
          default:
              self.geometry.orientation = .xy
            }
        }
        
        if self.inputWidth.valueDidChange,
           let inputWidth = self.inputWidth.value
        {
            self.geometry.width = inputWidth
            shouldOutputGeometry = true
        }
        
        if self.inputHeight.valueDidChange,
           let height = self.inputHeight.value
        {
            self.geometry.height = height
            shouldOutputGeometry = true
        }
        
        if  self.inputResolutionWidth.valueDidChange || self.inputResolutionHeight.valueDidChange,
            let width = self.inputResolutionWidth.value,
            let height = self.inputResolutionHeight.value
        {
            self.geometry.resolution = simd_int2(Int32(width), Int32(height))
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
     }
}

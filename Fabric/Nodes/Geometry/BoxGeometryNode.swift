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

public class BoxGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Box Geometry" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputWidthParam", ParameterPort(parameter:FloatParameter("Width", 1.0, .inputfield)) ),
            ("inputHeightParam", ParameterPort(parameter:FloatParameter("Height", 1.0, .inputfield)) ),
            ("inputDepthParam", ParameterPort(parameter:FloatParameter("Depth", 1.0, .inputfield)) ),
            ("inputResolutionParam", ParameterPort(parameter:Float3Parameter("Resolution", simd_float3(repeating: 1), .inputfield)) ),
        ]
    }
    
    public var inputWidthParam: NodePort<Float>             { port(named: "inputWidthParam") }
    public var inputHeightParam: NodePort<Float>            { port(named: "inputHeightParam") }
    public var inputDepthParam: NodePort<Float>             { port(named: "inputDepthParam") }
    public var inputResolutionParam: NodePort<simd_float3>  { port(named: "inputResolutionParam") }
    
    public override var geometry: BoxGeometry { _geometry }
    
    private let _geometry = BoxGeometry(width: 1, height: 1, depth: 1)

    
    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)
        
        if self.inputWidthParam.valueDidChange,
           let width = self.inputWidthParam.value
        {
            self.geometry.width = width
            shouldOutputGeometry = true
        }
        
        if self.inputHeightParam.valueDidChange,
            let height = self.inputHeightParam.value
        {
            self.geometry.height = height
            shouldOutputGeometry = true
        }
        
        if self.inputDepthParam.valueDidChange,
           let depth = self.inputDepthParam.value
        {
            self.geometry.depth = depth
            shouldOutputGeometry = true
        }
        
        if self.inputResolutionParam.valueDidChange,
           let resolution = self.inputResolutionParam.value
        {
//            self.geometry.resolution =  self.inputResolutionParam.value
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
    }
}

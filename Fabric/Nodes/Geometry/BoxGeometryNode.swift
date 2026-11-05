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
    public override class var nodeDescription: String { "Generates box geometry" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return [
            ("inputWidthParam", ParameterPort(parameter:FloatParameter("Width", 1.0, .inputfield, "Width of the box along the X axis in world units")) ),
            ("inputHeightParam", ParameterPort(parameter:FloatParameter("Height", 1.0, .inputfield, "Height of the box along the Y axis in world units")) ),
            ("inputDepthParam", ParameterPort(parameter:FloatParameter("Depth", 1.0, .inputfield, "Depth of the box along the Z axis in world units")) ),
            ("inputResolutionParam", ParameterPort(parameter:Float3Parameter("Resolution", simd_float3(repeating: 1), .inputfield, "Number of segments along each axis (X, Y, Z)")) ),
        ] + ports
    }
    
    public var inputWidthParam: NodePort<Float> { _inputWidthParam }
    private var _inputWidthParam: NodePort<Float>!
    public var inputHeightParam: NodePort<Float> { _inputHeightParam }
    private var _inputHeightParam: NodePort<Float>!
    public var inputDepthParam: NodePort<Float> { _inputDepthParam }
    private var _inputDepthParam: NodePort<Float>!
    public var inputResolutionParam: NodePort<simd_float3> { _inputResolutionParam }
    private var _inputResolutionParam: NodePort<simd_float3>!

    override public func bindPorts()
    {
        super.bindPorts()
        self._inputWidthParam = findPort(named: "inputWidthParam")
        self._inputHeightParam = findPort(named: "inputHeightParam")
        self._inputDepthParam = findPort(named: "inputDepthParam")
        self._inputResolutionParam = findPort(named: "inputResolutionParam")
    }
    
    public override var geometry: BoxGeometry { _geometry }
    
    private lazy var _geometry = BoxGeometry(context:self.context, width: 1, height: 1, depth: 1)

    
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
        
        // TODO: Fix
        if self.inputResolutionParam.valueDidChange,
           let resolution = self.inputResolutionParam.value
        {
            self.geometry.resolution = simd_int3(resolution)
            shouldOutputGeometry = true
        }
        
        return shouldOutputGeometry
    }
}

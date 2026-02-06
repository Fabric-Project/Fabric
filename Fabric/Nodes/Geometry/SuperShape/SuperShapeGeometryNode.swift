//
//  SuperShapeGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/5/25.
//

import Combine
import Metal
import MetalKit
import Satin
import FabricCore

final class SuperShapeGeometry: SatinGeometry {
    var r1: Float { didSet {
        if oldValue != r1 {
            _updateData = true
        }
    }}

    var a1: Float { didSet {
        if oldValue != a1 {
            _updateData = true
        }
    }}

    var b1: Float { didSet {
        if oldValue != b1 {
            _updateData = true
        }
    }}

    var m1: Float { didSet {
        if oldValue != m1 {
            _updateData = true
        }
    }}

    var n11: Float { didSet {
        if oldValue != n11 {
            _updateData = true
        }
    }}

    var n21: Float { didSet {
        if oldValue != n21 {
            _updateData = true
        }
    }}

    var n31: Float { didSet {
        if oldValue != n31 {
            _updateData = true
        }
    }}

    var r2: Float { didSet {
        if oldValue != r2 {
            _updateData = true
        }
    }}

    var a2: Float { didSet {
        if oldValue != a2 {
            _updateData = true
        }
    }}

    var b2: Float { didSet {
        if oldValue != b2 {
            _updateData = true
        }
    }}
    var m2: Float { didSet {
        if oldValue != m2 {
            _updateData = true
        }
    }}

    var n12: Float { didSet {
        if oldValue != n12 {
            _updateData = true
        }
    }}

    var n22: Float { didSet {
        if oldValue != n22 {
            _updateData = true
        }
    }}

    var n32: Float { didSet {
        if oldValue != n32 {
            _updateData = true
        }
    }}

    var res: Int { didSet {
        if oldValue != res {
            _updateData = true
        }
    }}

    init(r1: Float, a1: Float, b1: Float, m1: Float, n11: Float, n21: Float, n31: Float, r2: Float, a2: Float, b2: Float, m2: Float, n12: Float, n22: Float, n32: Float, res: Int) {
        self.r1 = r1
        self.a1 = a1
        self.b1 = b1
        self.m1 = m1
        self.n11 = n11
        self.n21 = n21
        self.n31 = n31
        self.r2 = r2
        self.a2 = a2
        self.b2 = b2
        self.m2 = m2
        self.n12 = n12
        self.n22 = n22
        self.n32 = n32
        self.res = res
        super.init()
    }

    override public func generateGeometryData() -> GeometryData {
        generateSuperShapeGeometryData(r1, a1, b1, m1, n11, n21, n31, r2, a2, b2, m2, n12, n22, n32, Int32(res), Int32(res))
    }
}



class SuperShapeGeometryNode : BaseGeometryNode
{
    override public class var name:String { "Super Shape Geometry" }
    override public class var nodeDescription: String { "Provides parametric Geometry based off of the Super Shape formula."}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("r1Param",  ParameterPort(parameter:FloatParameter("R1", 1.0, 0, 2, .slider, "Radial scale factor for the first supershape formula"))),
            ("a1Param",  ParameterPort(parameter:FloatParameter("A1", 1.0, 0.0, 5.0, .slider, "Horizontal stretch factor for the first supershape"))),
            ("b1Param",  ParameterPort(parameter:FloatParameter("B1", 1.0, 0.0, 5.0, .slider, "Vertical stretch factor for the first supershape"))),
            ("m1Param",  ParameterPort(parameter:FloatParameter("M1", 10, 0, 20, .slider, "Rotational symmetry count for the first supershape"))),
            ("n11Param", ParameterPort(parameter:FloatParameter("N11", 1.087265, 0.0, 100.0, .slider, "First shape exponent n1 for the first supershape"))),
            ("n21Param", ParameterPort(parameter:FloatParameter("N21", 0.938007, 0.0, 100.0, .slider, "Second shape exponent n2 for the first supershape"))),
            ("n31Param", ParameterPort(parameter:FloatParameter("N31", -0.615898, 0.0, 100.0, .slider, "Third shape exponent n3 for the first supershape"))),
            ("r2Param",  ParameterPort(parameter:FloatParameter("R2", 0.984062, 0, 2, .slider, "Radial scale factor for the second supershape formula"))),
            ("a2Param",  ParameterPort(parameter:FloatParameter("A2", 1.513944, 0.0, 5.0, .slider, "Horizontal stretch factor for the second supershape"))),
            ("b2Param",  ParameterPort(parameter:FloatParameter("B2", 0.642890, 0.0, 5.0, .slider, "Vertical stretch factor for the second supershape"))),
            ("m2Param",  ParameterPort(parameter:FloatParameter("M2", 5.225158, 0, 20, .slider, "Rotational symmetry count for the second supershape"))),
            ("n12Param", ParameterPort(parameter:FloatParameter("N12", 1.0, 0.0, 100.0, .slider, "First shape exponent n1 for the second supershape"))),
            ("n22Param", ParameterPort(parameter:FloatParameter("N22", 1.371561, 0.0, 100.0, .slider, "Second shape exponent n2 for the second supershape"))),
            ("n32Param", ParameterPort(parameter:FloatParameter("N32", 0.651718, 0.0, 100.0, .slider, "Third shape exponent n3 for the second supershape"))),
            ("resParam", ParameterPort(parameter:IntParameter("Resolution", 300, 3, 300, .inputfield, "Mesh resolution for both angular and vertical divisions"))),
        ]
    }

    // Proxy Ports
    public var r1Param:ParameterPort<Float>  { port(named: "r1Param") }
    public var a1Param:ParameterPort<Float>  { port(named: "a1Param") }
    public var b1Param:ParameterPort<Float>  { port(named: "b1Param") }
    public var m1Param:ParameterPort<Float>  { port(named: "m1Param") }
    public var n11Param:ParameterPort<Float>  { port(named: "n11Param") }
    public var n21Param:ParameterPort<Float>  { port(named: "n21Param") }
    public var n31Param:ParameterPort<Float>  { port(named: "n31Param") }
    public var r2Param:ParameterPort<Float>  { port(named: "r2Param") }
    public var a2Param:ParameterPort<Float>  { port(named: "a2Param") }
    public var b2Param:ParameterPort<Float>  { port(named: "b2Param") }
    public var m2Param:ParameterPort<Float>  { port(named: "m2Param") }
    public var n12Param:ParameterPort<Float>  { port(named: "n12Param") }
    public var n22Param:ParameterPort<Float>  { port(named: "n22Param") }
    public var n32Param:ParameterPort<Float>  { port(named: "n32Param") }
    public var resParam:ParameterPort<Int>  { port(named: "resParam") }

    public override var geometry: SuperShapeGeometry { _geometry }

    private lazy var _geometry = SuperShapeGeometry(
        r1: self.r1Param.value ?? 0.0,
        a1: self.a1Param.value ?? 0.0,
        b1: self.b1Param.value ?? 0.0,
        m1: self.m1Param.value ?? 0.0,
        n11: self.n11Param.value ?? 0.0,
        n21: self.n21Param.value ?? 0.0,
        n31: self.n31Param.value ?? 0.0,
        r2: self.r2Param.value ?? 0.0,
        a2: self.a2Param.value ?? 0.0,
        b2: self.b2Param.value ?? 0.0,
        m2: self.m2Param.value ?? 0.0,
        n12: self.n12Param.value ?? 0.0,
        n22: self.n22Param.value ?? 0.0,
        n32: self.n32Param.value ?? 0.0,
        res: self.resParam.value ?? 0
    )
    
    override public func evaluate(geometry: SatinGeometry, atTime: TimeInterval) -> Bool {
        
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        
        if self.r1Param.valueDidChange,
           let r1Param = self.r1Param.value
        {
            self.geometry.r1 = r1Param
            shouldOutput = true
        }
        
        if self.a1Param.valueDidChange,
           let a1Param = self.a1Param.value
        {
            self.geometry.a1 = a1Param
            shouldOutput = true
        }

        if self.b1Param.valueDidChange,
           let b1Param = self.b1Param.value
        {
            self.geometry.b1 = b1Param
            shouldOutput = true
        }

        if self.m1Param.valueDidChange,
           let m1Param = self.m1Param.value
        {
            self.geometry.m1 = m1Param
            shouldOutput = true
        }
        
        if self.n11Param.valueDidChange,
           let n11Param = self.n11Param.value
        {
            self.geometry.n11 = n11Param
            shouldOutput = true
        }
        
        if self.n21Param.valueDidChange,
           let n21Param = self.n21Param.value
        {
            self.geometry.n21 = n21Param
            shouldOutput = true
        }
        
        if self.n31Param.valueDidChange,
           let n31Param = self.n31Param.value
        {
            self.geometry.n31 = n31Param
            shouldOutput = true
        }
        
        if self.r2Param.valueDidChange,
           let r2Param = self.r2Param.value
        {
            self.geometry.r2 = r2Param
            shouldOutput = true
        }
        
        if self.a2Param.valueDidChange,
           let a2Param = self.a2Param.value
        {
            self.geometry.a2 = a2Param
            shouldOutput = true
        }
        
        if self.b2Param.valueDidChange,
           let b2Param = self.b2Param.value
        {
            self.geometry.b2 = b2Param
            shouldOutput = true
        }
        
        if self.m2Param.valueDidChange,
           let m2Param = self.m2Param.value
        {
            self.geometry.m2 = m2Param
            shouldOutput = true
        }
        
        if self.n12Param.valueDidChange,
           let n12Param = self.n12Param.value
        {
            self.geometry.n12 = n12Param
            shouldOutput = true
        }
        
        if self.n22Param.valueDidChange,
           let n22Param = self.n22Param.value
        {
            self.geometry.n22 = n22Param
            shouldOutput = true
        }
        
        if self.n32Param.valueDidChange,
           let n32Param = self.n32Param.value
        {
            self.geometry.n32 = n32Param
            shouldOutput = true
        }
        
        if self.resParam.valueDidChange,
           let resParam = self.resParam.value
        {
            self.geometry.res = resParam
            shouldOutput = true
        }

       return shouldOutput
    }
}

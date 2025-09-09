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



class SuperShapeGeometryNode : Node, NodeProtocol
{
    static let name = "Super Shape Geometry"
    static var nodeType = Node.NodeType.Geometery

    // Params
    var r1Param = FloatParameter("R1", 1.0, 0, 2, .slider)
    var a1Param = FloatParameter("A1", 1.0, 0.0, 5.0, .slider)
    var b1Param = FloatParameter("B1", 1.0, 0.0, 5.0, .slider)
    var m1Param = FloatParameter("M1", 10, 0, 20, .slider)
    var n11Param = FloatParameter("N11", 1.087265, 0.0, 100.0, .slider)
    var n21Param = FloatParameter("N21", 0.938007, 0.0, 100.0, .slider)
    var n31Param = FloatParameter("N31", -0.615898, 0.0, 100.0, .slider)
    var r2Param = FloatParameter("R2", 0.984062, 0, 2, .slider)
    var a2Param = FloatParameter("A2", 1.513944, 0.0, 5.0, .slider)
    var b2Param = FloatParameter("B2", 0.642890, 0.0, 5.0, .slider)
    var m2Param = FloatParameter("M2", 5.225158, 0, 20, .slider)
    var n12Param = FloatParameter("N12", 1.0, 0.0, 100.0, .slider)
    var n22Param = FloatParameter("N22", 1.371561, 0.0, 100.0, .slider)
    var n32Param = FloatParameter("N32", 0.651718, 0.0, 100.0, .slider)
    var resParam = IntParameter("Resolution", 300, 3, 300, .inputfield)

    override var inputParameters: [any Parameter] { super.inputParameters +
                                                    [ resParam,
                                                      r1Param,
                                                      a1Param,
                                                      b1Param,
                                                      m1Param,
                                                      n11Param,
                                                      n21Param,
                                                      n31Param,
                                                      r2Param,
                                                      a2Param,
                                                      b2Param,
                                                      m2Param,
                                                      n12Param,
                                                      n22Param,
                                                      n32Param] }

    let outputGeometry = NodePort<Geometry>(name: SuperShapeGeometryNode.name, kind: .Outlet)

    private lazy var geometry = SuperShapeGeometry(
        r1: r1Param.value,
        a1: a1Param.value,
        b1: b1Param.value,
        m1: m1Param.value,
        n11: n11Param.value,
        n21: n21Param.value,
        n31: n31Param.value,
        r2: r2Param.value,
        a2: a2Param.value,
        b2: b2Param.value,
        m2: m2Param.value,
        n12: n12Param.value,
        n22: n22Param.value,
        n32: n32Param.value,
        res: resParam.value
    )
    
    public override var ports:[any NodePortProtocol] {  [outputGeometry] + super.ports}
    
    override func execute(context:GraphExecutionContext,
                          renderPassDescriptor: MTLRenderPassDescriptor,
                          commandBuffer: MTLCommandBuffer)
    {
        self.geometry.r1 = r1Param.value
        self.geometry.a1 = a1Param.value
        self.geometry.b1 = b1Param.value
        self.geometry.m1 = m1Param.value
        self.geometry.n11 = n11Param.value
        self.geometry.n21 = n21Param.value
        self.geometry.n31 = n31Param.value
        self.geometry.r2 = r2Param.value
        self.geometry.a2 = a2Param.value
        self.geometry.b2 = b2Param.value
        self.geometry.m2 = m2Param.value
        self.geometry.n12 = n12Param.value
        self.geometry.n22 = n22Param.value
        self.geometry.n32 = n32Param.value
        self.geometry.res = resParam.value

        self.outputGeometry.send(self.geometry)
     }
}

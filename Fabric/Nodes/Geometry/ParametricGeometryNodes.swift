//
//  ParametricGeometryNodes.swift
//  Fabric
//
//  Created by Anton Marini on 6/18/26.
//

import Satin
import Foundation
import simd
import Metal

// MARK: - Helpers (private to this file)

@inline(__always)
private func _signedPow(_ v: Float, _ e: Float) -> Float {
    v == 0 ? 0 : (v < 0 ? -1 : 1) * pow(abs(v), e)
}

@inline(__always)
private func _sech(_ v: Float) -> Float { 1.0 / cosh(v) }

// MARK: - Möbius Strip

public class MobiusStripGeometryNode: BaseGeometryNode {
    public override class var name: String { "Mobius Strip Geometry" }
    public override class var nodeDescription: String { "Generates a Möbius strip — a single-sided surface with a half-twist" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return [
            ("inputRadius",      ParameterPort(parameter: FloatParameter("Radius",      1.0,  .inputfield, "Distance from center to the midline of the strip"))),
            ("inputWidth",       ParameterPort(parameter: FloatParameter("Width",        0.35, .inputfield, "Half-width of the strip cross-section"))),
            ("inputResolutionU", ParameterPort(parameter: IntParameter("Resolution U", 192,   .inputfield, "Segments along the strip length"))),
            ("inputResolutionV", ParameterPort(parameter: IntParameter("Resolution V",  32,   .inputfield, "Segments across the strip width"))),
        ] + ports
    }

    public var inputRadius:      ParameterPort<Float> { port(named: "inputRadius") }
    public var inputWidth:       ParameterPort<Float> { port(named: "inputWidth") }
    public var inputResolutionU: ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV: ParameterPort<Int>   { port(named: "inputResolutionV") }

    public override var geometry: ParametricGeometry { _geometry }
    private lazy var _geometry: ParametricGeometry = .mobiusStrip(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        if inputRadius.valueDidChange || inputWidth.valueDidChange ||
           inputResolutionU.valueDidChange || inputResolutionV.valueDidChange {
            let radius = inputRadius.value ?? 1.0
            let width  = inputWidth.value  ?? 0.35
            let resU   = Int32(inputResolutionU.value ?? 192)
            let resV   = Int32(inputResolutionV.value ?? 32)
            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = 0 ... (.pi * 2)
            geo.rangeV = -width ... width
            geo.generator = { u, v in
                let cu = cos(u), su = sin(u)
                let chu = cos(u * 0.5), shu = sin(u * 0.5)
                let ring = radius + v * chu
                return [ring * cu, ring * su, v * shu]
            }
            shouldOutput = true
        }
        return shouldOutput
    }
}

// MARK: - Helicoid

public class HelicoidGeometryNode: BaseGeometryNode {
    public override class var name: String { "Helicoid Geometry" }
    public override class var nodeDescription: String { "Generates a helicoid — a ruled spiral ramp surface" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return [
            ("inputRadius",      ParameterPort(parameter: FloatParameter("Radius",      1.5, .inputfield, "Outer radius of the helicoid"))),
            ("inputPitch",       ParameterPort(parameter: FloatParameter("Pitch",        0.2, .inputfield, "Vertical rise per radian of rotation"))),
            ("inputTurns",       ParameterPort(parameter: FloatParameter("Turns",        3.0, .inputfield, "Number of complete helical turns"))),
            ("inputResolutionU", ParameterPort(parameter: IntParameter("Resolution U", 192,  .inputfield, "Segments along the helix angle"))),
            ("inputResolutionV", ParameterPort(parameter: IntParameter("Resolution V",  64,  .inputfield, "Segments along the radial direction"))),
        ] + ports
    }

    public var inputRadius:      ParameterPort<Float> { port(named: "inputRadius") }
    public var inputPitch:       ParameterPort<Float> { port(named: "inputPitch") }
    public var inputTurns:       ParameterPort<Float> { port(named: "inputTurns") }
    public var inputResolutionU: ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV: ParameterPort<Int>   { port(named: "inputResolutionV") }

    public override var geometry: ParametricGeometry { _geometry }
    private lazy var _geometry: ParametricGeometry = .helicoid(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        if inputRadius.valueDidChange || inputPitch.valueDidChange || inputTurns.valueDidChange ||
           inputResolutionU.valueDidChange || inputResolutionV.valueDidChange {
            let radius = inputRadius.value ?? 1.5
            let pitch  = inputPitch.value  ?? 0.2
            let turns  = inputTurns.value  ?? 3.0
            let resU   = Int32(inputResolutionU.value ?? 192)
            let resV   = Int32(inputResolutionV.value ?? 64)
            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = 0 ... (.pi * 2 * turns)
            geo.rangeV = -radius ... radius
            geo.generator = { u, v in [v * cos(u), v * sin(u), pitch * u] }
            shouldOutput = true
        }
        return shouldOutput
    }
}

// MARK: - Superellipsoid

public class SuperellipsoidGeometryNode: BaseGeometryNode {
    public override class var name: String { "Superellipsoid Geometry" }
    public override class var nodeDescription: String { "Generates a superellipsoid — a generalization of spheres and cylinders controlled by two shape exponents" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return [
            ("inputRadiusX",     ParameterPort(parameter: FloatParameter("Radius X",    1.0, .inputfield, "Scale along the X axis"))),
            ("inputRadiusY",     ParameterPort(parameter: FloatParameter("Radius Y",    1.0, .inputfield, "Scale along the Y axis"))),
            ("inputRadiusZ",     ParameterPort(parameter: FloatParameter("Radius Z",    1.0, .inputfield, "Scale along the Z axis"))),
            ("inputExponentU",   ParameterPort(parameter: FloatParameter("Exponent U",  0.5, .inputfield, "Horizontal cross-section shape exponent (< 1 pinched, > 1 rounded)"))),
            ("inputExponentV",   ParameterPort(parameter: FloatParameter("Exponent V",  0.5, .inputfield, "Vertical cross-section shape exponent"))),
            ("inputResolutionU", ParameterPort(parameter: IntParameter("Resolution U", 160, .inputfield, "Segments along the U direction"))),
            ("inputResolutionV", ParameterPort(parameter: IntParameter("Resolution V",  96, .inputfield, "Segments along the V direction"))),
        ] + ports
    }

    public var inputRadiusX:     ParameterPort<Float> { port(named: "inputRadiusX") }
    public var inputRadiusY:     ParameterPort<Float> { port(named: "inputRadiusY") }
    public var inputRadiusZ:     ParameterPort<Float> { port(named: "inputRadiusZ") }
    public var inputExponentU:   ParameterPort<Float> { port(named: "inputExponentU") }
    public var inputExponentV:   ParameterPort<Float> { port(named: "inputExponentV") }
    public var inputResolutionU: ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV: ParameterPort<Int>   { port(named: "inputResolutionV") }

    public override var geometry: ParametricGeometry { _geometry }
    private lazy var _geometry: ParametricGeometry = .superellipsoid(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        if inputRadiusX.valueDidChange || inputRadiusY.valueDidChange || inputRadiusZ.valueDidChange ||
           inputExponentU.valueDidChange || inputExponentV.valueDidChange ||
           inputResolutionU.valueDidChange || inputResolutionV.valueDidChange {
            let rx  = inputRadiusX.value   ?? 1.0
            let ry  = inputRadiusY.value   ?? 1.0
            let rz  = inputRadiusZ.value   ?? 1.0
            let eu  = inputExponentU.value ?? 0.5
            let ev  = inputExponentV.value ?? 0.5
            let resU = Int32(inputResolutionU.value ?? 160)
            let resV = Int32(inputResolutionV.value ?? 96)
            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = -.pi ... .pi
            geo.rangeV = (-.pi * 0.5) ... (.pi * 0.5)
            geo.generator = { u, v in
                let cv = _signedPow(cos(v), ev), sv = _signedPow(sin(v), ev)
                let cu = _signedPow(cos(u), eu), su = _signedPow(sin(u), eu)
                return [rx * cv * cu, ry * cv * su, rz * sv]
            }
            shouldOutput = true
        }
        return shouldOutput
    }
}

// MARK: - Klein Bottle

public class KleinBottleGeometryNode: BaseGeometryNode {
    public override class var name: String { "Klein Bottle Geometry" }
    public override class var nodeDescription: String { "Generates a Klein bottle — a non-orientable closed surface with no interior" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return [
            ("inputRadius",      ParameterPort(parameter: FloatParameter("Radius",      2.0,  .inputfield, "Overall scale of the bottle"))),
            ("inputTube",        ParameterPort(parameter: FloatParameter("Tube Radius",  0.55, .inputfield, "Radius of the tubular cross-section"))),
            ("inputResolutionU", ParameterPort(parameter: IntParameter("Resolution U", 192,   .inputfield, "Segments around the bottle axis"))),
            ("inputResolutionV", ParameterPort(parameter: IntParameter("Resolution V",  96,   .inputfield, "Segments around the tube cross-section"))),
        ] + ports
    }

    public var inputRadius:      ParameterPort<Float> { port(named: "inputRadius") }
    public var inputTube:        ParameterPort<Float> { port(named: "inputTube") }
    public var inputResolutionU: ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV: ParameterPort<Int>   { port(named: "inputResolutionV") }

    public override var geometry: ParametricGeometry { _geometry }
    private lazy var _geometry: ParametricGeometry = .kleinBottle(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool {
        let geo = self.geometry
        var shouldOutput = super.evaluate(geometry: geo, atTime: atTime)

        if inputRadius.valueDidChange || inputTube.valueDidChange ||
           inputResolutionU.valueDidChange || inputResolutionV.valueDidChange {
            let radius = inputRadius.value ?? 2.0
            let tube   = inputTube.value   ?? 0.55
            let resU   = Int32(inputResolutionU.value ?? 192)
            let resV   = Int32(inputResolutionV.value ?? 96)
            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = 0 ... (.pi * 2)
            geo.rangeV = 0 ... (.pi * 2)
            geo.generator = { u, v in
                let cu = cos(u), su = sin(u)
                let hu = u * 0.5
                let chu = cos(hu), shu = sin(hu)
                let sv = sin(v), s2v = sin(2 * v)
                let ring = radius + tube * (chu * sv - shu * s2v)
                let z = tube * (shu * sv + chu * s2v)
                return [ring * cu, ring * su, z]
            }
            shouldOutput = true
        }
        return shouldOutput
    }
}

// MARK: - Catenoid

public class CatenoidGeometryNode: BaseGeometryNode {
    public override class var name: String { "Catenoid Geometry" }
    public override class var nodeDescription: String { "Generates a catenoid — the minimal surface of revolution formed by a catenary" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return [
            ("inputRadius",      ParameterPort(parameter: FloatParameter("Radius",      0.75, .inputfield, "Radius of the waist (narrowest point)"))),
            ("inputHeight",      ParameterPort(parameter: FloatParameter("Height",       2.0,  .inputfield, "Total height of the surface"))),
            ("inputResolutionU", ParameterPort(parameter: IntParameter("Resolution U", 160,   .inputfield, "Segments around the axis"))),
            ("inputResolutionV", ParameterPort(parameter: IntParameter("Resolution V",  96,   .inputfield, "Segments along the height"))),
        ] + ports
    }

    public var inputRadius:      ParameterPort<Float> { port(named: "inputRadius") }
    public var inputHeight:      ParameterPort<Float> { port(named: "inputHeight") }
    public var inputResolutionU: ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV: ParameterPort<Int>   { port(named: "inputResolutionV") }

    public override var geometry: ParametricGeometry { _geometry }
    private lazy var _geometry: ParametricGeometry = .catenoid(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        if inputRadius.valueDidChange || inputHeight.valueDidChange ||
           inputResolutionU.valueDidChange || inputResolutionV.valueDidChange {
            let radius = inputRadius.value ?? 0.75
            let height = inputHeight.value ?? 2.0
            let resU   = Int32(inputResolutionU.value ?? 160)
            let resV   = Int32(inputResolutionV.value ?? 96)
            let halfH  = height * 0.5
            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = 0 ... (.pi * 2)
            geo.rangeV = -halfH ... halfH
            geo.generator = { u, v in
                let r = radius * cosh(v / max(radius, 0.0001))
                return [r * cos(u), r * sin(u), v]
            }
            shouldOutput = true
        }
        return shouldOutput
    }
}

// MARK: - Paraboloid

public class ParaboloidGeometryNode: BaseGeometryNode {
    public override class var name: String { "Paraboloid Geometry" }
    public override class var nodeDescription: String { "Generates an elliptic paraboloid — a bowl-shaped quadric surface" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return [
            ("inputRadiusX",     ParameterPort(parameter: FloatParameter("Radius X",    1.0, .inputfield, "Horizontal scale along the X axis"))),
            ("inputRadiusY",     ParameterPort(parameter: FloatParameter("Radius Y",    1.0, .inputfield, "Horizontal scale along the Y axis"))),
            ("inputHeight",      ParameterPort(parameter: FloatParameter("Height",       2.0, .inputfield, "Vertical scale of the paraboloid"))),
            ("inputResolutionU", ParameterPort(parameter: IntParameter("Resolution U", 160, .inputfield, "Segments around the axis"))),
            ("inputResolutionV", ParameterPort(parameter: IntParameter("Resolution V",  80, .inputfield, "Segments along the radial direction"))),
        ] + ports
    }

    public var inputRadiusX:     ParameterPort<Float> { port(named: "inputRadiusX") }
    public var inputRadiusY:     ParameterPort<Float> { port(named: "inputRadiusY") }
    public var inputHeight:      ParameterPort<Float> { port(named: "inputHeight") }
    public var inputResolutionU: ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV: ParameterPort<Int>   { port(named: "inputResolutionV") }

    public override var geometry: ParametricGeometry { _geometry }
    private lazy var _geometry: ParametricGeometry = .paraboloid(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        if inputRadiusX.valueDidChange || inputRadiusY.valueDidChange || inputHeight.valueDidChange ||
           inputResolutionU.valueDidChange || inputResolutionV.valueDidChange {
            let rx = inputRadiusX.value ?? 1.0
            let ry = inputRadiusY.value ?? 1.0
            let h  = inputHeight.value  ?? 2.0
            let resU = Int32(inputResolutionU.value ?? 160)
            let resV = Int32(inputResolutionV.value ?? 80)
            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = 0 ... (.pi * 2)
            geo.rangeV = 0 ... 1
            geo.generator = { u, v in [rx * v * cos(u), ry * v * sin(u), h * v * v] }
            shouldOutput = true
        }
        return shouldOutput
    }
}

// MARK: - Enneper Surface

public class EnneperSurfaceGeometryNode: BaseGeometryNode {
    public override class var name: String { "Enneper Surface Geometry" }
    public override class var nodeDescription: String { "Generates an Enneper surface — a self-intersecting minimal surface with cubic saddle geometry" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return [
            ("inputScale",       ParameterPort(parameter: FloatParameter("Scale",        0.35, .inputfield, "Uniform scale applied to the surface"))),
            ("inputExtent",      ParameterPort(parameter: FloatParameter("Extent",        2.25, .inputfield, "Parameter domain half-extent for both U and V"))),
            ("inputResolutionU", ParameterPort(parameter: IntParameter("Resolution U", 160,   .inputfield, "Segments along the U direction"))),
            ("inputResolutionV", ParameterPort(parameter: IntParameter("Resolution V", 160,   .inputfield, "Segments along the V direction"))),
        ] + ports
    }

    public var inputScale:       ParameterPort<Float> { port(named: "inputScale") }
    public var inputExtent:      ParameterPort<Float> { port(named: "inputExtent") }
    public var inputResolutionU: ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV: ParameterPort<Int>   { port(named: "inputResolutionV") }

    public override var geometry: ParametricGeometry { _geometry }
    private lazy var _geometry: ParametricGeometry = .enneperSurface(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        if inputScale.valueDidChange || inputExtent.valueDidChange ||
           inputResolutionU.valueDidChange || inputResolutionV.valueDidChange {
            let scale  = inputScale.value  ?? 0.35
            let extent = inputExtent.value ?? 2.25
            let resU   = Int32(inputResolutionU.value ?? 160)
            let resV   = Int32(inputResolutionV.value ?? 160)
            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = -extent ... extent
            geo.rangeV = -extent ... extent
            geo.generator = { u, v in
                let x = u - (u * u * u) / 3.0 + u * v * v
                let y = v - (v * v * v) / 3.0 + v * u * u
                let z = u * u - v * v
                return scale * simd_make_float3(x, y, z)
            }
            shouldOutput = true
        }
        return shouldOutput
    }
}

// MARK: - Pseudosphere

public class PseudosphereGeometryNode: BaseGeometryNode {
    public override class var name: String { "Pseudosphere Geometry" }
    public override class var nodeDescription: String { "Generates a pseudosphere — a surface of constant negative Gaussian curvature" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return [
            ("inputRadius",       ParameterPort(parameter: FloatParameter("Radius",        1.0, .inputfield, "Radius of the pseudosphere"))),
            ("inputHeightExtent", ParameterPort(parameter: FloatParameter("Height Extent",  3.0, .inputfield, "Half-height of the parameter domain along the axis"))),
            ("inputResolutionU",  ParameterPort(parameter: IntParameter("Resolution U",  192, .inputfield, "Segments around the axis"))),
            ("inputResolutionV",  ParameterPort(parameter: IntParameter("Resolution V",   96, .inputfield, "Segments along the height"))),
        ] + ports
    }

    public var inputRadius:       ParameterPort<Float> { port(named: "inputRadius") }
    public var inputHeightExtent: ParameterPort<Float> { port(named: "inputHeightExtent") }
    public var inputResolutionU:  ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV:  ParameterPort<Int>   { port(named: "inputResolutionV") }

    public override var geometry: ParametricGeometry { _geometry }
    private lazy var _geometry: ParametricGeometry = .pseudosphere(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        if inputRadius.valueDidChange || inputHeightExtent.valueDidChange ||
           inputResolutionU.valueDidChange || inputResolutionV.valueDidChange {
            let radius = inputRadius.value       ?? 1.0
            let extent = inputHeightExtent.value ?? 3.0
            let resU   = Int32(inputResolutionU.value ?? 192)
            let resV   = Int32(inputResolutionV.value ?? 96)
            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = 0 ... (.pi * 2)
            geo.rangeV = -extent ... extent
            geo.generator = { u, v in
                let sv = _sech(v)
                let z  = v - tanh(v)
                return radius * simd_make_float3(sv * cos(u), sv * sin(u), z)
            }
            shouldOutput = true
        }
        return shouldOutput
    }
}

// MARK: - Dupin Cyclide

public class DupinCyclideGeometryNode: BaseGeometryNode {
    public override class var name: String { "Dupin Cyclide Geometry" }
    public override class var nodeDescription: String { "Generates a Dupin cyclide — a family of surfaces related to tori via sphere inversion" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return [
            ("inputMajorRadius",    ParameterPort(parameter: FloatParameter("Major Radius",    1.5, .inputfield, "Major radius of the base torus before inversion"))),
            ("inputMinorRadius",    ParameterPort(parameter: FloatParameter("Minor Radius",    0.45, .inputfield, "Minor (tube) radius of the base torus before inversion"))),
            ("inputTorusOffset",    ParameterPort(parameter: FloatParameter("Torus Offset",    2.4,  .inputfield, "Translation offset applied to the torus before inversion"))),
            ("inputInversionRadius",ParameterPort(parameter: FloatParameter("Inversion Radius",1.0,  .inputfield, "Radius of the inversion sphere"))),
            ("inputResolutionU",    ParameterPort(parameter: IntParameter("Resolution U",    192, .inputfield, "Segments around the primary axis"))),
            ("inputResolutionV",    ParameterPort(parameter: IntParameter("Resolution V",     96, .inputfield, "Segments around the tube cross-section"))),
        ] + ports
    }

    public var inputMajorRadius:     ParameterPort<Float> { port(named: "inputMajorRadius") }
    public var inputMinorRadius:     ParameterPort<Float> { port(named: "inputMinorRadius") }
    public var inputTorusOffset:     ParameterPort<Float> { port(named: "inputTorusOffset") }
    public var inputInversionRadius: ParameterPort<Float> { port(named: "inputInversionRadius") }
    public var inputResolutionU:     ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV:     ParameterPort<Int>   { port(named: "inputResolutionV") }

    public override var geometry: ParametricGeometry { _geometry }
    private lazy var _geometry: ParametricGeometry = .dupinCyclide(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        if inputMajorRadius.valueDidChange || inputMinorRadius.valueDidChange ||
           inputTorusOffset.valueDidChange || inputInversionRadius.valueDidChange ||
           inputResolutionU.valueDidChange || inputResolutionV.valueDidChange {
            let major = inputMajorRadius.value     ?? 1.5
            let minor = inputMinorRadius.value     ?? 0.45
            let offset = inputTorusOffset.value    ?? 2.4
            let invR  = inputInversionRadius.value ?? 1.0
            let resU  = Int32(inputResolutionU.value ?? 192)
            let resV  = Int32(inputResolutionV.value ?? 96)
            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = 0 ... (.pi * 2)
            geo.rangeV = 0 ... (.pi * 2)
            geo.generator = { u, v in
                let ring = major + minor * cos(v)
                let pt = simd_make_float3(ring * cos(u) + offset, ring * sin(u), minor * sin(v))
                let lenSq = max(simd_length_squared(pt), 0.0001)
                return pt * ((invR * invR) / lenSq)
            }
            shouldOutput = true
        }
        return shouldOutput
    }
}

// MARK: - Roman Surface

public class RomanSurfaceGeometryNode: BaseGeometryNode {
    public override class var name: String { "Roman Surface Geometry" }
    public override class var nodeDescription: String { "Generates Steiner's Roman surface — a self-intersecting immersion of the real projective plane" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return [
            ("inputScale",       ParameterPort(parameter: FloatParameter("Scale",        2.0, .inputfield, "Uniform scale of the surface"))),
            ("inputResolutionU", ParameterPort(parameter: IntParameter("Resolution U", 160, .inputfield, "Segments around the U direction"))),
            ("inputResolutionV", ParameterPort(parameter: IntParameter("Resolution V",  96, .inputfield, "Segments around the V direction"))),
        ] + ports
    }

    public var inputScale:       ParameterPort<Float> { port(named: "inputScale") }
    public var inputResolutionU: ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV: ParameterPort<Int>   { port(named: "inputResolutionV") }

    public override var geometry: ParametricGeometry { _geometry }
    private lazy var _geometry: ParametricGeometry = .romanSurface(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        if inputScale.valueDidChange || inputResolutionU.valueDidChange || inputResolutionV.valueDidChange {
            let scale = inputScale.value ?? 2.0
            let resU  = Int32(inputResolutionU.value ?? 160)
            let resV  = Int32(inputResolutionV.value ?? 96)
            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = 0 ... (.pi * 2)
            geo.rangeV = (-.pi * 0.5) ... (.pi * 0.5)
            geo.generator = { u, v in
                let sx = cos(u) * cos(v), sy = sin(u) * cos(v), sz = sin(v)
                return scale * simd_make_float3(sy * sz, sz * sx, sx * sy)
            }
            shouldOutput = true
        }
        return shouldOutput
    }
}

// MARK: - Cross Cap

public class CrossCapGeometryNode: BaseGeometryNode {
    public override class var name: String { "Cross Cap Geometry" }
    public override class var nodeDescription: String { "Generates a cross-cap — another immersion of the real projective plane with two self-intersection lines" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return [
            ("inputScale",       ParameterPort(parameter: FloatParameter("Scale",        2.0, .inputfield, "Uniform scale of the surface"))),
            ("inputResolutionU", ParameterPort(parameter: IntParameter("Resolution U", 160, .inputfield, "Segments along the U direction"))),
            ("inputResolutionV", ParameterPort(parameter: IntParameter("Resolution V",  96, .inputfield, "Segments along the V direction"))),
        ] + ports
    }

    public var inputScale:       ParameterPort<Float> { port(named: "inputScale") }
    public var inputResolutionU: ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV: ParameterPort<Int>   { port(named: "inputResolutionV") }

    public override var geometry: ParametricGeometry { _geometry }
    private lazy var _geometry: ParametricGeometry = .crossCap(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        if inputScale.valueDidChange || inputResolutionU.valueDidChange || inputResolutionV.valueDidChange {
            let scale = inputScale.value ?? 2.0
            let resU  = Int32(inputResolutionU.value ?? 160)
            let resV  = Int32(inputResolutionV.value ?? 96)
            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = 0 ... .pi
            geo.rangeV = 0 ... (.pi * 2)
            geo.generator = { u, v in
                let x = sin(u) * sin(u) * sin(2 * v) * 0.5
                let y = sin(2 * u) * sin(v) * 0.5
                let z = sin(2 * u) * cos(v) * 0.5
                return scale * simd_make_float3(x, y, z)
            }
            shouldOutput = true
        }
        return shouldOutput
    }
}

// MARK: - Bour Surface

public class BourSurfaceGeometryNode: BaseGeometryNode {
    public override class var name: String { "Bour Surface Geometry" }
    public override class var nodeDescription: String { "Generates a Bour surface — a minimal surface discovered by Edmond Bour in 1862" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return [
            ("inputRadius",      ParameterPort(parameter: FloatParameter("Radius",      1.35, .inputfield, "Radial extent of the parameter domain"))),
            ("inputTurns",       ParameterPort(parameter: FloatParameter("Turns",        4.0,  .inputfield, "Number of turns (multiples of π) in the angular domain"))),
            ("inputScale",       ParameterPort(parameter: FloatParameter("Scale",        0.65, .inputfield, "Uniform scale applied to the output surface"))),
            ("inputResolutionU", ParameterPort(parameter: IntParameter("Resolution U", 192,   .inputfield, "Segments along the radial direction"))),
            ("inputResolutionV", ParameterPort(parameter: IntParameter("Resolution V",  96,   .inputfield, "Segments along the angular direction"))),
        ] + ports
    }

    public var inputRadius:      ParameterPort<Float> { port(named: "inputRadius") }
    public var inputTurns:       ParameterPort<Float> { port(named: "inputTurns") }
    public var inputScale:       ParameterPort<Float> { port(named: "inputScale") }
    public var inputResolutionU: ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV: ParameterPort<Int>   { port(named: "inputResolutionV") }

    public override var geometry: ParametricGeometry { _geometry }
    private lazy var _geometry: ParametricGeometry = .bourSurface(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        if inputRadius.valueDidChange || inputTurns.valueDidChange || inputScale.valueDidChange ||
           inputResolutionU.valueDidChange || inputResolutionV.valueDidChange {
            let radius = inputRadius.value ?? 1.35
            let turns  = inputTurns.value  ?? 4.0
            let scale  = inputScale.value  ?? 0.65
            let resU   = Int32(inputResolutionU.value ?? 192)
            let resV   = Int32(inputResolutionV.value ?? 96)
            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = 0 ... radius
            geo.rangeV = 0 ... (.pi * turns)
            geo.generator = { r, theta in
                let x = r * cos(theta) - 0.5 * r * r * cos(2 * theta)
                let y = -r * sin(theta) - 0.5 * r * r * sin(2 * theta)
                let z = (4.0 / 3.0) * pow(max(r, 0.0), 1.5) * cos(1.5 * theta)
                return scale * simd_make_float3(x, y, z)
            }
            shouldOutput = true
        }
        return shouldOutput
    }
}

// MARK: - Breather Surface

public class BreatherSurfaceGeometryNode: BaseGeometryNode {
    public override class var name: String { "Breather Surface Geometry" }
    public override class var nodeDescription: String { "Generates a breather surface — a pseudo-spherical surface related to solutions of the sine-Gordon equation" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return [
            ("inputParameterA",  ParameterPort(parameter: FloatParameter("Parameter A",    0.4,   .inputfield, "Shape parameter in (0, 1); values near 0 or 1 collapse the surface"))),
            ("inputRangeUMin",   ParameterPort(parameter: FloatParameter("Range U Min",   -14.0,  .inputfield, "Lower bound of the U parameter domain"))),
            ("inputRangeUMax",   ParameterPort(parameter: FloatParameter("Range U Max",    14.0,  .inputfield, "Upper bound of the U parameter domain"))),
            ("inputRangeVMin",   ParameterPort(parameter: FloatParameter("Range V Min",   -37.4,  .inputfield, "Lower bound of the V parameter domain"))),
            ("inputRangeVMax",   ParameterPort(parameter: FloatParameter("Range V Max",    37.4,  .inputfield, "Upper bound of the V parameter domain"))),
            ("inputScale",       ParameterPort(parameter: FloatParameter("Scale",            0.2,  .inputfield, "Uniform scale applied to the output surface"))),
            ("inputResolutionU", ParameterPort(parameter: IntParameter("Resolution U",    192,    .inputfield, "Segments along the U direction"))),
            ("inputResolutionV", ParameterPort(parameter: IntParameter("Resolution V",    160,    .inputfield, "Segments along the V direction"))),
        ] + ports
    }

    public var inputParameterA:  ParameterPort<Float> { port(named: "inputParameterA") }
    public var inputRangeUMin:   ParameterPort<Float> { port(named: "inputRangeUMin") }
    public var inputRangeUMax:   ParameterPort<Float> { port(named: "inputRangeUMax") }
    public var inputRangeVMin:   ParameterPort<Float> { port(named: "inputRangeVMin") }
    public var inputRangeVMax:   ParameterPort<Float> { port(named: "inputRangeVMax") }
    public var inputScale:       ParameterPort<Float> { port(named: "inputScale") }
    public var inputResolutionU: ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV: ParameterPort<Int>   { port(named: "inputResolutionV") }

    public override var geometry: ParametricGeometry { _geometry }
    private lazy var _geometry: ParametricGeometry = .breatherSurface(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        if inputParameterA.valueDidChange || inputRangeUMin.valueDidChange || inputRangeUMax.valueDidChange ||
           inputRangeVMin.valueDidChange  || inputRangeVMax.valueDidChange  || inputScale.valueDidChange ||
           inputResolutionU.valueDidChange || inputResolutionV.valueDidChange {
            let rawA   = inputParameterA.value ?? 0.4
            let a      = simd_clamp(rawA, 0.05, 0.95)
            let b      = sqrt(max(1.0 - a * a, 0.0001))
            let uMin   = inputRangeUMin.value ?? -14.0
            let uMax   = inputRangeUMax.value ??  14.0
            let vMin   = inputRangeVMin.value ?? -37.4
            let vMax   = inputRangeVMax.value ??  37.4
            let scale  = inputScale.value ?? 0.2
            let resU   = Int32(inputResolutionU.value ?? 192)
            let resV   = Int32(inputResolutionV.value ?? 160)
            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = min(uMin, uMax) ... max(uMin, uMax)
            geo.rangeV = min(vMin, vMax) ... max(vMin, vMax)
            geo.generator = { u, v in
                let au = a * u
                let cau = cosh(au), sau = sinh(au)
                let sbv = sin(b * v), cbv = cos(b * v)
                let w0 = (1.0 - a * a) * cau * cau
                let w1 = a * a * sbv * sbv
                let w  = max(a * (w0 + w1), 0.0001)
                let x  = -u + 2.0 * (1.0 - a * a) * cau * sau / w
                let y  = 2.0 * b * cau * (-b * cos(v) * cbv - sin(v) * sbv) / w
                let z  = 2.0 * b * cau * (-b * sin(v) * cbv + cos(v) * sbv) / w
                return scale * simd_make_float3(x, y, z)
            }
            shouldOutput = true
        }
        return shouldOutput
    }
}

// MARK: - Dini Surface

public class DiniSurfaceGeometryNode: BaseGeometryNode {
    public override class var name: String { "Dini Surface Geometry" }
    public override class var nodeDescription: String { "Generates a Dini surface — a pseudo-spherical surface that looks like a twisted trumpet" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return [
            ("inputRadius",      ParameterPort(parameter: FloatParameter("Radius",       1.0,           .inputfield, "Overall radius of the surface"))),
            ("inputTwist",       ParameterPort(parameter: FloatParameter("Twist",         0.2,           .inputfield, "Axial twist applied per unit of U"))),
            ("inputRangeUMin",   ParameterPort(parameter: FloatParameter("Range U Min",   0.0,           .inputfield, "Lower bound of the U parameter domain"))),
            ("inputRangeUMax",   ParameterPort(parameter: FloatParameter("Range U Max",   .pi * 4.0,     .inputfield, "Upper bound of the U parameter domain"))),
            ("inputRangeVMin",   ParameterPort(parameter: FloatParameter("Range V Min",   0.08,          .inputfield, "Lower bound of the V parameter domain (avoid 0 singularity)"))),
            ("inputRangeVMax",   ParameterPort(parameter: FloatParameter("Range V Max",   1.45,          .inputfield, "Upper bound of the V parameter domain (avoid π singularity)"))),
            ("inputResolutionU", ParameterPort(parameter: IntParameter("Resolution U", 192,             .inputfield, "Segments along the U direction"))),
            ("inputResolutionV", ParameterPort(parameter: IntParameter("Resolution V",  96,             .inputfield, "Segments along the V direction"))),
        ] + ports
    }

    public var inputRadius:      ParameterPort<Float> { port(named: "inputRadius") }
    public var inputTwist:       ParameterPort<Float> { port(named: "inputTwist") }
    public var inputRangeUMin:   ParameterPort<Float> { port(named: "inputRangeUMin") }
    public var inputRangeUMax:   ParameterPort<Float> { port(named: "inputRangeUMax") }
    public var inputRangeVMin:   ParameterPort<Float> { port(named: "inputRangeVMin") }
    public var inputRangeVMax:   ParameterPort<Float> { port(named: "inputRangeVMax") }
    public var inputResolutionU: ParameterPort<Int>   { port(named: "inputResolutionU") }
    public var inputResolutionV: ParameterPort<Int>   { port(named: "inputResolutionV") }

    public override var geometry: ParametricGeometry { _geometry }
    private lazy var _geometry: ParametricGeometry = .diniSurface(context: self.context)

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool {
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)
        let geo = self.geometry

        if inputRadius.valueDidChange || inputTwist.valueDidChange ||
           inputRangeUMin.valueDidChange || inputRangeUMax.valueDidChange ||
           inputRangeVMin.valueDidChange || inputRangeVMax.valueDidChange ||
           inputResolutionU.valueDidChange || inputResolutionV.valueDidChange {
            let radius = inputRadius.value    ?? 1.0
            let twist  = inputTwist.value     ?? 0.2
            let uMin   = inputRangeUMin.value ?? 0.0
            let uMax   = inputRangeUMax.value ?? (.pi * 4.0)
            let vMin   = inputRangeVMin.value ?? 0.08
            let vMax   = inputRangeVMax.value ?? 1.45
            let resU   = Int32(inputResolutionU.value ?? 192)
            let resV   = Int32(inputResolutionV.value ?? 96)
            geo.resolution = simd_int2(resU, resV)
            geo.rangeU = min(uMin, uMax) ... max(uMin, uMax)
            geo.rangeV = min(vMin, vMax) ... max(vMin, vMax)
            geo.generator = { u, v in
                let safeV = simd_clamp(v, 0.0001, .pi - 0.0001)
                let x = radius * cos(u) * sin(safeV)
                let y = radius * sin(u) * sin(safeV)
                let z = radius * (cos(safeV) + log(tan(safeV * 0.5))) + twist * u
                return simd_make_float3(x, y, z)
            }
            shouldOutput = true
        }
        return shouldOutput
    }
}

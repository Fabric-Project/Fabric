//
//  ColorTweenNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

// MARK: - Oklab Conversion (linear sRGB ↔ Oklab)

private func linearSRGBToOklab(_ c: simd_float3) -> simd_float3
{
    // Linear sRGB → LMS (cone response)
    let l = 0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z
    let m = 0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z
    let s = 0.0883024619 * c.x + 0.2220049073 * c.y + 0.6896926158 * c.z

    // Cube root (perceptual nonlinearity)
    let l_ = cbrtf(l)
    let m_ = cbrtf(m)
    let s_ = cbrtf(s)

    // LMS → Oklab
    return simd_float3(
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    )
}

private func oklabToLinearSRGB(_ lab: simd_float3) -> simd_float3
{
    // Oklab → LMS (cube root space)
    let l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
    let m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
    let s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z

    // Undo cube root
    let l = l_ * l_ * l_
    let m = m_ * m_ * m_
    let s = s_ * s_ * s_

    // LMS → linear sRGB
    return simd_float3(
         4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    )
}

// MARK: - Color Tween Node

public class ColorTweenNode : Node
{
    override public class var name:String { "Color Tween" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Color) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Tween toward a target colour over a duration using an easing curve, interpolated in Oklab perceptual colour space" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputTarget", ParameterPort(parameter: Float4Parameter("Target", simd_float4(0, 0, 0, 1), .colorpicker, "Target colour (RGBA)"))),
            ("inputDuration", ParameterPort(parameter: FloatParameter("Duration", 1.0, .inputfield, "Tween duration in seconds"))),
            ("inputEasing", ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing curve"))),
            ("outputColor", NodePort<simd_float4>(name: "Color", kind: .Outlet, description: "Current tweened colour (RGBA)")),
            ("outputProgress", NodePort<Float>(name: "Progress", kind: .Outlet, description: "Tween progress (0-1)")),
        ]
    }

    // Port Proxies
    public var inputTarget:ParameterPort<simd_float4> { port(named: "inputTarget") }
    public var inputDuration:ParameterPort<Float> { port(named: "inputDuration") }
    public var inputEasing:ParameterPort<String> { port(named: "inputEasing") }
    public var outputColor:NodePort<simd_float4> { port(named: "outputColor") }
    public var outputProgress:NodePort<Float> { port(named: "outputProgress") }

    // Tween state
    private var tween = TweenState()
    private var fromLab:simd_float3 = .zero
    private var toLab:simd_float3 = .zero
    private var fromAlpha:Float = 1.0
    private var toAlpha:Float = 1.0
    private var currentOutput:simd_float4 = simd_float4(0, 0, 0, 1)

    override public func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let time = context.timing.time

        // Detect target change → snap-retarget
        if self.inputTarget.valueDidChange,
           let newTarget = self.inputTarget.value
        {
            let newLab = linearSRGBToOklab(simd_float3(newTarget.x, newTarget.y, newTarget.z))
            let newAlpha = newTarget.w

            if !tween.initialized
            {
                toLab = newLab
                toAlpha = newAlpha
                currentOutput = newTarget
                tween.initialized = true
            }
            else if newTarget != currentOutput
            {
                // Snap-retarget: current output becomes the new start
                fromLab = linearSRGBToOklab(simd_float3(currentOutput.x, currentOutput.y, currentOutput.z))
                fromAlpha = currentOutput.w
                toLab = newLab
                toAlpha = newAlpha
                tween.start(at: time)
            }
        }

        // Drive the tween
        if let duration = self.inputDuration.value,
           let easingName = self.inputEasing.value,
           let result = tween.update(time: time, duration: duration, easingName: easingName)
        {
            let t = result.easedT

            // Lerp in Oklab space
            let lab = fromLab + (toLab - fromLab) * t
            let alpha = fromAlpha + (toAlpha - fromAlpha) * t

            // Convert back to linear sRGB
            let rgb = oklabToLinearSRGB(lab)
            currentOutput = simd_float4(rgb.x, rgb.y, rgb.z, alpha)

            if result.t >= 1.0
            {
                // Ensure we land exactly on target (avoid round-trip precision drift)
                let finalRGB = oklabToLinearSRGB(toLab)
                currentOutput = simd_float4(finalRGB.x, finalRGB.y, finalRGB.z, toAlpha)
            }

            self.outputColor.send(currentOutput)
            self.outputProgress.send(result.t)
        }
        else if tween.initialized
        {
            self.outputColor.send(currentOutput)
            self.outputProgress.send(tween.tweening ? 0.0 : 1.0)
        }
    }
}

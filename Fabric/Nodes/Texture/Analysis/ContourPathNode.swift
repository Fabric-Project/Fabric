//
//  ContourPathNode.swift
//  Fabric
//
//  GPU Marching Squares → single contour (ordered points)
//

import Foundation
import Metal
import Satin
import simd

public final class ContourPathNode: Node {
    // MARK: - UI & Type
    override public class var name: String { "Contour Path" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Converts Mask Contours to Path Data" }

    // MARK: - Ports (Registry)
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            // Inputs
            ("inputMask", NodePort<EquatableTexture>(name: "Mask", kind: .Inlet)),

            // Params
            ("inputIso",  ParameterPort(parameter: FloatParameter("Iso Level", 0.5))),
            ("inputMaxSegments", ParameterPort(parameter: IntParameter("Max Segments", 1_000_000))),
            ("inputJoinEpsilon", ParameterPort(parameter: FloatParameter("Join Epsilon (px)", 1.0))),

            // Output (arbitrary payload for now)
            ("outputContour", NodePort<ContiguousArray<simd_float2>>(name: "Contour (points)", kind: .Outlet)),
        ]
    }

    // Proxies
    public var inputMask: NodePort<EquatableTexture> { port(named: "inputMask") }
    public var inputIso:  ParameterPort<Float>       { port(named: "inputIso") }
    public var inputMaxSegments: ParameterPort<Int>  { port(named: "inputMaxSegments") }
    public var inputJoinEpsilon: ParameterPort<Float> { port(named: "inputJoinEpsilon") }

    public var outputContour: NodePort<ContiguousArray<simd_float2>>  { port(named: "outputContour") }

    // MARK: - Satin Compute
    private var processor: TextureComputeProcessor?
    private var segmentsBuffer: MTLBuffer?
    private var counterBuffer: MTLBuffer?

    // For quick reuse
    private var lastAllocatedFor: (w: Int, h: Int, maxSegs: Int) = (0, 0, 0)

    // MARK: - Lifecycle
    required public init(context: Context) {
        super.init(context: context)
        setupProcessor(context: context)
    }

    required public init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
        setupProcessor(context: self.context)
    }

    // MARK: - Setup
    private func setupProcessor(context: Context) {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(
            forResource: "MarchingSquares",
            withExtension: "metal",
            subdirectory: "Shaders/Compute"
        ) else {
            print("ContourPathNode: Missing Shaders/Compute/MarchingSquares.metal")
            return
        }

        let proc = TextureComputeProcessor(device: context.device,
                                           pipelineURL: url,
                                           live: false)
        self.processor = proc
    }

    // MARK: - Execute
    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        guard
            inputMask.valueDidChange,
            let proc = processor,
            let inTex = inputMask.value?.texture,
            let device = context.graphRenderer?.context?.device
        else {
            outputContour.send(nil)
            return
        }

        // Bind input for sizing/dispatch
        proc.set(inTex, index: .Custom0)

        // Ensure buffers sized for this frame
        let maxSegs = max(1, inputMaxSegments.value ?? 1_000_000)
        ensureBuffers(device: device, width: inTex.width, height: inTex.height, maxSegments: maxSegs)

        // Bind buffers
        if let seg = segmentsBuffer { proc.set(seg, index: .Custom0) }   // segments
        if let ctr = counterBuffer  { proc.set(ctr, index: .Custom1) }   // atomic counter

        // Push uniforms
        proc.set("Iso", inputIso.value ?? 0.5)

        // Clear the counter to zero before compute (tiny inline reset)
        zeroCounter(commandBuffer: commandBuffer)

        // Dispatch the compute pass
        proc.update(commandBuffer)

        // Read back & stitch to a single ordered contour
        let epsilon = inputJoinEpsilon.value ?? 1.0
        let points = readAndBuildContour(device: device,
                                         commandBuffer: commandBuffer,
                                         width: inTex.width,
                                         height: inTex.height,
                                         epsilon: epsilon)

        // Emit
        outputContour.send( points )
    }

    // MARK: - Buffers
    private func ensureBuffers(device: MTLDevice, width: Int, height: Int, maxSegments: Int) {
        // Worst case per-cell up to 2 segments → user-specified cap controls
        let needRealloc =
            segmentsBuffer == nil ||
            counterBuffer  == nil ||
            lastAllocatedFor.w != width ||
            lastAllocatedFor.h != height ||
            lastAllocatedFor.maxSegs != maxSegments

        if !needRealloc { return }

        // Segments are float4: (x0, y0, x1, y1)
        let segmentStride = MemoryLayout<simd_float4>.stride
        let segLen = segmentStride * maxSegments

        segmentsBuffer = device.makeBuffer(length: segLen, options: .storageModeShared)
        segmentsBuffer?.label = "ContourSegments"

        // Counter: single uint32
        counterBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
        counterBuffer?.label = "ContourCounter"

        lastAllocatedFor = (width, height, maxSegments)
    }

    private func zeroCounter(commandBuffer: MTLCommandBuffer) {
        guard let ptr = counterBuffer?.contents() else { return }
        ptr.assumingMemoryBound(to: UInt32.self).pointee = 0
        // (Shared memory: CPU write is visible to GPU; if you prefer strictness, add a blitFence or small reset kernel.)
    }

    // MARK: - Readback & Stitching
    private func readAndBuildContour(device: MTLDevice,
                                     commandBuffer: MTLCommandBuffer,
                                     width: Int, height: Int,
                                     epsilon: Float) -> ContiguousArray<simd_float2> {
        guard
            let segBuf = segmentsBuffer,
            let ctrBuf = counterBuffer
        else { return [] }

        // Sync point (shared mode is typically fine; if needed, add a blit encoder barrier)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Count
        let count = ctrBuf.contents().assumingMemoryBound(to: UInt32.self).pointee
        let segCount = Int(count)

        if segCount == 0 { return [] }

        // Copy segments
        let segPtr = segBuf.contents().bindMemory(to: simd_float4.self, capacity: segCount)
        var segments: [simd_float4] = []
        segments.reserveCapacity(segCount)
        for i in 0..<segCount {
            segments.append(segPtr[i])
        }

        // Build an ordered single contour by chaining endpoints (greedy-ish; works well for single closed loop)
        return stitchSegmentsToPath(segments: segments, eps: epsilon)
    }

    private func stitchSegmentsToPath(segments: [simd_float4], eps: Float) -> ContiguousArray<simd_float2> {
        // Map endpoints → adjacency
        struct End: Hashable { let x: Int; let y: Int }
        func q(_ v: simd_float2) -> End { End(x: Int(roundf(v.x/eps)), y: Int(roundf(v.y/eps))) }

        var adj: [End: [simd_float2]] = [:]
        adj.reserveCapacity(segments.count * 2)

        for s in segments {
            let a = simd_float2(s.x, s.y)
            let b = simd_float2(s.z, s.w)
            adj[q(a), default: []].append(b)
            adj[q(b), default: []].append(a)
        }

        // Start at an arbitrary endpoint, walk neighbors picking the next unused
        var used = Set<End>()
        var path: [simd_float2] = []
        if let start = segments.first {
            var cur = simd_float2(start.x, start.y)
            let qStart = q(cur)
            path.append(cur)
            used.insert(qStart)

            // Walk until we close (heuristic cap)
            let cap = segments.count * 2 + 4
            for _ in 0..<cap {
                let key = q(cur)
                guard let nbrs = adj[key], !nbrs.isEmpty else { break }

                // Pick a neighbor that isn’t the immediate predecessor if possible
                var next: simd_float2? = nil
                if path.count >= 2 {
                    let prev = path[path.count-2]
                    next = nbrs.min(by: { distance($0, cur) < distance($1, cur) })
                    if let n = next, approxEqual(n, prev, eps: eps) {
                        // try second best
                        next = nbrs.dropFirst().first
                    }
                } else {
                    next = nbrs.min(by: { distance($0, cur) < distance($1, cur) })
                }

                guard let n = next else { break }
                if used.contains(q(n)) && approxEqual(n, path.first!, eps: eps) {
                    // closed loop
                    break
                }
                path.append(n)
                used.insert(q(n))
                cur = n
            }
        }

        return ContiguousArray(path)
    }

    private func approxEqual(_ a: simd_float2, _ b: simd_float2, eps: Float) -> Bool {
        return abs(a.x - b.x) <= eps && abs(a.y - b.y) <= eps
    }
}

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

    static let kMaxSegments: Int = 5_000_000
    
    // MARK: - Ports (Registry)
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            // Inputs
            ("inputMask", NodePort<FabricImage>(name: "Mask", kind: .Inlet, description: "Grayscale mask image to extract contours from")),

            // Params
            ("inputIso",  ParameterPort(parameter: FloatParameter("Iso Level", 0.5, .inputfield, "Threshold value for edge detection (0-1)"))),
            ("inputMaxSegments", ParameterPort(parameter: IntParameter("Max Segments", Self.kMaxSegments, .inputfield, "Maximum number of contour segments to generate"))),
            ("inputJoinEpsilon", ParameterPort(parameter: FloatParameter("Join Epsilon (px)", 1.0, .inputfield, "Pixel tolerance for joining contour endpoints"))),

            ("inputResultDelivery", ParameterPort(parameter: StringParameter(
                "Result Timing", GPUResultDeliveryMode.sync.rawValue,
                GPUResultDeliveryMode.allCases.map(\.rawValue), .dropdown,
                "Same Frame waits for GPU results; Next Frame publishes completed results on a later matching execution"))),

            // Output (arbitrary payload for now)
            ("outputContour", NodePort<ContiguousArray<simd_float2>>(name: "Contour (points)", kind: .Outlet, description: "Ordered contour points in pixel coordinates")),
        ]
    }

    // Proxies
    public var inputMask: NodePort<FabricImage> { port(named: "inputMask") }
    public var inputIso:  ParameterPort<Float>       { port(named: "inputIso") }
    public var inputMaxSegments: ParameterPort<Int>  { port(named: "inputMaxSegments") }
    public var inputJoinEpsilon: ParameterPort<Float> { port(named: "inputJoinEpsilon") }

    public var outputContour: NodePort<ContiguousArray<simd_float2>>  { port(named: "outputContour") }

    public var inputResultDelivery: ParameterPort<String> { port(named: "inputResultDelivery") }
    public var resultDeliveryMode: GPUResultDeliveryMode {
        get { GPUResultDeliveryMode(rawValue: inputResultDelivery.value ?? "") ?? .sync }
        set { inputResultDelivery.value = newValue.rawValue }
    }

    // MARK: - Satin Compute
    private var processor: TextureComputeProcessor?
    private var previousDeliveryMode: GPUResultDeliveryMode?

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
        // Bundle(for:) cannot see SPM package resources; Bundle.module owns them.
        guard let url = Bundle.module.url(forResource: "MarchingSquares", withExtension: "metal", subdirectory: "Compute")

        else {
            print("ContourPathNode: Missing Shaders/Compute/MarchingSquares.metal")
            return
        }

        let proc = TextureComputeProcessor(device: context.device,
                                           pipelineURL: url,
                                           live: false)
        // Discover the reflected uniform layout before assigning invocation-specific values.
        proc.update()
        self.processor = proc
    }

    override public func stopExecution(renderer: GraphRenderer) throws {
        previousDeliveryMode = nil
        try super.stopExecution(renderer: renderer)
    }

    // MARK: - Execute
    public override func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        let mode = resultDeliveryMode
        let modeChanged = previousDeliveryMode != mode
        if modeChanged {
            cancelPendingCompletions()
            previousDeliveryMode = mode
        }
        guard let image = inputMask.value else {
            cancelPendingCompletions()
            outputContour.send(nil)
            return
        }
        guard modeChanged || inputMask.valueDidChange || inputIso.valueDidChange
                || inputMaxSegments.valueDidChange || inputJoinEpsilon.valueDidChange else { return }
        guard let processor else {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Contour compute processor is unavailable")
        }
        let device = context.device
        let requested = max(1, inputMaxSegments.value ?? Self.kMaxSegments)
        let maximumCells = max(0, image.texture.width - 1).multipliedReportingOverflow(by: max(0, image.texture.height - 1))
        let cellLimit = maximumCells.overflow ? Int.max : maximumCells.partialValue
        let doubledCells = cellLimit.multipliedReportingOverflow(by: 2)
        let geometryLimit = doubledCells.overflow ? Int.max : max(1, doubledCells.partialValue)
        let maxSegments = min(requested, geometryLimit, Int(UInt32.max), device.maxBufferLength / MemoryLayout<simd_float4>.stride)
        guard maxSegments > 0,
              let segments = device.makeBuffer(length: maxSegments * MemoryLayout<simd_float4>.stride, options: .storageModeShared),
              let counter = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared) else {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Unable to allocate contour readback buffers")
        }
        segments.label = "Contour Segments"
        counter.label = "Contour Counter"
        // Only the counter needs clearing: the GPU writes every segment below its returned count.
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Unable to reset contour counter")
        }
        blit.fill(buffer: counter, range: 0..<MemoryLayout<UInt32>.stride, value: 0)
        blit.endEncoding()
        processor.set(image.texture, index: .Custom0)
        processor.set(segments, index: .Custom0)
        processor.set(counter, index: .Custom1)
        processor.set("Iso", inputIso.value ?? 0.5)
        processor.set("MaxSegments", UInt32(maxSegments))
        guard let compute = commandBuffer.makeComputeCommandEncoder() else {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Unable to encode contour analysis")
        }
        do {
            defer { compute.endEncoding() }
            try processor.update(compute)
        }
        let requestedEpsilon = inputJoinEpsilon.value ?? 1
        let epsilon = requestedEpsilon.isFinite && requestedEpsilon > 0 ? requestedEpsilon : 0.25
        // Capture the orientation and dimensions now; FabricImage metadata remains mutable.
        let transform = image.textureTransform
        let storageSize = simd_float2(Float(image.texture.width), Float(image.texture.height))
        let presentationSize = simd_float2(Float(image.presentationSize.width), Float(image.presentationSize.height))
        let output = outputContour
        let deliver = {
            let count = min(Int(counter.contents().load(as: UInt32.self)), maxSegments)
            let pointer = segments.contents().assumingMemoryBound(to: simd_float4.self)
            let inverse = simd_inverse(transform)
            func point(_ stored: simd_float2) -> simd_float2 {
                let uv = stored / storageSize
                let canonical = inverse * simd_float4(uv.x, uv.y, 0, 1)
                return simd_float2(canonical.x, canonical.y) * presentationSize
            }
            var values: [simd_float4] = []
            values.reserveCapacity(count)
            for index in 0..<count {
                let segment = pointer[index]
                let start = point(simd_float2(segment.x, segment.y))
                let end = point(simd_float2(segment.z, segment.w))
                values.append(simd_float4(start.x, start.y, end.x, end.y))
            }
            output.send(Self.stitchSegments(values, snapPx: max(epsilon, 0.0001)))
        }
        if mode == .sync {
            try renderer.waitForGPUResults(commandBuffer: commandBuffer)
            deliver()
        } else {
            try commandBuffer.addCompletion(deliver)
        }
    }

    @inline(__always)
    private static func isFinite(_ p: simd_float2) -> Bool { p.x.isFinite && p.y.isFinite }

    public func stitchSegmentsToPath(segments: [simd_float4], snapPx: Float = 0.25) -> ContiguousArray<simd_float2> {
        Self.stitchSegments(segments, snapPx: snapPx)
    }

    private static func stitchSegments(_ segments: [simd_float4], snapPx: Float) -> ContiguousArray<simd_float2> {

        // ---- keys & helpers ----
        struct IntKey: Hashable, Comparable
        {
            let x: Int32
            let y: Int32
            static func < (l: IntKey, r: IntKey) -> Bool
            {
                (l.x, l.y) < (r.x, r.y)
            }
        }
        
        struct FloatKey: Hashable, Comparable
        {
            let x: Float
            let y: Float
            static func < (l: FloatKey, r: FloatKey) -> Bool
            {
                (l.x, l.y) < (r.x, r.y)
            }
        }
        
        typealias Key = IntKey
        
        @inline(__always) func intKey(for p: simd_float2) -> IntKey {
            IntKey(x: Int32(lrintf(p.x / snapPx)), y: Int32(lrintf(p.y / snapPx)))
        }
        
        @inline(__always) func floatKey(for p: simd_float2) -> FloatKey {
            FloatKey(x: p.x , y: p.y )
        }

        // representative (average) position per snapped key
        var repPos: [Key: simd_float2] = [:]
        var repCnt: [Key: Int] = [:]
        @inline(__always) func addRep(_ k: Key, _ p: simd_float2) {
            if let cur = repPos[k] {
                repPos[k] = cur + p
                repCnt[k]! += 1
            } else {
                repPos[k] = p
                repCnt[k] = 1
            }
        }

        // undirected canonical edge
        struct Edge: Hashable { let a: Key, b: Key }
        @inline(__always) func canon(_ k0: Key, _ k1: Key) -> Edge {
            (k0 < k1) ? Edge(a: k0, b: k1) : Edge(a: k1, b: k0)
        }

        // ---- build deduped edges & reps ----
        var edgeSet = Set<Edge>()
        edgeSet.reserveCapacity(segments.count)

        for s in segments {
            let a = simd_float2(s.x, s.y)
            let b = simd_float2(s.z, s.w)
            guard isFinite(a), isFinite(b) else { continue }
            let ka = intKey(for: a), kb = intKey(for: b)
            guard ka != kb else { continue } // zero-length after snap
            edgeSet.insert(canon(ka, kb))
            addRep(ka, a)
            addRep(kb, b)
        }

        guard !edgeSet.isEmpty else { return [] }

        // finalize average positions
        for (k, n) in repCnt { repPos[k]! /= Float(n) }

        // adjacency (undirected)
        var adj: [Key: [Key]] = [:]
        adj.reserveCapacity(repPos.count)
        for e in edgeSet {
            adj[e.a, default: []].append(e.b)
            adj[e.b, default: []].append(e.a)
        }

        // directed edge type for consumption
        struct DE: Hashable { let u: Key, v: Key }

        // initialize all directed edges as "unused"
        var unused = Set<DE>()
        unused.reserveCapacity(edgeSet.count * 2)
        for e in edgeSet { unused.insert(.init(u: e.a, v: e.b)); unused.insert(.init(u: e.b, v: e.a)) }

        @inline(__always)
        func perimeter(_ loop: [Key]) -> Float {
            guard loop.count > 1 else { return 0 }
            var p: Float = 0
            for i in 0..<loop.count {
                let a = repPos[loop[i]]!, b = repPos[loop[(i+1) % loop.count]]!
                p += simd_length(a - b)
            }
            return p
        }

        // choose the next neighbor by smallest left-turn angle (stay on boundary)
        func nextByAngle(from u: Key, to v: Key, nbrs: [Key]) -> Key?
        {
            let p = repPos[u]!, q = repPos[v]!
            let dir = simd_normalize(q - p)
            var bestKey: Key? = nil
            var bestDot: Float = -Float.greatestFiniteMagnitude
            var bestLeft: Float = -1

            for w in nbrs where w != u
            {
                // must have unused directed edge v->w
                if !unused.contains(.init(u: v, v: w)) { continue }
                let a = repPos[w]! - q
                let len = simd_length(a)
                if len <= 0 { continue }
                let nd = a / len
                let dot = simd_dot(dir, nd)
                let cross = dir.x * nd.y - dir.y * nd.x // >0 means left turn

                // prefer left turns; break ties with larger dot (smaller angle)
                let leftFlag: Float = (cross > 0) ? 1 : 0
                if leftFlag > bestLeft || (leftFlag == bestLeft && dot > bestDot) {
                    bestLeft = leftFlag
                    bestDot = dot
                    bestKey = w
                }
            }
            return bestKey
        }

        // ---- extract all loops, pick the largest ----
        struct Loop
        {
            var keys:[Key]
            var perimieter:Float
        }
        
        var loops: [Loop] = []
        let capPerLoop = edgeSet.count * 2 + 8

        while let startDE = unused.first {
            var loop: [Key] = [startDE.u, startDE.v]
            unused.remove(startDE)

            var u = startDE.u
            var v = startDE.v
            var perimiter: Float = 0

            for _ in 0..<capPerLoop {
                guard let nbrs = adj[v], !nbrs.isEmpty else { break }
                guard let w = nextByAngle(from: u, to: v, nbrs: nbrs) else { break }

                // consume v->w
                let dew = DE(u: v, v: w)
                if (unused.remove(dew) == nil) { break }

                u = v
                v = w

                if v == loop.first! {
                    // closed
                    break
                }
                
                perimiter += simd_distance(repPos[u]!, repPos[v]!)
                loop.append(v)
            }
            
            let l = Loop(keys: loop, perimieter: perimiter)

            if loop.count > 2 { loops.append(l) }
        }

        guard let best = loops.max(by: { $0.perimieter < $1.perimieter }) else { return [] }
//        guard let best = loops.first else { return [] }
        
        // map to positions; drop consecutive near-duplicates
        var out: [simd_float2] = []
        out.reserveCapacity(best.keys.count)
        let dupThresh2 = (snapPx * 0.5) * (snapPx * 0.5)
        for k in best.keys {
            let p = repPos[k]! // average of raw endpoints (unsnapped)
            if let last = out.last, simd_length_squared(p - last) < dupThresh2 { continue }
            out.append(p)
        }

        // CCW winding (optional)
        if out.count >= 3 {
            var area: Float = 0
            for i in 0..<out.count {
                let a = out[i], b = out[(i+1) % out.count]
                area += a.x*b.y - b.x*a.y
            }
            if area < 0 { out.reverse() }
        }

        return ContiguousArray(out)
    }

    
//    @inline(__always)
//    private func finite(_ v: simd_float2) -> Bool { v.x.isFinite && v.y.isFinite }
//
//    @inline(__always)
//    private func inBounds(_ v: simd_float2, _ w: Int, _ h: Int, pad: Float = 2.0) -> Bool {
//        v.x >= -pad && v.y >= -pad && v.x <= Float(w)+pad && v.y <= Float(h)+pad
//    }
//
//    @inline(__always)
//    private static func isFinite(_ p: simd_float2) -> Bool { p.x.isFinite && p.y.isFinite }
//
//    /// Build one closed contour from unordered marching-squares segments.
//    /// - Parameters:
//    ///   - segments: float4(x0,y0,x1,y1) from GPU
//    ///   - snapPx: lattice step in pixels (0.25–0.5 is good)
//    /// - Returns: ordered points around the contour (pixel space)
//    func stitchSegmentsToPath(
//        segments: [simd_float4],
//        snapPx: Float = 0.25
//    ) -> ContiguousArray<simd_float2> {
//
//        // ---- 1) Snap to a pixel lattice (stable keys) ----
//        struct Key: Hashable { let x: Int32, y: Int32 }
//        @inline(__always) func key(for p: simd_float2) -> Key {
//            Key(x: Int32(lrintf(p.x / snapPx)), y: Int32(lrintf(p.y / snapPx)))
//        }
//        
//        // representative position for a key (avg of all snapped samples)
//        var repPos: [Key: simd_float2] = [:]
//        var repCnt: [Key: Int] = [:]
//        @inline(__always) func addRep(_ k: Key, _ p: simd_float2) {
//            repPos[k, default: .zero] += p
//            repCnt[k, default: 0] += 1
//        }
//
//        // ---- 2) Dedupe segments (unordered edge) ----
//        struct Edge: Hashable { let a: Key, b: Key } // canonical (a <= b)
//        func canon(_ k0: Key, _ k1: Key) -> Edge {
//            if (k0.x < k1.x) || (k0.x == k1.x && k0.y <= k1.y) { return Edge(a: k0, b: k1) }
//            else { return Edge(a: k1, b: k0) }
//        }
//
//        var edgeSet = Set<Edge>()
//        edgeSet.reserveCapacity(segments.count)
//
//        for s in segments {
//            let a = simd_float2(s.x, s.y), b = simd_float2(s.z, s.w)
//            guard isFinite(a), isFinite(b) else { continue }
//            let ka = key(for: a), kb = key(for: b)
//            guard ka != kb else { continue }                 // skip zero-length edges after snap
////            edgeSet.insert(canon(ka, kb))
//            edgeSet.insert(Edge(a: ka, b: kb))
//            addRep(ka, a)
//            addRep(kb, b)
//        }
//
//        // finalize representative positions
//        for (k, n) in repCnt { repPos[k]! /= Float(n) }
//
//        // ---- 3) Build adjacency (multigraph collapsed to simple graph) ----
//        var adj: [Key: [Key]] = [:]
//        adj.reserveCapacity(repPos.count)
//        for e in edgeSet {
//            adj[e.a, default: []].append(e.b)
//            adj[e.b, default: []].append(e.a)
//        }
//        
////        // prune dangling vertices (degree < 2) – optional, helps noisy inputs
////        for (k, nbs) in adj {
////            if nbs.count < 1 { adj.removeValue(forKey: k) }
////        }
//        
//        guard !adj.isEmpty else { return [] }
//
//        // ---- 4) Trace one loop by consuming edges ----
//        // pick a deterministic start (lowest key)
//        let start = adj.keys.min { (l, r) in (l.x, l.y) < (r.x, r.y) }!
//        var pathKeys: [Key] = [start]
//        var cur = start
//        var prev: Key? = nil
//
//        // For consumption, use a local copies we mutate
//        var localAdj = adj
//        let maxSteps = max(8, edgeSet.count * 2)
//
//        for _ in 0..<maxSteps {
//            guard var nbrs = localAdj[cur], !nbrs.isEmpty else { break }
//
//            // pick next neighbor: prefer not going back to prev; otherwise pick nearest by Euclid distance in rep space
//            let rp = repPos[cur]!
//            let next: Key = {
//                // remove immediate backtrack if possible
//                let filtered = prev == nil ? nbrs : nbrs.filter { $0 != prev! }
//                if let candidate = filtered.min(by: { simd_distance(repPos[$0]!, rp) < simd_distance(repPos[$1]!, rp) }) {
//                    return candidate
//                }
//                return nbrs[0]
//            }()
//
//            // consume (remove) the undirected edge cur<->next so we don't revisit
//            localAdj[cur] = nbrs.filter { $0 != next }
//            localAdj[next] = (localAdj[next] ?? []).filter { $0 != cur }
//
//            // close if we’re back at start (and have enough points)
//            if next == start && pathKeys.count > 2 { break }
//
//            pathKeys.append(next)
//            prev = cur
//            cur = next
//        }
//
//        // ---- 5) Map keys to positions; dedupe consecutive near-equals ----
//        var out: [simd_float2] = []
//        out.reserveCapacity(pathKeys.count)
//        let thresh2: Float = (snapPx * 0.5) * (snapPx * 0.5)
//        for k in pathKeys {
//            let p = repPos[k]!
////            if let last = out.last, simd_length_squared(p - last) < thresh2 { continue }
//            out.append(p)
//        }
//
//        // ensure CCW if you care (optional)
////        func signedArea(_ pts: [simd_float2]) -> Float {
////            var a: Float = 0
////            for i in 0..<pts.count {
////                let p = pts[i], q = pts[(i+1) % pts.count]
////                a += p.x*q.y - q.x*p.y
////            }
////            return a * 0.5
////        }
////        if out.count >= 3, signedArea(out) < 0 { out.reverse() }
//
//        return ContiguousArray(out)
//    }

    
//    private func stitchSegmentsToPath(segments: [simd_float4], eps: Float) -> ContiguousArray<simd_float2> {
//        // Map endpoints → adjacency
//        struct End: Hashable { let x: Int; let y: Int }
//        
//        // DEBUG:
////        var tempPoints = ContiguousArray<simd_float2>()
////        
////        for segment in segments {
////            tempPoints.append(contentsOf: [
////                simd_float2(segment.x, segment.y),
////            ])
////        }
////        
////        return tempPoints
//        // END DEBUG
//        
//        
//        @inline(__always)
//         func q(_ v: simd_float2) -> End {
//             // clamp before casting
//             let sx = max(-1e8, min(1e8, v.x / eps))
//             let sy = max(-1e8, min(1e8, v.y / eps))
//             return End(x: Int(lrintf(sx)), y: Int(lrintf(sy)))
//         }
//
//        var adj: [End: [simd_float2]] = [:]
//        adj.reserveCapacity(segments.count * 2)
//
//        for s in segments {
//            let a = simd_float2(s.x, s.y)
//            let b = simd_float2(s.z, s.w)
//            let ia = q(a)
//            let ib = q(b)
//            adj[ia ] = [b]
//            adj[ib ] = [a]
////            adj[q(a), default: []].append(b)
////            adj[q(b), default: []].append(a)
//        }
//
//        // Start at an arbitrary endpoint, walk neighbors picking the next unused
//        var used = Set<End>()
//        var path: [simd_float2] = []
//        if let start = segments.first {
//            var cur = simd_float2(start.x, start.y)
//            let qStart = q(cur)
//            path.append(cur)
//            used.insert(qStart)
//
//            // Walk until we close (heuristic cap)
//            let cap = segments.count * 2 + 4
//            for _ in 0..<cap {
//                let key = q(cur)
//                guard let nbrs = adj[key], !nbrs.isEmpty else { break }
//
//                // Pick a neighbor that isn’t the immediate predecessor if possible
//                var next: simd_float2? = nil
//                if path.count >= 2 {
//                    let prev = path[path.count-2]
//                    next = nbrs.min(by: { distance($0, cur) < distance($1, cur) })
//                    if let n = next, approxEqual(n, prev, eps: eps) {
//                        // try second best
//                        next = nbrs.dropFirst().first
//                    }
//                } else {
//                    next = nbrs.min(by: { distance($0, cur) < distance($1, cur) })
//                }
//
//                guard let n = next else { break }
//                if used.contains(q(n)) && approxEqual(n, path.first!, eps: eps) {
//                    // closed loop
//                    break
//                }
//                path.append(n)
//                used.insert(q(n))
//                cur = n
//            }
//        }
//
//        return ContiguousArray(path)
//    }

    private func approxEqual(_ a: simd_float2, _ b: simd_float2, eps: Float) -> Bool {
        return abs(a.x - b.x) <= eps && abs(a.y - b.y) <= eps
    }
}

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
            ("inputMask", NodePort<FabricImage>(name: "Mask", kind: .Inlet)),

            // Params
            ("inputIso",  ParameterPort(parameter: FloatParameter("Iso Level", 0.5))),
            ("inputMaxSegments", ParameterPort(parameter: IntParameter("Max Segments", Self.kMaxSegments))),
            ("inputJoinEpsilon", ParameterPort(parameter: FloatParameter("Join Epsilon (px)", 1.0))),

            // Output (arbitrary payload for now)
            ("outputContour", NodePort<ContiguousArray<simd_float2>>(name: "Contour (points)", kind: .Outlet)),
        ]
    }

    // Proxies
    public var inputMask: NodePort<FabricImage> { port(named: "inputMask") }
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
        guard let url = bundle.url(forResource: "MarchingSquares", withExtension: "metal", subdirectory: "Compute")

        else {
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
                                 commandBuffer: MTLCommandBuffer)
    {
        guard
            inputMask.valueDidChange,
            let proc = processor,
            let inTex = inputMask.value?.texture,
            let graphRenderer = context.graphRenderer,
            let device = graphRenderer.context?.device
        else {
            outputContour.send(nil)
//            print("not outputting contour")
            return
        }
        
        
//        print("recomputing contour")

        // Bind input for sizing/dispatch
        proc.set(inTex, index: .Custom0)
        
        // Ensure buffers sized for this frame
        let maxSegs = max(1, inputMaxSegments.value ?? Self.kMaxSegments)
        ensureBuffers(device: device, width: inTex.width, height: inTex.height, maxSegments: maxSegs)
        
        // Bind buffers
        if let seg = segmentsBuffer { proc.set(seg, index: .Custom0) }   // segments
        if let ctr = counterBuffer  { proc.set(ctr, index: .Custom1) }   // atomic counter
        
        // Push uniforms
        proc.set("Iso", inputIso.value ?? 0.5)
        proc.set("MaxSegments", UInt32(maxSegs))

        // Clear the counter to zero before compute (tiny inline reset)
        zeroCounter(commandBuffer: commandBuffer)
        
        if let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        {
            // Dispatch the compute pass
            proc.update(computeEncoder)
            
            computeEncoder.endEncoding()
        }
        
        // Read back & stitch to a single ordered contour
        let epsilon = inputJoinEpsilon.value ?? 1.0
        /*let points = */readAndBuildContour(device: device,
                                         commandBuffer: commandBuffer,
                                         width: inTex.width,
                                         height: inTex.height,
                                         epsilon: epsilon)

        // Emit
//        outputContour.send( points )
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

        print("Allocing")
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
        
        if let blit = commandBuffer.makeBlitCommandEncoder(),
           let counterBuffer,
           let segmentsBuffer
        {
            blit.fill(buffer: counterBuffer, range: 0 ..< MemoryLayout<UInt32>.size, value: 0)

            blit.fill(buffer: segmentsBuffer, range: 0 ..< counterBuffer.allocatedSize, value:0)

            blit.endEncoding()
        }
    }

    // MARK: - Readback & Stitching
    private func readAndBuildContour(device: MTLDevice,
                                     commandBuffer: MTLCommandBuffer,
                                     width: Int, height: Int,
                                     epsilon: Float)
    {
        guard
            let segBuf = segmentsBuffer,
            let ctrBuf = counterBuffer
        else { return /*[]*/ }

        // Count
        let count = ctrBuf.contents().assumingMemoryBound(to: UInt32.self).pointee
        let segCount = min( Int(count), self.inputMaxSegments.value ?? Self.kMaxSegments )
        
        if segCount == 0 { return /*[]*/ }
        
        // Copy segments
        let segPtr = segBuf.contents().bindMemory(to: simd_float4.self, capacity: segCount)
        var segments: [simd_float4] = []
        segments.reserveCapacity(segCount)
        for i in 0..<segCount {
            segments.append(segPtr[i])
        }
        
        self.outputContour.send( self.stitchSegmentsToPath(segments: segments) )
    }
    
    @inline(__always)
    private func isFinite(_ p: simd_float2) -> Bool { p.x.isFinite && p.y.isFinite }

    public func stitchSegmentsToPath( segments: [simd_float4], snapPx: Float = 0.25) -> ContiguousArray<simd_float2> {

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
//    private func isFinite(_ p: simd_float2) -> Bool { p.x.isFinite && p.y.isFinite }
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

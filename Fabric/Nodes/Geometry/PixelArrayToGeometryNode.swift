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

public class PixelArrayToGeometryNode : BaseGeometryNode
{
    public override class var name:String { "2D Pixel Points To Geometry" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return [
            ("inputPoints", NodePort<ContiguousArray<simd_float2>>(name: "Points", kind: .Inlet) ),
        ] + ports
    }
    
    public var inputPoints: NodePort<ContiguousArray<simd_float2>> { port(named: "inputPoints") }
    
    public override var geometry: PolyLine2DGeometry { _geometry }
    
//    override public func markDirty() {
//        super.markDirty()
//        
//        print("PixelArrayToGeometryNode marked dirty")
//    }
//    
//    override public func markClean() {
//        super.markClean()
//        
//        print("PixelArrayToGeometryNode marked clean")
//    }
        
    // Basic Geom we change later
    private var _geometry = PolyLine2DGeometry(points: [.zero, .zero, .zero])
    
//    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
//    {
//        
//        if self.inputPoints.valueDidChange,
//           let points = self.inputPoints.value,
//           points.count > 3
//        {
//            let n = points.count
//            
//            let g = ParametricGeometry(rangeU: 0...Float(n - 1),
//                                       rangeV:  0...0,
//                                       resolution: simd_int2(Int32(n), 1)) { u, _ in
//                let i = max(0, min(n - 1, Int(round(u))))
//                let p = points[i]
//                return simd_float3(p.x, p.y, 0) / 1000.0
//            }
//                                        
//            g.primitiveType = .line
//            self._geometry = g
//
//            print("rebuilt parametric geometry")
//
//            shouldOutputGeometry = true
//        }
//        
//        
////        // TODO: Fix
////        if self.inputResolutionParam.valueDidChange,
////           let resolution = self.inputResolutionParam.value
////        {
//////            self.geometry.resolution =  self.inputResolutionParam.value
////            shouldOutputGeometry = true
////        }
////        
//        return shouldOutputGeometry
//    }
    
    public override func execute(context: GraphExecutionContext, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: any MTLCommandBuffer)
    {
//        print("PixelArrayToGeometryNode execute \(context.timing.frameNumber)")

        if self.inputPoints.valueDidChange
        {
//            print("PixelArrayToGeometryNode inputPointsdid change")

            if let points = self.inputPoints.value
            {
//                print("PixelArrayToGeometryNode have points")

                if points.count > 3
                {
                    let pointsCopy = ContiguousArray(points)
                    
                    let g = PolyLine2DGeometry(points: pointsCopy)

                    let _ = self.evaluate(geometry: g, atTime: 0.0)
                    
                    g.primitiveType = self.primitiveType()
                    
                    self._geometry = g

                    self.outputGeometry.send(self._geometry, force: true)
                }
            }
        }
    }
}


public class PolyLine2DGeometry : SatinGeometry
{
    var points: ContiguousArray<simd_float2>
    
    init(points: ContiguousArray<simd_float2>) {
        self.points = points
    }
    
    override public func generateGeometryData() -> GeometryData
    {
        self.buildGeometry( points: &self.points )
    }
    
    private func bounds(of pts: ContiguousArray<simd_float2>) -> simd_float4
    {
        guard let first = pts.first else { return .zero }
        var minv = first
        var maxv = first
        for p in pts
        {
            // skip junk if needed
            if !_fastPath(p.x.isFinite && p.y.isFinite) { continue }
            minv = simd.min(minv, p)
            maxv = simd.max(maxv, p)
        }
        return simd_float4(minv.x, minv.y, maxv.x, maxv.y)
    }
    
    
    func buildGeometry( points:inout ContiguousArray<simd_float2>) -> GeometryData
    {
        let length = Int32(points.count)

        let pathBounds:simd_float4 = bounds(of: points)
        
        // the triangulator expects an array of pointer(s)
        return  points.withUnsafeMutableBufferPointer { pathBuf in
            
            // triangle data to fill
            var triData = createTriangleData()
            var gData = createGeometryData()

            triangulatePath(pathBuf.baseAddress, length, &triData)
            createGeometryDataFromPath(pathBuf.baseAddress, length, &gData, pathBounds)
            copyTriangleDataToGeometryData(&triData, &gData)

            freeTriangleData(&triData)
            
            return gData
        }
        
    }
}

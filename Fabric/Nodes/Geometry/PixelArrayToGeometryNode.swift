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
    
    public override var geometry: ParametricGeometry { _geometry }
    
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
    private var _geometry = ParametricGeometry(rangeU: 0.0 ... 0.0 ,
                                               rangeV: 0.0 ... 0.0 ,
                                               resolution: simd_int2(x: 1, y: 1)) { u, v in
        return .zero
    }
    
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
//                    print("PixelArrayToGeometryNode start rebuild")

                    let n = points.count
                    
                    let g = ParametricGeometry(rangeU: 0...Float(n - 1),
                                               rangeV:  0...0,
                                               resolution: simd_int2(Int32(n), 1)) { u, _ in
                        let i = max(0, min(n - 1, Int(round(u))))
                        let p = points[i]
                        return simd_float3(p.x, p.y, 0) / 1000.0
                    }
                    
                    g.primitiveType = .line
                    self._geometry = g
                    
//                    print("rebuilt parametric geometry")
//                    
//                    print("outputting geometry")
                    
                    self.outputGeometry.send(self.geometry, force: true)
                }
            }
        }
    }
}

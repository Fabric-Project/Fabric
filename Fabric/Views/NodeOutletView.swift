//
//  NodeOutlet.swift
//  v
//
//  Created by Anton Marini on 5/20/24.
//

import SwiftUI

struct NodeOutletView: View
{
    let port: (any AnyPort)

    var body: some View 
    {
        Circle()
            .fill(port.color())
            .frame(width: 15)
            
//            .padding(.leading, 20)
//            .position(node.localOutletPositions[index])
            .draggable<OutletData>(
                
                OutletData(nodeID: self.port.id, outletIndex:0)
                            
            )
            .anchorPreference(
                key: PortAnchorKey.self,
                value: .center,
                transform: {  anchor in
                   
                    [  port.id : anchor ]
                })
    }
    
//        private func tempPath(start:CGPoint) -> some View
//        {
//           Path { path in
//    
//               let end = self.node.localOutletPositions[self.index]
//    
//               let control1 = CGPoint(x: start.x, y:(end.y + start.y) / 2.0 )
//               let control2 = CGPoint(x: end.x, y:(end.y + start.y) / 2.0 )
//    
//               path.move(to: start )
//               path.addCurve(to: end, control1: control1, control2: control2)
//            }
//        }
}

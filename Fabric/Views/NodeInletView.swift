//
//  NodeInlet.swift
//  v
//
//  Created by Anton Marini on 5/20/24.
//

import SwiftUI

struct NodeInletView: View
{
    static let radius:CGFloat = 15
    
    @Environment(Graph.self) var graph:Graph

    let port: (any AnyPort)

    @State private var isDropTargeted = false

    
    var body: some View
    {
        Circle()
            .fill( port.color() )
            .frame(width: 15)
//            .padding(.leading, 20)
//            .position(node.localInletPositions[index])
            .dropDestination(for: OutletData.self) { outletData, location in
//                return animateDrop(at: location)
                print("drop destination \(self.port.name)")
//                return true
                return self.processDrop(outletData)
            } isTargeted: {
                isDropTargeted = $0
            }
            .anchorPreference(
                key: PortAnchorKey.self,
                value: .center,
                transform: {  anchor in
                    
                    [ port.id : anchor ]
                }
              )
    }
    
    private func processDrop(_ outletData :[OutletData]) -> Bool
    {
//        for outletData in outletData
//        {
//            if let sourceNode = self.graph.nodeForID(id: outletData.nodeID)
//            {
//                let connection = NodeConnection(source: sourceNode,
//                                                sourceOutlet: outletData.outletIndex,
//                                                destination: self.node,
//                                                destinationInlet: self.index)
//                       
//                self.graph.addConnection(connection: connection)
//            }
//            
//            else
//            {
//                return false
//            }
//        }
        
        return true
    }
}

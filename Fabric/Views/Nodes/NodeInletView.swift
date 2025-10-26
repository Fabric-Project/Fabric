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

    var port: Port

    @State private var isDropTargeted = false

    
    var body: some View
    {
        HStack {
            Circle()
                .fill(port.color )
                .stroke(Color.red, lineWidth: port.published ? 1.0 : 0.0)
                .frame(width: 15)
                .brightness( port.published ? 0.2 : 0.0)
            //            .padding(.leading, 20)
            //            .position(node.localInletPositions[index])
                .dropDestination(for: OutletData.self) { outletData, location in
                    //                return animateDrop(at: location)
                    print("drop destination \(self.port.name), \(outletData)")
                    
                    if let firstOutlet = outletData.first,
                       let outletPort = self.graph.nodePort(forID: firstOutlet.portID)
                    {
                        
                        self.port.connect(to: outletPort)
                        
                        self.graph.shouldUpdateConnections.toggle()
                        return true
                    }
                    return false
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
               
//                .help("\(port.name): \(port.valueType())")

            Text(self.port.name)
                .foregroundStyle(Color.secondary)
                .font(.system(size: 9))
                .lineLimit(1)
        }
        .frame(height: 15)
//        .contextMenu {
//            
//            Toggle( self.port.isPublished() ? "Unpublish \(self.port.name)" : "Publish \(self.port.name)",
//                    isOn: Binding<Bool>.init(get: { return self.port.isPublished() },
//                                                            set: { val in
//                
//                self.port.setPublished(self.port.isPublished() ? false : true)
//            }))
//            .toggleStyle(CheckboxToggleStyle())
//        }
    }
}

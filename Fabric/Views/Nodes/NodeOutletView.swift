//
//  NodeOutlet.swift
//  v
//
//  Created by Anton Marini on 5/20/24.
//

import SwiftUI

struct NodeOutletView: View
{
    let port: Port
    let editingContext: GraphCanvasContext
    
    @State private var isDropTargeted = false

    var body: some View
    {
        let graph = editingContext.currentGraph

        HStack
        {
            Text(port.displayName)
                .foregroundStyle(Color.secondary)
                .font(.system(size: 9))
                .lineLimit(1)

            Circle()
                .fill(port.color)
                .stroke(Color.red, lineWidth: port.published ? 1.0 : 0.0)
                .frame(width: 15)
                .brightness(port.published ? 0.2 : 0.0)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("graph"))
                        .onChanged { value in
                            self.editingContext.dragPreviewSourcePortID = self.port.id
                            self.editingContext.dragPreviewTargetPosition = value.location
                        }
                        .onEnded { value in
                            defer {
                                self.editingContext.dragPreviewSourcePortID = nil
                                self.editingContext.dragPreviewTargetPosition = nil
                            }

                            guard let targetPortID = self.editingContext.nearestPortID(to: value.location),
                                  let targetPort = self.editingContext.currentGraph.nodePort(forID: targetPortID),
                                  targetPort.id != self.port.id,
                                  targetPort.kind == .Inlet,
                                  targetPort.canConnect(to: self.port)

//                                  targetPort.portType.canConnect(to: self.port.portType)
                            else
                            {
                                return
                            }

                            graph.connect(self.port, to: targetPort)
                        }
                )
                .modifier(PortInspectionTooltip(port: port))

        }
        .frame(height: 15)
        .contentShape(.interaction, Rectangle())
        .modifier(PortRenameAlert(port: port, graph: graph))
    }
}

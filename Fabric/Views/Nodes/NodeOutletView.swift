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
        // Hoist published check: editingContext.currentGraph is a computed
        // property traversing the subgraph stack. Caching the result avoids
        // redundant traversal and duplicate observation tracking per render.
        let graph = editingContext.currentGraph
        let isPublished = graph.isPublished(port)

        HStack
        {
            Text(self.port.name)
                .foregroundStyle(Color.secondary)
                .font(.system(size: 9))
                .lineLimit(1)

            Circle()
                .fill(port.color)
                .stroke(Color.red, lineWidth: isPublished ? 1.0 : 0.0)
                .frame(width: 15)
                .brightness(isPublished ? 0.2 : 0.0)
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

                            guard let targetPortID = self.findPortAt(position: value.location, in: value.location),
                                  let targetPort = self.editingContext.currentGraph.nodePort(forID: targetPortID),
                                  targetPort.id != self.port.id,
                                  targetPort.kind == .Inlet,
                                  targetPort.canConnect(to: self.port)

//                                  targetPort.portType.canConnect(to: self.port.portType)
                            else
                            {
                                return
                            }

                            self.port.connect(to: targetPort)
                        }
                )
                .anchorPreference(
                    key: PortAnchorKey.self,
                    value: .center,
                    transform: {  anchor in

                        [  port.id : anchor ]
                    })
                .help("\(port.name): \(port.portType.rawValue) - \(port.parameter?.description ?? "" )")

        }
        .frame(height: 15)
        .contextMenu { PortContextMenu(port: port, graph: graph) }
    }

    private func findPortAt(position: CGPoint, in geometryPosition: CGPoint) -> UUID? {
        let hitRadius: CGFloat = 25
        var closestPort: (UUID, CGFloat)? = nil

        for (portID, portPosition) in self.editingContext.portPositions {
            let distance = hypot(position.x - portPosition.x, position.y - portPosition.y)

            if distance < hitRadius {
                if let (_, currentClosest) = closestPort {
                    if distance < currentClosest {
                        closestPort = (portID, distance)
                    }
                } else {
                    closestPort = (portID, distance)
                }
            }
        }

        return closestPort?.0
    }
}

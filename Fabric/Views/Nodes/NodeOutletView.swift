//
//  NodeOutlet.swift
//  v
//
//  Created by Anton Marini on 5/20/24.
//

import SwiftUI

struct NodeOutletView: View
{
    @Environment(Graph.self) var graph:Graph

    let port: Port

    @State private var isDropTargeted = false

    var body: some View
    {
        HStack
        {
            Text(self.port.name)
                .foregroundStyle(Color.secondary)
                .font(.system(size: 9))
                .lineLimit(1)

            Circle()
                .fill(port.color)
                .frame(width: 15)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("graph"))
                        .onChanged { value in
                            self.graph.dragPreviewSourcePortID = self.port.id
                            self.graph.dragPreviewTargetPosition = value.location
                        }
                        .onEnded { value in
                            defer {
                                self.graph.dragPreviewSourcePortID = nil
                                self.graph.dragPreviewTargetPosition = nil
                            }

                            guard let targetPortID = self.findPortAt(position: value.location, in: value.location),
                                  let targetPort = self.graph.nodePort(forID: targetPortID),
                                  targetPort.id != self.port.id,
                                  targetPort.kind == .Inlet,
                                  targetPort.portType == self.port.portType else {
                                return
                            }

                            self.port.connect(to: targetPort)
                            self.graph.shouldUpdateConnections.toggle()
                        }
                )
                .anchorPreference(
                    key: PortAnchorKey.self,
                    value: .center,
                    transform: {  anchor in

                        [  port.id : anchor ]
                    })
        }
        .frame(height: 15)
    }

    private func findPortAt(position: CGPoint, in geometryPosition: CGPoint) -> UUID? {
        let hitRadius: CGFloat = 25
        var closestPort: (UUID, CGFloat)? = nil

        for (portID, portPosition) in self.graph.portPositions {
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

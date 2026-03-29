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
    
    let port: Port
    let editingContext: GraphCanvasContext

    @State private var isDropTargeted = false
    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View
    {
        // Hoist published check: editingContext.currentGraph is a computed
        // property traversing the subgraph stack. Caching the result avoids
        // redundant traversal and duplicate observation tracking per render.
        let graph = editingContext.currentGraph
        let isPublished = graph.isPublished(port)

        HStack {
            Circle()
                .fill(port.color )
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
                                  targetPort.kind == .Outlet,
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

                        [ port.id : anchor ]
                    }
                )
               
                .help("\(port.name): \(port.portType.rawValue) - \(port.parameter?.description ?? "" )")

            Text(graph.publishedName(for: port))
                .foregroundStyle(Color.secondary)
                .font(.system(size: 9))
                .lineLimit(1)
        }
        .frame(height: 15)
        .contextMenu { PortContextMenu(port: port, graph: graph, isRenaming: $isRenaming) }
        .alert("Rename Published Port", isPresented: $isRenaming) {
            TextField("Published name", text: $renameText)
            Button("OK") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                graph.setPublishedName(trimmed.isEmpty ? nil : trimmed, for: port)
            }
            Button("Clear", role: .destructive) {
                graph.setPublishedName(nil, for: port)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter a custom name for this published port, or clear to use the default.")
        }
        .onChange(of: isRenaming) {
            if isRenaming {
                renameText = graph.publishedName(for: port)
            }
        }
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

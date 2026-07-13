//
//  GraphConnectionsView.swift
//  Fabric
//

import SwiftUI

struct GraphConnectionsView: View
{
    let editingContext: GraphCanvasContext

    var body: some View
    {
        let currentGraph = editingContext.currentGraph
        let connectionPairs = editingContext.connectionPairs(for: currentGraph)

        ForEach(connectionPairs) { connectionPair in
            let outlet = connectionPair.outlet
            let inlet = connectionPair.inlet

            if let start = self.canvasPosition(for: outlet, in: currentGraph),
               let end = self.canvasPosition(for: inlet, in: currentGraph)
            {
                let path = calcPathUsing(port: outlet, start: start, end: end)

                path.stroke(outlet.backgroundColor, lineWidth: 2)
                    .contentShape(
                        path.stroke(style: StrokeStyle(lineWidth: 5))
                    )
                    .onTapGesture(count: 2) {
                        outlet.disconnect(from: inlet)
                    }
            }
        }

        if let sourcePortID = editingContext.dragPreviewSourcePortID,
           let targetPosition = editingContext.dragPreviewTargetPosition,
           let sourcePort = currentGraph.nodePort(forID: sourcePortID),
           let start = self.canvasPosition(for: sourcePort, in: currentGraph)
        {
            let path = calcPathUsing(port: sourcePort, start: start, end: targetPosition)

            path.stroke(sourcePort.backgroundColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targetPosition)
        }
    }

    private func canvasPosition(for port: Port, in graph: Graph) -> CGPoint?
    {
        guard let node = port.node else { return nil }

        let nodeViewModel = graph.viewModel(for: node)
        return editingContext.canvasPosition(for: port,
                                             nodeOffset: nodeViewModel.offset,
                                             nodeSize: nodeViewModel.nodeSize)
    }

    private func calcPathUsing(port: Port, start: CGPoint, end: CGPoint) -> Path
    {
        let lowerBound = 5.0
        let upperBound = 10.0
        let stemOffset: CGFloat = clamp(dist(p1: start, p2: end) / 4.0, lowerBound: lowerBound, upperBound: upperBound)

        switch port.direction
        {
        case .Vertical:
            let stemHeight: CGFloat = clamp(abs(end.y - start.y) / 4.0, lowerBound: lowerBound, upperBound: upperBound)
            let start1 = CGPoint(x: start.x, y: start.y + stemHeight)
            let end1   = CGPoint(x: end.x,   y: end.y   - stemHeight)
            let controlOffset: CGFloat = max(stemHeight + stemOffset, abs(end1.y - start1.y) / 2.4)
            let control1 = CGPoint(x: start1.x, y: start1.y + controlOffset)
            let control2 = CGPoint(x: end1.x,   y: end1.y   - controlOffset)

            return Path { path in
                path.move(to: start)
                path.addLine(to: start1)
                path.addCurve(to: end1, control1: control1, control2: control2)
                path.addLine(to: end)
            }

        case .Horizontal:
            let stemHeight: CGFloat = clamp(abs(end.x - start.x) / 4.0, lowerBound: lowerBound, upperBound: upperBound)
            let start1 = CGPoint(x: start.x + stemHeight, y: start.y)
            let end1   = CGPoint(x: end.x   - stemHeight, y: end.y)
            let controlOffset: CGFloat = max(stemHeight + stemOffset, abs(end1.x - start1.x) / 2.4)
            let control1 = CGPoint(x: start1.x + controlOffset, y: start1.y)
            let control2 = CGPoint(x: end1.x   - controlOffset, y: end1.y)

            return Path { path in
                path.move(to: start)
                path.addLine(to: start1)
                path.addCurve(to: end1, control1: control1, control2: control2)
                path.addLine(to: end)
            }
        }
    }

    private func clamp(_ x: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat
    {
        return max(min(x, upperBound), lowerBound)
    }

    private func dist(p1: CGPoint, p2: CGPoint) -> CGFloat
    {
        return hypot(p1.x - p2.x, p1.y - p2.y)
    }
}

//
//  NodeConnectionView.swift
//  v
//
//  Created by Anton Marini on 5/26/24.
//

import SwiftUI

struct NodeConnectionView :View
{
    @State var connection:NodeConnection
    
    var body : some View
    {
        Path { path in
            
            self.updatePath(&path)
            
        }
        .stroke( connection.selected ? .orange : .gray , lineWidth: 1.0)
        //                            .stroke(.gray, style: StrokeStyle( lineWidth: 1.0, dash: [5]))
        .contentShape(
            Path { path in
                
                self.updatePath(&path)
                
            }
            .stroke(lineWidth: 20.0)
        )
        .onTapGesture {
            connection.selected.toggle()
        }        
//        .onKeyPress(.delete) {
//            if connection.selected
//            {
//                connection.delegate?.shouldDelete(connection: connection)
//            }
//        }
    }
    
    private func clamp(_ x:CGFloat, lowerBound:CGFloat, upperBound:CGFloat) -> CGFloat
    {
        return max(min(x, upperBound), lowerBound)
    }
    
    private func dist(p1:CGPoint, p2:CGPoint) -> CGFloat
    {
        let distance = hypot(p1.x - p2.x, p1.y - p2.y)
        return distance
    }
    
    private func updatePath(_ path: inout Path)
    {
        guard
            let localStart = connection.destination.localInletPositions.safeGet(index: connection.destinationInlet),
            let localEnd = connection.source.localOutletPositions.safeGet(index: connection.sourceOutlet)
        else
        {
            return
        }
        
        let start:CGPoint = CGPoint(x: localEnd.x + connection.source.offset.width,
                                    y: localEnd.y + connection.source.offset.height)

        let end:CGPoint = CGPoint(x:  localStart.x + connection.destination.offset.width,
                                  y:  localStart.y + connection.destination.offset.height)

        // Min 5 stem height
        let boundMin = 5
        let boundMax = 10
        let stemHeight = self.clamp( abs( end.y - start.y) / 4.0 , lowerBound: boundMin, upperBound: boundMax)
        let stemOffset =  self.clamp( self.dist(p1: start, p2:end) / 4.0, lowerBound: boundMin, upperBound: boundMax) /*min( max(5, self.dist(p1: start, p2:end)), 40 )*/

        let start1:CGPoint = CGPoint(x: start.x,
                                     y: start.y + stemHeight)
        
        let end1:CGPoint = CGPoint(x: end.x,
                                   y: end.y - stemHeight)
        
        let controlOffset = max(stemHeight + stemOffset, abs(end1.y - start1.y) / 2.4)
        let control1 = CGPoint(x: start1.x, y: start1.y + controlOffset )
        let control2 = CGPoint(x: end1.x, y:end1.y - controlOffset  )
        
        path.move(to: start )
        path.addLine(to: start1)
        
        path.addCurve(to: end1, control1: control1, control2: control2)
        
        path.addLine(to: end)
        
//        path.addArc(center: control1, radius: 10, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 360), clockwise: true)
//        path.addArc(center: control2, radius: 10, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 360), clockwise: true)
    }
}

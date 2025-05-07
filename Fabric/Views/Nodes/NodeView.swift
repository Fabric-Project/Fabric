//
//  NodeView.swift
//  v
//
//  Created by Anton Marini on 4/27/24.
//

import SwiftUI
import Satin

struct NodeView : View
{
    @SwiftUI.Environment(Graph.self) var graph:Graph

    let node:Node
    
    // Drag to Offset bullshit
    @State var offset = CGSize.zero
    @GestureState private var dragOffset: CGSize = .zero
    
    var body: some View
    {
        GeometryReader { geom in
            
//            let nodeClass = self.node 
            
            // Param List
            ZStack
            {
                Color( (self.node.isSelected) ? "NodeBackgroundColorSelected" : "NodeBackgroundColor")
//                Color( (self.node.isSelected) ? self.node.nodeType.backgroundColor() : self.node.nodeType.backgroundColor().opacity(0.5) )

                VStack
                {
                    // Name
                    Text( self.node.name )
                        .font(.system(size: 9))
                        .bold()
                        .frame(maxHeight: 20)
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Spacer(minLength: 0)
                    ForEach(self.node.ports.filter({$0.kind == .Inlet && $0.direction == .Vertical}), id: \.id) { port in
                        NodeInletView(port: port)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: self.node.nodeSize.width, height: self.node.nodeSize.height + NodeInletView.radius, alignment: .top)
//
                HStack(alignment: .bottom, spacing: 10) {
                    Spacer(minLength: 0)
                    ForEach(self.node.ports.filter({$0.kind == .Outlet && $0.direction == .Vertical}), id: \.id) { port in
                        NodeOutletView(port: port)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: self.node.nodeSize.width, height: self.node.nodeSize.height + NodeInletView.radius, alignment: .bottom)
                
                
                
                VStack(alignment: .leading, spacing: 10) {
                    Spacer(minLength: 0)
                    ForEach(self.node.ports.filter({$0.kind == .Inlet && $0.direction == .Horizontal}), id: \.id) { port in
                        NodeInletView(port: port)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: self.node.nodeSize.width + NodeInletView.radius, height: self.node.nodeSize.height , alignment: .leading)
                
                
                VStack(alignment: .trailing, spacing: 10) {
                    Spacer(minLength: 0)
                    ForEach(self.node.ports.filter({$0.kind == .Outlet && $0.direction == .Horizontal}), id: \.id) { port in
                        NodeOutletView(port: port)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: self.node.nodeSize.width + NodeInletView.radius, height: self.node.nodeSize.height , alignment: .trailing)
                
                
            }
            .frame(width: self.node.nodeSize.width, height: self.node.nodeSize.height)
            .cornerRadius(15.0)
            .overlay {
                RoundedRectangle(cornerRadius: 15.0)
//                    .stroke( (self.node.isSelected) ? self.node.nodeType.color() : .gray, lineWidth: 1.0)
                    .stroke( (self.node.isSelected) ? self.node.nodeType.color() : self.node.nodeType.backgroundColor(), lineWidth: 1.0)

            }
            .offset( self.node.isDragging ?  CGSize(
                width: self.offset.width + self.dragOffset.width,// + self.dragOffset.width,
                height: self.offset.height + self.dragOffset.height// + self.dragOffset.height
                ) : self.node.offset
            )
            .gesture(
                SimultaneousGesture(
                    SimultaneousGesture(
                        DragGesture(minimumDistance: 3)
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation

                                self.node.isDragging = true

                                self.graph.selectNode(node: self.node, expandSelection: false)

                                self.node.offset = self.offset + self.dragOffset
//                                self.node.offset = CGSize(
//                                    width: self.offset.width + self.dragOffset.width,
//                                    height: self.offset.height + self.dragOffset.height
//                                )

                            }
                            .onEnded { value in
                                
                                self.offset.width += value.translation.width
                                self.offset.height += value.translation.height
                                

                                self.node.offset = self.offset
                                
                                self.node.isDragging = false
                            },

                    TapGesture(count: 1)
                        .onEnded({ value in
//                            self.graph.selectNode(node: self.node, expandSelection: false)
                        
                            self.node.isSelected.toggle()

                        })
                        ),
                    
                    TapGesture(count: 2)
                        .onEnded( { value in
                            self.node.showParams.toggle()
//                            self.graph.selectNode(node: self.node, expandSelection: false)
                        })
                    
                )
            )
            
//            .contextMenu {
//                [weak node, weak graph] in
//                Button {
//                    graph!.deleteNode(node!)
//                } label: {
//                    Label("Delete \(node!.name)", systemImage: "minus")
//                }
//            }
//            .focusEffectDisabled()
//            .onKeyPress(.space) {
//                self.node.showParams.toggle()
//                return .handled
//            }

        }
    }
}
    

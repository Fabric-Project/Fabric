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
    // Rename
    @Binding public var renaming: Bool
    @State private var renamingText: String = ""
    @FocusState private var renameFieldFocused: Bool
    
    var body: some View
    {
        GeometryReader { geom in
            
//            let nodeClass = self.node 
            
            // Param List
            ZStack(alignment: .topLeading)
            {
                self.node.isSelected ? Color("NodeBackgroundColorSelected") : Color("NodeBackgroundColor")
                                
                Rectangle()
                    .fill( Color.black.gradient )
//                    .fill( (self.node.isSelected) ? self.node.nodeType.color().gradient : self.node.nodeType.backgroundColor().gradient )
                    .frame(height: 30)
            
                VStack(alignment: .leading, spacing: 10) {
//                    
                    // Name
                    if renaming {
                        TextField("", text: $renamingText, onCommit: {
                            let trimmed = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
                            node.displayName = trimmed.isEmpty ? nil : trimmed
                            renaming = false
                        })
                        .textFieldStyle(.plain)
                        .focused($renameFieldFocused)
                        .font(.system(size: 9))
                        .bold()
                        .foregroundStyle( self.node.nodeType.color() )
                        .frame(maxHeight: 20)
                        .padding(.top, 5)
                        .padding(.horizontal, 20)
                        .onExitCommand {
                            renaming = false
                        }
                    } else {
                        Text( self.node.name )
                            .font(.system(size: 9))
                            .bold()
    //                        .foregroundStyle(.primary)
                            .foregroundStyle(  self.node.nodeType.color()  )
                            .frame(maxHeight: 20)
                            .padding(.top, 5)
                            .padding(.horizontal, 20)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { // double click to rename
                                renaming = true
                            }
                    }
                    
//                    Spacer()
                    
                    ForEach(self.node.ports.filter({$0.kind == .Inlet && $0.direction == .Horizontal}), id: \.id) { port in
                        NodeInletView(port: port)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: self.node.nodeSize.width + NodeInletView.radius, alignment: .leading)
                
                
                VStack(alignment: .trailing, spacing: 10) {
                    Spacer(minLength: 0)
                        .frame(height: 25)
                    
                    ForEach(self.node.ports.filter({$0.kind == .Outlet && $0.direction == .Horizontal}), id: \.id) { port in
                        NodeOutletView(port: port)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: self.node.nodeSize.width + NodeInletView.radius, alignment: .trailing)
                
                
            }
            .frame(width: self.node.nodeSize.width, height: self.node.nodeSize.height)
            .cornerRadius(self.cornerRadius())
            .overlay {
                RoundedRectangle(cornerRadius: self.cornerRadius())
                    .stroke(  (self.node.isSelected) ? self.node.nodeType.color() : .gray /*self.node.nodeType.backgroundColor()*/ , lineWidth: (self.node.isSelected) ? 1.5 : 1.0)
            }
            .onChange(of: renaming) { _, new in
                if new { renamingText = self.node.name }
                renameFieldFocused = new
            }
        }
    }
    
    func cornerRadius() -> CGFloat {
        switch self.node.nodeType {
        case .Subgraph:
            return 5.0
        default:
            return 15.0
        }
    }
}
    

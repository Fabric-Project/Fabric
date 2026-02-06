//
//  NodeTitleView.swift
//  Fabric
//
//  Created by Anton Marini on 1/12/26.
//

import SwiftUI

struct NodeTitleView: View {
    
    let node: Node
    
    // Rename
    @State public var renaming: Bool = false
    @State private var renamingText: String = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        // Name
        Group {
            if renaming {
                TextField("", text: $renamingText, onCommit: {
                    let trimmed = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let oldName = node.name
                    node.graph?.undoManager?.registerUndo(withTarget: node) { node in
                        node.displayName = oldName
                    }
                    node.graph?.undoManager?.setActionName("Rename Node")
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
                .onDisappear {
                    renaming = false
                }
            } else {
                Text( self.node.name )
                    .font(.system(size: 9))
                    .bold()
                //                        .foregroundStyle(.primary)
                    .foregroundStyle(  self.node.nodeType.color()  )
                    .frame(maxHeight: 20)
                    .contentShape(Rectangle())
                    .padding(.top, 5)
                    .padding(.horizontal, 20)
                    .onTapGesture(count: 2) { // double click to rename
                        renaming = true
                    }
            }
        }
        .onChange(of: renaming) { _, new in
            if new { renamingText = self.node.name }
            renameFieldFocused = new
        }
    }
}

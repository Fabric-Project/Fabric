//
//  NodeTitleView.swift
//  Fabric
//
//  Created by Anton Marini on 1/12/26.
//

import SwiftUI

struct NodeTitleView: View {

    @Bindable var nodeViewModel: NodeViewModel

    // Rename
    @State public var renaming: Bool = false
    @State private var renamingText: String = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        Group {
            if renaming {
                TextField("", text: $renamingText, onCommit: {
                    let trimmed = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let oldDisplayName = nodeViewModel.displayName
                    nodeViewModel.node.graph?.undoManager?.registerUndo(withTarget: nodeViewModel) { nodeViewModel in
                        nodeViewModel.displayName = oldDisplayName
                    }
                    nodeViewModel.node.graph?.undoManager?.setActionName("Rename Node")
                    nodeViewModel.displayName = trimmed.isEmpty ? nil : trimmed
                    renaming = false
                })
                .textFieldStyle(.plain)
                .focused($renameFieldFocused)
                .font(.system(size: 9))
                .bold()
                .foregroundStyle( nodeViewModel.nodeType.color() )
                .frame(maxHeight: 20)
                .padding(.top, 5)
                .padding(.horizontal, 20)
                .onDisappear {
                    renaming = false
                }
            } else {
                Text( nodeViewModel.name )
                    .font(.system(size: 9))
                    .bold()
                    .foregroundStyle( nodeViewModel.nodeType.color() )
                    .frame(maxHeight: 20)
                    .contentShape(Rectangle())
                    .padding(.top, 5)
                    .padding(.horizontal, 20)
                    .onTapGesture(count: 2) {
                        renaming = true
                    }
            }
        }
        .onChange(of: renaming) { _, new in
            if new { renamingText = nodeViewModel.name }
            renameFieldFocused = new
        }
    }
}

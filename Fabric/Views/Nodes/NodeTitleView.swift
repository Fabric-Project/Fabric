//
//  NodeTitleView.swift
//  Fabric
//
//  Created by Anton Marini on 1/12/26.
//

import SwiftUI

struct NodeTitleView: View {

    @Bindable var vm: NodeViewModel

    // Rename
    @State public var renaming: Bool = false
    @State private var renamingText: String = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        Group {
            if renaming {
                TextField("", text: $renamingText, onCommit: {
                    let trimmed = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let oldDisplayName = vm.displayName
                    vm.node.graph?.undoManager?.registerUndo(withTarget: vm) { vm in
                        vm.displayName = oldDisplayName
                    }
                    vm.node.graph?.undoManager?.setActionName("Rename Node")
                    vm.displayName = trimmed.isEmpty ? nil : trimmed
                    renaming = false
                })
                .textFieldStyle(.plain)
                .focused($renameFieldFocused)
                .font(.system(size: 9))
                .bold()
                .foregroundStyle( vm.nodeType.color() )
                .frame(maxHeight: 20)
                .padding(.top, 5)
                .padding(.horizontal, 20)
                .onDisappear {
                    renaming = false
                }
            } else {
                Text( vm.name )
                    .font(.system(size: 9))
                    .bold()
                    .foregroundStyle( vm.nodeType.color() )
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
            if new { renamingText = vm.name }
            renameFieldFocused = new
        }
    }
}

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
    @State private var renaming: Bool = false
    @State private var renamingText: String = ""
    @FocusState private var renameFieldFocused: Bool

    private var typeName: String { type(of: node).name }
    private var hasDisplayName: Bool {
        if let n = node.displayName, !n.isEmpty { return true }
        return false
    }

    private var secondaryColor: Color {
        let typeColor = node.nodeType.color()
        // Parameter nodes use a near-white type colour that would read as
        // indistinct next to the white display name; dim it for contrast.
        // Other categories already contrast via hue so use them at full
        // strength.
        if case .Parameter = node.nodeType {
            return typeColor.opacity(0.6)
        }
        return typeColor
    }

    var body: some View {
        Group {
            if renaming {
                HStack(spacing: 0) {
                    TextField("", text: $renamingText)
                        .textFieldStyle(.plain)
                        .focused($renameFieldFocused)
                        .font(.system(size: 9))
                        .bold()
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: true, vertical: false)
                        .onSubmit(commitRename)
                        .onDisappear {
                            renaming = false
                        }

                    Text(" \(typeName)")
                        .font(.system(size: 9))
                        .bold()
                        .foregroundStyle(secondaryColor)
                }
            } else if hasDisplayName, let displayName = node.displayName {
                let primary = Text(displayName).foregroundStyle(.white)
                let secondary = Text(" \(typeName)").foregroundStyle(secondaryColor)
                Text("\(primary)\(secondary)")
                    .font(.system(size: 9))
                    .bold()
            } else {
                Text(typeName)
                    .font(.system(size: 9))
                    .bold()
                    .foregroundStyle( self.node.nodeType.color() )
            }
        }
        .frame(maxHeight: 20)
        .padding(.top, 5)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { // double click to rename
            if !renaming { renaming = true }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to rename node")
        .onChange(of: renaming) { _, new in
            if new { renamingText = self.node.name }
            renameFieldFocused = new
        }
    }

    private func commitRename() {
        let trimmed = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldName = node.name
        node.graph?.undoManager?.registerUndo(withTarget: node) { node in
            node.displayName = oldName
        }
        node.graph?.undoManager?.setActionName("Rename Node")
        node.displayName = trimmed.isEmpty ? nil : trimmed
        renaming = false
    }
}

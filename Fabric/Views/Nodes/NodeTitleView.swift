//
//  NodeTitleView.swift
//  Fabric
//
//  Created by Anton Marini on 1/12/26.
//

import SwiftUI

struct NodeTitleView: View
{
    @Bindable var nodeViewModel: NodeViewModel

    @State private var renaming: Bool = false
    @State private var renamingText: String = ""
    @FocusState private var renameFieldFocused: Bool

    private var typeName: String { type(of: nodeViewModel.node).name }

    private var hasPrimaryLabel: Bool { nodeViewModel.name != typeName }

    // `name` already resolves userName ?? node-generated displayName ?? typeName.
    private var primaryLabel: String { nodeViewModel.name }

    /// Opaque across the title, fading to clear over the last ~1 character so an
    /// over-long title dissolves at the node's right edge rather than hard-clipping.
    private var titleEdgeFade: LinearGradient
    {
        let width = max(nodeViewModel.nodeSize.width, 1)
        let fade = min(8, width)
        let solid = max(0, (width - fade) / width)
        return LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: solid),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var secondaryColor: Color
    {
        let typeColor = nodeViewModel.nodeType.color()

        if case .Parameter = nodeViewModel.nodeType
        {
            return typeColor.opacity(0.6)
        }

        return typeColor
    }

    var body: some View
    {
        Group
        {
            if renaming
            {
                HStack(spacing: 0)
                {
                    TextField(nodeViewModel.name, text: $renamingText)
                        .textFieldStyle(.plain)
                        .focused($renameFieldFocused)
                        .font(.system(size: 9))
                        .bold()
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: true, vertical: false)
                        .onSubmit(commitRename)
                        .onDisappear
                        {
                            renaming = false
                        }

                    Text(" \(typeName)")
                        .font(.system(size: 9))
                        .bold()
                        .foregroundStyle(secondaryColor)
                }
            }
            else if hasPrimaryLabel
            {
                let primary = Text(primaryLabel).foregroundStyle(.white)
                let secondary = Text(" \(typeName)").foregroundStyle(secondaryColor)
                Text("\(primary)\(secondary)")
                    .font(.system(size: 9))
                    .bold()
            }
            else
            {
                Text(typeName)
                    .font(.system(size: 9))
                    .bold()
                    .foregroundStyle(nodeViewModel.nodeType.color())
            }
        }
        // Lay the title out at its full intrinsic width (single line, no
        // ellipsis), then constrain to the node width and soft-fade the trailing
        // edge so an over-long title dissolves at the node boundary instead of
        // hard-clipping with a "…".
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxHeight: 20)
        .padding(.top, 5)
        .padding(.leading, 20)
        .frame(width: nodeViewModel.nodeSize.width, alignment: .leading)
        .clipped()
        .mask(titleEdgeFade)
        .contentShape(Rectangle())
        .onTapGesture(count: 2)
        {
            if !renaming { renaming = true }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to rename node")
        .onChange(of: renaming)
        { _, new in
            if new { renamingText = nodeViewModel.userName ?? "" }
            renameFieldFocused = new
        }
    }

    private func commitRename()
    {
        let trimmed = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldUserName = nodeViewModel.userName

        nodeViewModel.node.graph?.undoManager?.registerUndo(withTarget: nodeViewModel)
        { nodeViewModel in
            nodeViewModel.userName = oldUserName
        }
        nodeViewModel.node.graph?.undoManager?.setActionName("Rename Node")

        nodeViewModel.userName = trimmed.isEmpty ? nil : trimmed
        renaming = false
    }
}

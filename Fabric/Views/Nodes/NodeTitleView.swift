//
//  NodeTitleView.swift
//  Fabric
//
//  Created by Anton Marini on 1/12/26.
//

import SwiftUI

struct NodeTitleView: View
{
    var nodeViewModel: NodeViewModel

    @State private var renaming: Bool = false
    @State private var renamingText: String = ""
    @FocusState private var renameFieldFocused: Bool

    private var registryName: String { nodeViewModel.registryName }

    // Nil when the node has neither a rename nor a generated name, so the title
    // is its type name alone.
    private var primaryLabel: String? { nodeViewModel.customLabel }

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

   

    var body: some View
    {
        Group
        {
            let secondaryColor = nodeViewModel.nodeType.secondaryColor()
            
            if renaming
            {
                HStack(spacing: 0)
                {
                    // Placeholder previews the empty-commit outcome: with no
                    // rename, customLabel (the node-generated name) shows; the
                    // registry name already follows as the suffix Text.
                    TextField(nodeViewModel.customLabel ?? "", text: $renamingText)
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

                    Text(verbatim: " \(registryName)")
                        .font(.system(size: 9))
                        .bold()
                        .foregroundStyle(secondaryColor)
                }
            }
            else if let primaryLabel
            {
                // Text(verbatim:) + concatenation: these are data strings, not UI
                // copy — the literal-interpolation initializer would do a doomed
                // localization lookup on every render.
                let primary = Text(primaryLabel).foregroundStyle(.white)
                let secondary = Text(verbatim: " \(registryName)").foregroundStyle(secondaryColor)
                (primary + secondary)
                    .font(.system(size: 9))
                    .bold()
            }
            else
            {
                Text(registryName)
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
        // Return commits via onSubmit; clicking elsewhere must also commit,
        // otherwise the edit is silently lost and the field stays stuck in
        // rename mode (the double-tap gesture is guarded by !renaming).
        .onChange(of: renameFieldFocused)
        { _, focused in
            if !focused && renaming { commitRename() }
        }
        .onExitCommand
        {
            if renaming { renaming = false }
        }
    }

    private func commitRename()
    {
        let trimmed = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldUserName = nodeViewModel.userName
        let newUserName = trimmed.isEmpty ? nil : trimmed

        guard newUserName != oldUserName else
        {
            renaming = false
            return
        }

        nodeViewModel.node.graph?.undoManager?.registerUndo(withTarget: nodeViewModel)
        { nodeViewModel in
            nodeViewModel.userName = oldUserName
        }
        nodeViewModel.node.graph?.undoManager?.setActionName("Rename Node")

        nodeViewModel.userName = newUserName
        renaming = false
    }
}

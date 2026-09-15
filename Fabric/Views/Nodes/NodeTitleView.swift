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

    /// Leading inset in the port column's own coordinates, so the title sits
    /// with the port labels below it.
    private let leadingInset: CGFloat = 20

    /// The row's inset from the node's top edge, and the icon cell's inset
    /// from the trailing edge: one number, so the icon is centred the same
    /// distance from both edges.
    private let rowInset: CGFloat = 5

    /// The row's height, and the icon cell's side.
    private let rowHeight: CGFloat = 20

    /// NodeView lays the port columns out one inlet radius wider than the
    /// node and centres them in it, which is what puts the port circles
    /// astride both edges. It also shifts everything in those columns, this
    /// row included, half a radius to the left of the node. The row runs
    /// that much wider so its trailing edge lands on the node's real edge.
    private let portOverhangShift: CGFloat = NodeInletView.radius / 2

    private var titleIcon: NodeTitleIcon? { nodeViewModel.titleIcon }

    /// The row's full width, from the column's leading edge to the node's
    /// real trailing edge.
    private var rowWidth: CGFloat { nodeViewModel.nodeSize.width + portOverhangShift }

    /// The width the title text may occupy: the row less the leading inset
    /// and, when there is an icon, its cell and inset.
    private var textWidth: CGFloat
    {
        max(rowWidth - leadingInset - (titleIcon == nil ? 0 : rowHeight + rowInset), 1)
    }

    /// Opaque across the title, fading to clear over the last ~1 character so an
    /// over-long title dissolves at the text area's right edge rather than
    /// hard-clipping, before the icon where there is one.
    private var titleEdgeFade: LinearGradient
    {
        let width = textWidth
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
        NodeTitleText(nodeViewModel: nodeViewModel,
                      renaming: $renaming,
                      renamingText: $renamingText,
                      renameFieldFocused: $renameFieldFocused,
                      commitRename: commitRename)
            // Lay the title out at its full intrinsic width (single line, no
            // ellipsis), then constrain to the text area and soft-fade the
            // trailing edge so an over-long title dissolves there instead of
            // hard-clipping with a "…".
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: textWidth, height: rowHeight, alignment: .leading)
            .clipped()
            .mask(titleEdgeFade)
            // The icon is placed against the row's trailing edge, independent
            // of the text: the text only leaves it room via textWidth. It is
            // centred in a square cell the row's height, inset from the edge
            // by the row's own top inset, so its distance from the trailing
            // edge matches its distance from the top.
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing)
            {
                if let titleIcon
                {
                    NodeTitleIconView(icon: titleIcon, cellSide: rowHeight)
                        .padding(.trailing, rowInset)
                }
            }
        .padding(.top, rowInset)
        .padding(.leading, leadingInset)
        .frame(width: rowWidth, alignment: .leading)
        .contentShape(Rectangle())
        .help(titleIcon?.tooltip ?? "")
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

/// The title text alone: the rename field while renaming, otherwise the
/// subtitle and type name, or the type name by itself.
private struct NodeTitleText: View
{
    let nodeViewModel: NodeViewModel
    @Binding var renaming: Bool
    @Binding var renamingText: String
    let renameFieldFocused: FocusState<Bool>.Binding
    let commitRename: () -> Void

    private var title: String { nodeViewModel.title }

    // Nil when the node has neither a rename nor a generated name, so the title
    // is its type name alone.
    private var primaryLabel: String? { nodeViewModel.subtitle }

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
                    // rename, the node-derived subtitle shows; the registered
                    // title already follows as the suffix Text.
                    TextField(nodeViewModel.subtitle ?? "", text: $renamingText)
                        .textFieldStyle(.plain)
                        .focused(renameFieldFocused)
                        .font(.system(size: 9))
                        .bold()
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: true, vertical: false)
                        .onSubmit(commitRename)
                        .onDisappear
                        {
                            renaming = false
                        }

                    Text(verbatim: " \(title)")
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
                let secondary = Text(verbatim: " \(title)").foregroundStyle(secondaryColor)
                (primary + secondary)
                    .font(.system(size: 9))
                    .bold()
            }
            else
            {
                Text(title)
                    .font(.system(size: 9))
                    .bold()
                    .foregroundStyle(nodeViewModel.nodeType.color())
            }
        }
    }
}

/// A title icon in its square cell, coloured by its tint.
private struct NodeTitleIconView: View
{
    let icon: NodeTitleIcon
    let cellSide: CGFloat

    private var color: Color
    {
        switch icon.tint
        {
        case .neutral: .white
        case .warning: .yellow
        case .error:   .red
        }
    }

    var body: some View
    {
        Image(systemName: icon.systemName)
            .font(.system(size: 9))
            .bold()
            .foregroundStyle(color)
            .frame(width: cellSide, height: cellSide)
            .accessibilityLabel(icon.tooltip)
    }
}

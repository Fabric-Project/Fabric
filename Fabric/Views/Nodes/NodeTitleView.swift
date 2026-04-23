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

    private var primaryLabel: String
    {
        if let displayName = nodeViewModel.displayName, !displayName.isEmpty { return displayName }

        return nodeViewModel.name
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
                    TextField("", text: $renamingText)
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
        .frame(maxHeight: 20)
        .padding(.top, 5)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
        .onTapGesture(count: 2)
        {
            if !renaming { renaming = true }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to rename node")
        .onChange(of: renaming)
        { _, new in
            if new { renamingText = nodeViewModel.name }
            renameFieldFocused = new
        }
    }

    private func commitRename()
    {
        let trimmed = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldDisplayName = nodeViewModel.displayName

        nodeViewModel.node.graph?.undoManager?.registerUndo(withTarget: nodeViewModel)
        { nodeViewModel in
            nodeViewModel.displayName = oldDisplayName
        }
        nodeViewModel.node.graph?.undoManager?.setActionName("Rename Node")

        nodeViewModel.displayName = trimmed.isEmpty ? nil : trimmed
        renaming = false
    }
}

//
//  CloneSetContextMenu.swift
//  Fabric
//
//  Created by Claude on 9/9/26.
//

import SwiftUI

/// Clone set items of a Subgraph node's context menu. Renaming presents the
/// alert owned by CloneSetRenameAlert on the node, keyed by node id.
struct CloneSetContextMenu: View
{
    let subgraphNode: SubgraphNode
    let currentGraph: Graph
    @Binding var renamingNodeID: UUID?

    var body: some View
    {
        let siblings = currentGraph.cloneSiblings(of: subgraphNode)

        Divider()

        Button {
            currentGraph.duplicateAsClone(subgraphNode)
        } label: {
            Text("Duplicate as Clone")
        }

        if subgraphNode.cloneSetID != nil
        {
            Button {
                renamingNodeID = subgraphNode.id
            } label: {
                Text("Rename Clone Set…")
            }
        }

        if !siblings.isEmpty
        {
            Button {
                currentGraph.deselectAllNodes()
                for sibling in siblings where sibling.graph === currentGraph
                {
                    currentGraph.selectNode(node: sibling, expandSelection: true)
                }
            } label: {
                Text("Select Sibling Clones")
            }

            Button {
                currentGraph.unlinkClone(subgraphNode)
            } label: {
                Text("Unlink from Clones")
            }
        }
    }
}

/// Owns the rename alert for a Subgraph node's clone set, presented when the
/// canvas's renaming id names this node.
struct CloneSetRenameAlert: ViewModifier
{
    let subgraphNode: SubgraphNode
    let graph: Graph
    @Binding var renamingNodeID: UUID?

    @State private var renameText = ""

    private var isRenaming: Binding<Bool>
    {
        Binding(
            get: { renamingNodeID == subgraphNode.id },
            set: { presenting in if !presenting, renamingNodeID == subgraphNode.id { renamingNodeID = nil } }
        )
    }

    func body(content: Content) -> some View
    {
        content
            .alert("Rename Clone Set", isPresented: isRenaming) {
                TextField("Set name", text: $renameText)
                Button("OK", action: commitRename)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The name shows on every member of the set. Leave it empty for a system name.")
            }
            .onChange(of: isRenaming.wrappedValue) {
                if isRenaming.wrappedValue
                {
                    renameText = subgraphNode.cloneSetInfo?.name ?? ""
                }
            }
    }

    private func commitRename()
    {
        guard let setID = subgraphNode.cloneSetID else { return }
        graph.renameCloneSet(setID, to: renameText)
    }
}

/// Applies CloneSetRenameAlert to Subgraph nodes and leaves other nodes as they are.
struct CloneSetRenameAlertIfSubgraph: ViewModifier
{
    let node: Node
    let graph: Graph
    @Binding var renamingNodeID: UUID?

    func body(content: Content) -> some View
    {
        if let subgraphNode = node as? SubgraphNode
        {
            content.modifier(CloneSetRenameAlert(subgraphNode: subgraphNode,
                                                 graph: graph,
                                                 renamingNodeID: $renamingNodeID))
        }
        else
        {
            content
        }
    }
}

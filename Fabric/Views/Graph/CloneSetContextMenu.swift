//
//  CloneSetContextMenu.swift
//  Fabric
//
//  Created by Claude on 9/9/26.
//

import SwiftUI

/// A rename in progress: which node's set, and the draft name. Created with
/// the set's current name when the menu item is chosen, so the alert opens
/// showing it; the draft is what OK commits, empty included.
struct CloneSetRenameRequest: Equatable
{
    let nodeID: UUID
    var name: String
}

/// Clone set items of a Subgraph node's context menu. Renaming presents the
/// alert owned by CloneSetRenameAlert on the node, keyed by node id.
struct CloneSetContextMenu: View
{
    let subgraphNode: SubgraphNode
    let currentGraph: Graph
    @Binding var renameRequest: CloneSetRenameRequest?

    var body: some View
    {
        let siblings = currentGraph.cloneSiblings(of: subgraphNode)

        Divider()

        Button {
            currentGraph.duplicateAsClone(subgraphNode)
        } label: {
            Text("Duplicate as Clone")
        }

        if let setInfo = subgraphNode.cloneSetInfo
        {
            Button {
                renameRequest = CloneSetRenameRequest(nodeID: subgraphNode.id, name: setInfo.name)
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

/// Owns the rename alert for a Subgraph node's clone set, presented while
/// the canvas's request names this node. The text field edits the request's
/// draft directly, so there is no hand-off to time against the alert.
struct CloneSetRenameAlert: ViewModifier
{
    let subgraphNode: SubgraphNode
    let graph: Graph
    @Binding var renameRequest: CloneSetRenameRequest?

    private var isPresented: Binding<Bool>
    {
        Binding(
            get: { renameRequest?.nodeID == subgraphNode.id },
            set: { presenting in if !presenting, renameRequest?.nodeID == subgraphNode.id { renameRequest = nil } }
        )
    }

    private var draftName: Binding<String>
    {
        Binding(
            get: { renameRequest?.name ?? "" },
            set: { renameRequest?.name = $0 }
        )
    }

    func body(content: Content) -> some View
    {
        content
            .alert("Rename Clone Set", isPresented: isPresented) {
                TextField("Set name", text: draftName)
                Button("OK", action: commitRename)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The name shows on every member of the set. Leave it empty for a system name.")
            }
    }

    private func commitRename()
    {
        guard let setID = subgraphNode.cloneSetID, let request = renameRequest else { return }
        graph.renameCloneSet(setID, to: request.name)
    }
}

/// Applies CloneSetRenameAlert to Subgraph nodes and leaves other nodes as they are.
struct CloneSetRenameAlertIfSubgraph: ViewModifier
{
    let node: Node
    let graph: Graph
    @Binding var renameRequest: CloneSetRenameRequest?

    func body(content: Content) -> some View
    {
        if let subgraphNode = node as? SubgraphNode
        {
            content.modifier(CloneSetRenameAlert(subgraphNode: subgraphNode,
                                                 graph: graph,
                                                 renameRequest: $renameRequest))
        }
        else
        {
            content
        }
    }
}

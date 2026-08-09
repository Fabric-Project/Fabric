//
//  NodeSelectionInspector.swift
//  Fabric
//
//  Created by Anton Marini on 4/29/25.
//

import SwiftUI
import Satin
import UniformTypeIdentifiers

public struct NodeSelectionInspector: View
{
    let editingContext: GraphCanvasContext

    public init(editingContext: GraphCanvasContext)
    {
        self.editingContext = editingContext
    }

    public var body: some View {

        let currentGraph = self.editingContext.currentGraph

        List {

            Section(header: Text("Published"))
            {
                GroupBox
                {
                    ParameterGroupView(parameterGroup:currentGraph.publishedParameterGroup)
                        // publishedParameterGroup is a plain class rebuilt in
                        // place, invisible to observation — but every rebuild
                        // bumps connectionRevision, so re-identify just this
                        // view (not the whole List) to pick up the new params.
                        .id(currentGraph.connectionRevision)
                }
            }

            Section(header: Text("Selected"))
            {
                ForEach(currentGraph.selectedNodes) { node in
                    SelectedNodeCard(nodeViewModel: currentGraph.viewModel(for: node),
                                     fileContentTypes: Self.fileContentTypes(for: node))
                }
            }
        }
        .listStyle(.sidebar)
    }

    private static func fileContentTypes(for node: Node) -> [UTType]
    {
        if let dropTarget = type(of: node) as? any NodeFileLoadingProtocol.Type {
            return dropTarget.supportedContentTypes
        }
        return [.data]
    }

}

/// One inspector card per selected node. A separate view so each card
/// observes only its own NodeViewModel — renaming one node or toggling its
/// settings re-evaluates that card alone, not every card in the inspector.
private struct SelectedNodeCard: View
{
    @Bindable var nodeViewModel: NodeViewModel
    let fileContentTypes: [UTType]

    var body: some View
    {
        // Read the port list unconditionally: it is the card's only observable
        // signal that the node's parameters changed (parameterGroup is a plain
        // class rebuilt in place), and it must fire even while the params
        // branch below is absent.
        let portIDs = nodeViewModel.ports.map(\.id)

        GroupBox
        {
            VStack(alignment: .leading) {

                label
                    .padding(.horizontal, 5)

                if nodeViewModel.providesSettingsView() {
                    Toggle("Settings", isOn: $nodeViewModel.showSettings)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .padding(.horizontal, 5)
                }

                if !nodeViewModel.parameterGroup.params.isEmpty {

                    Divider()

                    ParameterGroupView(parameterGroup: nodeViewModel.parameterGroup,
                                       fileContentTypes: fileContentTypes)
                        .id(portIDs)
                }
            }
        }
    }

    @ViewBuilder private var label: some View
    {
        if let customLabel = nodeViewModel.customLabel
        {
            VStack(alignment: .leading) {
                Text(customLabel).foregroundStyle(.primary).bold()
                Text(nodeViewModel.registryName).foregroundStyle(.secondary).bold()
            }
        }
        else
        {
            Text(nodeViewModel.registryName).foregroundStyle(.primary).bold()
        }
    }
}

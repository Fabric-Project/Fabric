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
                ParameterGroupView(parameterGroup:currentGraph.publishedParameterGroup)
            }

            ForEach(currentGraph.selectedNodes) { node in

                @Bindable var nodeViewModel: NodeViewModel = currentGraph.viewModel(for: node)

                Section(header: Text( nodeViewModel.name ) )
                {
                    Toggle("Node Settings", isOn: $nodeViewModel.showSettings)
                        .opacity(nodeViewModel.providesSettingsView() ? 1.0 : 0.0)

                    ParameterGroupView(parameterGroup: nodeViewModel.parameterGroup,
                                       fileContentTypes: Self.fileContentTypes(for: node))
                }
            }
        }
        .listStyle(.sidebar)
        .id(currentGraph.connectionRevision)

    }

    private static func fileContentTypes(for node: Node) -> [UTType]
    {
        if let dropTarget = type(of: node) as? any NodeFileLoadingProtocol.Type {
            return dropTarget.supportedContentTypes
        }
        return [.data]
    }
}

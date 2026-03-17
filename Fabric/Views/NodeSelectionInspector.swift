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
    let graph:Graph
    @Binding private var inputFocus: FabricEditorInputFocus

    public init(graph:Graph, inputFocus: Binding<FabricEditorInputFocus>)
    {
        self.graph = graph
        self._inputFocus = inputFocus
    }

    public var body: some View {

        let graph = self.graph.activeSubGraph ?? self.graph

        let selectedNodes = graph.nodes.filter( { $0.isSelected } )

        List {

            Section(header: Text("Published"))
            {
                ParameterGroupView(parameterGroup:graph.publishedParameterGroup)
            }

            ForEach(selectedNodes, id: \.id) { node in

                Section(header: Text( node.name ) )
                {
                    @Bindable var bindableNode:Node = node

                    Toggle("Node Settings", isOn: $bindableNode.showSettings)
                        .opacity(bindableNode.providesSettingsView() ? 1.0 : 0.0)

                    ParameterGroupView(parameterGroup: node.parameterGroup,
                                       fileContentTypes: Self.fileContentTypes(for: node))
                }
            }
        }
        .listStyle(.sidebar)
        .id(graph.shouldUpdateConnections)

    }

    private static func fileContentTypes(for node: Node) -> [UTType]
    {
        if let dropTarget = type(of: node) as? any NodeFileDropTarget.Type {
            return dropTarget.supportedContentTypes
        }
        return [.data]
    }
}

//#Preview {
////    NodeSelectionInspector()
//}

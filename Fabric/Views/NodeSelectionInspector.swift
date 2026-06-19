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
    @Binding private var inputFocus: FabricEditorInputFocus

    public init(editingContext: GraphCanvasContext, inputFocus: Binding<FabricEditorInputFocus>)
    {
        self.editingContext = editingContext
        self._inputFocus = inputFocus
    }

    public var body: some View {

        let currentGraph = self.editingContext.currentGraph

        let selectedNodes = currentGraph.nodes.filter( { $0.isSelected } )

        List {

            Section(header: Text("Published"))
            {
                ParameterGroupView(parameterGroup:currentGraph.publishedParameterGroup)
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
        .id(currentGraph.shouldUpdateConnections)

    }

    private static func fileContentTypes(for node: Node) -> [UTType]
    {
        if let dropTarget = type(of: node) as? any NodeFileLoadingProtocol.Type {
            return dropTarget.supportedContentTypes
        }
        return [.data]
    }
}

//#Preview {
////    NodeSelectionInspector()
//}

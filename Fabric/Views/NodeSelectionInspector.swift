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

        List {

            Section(header: Text("Published"))
            {
                ParameterGroupView(parameterGroup:currentGraph.publishedParameterGroup)
            }

            ForEach(currentGraph.selectedNodes, id: \.id) { node in

                let vm = currentGraph.viewModel(for: node)

                Section(header: Text( vm.name ) )
                {
                    @Bindable var bindableVM: NodeViewModel = vm

                    Toggle("Node Settings", isOn: $bindableVM.showSettings)
                        .opacity(vm.providesSettingsView() ? 1.0 : 0.0)

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

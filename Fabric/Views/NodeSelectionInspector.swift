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
                }
            }
            
            Section(header: Text("Selected"))
            {
                ForEach(currentGraph.selectedNodes) { node in
                    
                    @Bindable var nodeViewModel: NodeViewModel = currentGraph.viewModel(for: node)
                    
                    GroupBox{
                        
                        VStack(alignment: .leading) {
                            
                            self.labelForNodeModelView(nodeViewModel)
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
                                                   fileContentTypes: Self.fileContentTypes(for: node))
                            }

                        }
                    }
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

    @ViewBuilder
    private func labelForNodeModelView(_ nodeViewModel: NodeViewModel) -> some View
    {
        if nodeViewModel.hasCustomLabel
        {
            VStack(alignment: .leading) {
                Text(nodeViewModel.name).foregroundStyle(.primary).bold()
                Text(nodeViewModel.typeName).foregroundStyle(.secondary).bold()
            }
        }
        else
        {
            Text(nodeViewModel.typeName).foregroundStyle(.primary).bold()
        }
    }
}

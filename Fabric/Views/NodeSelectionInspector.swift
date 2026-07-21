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
                            
                            Divider()
                            
                            let providesSettings = nodeViewModel.providesSettingsView()
                            
                            let title = nodeViewModel.showSettings ? "Hide Node Settings" : "Open Node Settings"
                            HStack {
                                Toggle(title, isOn: $nodeViewModel.showSettings)
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                                    .opacity( providesSettings ? 1.0 : 0.0)
                                    .frame(height:providesSettings ? nil : 0)
                                    .padding(.horizontal, 5)
                            }
                            
                            ParameterGroupView(parameterGroup: nodeViewModel.parameterGroup,
                                               fileContentTypes: Self.fileContentTypes(for: node))
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

    // TODO: This should be standardized somewhere...
    @ViewBuilder
    private func labelForNodeModelView(_ nodeViewModel:NodeViewModel) -> AnyView
    {
        let typeName: String = type(of: nodeViewModel.node).name
        let hasPrimaryLabel: Bool = nodeViewModel.name != typeName
        
        let primaryLabel = nodeViewModel.displayName ?? nodeViewModel.name
        
        
        if hasPrimaryLabel
        {
            return AnyView( VStack(alignment: .leading) {
                Text(typeName).foregroundStyle(nodeViewModel.nodeType.color())
                Text(primaryLabel).foregroundStyle(.white.opacity(0.6))
                }
            )
        }
        else
        {
            return AnyView(Text(typeName)
                .foregroundStyle(nodeViewModel.nodeType.color()))
        }
    }
}

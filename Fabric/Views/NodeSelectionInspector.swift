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
                .groupBoxStyle(InspectorCardGroupBoxStyle())
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
                                    .overlay(nodeViewModel.nodeType.color())

                                ParameterGroupView(parameterGroup: nodeViewModel.parameterGroup,
                                                   fileContentTypes: Self.fileContentTypes(for: node))
                            }
                        }
                    }
                    // Same card style as the Published group; the node's category
                    // colour becomes the outline, mirroring the canvas. Fill and
                    // outline share one shape, so the border always tracks the radius.
                    .groupBoxStyle(InspectorCardGroupBoxStyle(outline: nodeViewModel.nodeType.color()))
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
        
        let primaryLabel = nodeViewModel.name
        
        
        // The node's category colour is carried by the section outline (mirroring
        // the coloured outline of nodes on the canvas), so the title itself is
        // plain adaptive `.primary`, bold — legible on light and dark panels.
        if hasPrimaryLabel
        {
            return AnyView( VStack(alignment: .leading) {
                Text(typeName).foregroundStyle(.primary).bold()
                Text(primaryLabel).foregroundStyle(.primary).bold()
                }
            )
        }
        else
        {
            return AnyView(Text(typeName).foregroundStyle(.primary).bold())
        }
    }
}

/// Card styling for the inspector's group boxes: keeps the system GroupBox fill
/// (via the built-in `.automatic` style) and adds a coloured outline. One rounded
/// shape drives both the clip and the outline, so the border can never drift from
/// the corner radius — there is no public accessor for a system GroupBox's radius.
/// `outline` is `.clear` for a plain group and the node's category colour for a
/// selected node, mirroring the coloured outline of nodes on the canvas.
private struct InspectorCardGroupBoxStyle: GroupBoxStyle
{
    var outline: Color = .clear
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View
    {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        GroupBox { configuration.content }
            .groupBoxStyle(.automatic)   // system grouped fill + padding; avoids recursion
            .compositingGroup()
            .clipShape(shape)
            .overlay { shape.strokeBorder(outline, lineWidth: 1) }
    }
}

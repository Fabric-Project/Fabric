//
//  NodeRegisitryView.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import SwiftUI
import Satin

public struct NodeRegisitryView: View {

    public let graph: Graph
    @Binding public var scrollOffset: CGPoint
    @Binding public var scrollGeometry: ScrollGeometry
    public var onScrollToPosition: ((CGPoint) -> Void)?

    @State private var searchString:String = ""
    @State private var selection: Node.NodeTypeGroups = .All

    public init(graph: Graph, 
                scrollOffset: Binding<CGPoint>,
                scrollGeometry: Binding<ScrollGeometry>,
                onScrollToPosition: ((CGPoint) -> Void)? = nil) {
        self.graph = graph
        self._scrollOffset = scrollOffset
        self._scrollGeometry = scrollGeometry
        self.onScrollToPosition = onScrollToPosition
    }
    
    public var body: some View
    {
        VStack(spacing: 0)
        {
            Divider()
            
            Spacer()

            HStack
            {
                Spacer()
                                    
                ForEach(Node.NodeTypeGroups.allCases, id: \.self) { nodeGroup in
                    //Label(nodeType.rawValue, systemImage: nodeType.imageName())
                    nodeGroup.image()
                        .foregroundStyle( nodeGroup == selection ? Color.accentColor : Color.secondary.opacity(0.5))
                        .tag(nodeGroup)
                        .help(nodeGroup.rawValue)
                        .onTapGesture {
                            self.selection = nodeGroup
                        }
                }
                
                Spacer()
            }
            
            Spacer()

            Divider()

            Spacer()

            List
            {
                ForEach(selection.nodeTypes(), id: \.self) { nodeType in
                    
                    let filteredNodes = self.filteredNodes(forType: nodeType)
                    
                    if !filteredNodes.isEmpty
                    {
                        Section(header: Text("\(nodeType)")) {
                            
                            ForEach( 0 ..< filteredNodes.count, id:\.self ) { idx in
                                
                                let node = filteredNodes[idx]
                                
                                Text(node.nodeName)
                                    .font( .system(size: 11) )
                                    .onTapGesture {
                                        do {
                                            // Graph handles collision detection and returns final position and size
                                            let result = try self.graph.addNode(node, initialOffset: self.scrollOffset)
                                            
                                            // UI layer checks if node bounds are visible
                                            if !self.isNodeVisible(center: result.center, size: result.size) {
                                                // Node is outside visible bounds, scroll to center it
                                                self.onScrollToPosition?(result.center)
                                            }
                                        }
                                        catch
                                        {
                                            print("Error adding node: \(error)")
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: VerticalEdge.bottom, content: {
            
            VStack
            {
                Divider()
                
                HStack
                {
                    Spacer()

                    TextField("Search", text: $searchString)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .controlSize(.small)
                    
                    Spacer()
                    
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .onTapGesture {
                            self.searchString = ""
                        }
                    
                    Spacer()

                }
                .padding(.bottom, 3)
            }
        })
    }
    
    func filteredNodes(forType nodeType:Node.NodeType) -> [NodeClassWrapper]
    {
        let availableNodes:[NodeClassWrapper] = NodeRegistry.shared.availableNodes
        let nodesForType:[NodeClassWrapper] = availableNodes.filter( { $0.nodeType == nodeType })
        return  self.searchString.isEmpty ? nodesForType : nodesForType.filter {  $0.nodeName.localizedCaseInsensitiveContains(self.searchString) }
    }
    
    /// Checks if a node's bounds are visible in the current viewport
    /// Returns true only if the entire node is within the visible area
    private func isNodeVisible(center: CGPoint, size: CGSize) -> Bool
    {
        // Calculate visible bounds in canvas coordinates
        let contentOffset = scrollGeometry.contentOffset
        let containerSize = scrollGeometry.containerSize
        let contentSize = scrollGeometry.contentSize
        
        // The visible region in content coordinates
        let visibleMinX = contentOffset.x
        let visibleMaxX = contentOffset.x + containerSize.width
        let visibleMinY = contentOffset.y
        let visibleMaxY = contentOffset.y + containerSize.height
        
        // Convert canvas position to content coordinates
        // Canvas is centered in the content area
        let canvasOriginX = (contentSize.width - 10000) / 2.0
        let canvasOriginY = (contentSize.height - 10000) / 2.0
        
        let contentCenterX = canvasOriginX + center.x + 5000 // 5000 is half canvas size
        let contentCenterY = canvasOriginY + center.y + 5000
        
        // Calculate node bounds in content coordinates
        let nodeMinX = contentCenterX - size.width / 2.0
        let nodeMaxX = contentCenterX + size.width / 2.0
        let nodeMinY = contentCenterY - size.height / 2.0
        let nodeMaxY = contentCenterY + size.height / 2.0
        
        // Check if entire node is within visible bounds with some margin
        let margin: CGFloat = 20.0
        return nodeMinX >= visibleMinX + margin &&
               nodeMaxX <= visibleMaxX - margin &&
               nodeMinY >= visibleMinY + margin &&
               nodeMaxY <= visibleMaxY - margin
    }
}

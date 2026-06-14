//
//  NodeView.swift
//  v
//
//  Created by Anton Marini on 4/27/24.
//

import SwiftUI
import Satin

struct NodeView : View
{
    @Bindable var vm: NodeViewModel
    let editingContext: GraphCanvasContext

    var body: some View
    {
        ZStack(alignment: .topLeading)
        {
            vm.isSelected ? Color("NodeBackgroundColorSelected") : Color("NodeBackgroundColor")

            Rectangle()
                .fill( Color.black.gradient )
                .frame(height: 30)

            VStack(alignment: .leading, spacing: 10) {
                NodeTitleView(vm: vm)

                ForEach(vm.ports.filter({$0.kind == .Inlet && $0.direction == .Horizontal}), id: \.id) { port in
                    NodeInletView(port: port, editingContext: self.editingContext)
                }
                Spacer(minLength: 0)
            }
            .frame(width: vm.nodeSize.width + NodeInletView.radius, alignment: .leading)

            VStack(alignment: .trailing, spacing: 10) {
                Spacer(minLength: 0)
                    .frame(height: 25)

                ForEach(vm.ports.filter({$0.kind == .Outlet && $0.direction == .Horizontal}), id: \.id) { port in
                    NodeOutletView(port: port, editingContext: self.editingContext)
                }
                Spacer(minLength: 0)
            }
            .frame(width: vm.nodeSize.width + NodeInletView.radius, alignment: .trailing)
        }
        .frame(width: vm.nodeSize.width, height: vm.nodeSize.height)
        .clipShape(.rect(cornerRadius: cornerRadius()))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius())
                .stroke(vm.isSelected ? vm.nodeType.color() : .gray, lineWidth: vm.isSelected ? 1.5 : 1.0)
        }
    }

    func cornerRadius() -> CGFloat {
        switch vm.nodeType {
        case .Subgraph:
            return 5.0
        default:
            return 15.0
        }
    }
}

//
//  GraphNodeSettingsView.swift
//  Fabric
//

import SwiftUI

struct GraphNodeSettingsView: View
{
    @Binding var settingsEntries: [GraphSettingsEntry]
    let focus: FocusState<FabricEditorFocusTarget?>.Binding

    var body: some View
    {
        ForEach(settingsEntries, id: \.id) { entry in
            NodeSettingsPopoverAnchor(nodeViewModel: entry.nodeViewModel,
                                      anchorSize: entry.anchorSize,
                                      focus: focus,
                                      onClose: {
                entry.nodeViewModel.showSettings = false
            })
            .offset(entry.nodeViewModel.offset)
        }
    }

    /// Stable anchor for a settings popover.
    /// Reads no @Observable properties — anchorSize is a plain CGSize snapshot
    /// taken at open time, so port-count changes on the node do not re-render this view.
    private struct NodeSettingsPopoverAnchor: View
    {
        let nodeViewModel: NodeViewModel
        let anchorSize: CGSize
        let focus: FocusState<FabricEditorFocusTarget?>.Binding
        let onClose: () -> Void
        @State private var isPresented: Bool = true

        var body: some View
        {
            Rectangle()
                .fill(Color.clear)
                .frame(width: anchorSize.width, height: anchorSize.height)
                .popover(isPresented: $isPresented) {
                    NodeSettingView(nodeViewModel: nodeViewModel)
                        .interactiveDismissDisabled(true)
                        .focusable(true, interactions: .edit)
                        .focused(focus, equals: .nodeSettings(nodeViewModel.id))
                        .focusEffectDisabled()
                        .onAppear {
                            focus.wrappedValue = .nodeSettings(nodeViewModel.id)
                        }
                        .onDisappear {
                            if focus.wrappedValue == .nodeSettings(nodeViewModel.id)
                            {
                                focus.wrappedValue = .canvas
                            }
                        }
                }
                .onChange(of: isPresented) { _, newValue in
                    if !newValue { onClose() }
                }
        }
    }
}

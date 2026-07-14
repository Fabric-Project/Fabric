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
                        // Return-to-invoker: closing the panel that holds
                        // keyboard focus hands focus back to the canvas.
                        // FocusState cannot see focus inside a popover's
                        // window (its bindings never update when a field in
                        // the panel is being edited), so containment can't be
                        // read here. Instead, one runloop turn after teardown,
                        // detect *dangling* focus: if the focus enum doesn't
                        // know where focus is and no text editor survived as
                        // first responder, focus died with this panel —
                        // return it to the canvas. If typing continues in
                        // another panel's field (a live NSText first
                        // responder) or the enum names a live region, leave
                        // focus alone.
                        .onDisappear {
                            restoreCanvasFocusIfDangling()
                        }
                }
                .onChange(of: isPresented) { _, newValue in
                    if !newValue { onClose() }
                }
        }

        private func restoreCanvasFocusIfDangling()
        {
#if os(macOS)
            DispatchQueue.main.async {
                guard focus.wrappedValue == nil else { return }

                let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible)
                guard !(window?.firstResponder is NSText) else { return }

                focus.wrappedValue = .canvas
            }
#endif
        }
    }
}

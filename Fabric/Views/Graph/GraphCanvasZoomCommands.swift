import SwiftUI

/// Scene-scoped actions supplied by the canvas's view-local zoom state.
struct GraphCanvasZoomActions
{
    let zoomIn: (() -> Void)?
    let zoomOut: (() -> Void)?
}

private struct GraphCanvasZoomActionsKey: FocusedValueKey
{
    typealias Value = GraphCanvasZoomActions
}

extension FocusedValues
{
    var graphCanvasZoomActions: GraphCanvasZoomActions?
    {
        get { self[GraphCanvasZoomActionsKey.self] }
        set { self[GraphCanvasZoomActionsKey.self] = newValue }
    }
}

public struct GraphCanvasZoomCommands: Commands
{
    @FocusedValue(\.graphCanvasZoomActions) private var actions

    public init() {}

    public var body: some Commands
    {
        CommandGroup(after: .toolbar)
        {
            Menu("Canvas Zoom")
            {
                Button("Zoom In") { actions?.zoomIn?() }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(actions?.zoomIn == nil)

                Button("Zoom Out") { actions?.zoomOut?() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(actions?.zoomOut == nil)
            }
        }
    }
}

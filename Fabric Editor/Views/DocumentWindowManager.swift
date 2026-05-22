//
//  DocumentWindowManager.swift
//  Fabric Editor
//
//  Created by Anton Marini on 10/28/25.
//

import Foundation
import AppKit
import Metal
import simd
import Fabric
import Satin


private enum ToolbarID
{
    static let output = NSToolbar.Identifier("OutputToolbar")
    static let playPause = NSToolbarItem.Identifier("playPause")
}

class DocumentOutputWindowManager : NSObject
{
    weak var ownerDocument: FabricDocument?
    private var outputwindow: NSWindow? = nil
    private var outputViewController: MetalViewController? = nil
    private weak var graphRenderer: GraphRenderer? = nil

    // Toolbar shit
    private weak var playPauseItem: NSToolbarItem?

    override init()
    {
        self.outputwindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 600),
                                     styleMask: [.titled, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
                                     backing: .buffered, defer: false)
        self.outputwindow?.isReleasedWhenClosed = false
        self.outputwindow?.makeKeyAndOrderFront(nil)
        self.outputwindow?.level = .normal

        super.init()

        self.outputwindow?.delegate = self
        self.installToolbar()
    }

    private func installToolbar()
    {
        let tb = NSToolbar(identifier: ToolbarID.output)
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.sizeMode = .regular
        tb.allowsUserCustomization = false

        self.outputwindow?.toolbar = tb
        self.outputwindow?.toolbarStyle = .unified
    }

    func setGraph(graph: Graph, graphRenderer: GraphRenderer)
    {
        self.graphRenderer = graphRenderer
        graphRenderer.graph = graph

        let vc = MetalViewController(renderer: graphRenderer)
        vc.view.frame = self.outputwindow?.contentView?.bounds ?? .zero

        self.outputViewController = vc
        self.outputwindow?.contentViewController = vc
    }

    func setWindowName(_ name: String)
    {
        self.outputwindow?.title = name
    }

    func snapshotExportTime() -> TimeInterval
    {
        return self.graphRenderer?.lastGraphExecutionTime ?? 0
    }

    func closeOutputWindow()
    {
        self.outputwindow?.close()
    }

    deinit
    {
        print("Free DocumentOutputWindowManager")
    }
}

extension DocumentOutputWindowManager: NSWindowDelegate
{
    func windowDidBecomeMain(_ notification: Notification)
    {
        ActiveFabricDocumentStore.shared.activeDocument = self.ownerDocument
    }

    func windowWillClose(_ notification: Notification)
    {
        self.graphRenderer?.graph = nil
        self.outputwindow?.contentViewController = nil
        self.outputViewController = nil
        self.graphRenderer = nil
    }
}

extension DocumentOutputWindowManager: NSToolbarDelegate
{

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    {
        [
            ToolbarID.playPause,
            .flexibleSpace,
            .space,
        ]
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    {
        [.flexibleSpace,
         ToolbarID.playPause,
        ]
    }

    public func toolbar(_ toolbar: NSToolbar,
                        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                        willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {

        switch itemIdentifier
        {
        case ToolbarID.playPause:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Pause"
            item.toolTip = "Start or stop the output render loop"
            item.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(togglePlayback)
            self.playPauseItem = item
            return item

        default:
            return nil
        }
    }

    @objc private func togglePlayback()
    {
        guard let metalView = self.graphRenderer?.metalView else { return }
        metalView.isPaused.toggle()

        self.playPauseItem?.image = NSImage(
            systemSymbolName: metalView.isPaused ? "play.fill" : "pause.fill",
            accessibilityDescription: nil
        )
        self.playPauseItem?.label = metalView.isPaused ? "Play" : "Pause"
    }
}

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


private enum ToolbarID
{
    static let output = NSToolbar.Identifier("OutputToolbar")
    
    static let playPause   = NSToolbarItem.Identifier("playPause")
    
}

class DocumentOutputWindowManager : NSObject
{
    weak var ownerDocument: FabricDocument?
    private var outputwindow:NSWindow? = nil
    private var outputRenderer:CAMetalDisplayLinkRenderer? = nil
    
    // Toolbar shit
    private weak var playPauseItem: NSToolbarItem?

    
    override init()
    {
        self.outputwindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 600),
                                     styleMask: [.titled, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
                                     backing: .buffered, defer: false)
        self.outputwindow?.isReleasedWhenClosed = false
        self.outputwindow?.makeKeyAndOrderFront(nil)
        self.outputwindow?.level = .normal // NSWindow.Level(NSWindow.Level.normal.rawValue + 1)

        super.init()

        self.outputwindow?.delegate = self
        self.installToolbar()
    }
    
    private func installToolbar()
    {
        let tb = NSToolbar(identifier: ToolbarID.output)
        tb.delegate = self
        tb.displayMode = .iconOnly      // or .iconAndLabel
        tb.sizeMode   = .regular
        tb.allowsUserCustomization = false

        self.outputwindow?.toolbar = tb
        self.outputwindow?.toolbarStyle = .unified // or .unifiedCompact
    }
    
    func setGraph(graph:Graph)
    {
        self.outputRenderer = CAMetalDisplayLinkRenderer(graph:graph)
        self.outputRenderer?.frame = CGRect(x: 0,
                                            y: 0,
                                            width: self.outputwindow?.frame.size.width ?? 600,
                                            height: self.outputwindow?.frame.size.height ?? 600)
            
        self.outputwindow?.contentView = self.outputRenderer
    }
    
    func setWindowName(_ name:String)
    {
        self.outputwindow?.title = name
    }

    func snapshotExportTime() -> TimeInterval
    {
        guard
            let outputRenderer = self.outputRenderer,
            let lastRenderedGraphTime = outputRenderer.lastRenderedGraphTime
        else
        {
            return 0
        }

        return lastRenderedGraphTime
    }
    
    var isPaused: Bool {
        self.outputRenderer?.isPaused ?? true
    }

    func togglePlayback() {
        self.outputRenderer?.isPaused.toggle()
        self.updatePlayPauseButton()
    }

    func setPlaybackPaused(_ paused: Bool) {
        self.outputRenderer?.isPaused = paused
        self.updatePlayPauseButton()
    }

    private func updatePlayPauseButton() {
        let paused = self.isPaused
        self.playPauseItem?.image = NSImage(
            systemSymbolName: paused ? "play.fill" : "pause.fill",
            accessibilityDescription: paused ? "Play" : "Pause"
        )
        self.playPauseItem?.label = paused ? "Play" : "Pause"
    }

    func hideOutputWindow() {
        self.outputwindow?.orderOut(nil)
    }

    func showOutputWindow() {
        self.outputwindow?.makeKeyAndOrderFront(nil)
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
        // Tell the renderer to stop *all* time/display-linked work
        self.outputRenderer?.teardown()

        // Break strong reference cycles and detach the view from the window
        self.outputwindow?.contentView = nil
        self.outputRenderer = nil
    }
}

extension DocumentOutputWindowManager: NSToolbarDelegate
{

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    {
        [
            ToolbarID.playPause,
//            ToolbarID.snapshot,
//            ToolbarID.fit,
            .flexibleSpace,
            .space,
        ]
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    {
        [.flexibleSpace,
         ToolbarID.playPause,
//         ToolbarID.snapshot,
//         ToolbarID.fit
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
            item.action = #selector(toolbarTogglePlayback)
            self.playPauseItem = item
            return item

        default:
            return nil
        }
    }
    
    @objc private func toolbarTogglePlayback() {
        self.togglePlayback()
    }
}

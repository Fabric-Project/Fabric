//
//  DocumentWindowManager.swift
//  Fabric Editor
//
//  Created by Anton Marini on 10/28/25.
//

import Foundation
import AppKit
import Fabric
import Satin


private enum ToolbarID
{
    static let output = NSToolbar.Identifier("OutputToolbar")
    static let playPause = NSToolbarItem.Identifier("playPause")
}

/// Manages the separate output window. The window does not own rendering:
/// `OutputPresenter` lends it the document's `MetalViewController` while the
/// presentation mode is `.separateWindow`, and takes it back for the editor
/// canvas otherwise.
@MainActor
class DocumentOutputWindowManager : NSObject
{
    weak var ownerDocument: FabricDocument?
    weak var presenter: OutputPresenter?

    // Created on first present(), so documents opened in editor-canvas mode
    // never pay for a window they may not show.
    private var outputWindow: NSWindow?
    private var windowTitle = ""

    // Toolbar shit
    private weak var playPauseItem: NSToolbarItem?

    func present(_ viewController: NSViewController)
    {
        let window = self.makeWindowIfNeeded()

        viewController.view.frame = window.contentView?.bounds ?? .zero
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
    }

    func withdraw()
    {
        self.outputWindow?.orderOut(nil)
        self.outputWindow?.contentViewController = nil
    }

    func setWindowTitle(_ title: String)
    {
        self.windowTitle = title
        self.outputWindow?.title = title
    }

    func reflectPlaybackState()
    {
        guard let presenter = self.presenter else { return }

        self.playPauseItem?.image = NSImage(
            systemSymbolName: presenter.playbackControlSymbolName,
            accessibilityDescription: presenter.playbackControlLabel
        )
        self.playPauseItem?.label = presenter.playbackControlLabel
    }

    func closeWindow()
    {
        self.outputWindow?.delegate = nil
        self.outputWindow?.contentViewController = nil
        self.outputWindow?.close()
        self.outputWindow = nil
    }

    private func makeWindowIfNeeded() -> NSWindow
    {
        if let window = self.outputWindow {
            return window
        }

        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.title = self.windowTitle
        window.delegate = self

        let toolbar = NSToolbar(identifier: ToolbarID.output)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        self.outputWindow = window
        return window
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

    func windowShouldClose(_ sender: NSWindow) -> Bool
    {
        // The red close button routes here via performClose; move the output
        // into the editor canvas instead of tearing rendering down. Document
        // teardown uses close() directly, which skips this delegate method.
        self.presenter?.mode = .editorCanvas
        return false
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
            item.toolTip = "Start or stop the output render loop"
            item.target = self
            item.action = #selector(togglePlayback)
            self.playPauseItem = item
            self.reflectPlaybackState()
            return item

        default:
            return nil
        }
    }

    @objc private func togglePlayback()
    {
        self.presenter?.togglePlayback()
    }
}

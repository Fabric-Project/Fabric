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
    private var pendingWithdrawCompletion: (() -> Void)?
    private var isExitingFullScreen = false

    // Toolbar shit
    private weak var playPauseItem: NSToolbarItem?

    func present(_ viewController: NSViewController)
    {
        self.pendingWithdrawCompletion = nil

        let window = self.makeWindowIfNeeded()

        viewController.view.frame = window.contentView?.bounds ?? .zero
        window.contentViewController = viewController

        // orderFront, not makeKeyAndOrderFront: the mode is app-wide, so
        // every open document presents at once and none of their output
        // windows should steal the keyboard from the editor.
        window.orderFront(nil)
    }

    /// Completion fires once the window has given the view controller back —
    /// immediately, unless the window must exit full screen first.
    func withdraw(completion: @escaping () -> Void = {})
    {
        guard let window = self.outputWindow else {
            completion()
            return
        }

        if window.styleMask.contains(.fullScreen) || self.isExitingFullScreen
        {
            // A second withdraw can arrive while the exit animation runs;
            // toggling again would bounce the window back into full screen,
            // so only the parked completion is replaced.
            self.pendingWithdrawCompletion = completion
            if !self.isExitingFullScreen
            {
                self.isExitingFullScreen = true
                window.toggleFullScreen(nil)
            }
            return
        }

        window.orderOut(nil)
        window.contentViewController = nil
        completion()
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
        guard let window = self.outputWindow else {
            self.pendingWithdrawCompletion = nil
            self.isExitingFullScreen = false
            return
        }

        if window.styleMask.contains(.fullScreen) || self.isExitingFullScreen
        {
            // Closing a full-screen window in place strands its Space; exit
            // first and finish from windowDidExitFullScreen.
            self.pendingWithdrawCompletion = { [weak self] in self?.closeWindow() }
            if !self.isExitingFullScreen
            {
                self.isExitingFullScreen = true
                window.toggleFullScreen(nil)
            }
            return
        }

        self.pendingWithdrawCompletion = nil
        window.delegate = nil
        window.contentViewController = nil
        window.close()
        self.outputWindow = nil
    }

    private func makeWindowIfNeeded() -> NSWindow
    {
        if let window = self.outputWindow {
            return window
        }

        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 600),
                              styleMask: [.titled, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
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

    func windowDidExitFullScreen(_ notification: Notification)
    {
        self.isExitingFullScreen = false
        guard let completion = self.pendingWithdrawCompletion else { return }
        self.pendingWithdrawCompletion = nil
        self.withdraw(completion: completion)
    }

    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions
    {
        // Without this, a window with a toolbar keeps its title bar strip on
        // screen in full screen; hiding it with the menu bar leaves nothing
        // but the rendered output.
        proposedOptions.union(.autoHideToolbar)
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

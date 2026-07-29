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
    private var didPresentFatalRuntimeError = false
    private var lastRecoverableRuntimeError: (any FabricErrorProtocol)?

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

    func setGraphRenderer(_ graphRenderer: GraphRenderer)
    {
        self.graphRenderer = graphRenderer
        graphRenderer.errorDelegate = self

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
        self.graphRenderer?.errorDelegate = nil
        self.outputwindow?.contentViewController = nil  // triggers MetalViewController.cleanup() → renderer.cleanup()
        self.outputViewController = nil
        self.graphRenderer = nil
    }
}

extension DocumentOutputWindowManager: ErrorRenderDelegate
{
    func renderer(_ renderer: Renderer, didFailWith error: any Error)
    {
        MainActor.assumeIsolated {
            self.handleRuntimeError(error)
        }
    }

    private func handleRuntimeError(_ error: any Error)
    {
        let fabricError = self.fabricError(from: error)

        switch fabricError.severity {
        case .recoverable:
            self.lastRecoverableRuntimeError = fabricError
            print("Recoverable Fabric runtime error: \(fabricError.localizedDescription)")

        case .fatal:
            guard !self.didPresentFatalRuntimeError else { return }
            self.didPresentFatalRuntimeError = true
            self.graphRenderer?.metalView.isPaused = true
            self.presentFatalRuntimeErrorAlert(fabricError)
        }
    }

    private func fabricError(from error: any Error) -> any FabricErrorProtocol
    {
        if let fabricError = error as? any FabricErrorProtocol {
            return fabricError
        }

        return FabricError(.execution(.failed),
                           severity: .fatal,
                           message: error.localizedDescription,
                           underlyingError: error)
    }

    private func presentFatalRuntimeErrorAlert(_ error: any FabricErrorProtocol)
    {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Rendering Stopped"
        alert.informativeText = error.localizedDescription
        alert.runModal()
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

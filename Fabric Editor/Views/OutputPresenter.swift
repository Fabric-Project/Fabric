//
//  OutputPresenter.swift
//  Fabric Editor
//
//  Created by Toby Harris on 8/11/26.
//

import AppKit
import SwiftUI
import Fabric
import Satin

/// Where a document's rendered output is hosted.
enum OutputPresentationMode: String
{
    case separateWindow
    case editorCanvas
}

/// Owns the document's single `MetalViewController` and moves it between the
/// two hosts: the output window and the editor canvas background. Renderer,
/// Metal view, and the display link that drives graph execution are shared
/// across both, so playback state and the drawable pipeline carry over a mode
/// change.
@MainActor @Observable
final class OutputPresenter
{
    private static let modeDefaultsKey = "outputPresentationMode"

    var mode: OutputPresentationMode
    {
        didSet
        {
            guard self.mode != oldValue else { return }
            UserDefaults.standard.set(self.mode.rawValue, forKey: Self.modeDefaultsKey)
            self.applyMode()
        }
    }

    var isPaused: Bool = false
    {
        didSet
        {
            guard self.isPaused != oldValue else { return }
            self.viewController.metalView.isPaused = self.isPaused
            self.windowManager.reflectPlaybackState()
        }
    }

    // The one place the playback control's face is defined; both toolbars use it.
    var playbackControlLabel: String { self.isPaused ? "Play" : "Pause" }
    var playbackControlSymbolName: String { self.isPaused ? "play.fill" : "pause.fill" }

    @ObservationIgnored private let viewController: MetalViewController
    @ObservationIgnored private let windowManager: DocumentOutputWindowManager
    @ObservationIgnored private weak var renderer: GraphRenderer?
    @ObservationIgnored private weak var canvasContainer: NSView?

    @ObservationIgnored private var didPresentFatalRuntimeError = false

    init(ownerDocument: FabricDocument, renderer: GraphRenderer)
    {
        let storedMode = UserDefaults.standard.string(forKey: Self.modeDefaultsKey)
        self.mode = storedMode.flatMap(OutputPresentationMode.init(rawValue:)) ?? .separateWindow

        self.renderer = renderer
        self.viewController = MetalViewController(renderer: renderer)
        self.windowManager = DocumentOutputWindowManager()

        renderer.errorDelegate = self
        self.windowManager.ownerDocument = ownerDocument
        self.windowManager.presenter = self

        self.applyMode()
    }

    func setWindowTitle(_ title: String)
    {
        self.windowManager.setWindowTitle(title)
    }

    func togglePlayback()
    {
        self.isPaused.toggle()
    }

    /// Full teardown when the document's editor window goes away. The
    /// `MetalViewController` cleans its renderer up when the presenter is
    /// released along with the document.
    func teardown()
    {
        self.renderer?.errorDelegate = nil
        self.viewController.view.removeFromSuperview()
        self.canvasContainer = nil
        self.windowManager.closeWindow()
    }

    // MARK: - Canvas hosting

    /// `OutputCanvasHostView` hands its container over once it exists; the
    /// container appears after the mode flips, never before.
    func attachCanvasContainer(_ container: NSView)
    {
        guard self.canvasContainer !== container else { return }
        self.canvasContainer = container
        self.applyMode()
    }

    func detachCanvasContainer(_ container: NSView)
    {
        guard self.canvasContainer === container else { return }
        self.canvasContainer = nil
    }

    private func applyMode()
    {
        switch self.mode
        {
        case .separateWindow:
            self.viewController.view.removeFromSuperview()
            self.windowManager.present(self.viewController)

        case .editorCanvas:
            self.windowManager.withdraw()
            self.installInCanvas()
        }
    }

    private func installInCanvas()
    {
        guard let container = self.canvasContainer else { return }

        let view = self.viewController.view
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }
}

extension OutputPresenter: ErrorRenderDelegate
{
    nonisolated func renderer(_ renderer: Renderer, didFailWith error: any Error)
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
            print("Recoverable Fabric runtime error: \(fabricError.localizedDescription)")

        case .fatal:
            guard !self.didPresentFatalRuntimeError else { return }
            self.didPresentFatalRuntimeError = true
            self.isPaused = true
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

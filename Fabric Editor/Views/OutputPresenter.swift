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

/// Where rendered output is hosted.
enum OutputPresentationMode: String
{
    case separateWindow
    case editorCanvas
}

/// The app-wide output presentation mode, persisted across launches. Every
/// document's presenter observes it and re-hosts accordingly.
@MainActor @Observable
final class OutputSettings
{
    static let shared = OutputSettings()

    private static let modeDefaultsKey = "outputPresentationMode"

    var mode: OutputPresentationMode
    {
        didSet
        {
            guard self.mode != oldValue else { return }
            UserDefaults.standard.set(self.mode.rawValue, forKey: Self.modeDefaultsKey)
        }
    }

    private init()
    {
        let storedMode = UserDefaults.standard.string(forKey: Self.modeDefaultsKey)
        self.mode = storedMode.flatMap(OutputPresentationMode.init(rawValue:)) ?? .separateWindow
    }
}

/// Owns the document's single `MetalViewController` and moves it between the
/// two hosts: the output window and the editor canvas background. Renderer,
/// Metal view, and the display link that drives graph execution are shared
/// across both, so playback state and the drawable pipeline carry over a mode
/// change.
@MainActor @Observable
final class OutputPresenter
{
    var isPaused: Bool = false
    {
        didSet
        {
            guard self.isPaused != oldValue else { return }
            self.viewController.metalView.isPaused = self.isPaused
            self.windowManager.reflectPlaybackState()

            // Resuming re-arms the fatal-error alert; without this a second
            // fatal error after a user resume would be silently swallowed.
            if !self.isPaused { self.didPresentFatalRuntimeError = false }
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
    @ObservationIgnored private var isActive = true

    // Observation fires on willSet, so same-value writes to the app-wide
    // mode still wake every presenter; re-hosting is gated on this instead.
    @ObservationIgnored private var appliedMode: OutputPresentationMode?

    init(ownerDocument: FabricDocument, renderer: GraphRenderer)
    {
        self.renderer = renderer
        self.viewController = MetalViewController(renderer: renderer)
        self.windowManager = DocumentOutputWindowManager()

        renderer.errorDelegate = self
        self.windowManager.ownerDocument = ownerDocument
        self.windowManager.presenter = self

        self.applyMode()
        self.startObservingMode()
    }

    func setWindowTitle(_ title: String)
    {
        self.windowManager.setWindowTitle(title)
    }

    func togglePlayback()
    {
        self.isPaused.toggle()
    }

    /// Full teardown when the document's editor window goes away. Renderer
    /// cleanup is explicit rather than left to the view controller's deinit:
    /// SwiftUI value copies can keep the presenter alive past the document,
    /// and a renderer still marked set-up makes any re-created controller
    /// skip its own setup.
    func teardown()
    {
        self.isActive = false
        self.renderer?.errorDelegate = nil
        self.viewController.viewIfLoaded?.removeFromSuperview()
        self.canvasContainer = nil
        self.windowManager.closeWindow()
        self.viewController.cleanup()
    }

    // MARK: - Canvas hosting

    /// `OutputCanvasHostView` hands its container over once it exists; the
    /// container appears after the mode flips, never before, so the install
    /// that `applyMode` started is completed here.
    func attachCanvasContainer(_ container: NSView)
    {
        guard self.canvasContainer !== container else { return }
        self.canvasContainer = container

        guard self.isActive, self.appliedMode == .editorCanvas else { return }
        self.withdrawWindowThenInstallInCanvas()
    }

    func detachCanvasContainer(_ container: NSView)
    {
        guard self.canvasContainer === container else { return }
        self.canvasContainer = nil
    }

    /// Re-arming observation of the app-wide mode; each presenter applies
    /// changes to its own hosts. The outer closure must capture weakly: the
    /// observation registrar holds it until the mode next changes, which may
    /// be long after this document closes. The hop through `Task` is
    /// required, not a runloop dodge: `onChange` fires on willSet, so
    /// synchronous work here would read the outgoing mode and re-arm
    /// against it.
    private func startObservingMode()
    {
        withObservationTracking {
            _ = OutputSettings.shared.mode
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.applyMode()
                self.startObservingMode()
            }
        }
    }

    private func applyMode()
    {
        guard self.isActive else { return }

        let mode = OutputSettings.shared.mode
        guard mode != self.appliedMode else { return }
        self.appliedMode = mode

        switch mode
        {
        case .separateWindow:
            self.viewController.viewIfLoaded?.removeFromSuperview()
            self.windowManager.present(self.viewController)

        case .editorCanvas:
            self.withdrawWindowThenInstallInCanvas()
        }
    }

    /// Withdrawal completes asynchronously when the window has to exit full
    /// screen first; repeating it while that exit is in flight just replaces
    /// the parked install.
    private func withdrawWindowThenInstallInCanvas()
    {
        self.windowManager.withdraw { [weak self] in
            self?.installInCanvas()
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

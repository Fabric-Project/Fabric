//
//  OutputCanvasHostView.swift
//  Fabric Editor
//
//  Created by Toby Harris on 8/11/26.
//

import SwiftUI
import AppKit

/// Hosts the presenter's Metal view as the node canvas background. The
/// preview is display-only: the container opts out of hit testing entirely so
/// canvas interaction is untouched.
struct OutputCanvasHostView: NSViewRepresentable
{
    let presenter: OutputPresenter

    final class PassthroughContainerView: NSView
    {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    final class Coordinator
    {
        weak var presenter: OutputPresenter?
    }

    func makeCoordinator() -> Coordinator
    {
        Coordinator()
    }

    func makeNSView(context: Context) -> PassthroughContainerView
    {
        PassthroughContainerView()
    }

    func updateNSView(_ nsView: PassthroughContainerView, context: Context)
    {
        context.coordinator.presenter = self.presenter
        self.presenter.attachCanvasContainer(nsView)
    }

    static func dismantleNSView(_ nsView: PassthroughContainerView, coordinator: Coordinator)
    {
        MainActor.assumeIsolated {
            coordinator.presenter?.detachCanvasContainer(nsView)
        }
    }
}

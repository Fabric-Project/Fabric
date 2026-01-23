//
//  ScrollWheelZoomEventMonitor.swift
//  Fabric
//
//  Created by Chris Hocking on 21/1/2026.
//

#if os(macOS)
import AppKit
import SwiftUI

struct ScrollWheelZoomModifier: ViewModifier {
    var requiredModifiers: NSEvent.ModifierFlags
    var consumeScrollEvent: Bool
    var onZoom: (_ deltaY: CGFloat, _ normalizedAnchorInView: CGPoint) -> Void

    func body(content: Content) -> some View {
        content
            .background {
                ScrollWheelZoomEventMonitor(
                    requiredModifiers: requiredModifiers,
                    consumeScrollEvent: consumeScrollEvent,
                    onZoom: onZoom
                )
                .allowsHitTesting(false)
            }
    }
}

extension View {
    func scrollWheelZoom(
        requiredModifiers: NSEvent.ModifierFlags = .command,
        consumeScrollEvent: Bool = true,
        onZoom: @escaping (_ deltaY: CGFloat, _ normalizedAnchorInView: CGPoint) -> Void
    ) -> some View {
        modifier(
            ScrollWheelZoomModifier(
                requiredModifiers: requiredModifiers,
                consumeScrollEvent: consumeScrollEvent,
                onZoom: onZoom
            )
        )
    }
}

/// Captures scroll wheel events when a modifier key is held, and reports them with a normalized anchor.
/// Uses a local event monitor so it doesn't need to win hit-testing.
struct ScrollWheelZoomEventMonitor: NSViewRepresentable {

    /// Which modifier(s) must be held to trigger zoom (e.g. .command, .option).
    var requiredModifiers: NSEvent.ModifierFlags = .command

    var consumeScrollEvent: Bool = true

    /// Called when zoom should occur. `deltaY` matches NSEvent.scrollingDeltaY.
    var onZoom: (_ deltaY: CGFloat, _ normalizedAnchorInView: CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view, requiredModifiers: requiredModifiers, consumeScrollEvent: consumeScrollEvent, onZoom: onZoom)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(requiredModifiers: requiredModifiers, consumeScrollEvent: consumeScrollEvent, onZoom: onZoom)
        context.coordinator.view = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        weak var view: NSView?
        private var monitor: Any?
        private var requiredModifiers: NSEvent.ModifierFlags = .command
        private var consumeScrollEvent: Bool = true
        private var onZoom: ((_ deltaY: CGFloat, _ normalizedAnchorInView: CGPoint) -> Void)?

        func attach(
            to view: NSView,
            requiredModifiers: NSEvent.ModifierFlags,
            consumeScrollEvent: Bool,
            onZoom: @escaping (_ deltaY: CGFloat, _ normalizedAnchorInView: CGPoint) -> Void
        ) {
            self.view = view
            self.requiredModifiers = requiredModifiers
            self.consumeScrollEvent = consumeScrollEvent
            self.onZoom = onZoom

            // Remove any existing monitor (defensive).
            detach()

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard
                    let self,
                    let view = self.view,
                    let onZoom = self.onZoom
                else {
                    return event
                }

                // Only act when the required modifier(s) are held.
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard flags.contains(self.requiredModifiers) else {
                    return event
                }

                // Only zoom if the cursor is over *this* view.
                let locationInWindow = event.locationInWindow
                let locationInView = view.convert(locationInWindow, from: nil)
                guard view.bounds.width > 0, view.bounds.height > 0, view.bounds.contains(locationInView) else {
                    return event
                }

                // Normalize to SwiftUI-style UnitPoint space: x: 0..1 left->right, y: 0..1 top->bottom
                let normalized = CGPoint(
                    x: locationInView.x / view.bounds.width,
                    y: 1.0 - (locationInView.y / view.bounds.height)
                )

                onZoom(event.scrollingDeltaY, normalized)

                // Consume the scroll event so the ScrollView doesn't also scroll.
                return self.consumeScrollEvent ? nil : event
            }
        }

        func update(
            requiredModifiers: NSEvent.ModifierFlags,
            consumeScrollEvent: Bool,
            onZoom: @escaping (_ deltaY: CGFloat, _ normalizedAnchorInView: CGPoint) -> Void
        ) {
            self.requiredModifiers = requiredModifiers
            self.consumeScrollEvent = consumeScrollEvent
            self.onZoom = onZoom
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
#endif

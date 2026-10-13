//
//  WithoutTypingUndo.swift
//  Fabric
//

import SwiftUI

#if os(macOS)
import AppKit

extension View
{
    /// Turns off typing undo in the text views this view hosts. A text view
    /// with undo on records typing on the window's undo manager, which is the
    /// one the graph records on; a control bound to a settings draft records
    /// its text through the draft alone, and two records of one change
    /// interleave and undo each other. CodeEditorView turns undo on in its
    /// code view and offers no way to turn it off, and SwiftUI's TextEditor
    /// has none either, so this finds the text views once they are in the
    /// window and sets it there. A text field needs none of this: its field
    /// editor records typing on a cell undo manager of its own.
    func withoutTypingUndo() -> some View
    {
        background(TypingUndoSwitch())
    }
}

/// Sits behind the view it is applied to and switches typing undo off in the
/// text views that view hosts.
private struct TypingUndoSwitch: NSViewRepresentable
{
    func makeNSView(context: Context) -> SwitchView { SwitchView() }

    func updateNSView(_ nsView: SwitchView, context: Context)
    {
        nsView.switchOffTypingUndo()
    }

    final class SwitchView: NSView
    {
        // The hosted text view may join the window after this view; it is
        // there by the time SwiftUI lays the two out together.
        override func viewDidMoveToWindow()
        {
            super.viewDidMoveToWindow()
            self.switchOffTypingUndo()
        }

        override func layout()
        {
            super.layout()
            self.switchOffTypingUndo()
        }

        /// The text views, not field editors, that meet this view's frame,
        /// in the nearest ancestor that holds any: SwiftUI decides how deep
        /// the views it hosts side by side sit.
        func switchOffTypingUndo()
        {
            guard let window = self.window else { return }
            let area = self.convert(self.bounds, to: nil)
            var ancestor = self.superview
            while let view = ancestor
            {
                let textViews = Self.textViews(in: view).filter {
                    !$0.isFieldEditor && $0.convert($0.bounds, to: nil).intersects(area)
                }
                if !textViews.isEmpty
                {
                    textViews.forEach { $0.allowsUndo = false }
                    return
                }
                if view === window.contentView { return }
                ancestor = view.superview
            }
        }

        private static func textViews(in view: NSView) -> [NSTextView]
        {
            (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews(in:))
        }
    }
}
#else

extension View
{
    /// Typing undo is AppKit's; see the macOS implementation.
    func withoutTypingUndo() -> some View { self }
}
#endif

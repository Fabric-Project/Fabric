#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Fabric

/// Typing in a settings control records on the document's undo manager only
/// through the control's draft or parameter model.
@Suite("Typing Undo")
@MainActor
struct TypingUndoTests
{
    private final class WindowUndo: NSObject, NSWindowDelegate
    {
        let undoManager = UndoManager()
        func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undoManager }
    }

    /// An editable text view as CodeEditorView's code view is one: undo on.
    private struct HostedTextView: NSViewRepresentable
    {
        let textView: NSTextView
        func makeNSView(context: Context) -> NSTextView
        {
            textView.allowsUndo = true
            return textView
        }
        func updateNSView(_ nsView: NSTextView, context: Context) { }
    }

    private func makeWindow<Content: View>(_ content: Content) -> (NSWindow, WindowUndo)
    {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let windowUndo = WindowUndo()
        window.delegate = windowUndo
        let host = NSHostingView(rootView: content.frame(width: 300, height: 200))
        host.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(host)
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        return (window, windowUndo)
    }

    private func type(_ text: String, into textView: NSTextView, in window: NSWindow)
    {
        window.makeFirstResponder(textView)
        textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    @Test("A text view with undo on records typing on the window's undo manager")
    func textViewRecordsTyping()
    {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let (window, windowUndo) = makeWindow(HostedTextView(textView: textView))
        defer { window.close() }

        type("abc", into: textView, in: window)
        #expect(textView.string == "abc")
        #expect(windowUndo.undoManager.canUndo)
    }

    @Test("A text view under withoutTypingUndo records nothing on the window's undo manager")
    func textViewWithoutTypingUndoRecordsNothing()
    {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let (window, windowUndo) = makeWindow(HostedTextView(textView: textView).withoutTypingUndo())
        defer { window.close() }
        #expect(!textView.allowsUndo)

        type("abc", into: textView, in: window)
        #expect(textView.string == "abc")
        #expect(!windowUndo.undoManager.canUndo)
    }

    @Test("A text field records typing on its field editor's own undo manager, not the window's")
    func textFieldRecordsNothingOnTheWindow() throws
    {
        final class Text: ObservableObject { @Published var value = "" }
        struct Field: View
        {
            @ObservedObject var text: Text
            var body: some View { TextField("Text", text: $text.value) }
        }
        let text = Text()
        let (window, windowUndo) = makeWindow(Field(text: text))
        defer { window.close() }
        func field(in view: NSView) -> NSTextField?
        {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap(field(in:)).first
        }
        let textField = try #require(window.contentView.flatMap(field(in:)))

        window.makeFirstResponder(textField)
        let fieldEditor = try #require(window.firstResponder as? NSTextView)
        fieldEditor.insertText("abc", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(textField.stringValue == "abc")
        #expect(fieldEditor.undoManager !== windowUndo.undoManager)
        #expect(!windowUndo.undoManager.canUndo)
    }
}
#endif

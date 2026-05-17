//
//  EditorInputFocus.swift
//  Fabric
//
//  Created by Codex on 3/9/26.
//

import SwiftUI

public enum FabricEditorInputFocus: String, Codable, Hashable
{
    case canvas
    case registry
    case inspector
    case nodeSettings
}

/// Setter for the editor's input focus, injected via Environment by
/// GraphCanvas (which owns the binding). Descendant views — in
/// particular settings popover content — call this to claim arrow
/// keys when one of their text fields gains focus.
///
/// Why a callback in Environment and not `@FocusedValue`: the
/// settings popover is presented in its own NSWindow on macOS, and
/// FocusedValues don't bridge across that boundary, so a focused
/// value set inside the popover isn't visible to GraphCanvas.
/// SwiftUI environment values DO propagate to popover content.
///
/// Defaults to a no-op so call sites don't need optional chaining
/// when no GraphCanvas ancestor is present (matching SwiftUI's
/// own `dismiss` / `openURL` pattern).
///
/// Applied per text field — any TextField inside a settings view
/// that should hold the arrow keys reads this from the Environment
/// and invokes it with `.nodeSettings` when its `@FocusState`
/// becomes true.
///
/// Note: the Environment value is a bare closure. Closures aren't
/// Equatable, so each GraphCanvas body re-eval injects a "new"
/// closure and SwiftUI invalidates descendant readers. Tolerable
/// here (GraphCanvas re-evals infrequently, popover content is
/// cheap). If more callers appear, consider wrapping in a
/// `DismissAction`-style struct.
private struct EditorInputFocusSetterKey: EnvironmentKey
{
    static let defaultValue: @MainActor (FabricEditorInputFocus) -> Void = { _ in }
}

extension EnvironmentValues
{
    var setEditorInputFocus: @MainActor (FabricEditorInputFocus) -> Void
    {
        get { self[EditorInputFocusSetterKey.self] }
        set { self[EditorInputFocusSetterKey.self] = newValue }
    }
}

extension View
{
    /// Apply to any focusable control (typically a TextField) inside
    /// a node-settings popover. When the control gains focus, pushes
    /// the editor's input focus to `.nodeSettings` so the GraphCanvas
    /// key handler yields arrow keys back to the control.
    ///
    /// Bundles the `@Environment(\.setEditorInputFocus)` read and the
    /// focus-change observer so per-field call sites stay one line.
    /// Safe to apply to fields that already have their own
    /// `@FocusState` + `.focused(...)` — SwiftUI tolerates multiple
    /// `.focused` modifiers on the same field, each tracking it.
    func reclaimsNodeSettingsFocus() -> some View
    {
        modifier(ReclaimsNodeSettingsFocusModifier())
    }
}

private struct ReclaimsNodeSettingsFocusModifier: ViewModifier
{
    @FocusState private var focused: Bool
    @Environment(\.setEditorInputFocus) private var setEditorInputFocus

    func body(content: Content) -> some View
    {
        content
            .focused($focused)
            .onChange(of: focused) { _, isFocused in
                if isFocused { setEditorInputFocus(.nodeSettings) }
            }
    }
}

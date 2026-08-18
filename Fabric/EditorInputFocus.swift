//
//  EditorInputFocus.swift
//  Fabric
//

import Foundation

/// The editor's focusable regions, bound to SwiftUI's focus system via
/// `@FocusState` / `.focused(_:equals:)`. The value is written by SwiftUI on
/// every real focus change — when a text field (node settings, rename, search)
/// holds focus the value is that field's case or nil, so key handlers guarded
/// on `.canvas` can never intercept keys destined for text editing.
public enum FabricEditorFocusTarget: Hashable
{
    case canvas
    case noteEditor(UUID)
    case nodeSettings(UUID)
    case registrySearch
    case registryList
}

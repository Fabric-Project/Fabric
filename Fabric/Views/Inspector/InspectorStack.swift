//
//  InspectorStack.swift
//  Fabric
//

import SwiftUI

/// The scroll an inspector's sections sit in, in place of a `List`.
///
/// A deviation from the stock container, made once here. A text field in a
/// `List` row, of any style, edits with an opaque field editor that paints the
/// system text background over the field's own surface, and SwiftUI puts it
/// back when it is switched off; a stack in a scroll view edits in place. What
/// the `List` gave beyond scrolling is rebuilt: a click on the ground beside
/// or below the sections moves focus to the ground and so ends an edit in a
/// field. The ground is a clear leaf behind the content, focusable with the
/// default interactions: focusing a container lands on its first field, and a
/// leaf with only the activate interaction is focusable only while keyboard
/// navigation is on. The click reaches the ground by the tap on the scroll
/// view, since the ground sits behind the content, outside what a click on
/// the scroll's empty space hits.
///
/// A `List` cannot sit inside this, as it could not inside a `Form`: one
/// scroll inside another. A panel whose rows need a `List`, for its drag,
/// swipe and selection, keeps its own scrolling and takes `InspectorSection`
/// alone.
public struct InspectorStack<Content: View>: View
{
    private let content: Content
    @FocusState private var groundFocused: Bool

    public init(@ViewBuilder content: () -> Content)
    {
        self.content = content()
    }

    public var body: some View
    {
        ScrollView
        {
            VStack(alignment: .leading, spacing: 16)
            {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background
        {
            Color.clear
                .focusable()
                .focused($groundFocused)
                .focusEffectDisabled()
        }
        // A tap, not a button: the ground is not an action. See above for why
        // the tap, and not the ground's own click.
        .onTapGesture { groundFocused = true }
    }
}

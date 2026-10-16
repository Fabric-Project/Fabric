//
//  InspectorSection.swift
//  Fabric
//

import SwiftUI

/// A section of an inspector: a heading above one card.
///
/// The look of a grouped `Form`'s section, rebuilt from the parts the `Form`
/// draws it with, for a panel that cannot be a `Form`: one whose fields must
/// not sit in a `List` (see `InspectorStack`), or whose rows must be a `List`,
/// which a `Form` cannot hold. The card is a `GroupBox`, which is what a
/// grouped `Form` draws a section as, so its fill and border stay the system's;
/// the heading is `InspectorSectionHeading`, the one place its styling is
/// stated. `accessory` sits at the heading's trailing edge.
///
/// A section whose content is several cards takes the heading alone, above
/// its own cards.
public struct InspectorSection<Content: View, Accessory: View>: View
{
    private let title: String
    private let content: Content
    private let accessory: Accessory

    public init(_ title: String,
                @ViewBuilder content: () -> Content,
                @ViewBuilder accessory: () -> Accessory)
    {
        self.title = title
        self.content = content()
        self.accessory = accessory()
    }

    public var body: some View
    {
        VStack(alignment: .leading, spacing: 8)
        {
            HStack(spacing: 8)
            {
                InspectorSectionHeading(title)
                Spacer()
                accessory
            }
            GroupBox
            {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

public extension InspectorSection where Accessory == EmptyView
{
    init(_ title: String, @ViewBuilder content: () -> Content)
    {
        self.init(title, content: content, accessory: { EmptyView() })
    }
}

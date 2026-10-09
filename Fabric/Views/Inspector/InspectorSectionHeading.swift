//
//  InspectorSectionHeading.swift
//  Fabric
//

import SwiftUI

/// The heading of an inspector section: a grouped `Form`'s section heading,
/// stated once. `InspectorSection` puts it above a card; a section of several
/// cards puts it above them itself.
public struct InspectorSectionHeading: View
{
    private let title: String

    public init(_ title: String)
    {
        self.title = title
    }

    public var body: some View
    {
        Text(title)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }
}

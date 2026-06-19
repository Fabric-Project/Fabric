//
//  GraphBackground.swift
//  Fabric
//

import SwiftUI

struct GraphBackground: View
{
    let geom: GeometryProxy

    var body: some View
    {
        Image("background")
            .resizable(resizingMode: .tile)
            .offset(-geom.size / 2)
    }
}

//
//  AboutView.swift
//  Fabric
//
//  Created by Toby Harris on 11/8/25.
//

import SwiftUI
import Fabric

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            FabricLogoView()
                .frame(height: 60)
                .padding([.top], 20)
            
            Text("Fabric Editor")
                .font(.system(size: 24, weight: .bold))
            
            Text("A node-based visual programming environment")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text("Version \(version) (\(build))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .padding([.horizontal], 40)
            
            Text("© 2025 Anton Marini")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding([.bottom], 20)
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    AboutView()
}

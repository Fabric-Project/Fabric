//
//  FabricApp.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI

@main
struct FabricApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: FabricDocument()) { file in
            
            ContentView(document: file.$document)
        }
    }
}

//
//  CheckForUpdatesViewModel.swift
//  Fabric Editor
//
//  Created by Anton Marini on 11/13/25.
//

import SwiftUI
import Sparkle

// see https://sparkle-project.org/documentation/programmatic-setup/

// This view model class publishes when new updates can be checked by the user
final class CheckForUpdatesViewModel: ObservableObject
{
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater)
    {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

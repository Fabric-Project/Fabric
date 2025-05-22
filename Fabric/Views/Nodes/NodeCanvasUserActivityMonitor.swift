//
//  NodeCanvasActivityHelper.swift
//  Fabric
//
//  Created by Anton Marini on 5/22/25.
//

import SwiftUI
import Combine

@Observable
final class NodeCanvasUserActivityMonitor {
    var isActive: Bool = true

    @ObservationIgnored
    private var monitor:Any?
    
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    @ObservationIgnored
    private var lastMouseMovement = Date()

    @ObservationIgnored
    private let fadeOutDelay: TimeInterval

    init(fadeOutDelay: TimeInterval = 3.0)
    {
        self.fadeOutDelay = fadeOutDelay
        startMonitoring()
    }

    private func startMonitoring()
    {
        self.monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.resetActivity()
            return event
        }

        Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkInactivity()
            }
            .store(in: &cancellables)
    }

    deinit
    {
        if let monitor = self.monitor
        {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func resetActivity()
    {
        lastMouseMovement = Date()
        
        isActive = true
    }

    private func checkInactivity()
    {
        if Date().timeIntervalSince(lastMouseMovement) > fadeOutDelay
        {
            isActive = false
        }
    }
}

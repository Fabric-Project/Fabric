//
//  PortValueObservation.swift
//  Fabric
//

import Foundation
import Synchronization

/// A watcher of a port's value, as `Port.addValueObserver(_:)` returns it.
/// Its callback runs on the thread that changed the value, inside the change,
/// so it must only note that something changed and return; a control hops to
/// main from there.
public final class PortValueObservation: @unchecked Sendable
{
    fileprivate let valueDidChange: () -> Void

    fileprivate init(_ valueDidChange: @escaping () -> Void)
    {
        self.valueDidChange = valueDidChange
    }
}

extension Port
{
    public func addValueObserver(_ valueDidChange: @escaping () -> Void) -> PortValueObservation
    {
        let observation = PortValueObservation(valueDidChange)
        self.valueObservers.withLock { $0.append(observation) }
        self.valueObserverCount.add(1, ordering: .releasing)
        return observation
    }

    public func removeValueObserver(_ observation: PortValueObservation)
    {
        let removed = self.valueObservers.withLock { observers in
            let before = observers.count
            observers.removeAll { $0 === observation }
            return before - observers.count
        }
        if removed > 0 { self.valueObserverCount.subtract(removed, ordering: .releasing) }
    }

    internal func notifyValueObservers()
    {
        guard self.valueObserverCount.load(ordering: .acquiring) > 0 else { return }
        let observers = self.valueObservers.withLock { $0 }
        for observer in observers { observer.valueDidChange() }
    }
}

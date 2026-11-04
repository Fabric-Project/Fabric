//
//  ParameterViewModel.swift
//  Fabric
//
//  Created by Anton Marini on 10/12/25.
//

import Foundation
import Combine
import Observation
import Synchronization

/// A control's value, observable by its view. A control over a port follows
/// the port: the port's observer notes a change on whatever thread sent it,
/// and one hop to main per turn reads the port and updates `uiValue` if it
/// differs. A control with no port, a node setting or a range bound, follows
/// the publisher it is given.
@Observable
final class ParameterObservableModel<Value: Equatable>
{
    var uiValue: Value
    {
        didSet
        {
            guard !applyingEngine else { return }
            if getValue() != uiValue
            {
                applyingUI = true
                setValue(uiValue)
                applyingUI = false
            }
        }
    }

    @ObservationIgnored let label: String
    @ObservationIgnored private let getValue: () -> Value
    @ObservationIgnored private let setValue: (Value) -> Void

    @ObservationIgnored private var sub: AnyCancellable?
    @ObservationIgnored private var applyingEngine = false
    @ObservationIgnored private var applyingUI = false

    @ObservationIgnored private var observedPort: Port?
    @ObservationIgnored private var observation: PortValueObservation?
    private let refreshPending = Atomic<Bool>(false)

    init(label: String,
         get: @escaping () -> Value,
         set: @escaping (Value) -> Void,
         publisher: PassthroughSubject<Value, Never>)
    {
        self.label = label
        self.getValue = get
        self.setValue = set
        self.uiValue = get()

        self.sub = publisher
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(16), scheduler: RunLoop.main, latest: true)
            .removeDuplicates()
            .sink { [weak self] newVal in
                guard let self, !self.applyingUI else { return }
                self.applyingEngine = true
                if self.uiValue != newVal { self.uiValue = newVal }
                self.applyingEngine = false
            }
    }

    /// `publisher` is followed only when the control has no port.
    convenience init(control: ControlValue<Value>, publisher: PassthroughSubject<Value, Never>) where Value: PortValueRepresentable & Codable & Hashable
    {
        guard let port = control.port else
        {
            self.init(label: control.label, get: control.get, set: control.set, publisher: publisher)
            return
        }

        self.init(label: control.label, get: control.get, set: control.set, observing: port)
    }

    private init(label: String, get: @escaping () -> Value, set: @escaping (Value) -> Void, observing port: Port)
    {
        self.label = label
        self.getValue = get
        self.setValue = set
        self.uiValue = get()
        self.observedPort = port
        self.observation = port.addValueObserver { [weak self, unowned port] in
            self?.portValueDidChange(port)
        }
    }

    /// On the sending thread: schedule one refresh unless one is pending.
    private func portValueDidChange(_ port: Port)
    {
        guard let node = port.node,
              !self.refreshPending.exchange(true, ordering: .acquiringAndReleasing)
        else { return }

        node.performOnMainAsync { [weak self] in
            guard let self else { return }
            self.refreshPending.store(false, ordering: .releasing)
            let value = self.getValue()
            guard self.uiValue != value else { return }
            self.applyingEngine = true
            self.uiValue = value
            self.applyingEngine = false
        }
    }

    deinit
    {
        sub?.cancel()
        if let observation { observedPort?.removeValueObserver(observation) }
    }
}

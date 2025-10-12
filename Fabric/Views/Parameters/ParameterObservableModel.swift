//
//  ParameterViewModel.swift
//  Fabric
//
//  Created by Anton Marini on 10/12/25.
//

import Foundation
import Combine
import Observation

import Foundation
import Combine
import Observation

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

    init(label: String,
         get: @escaping () -> Value,
         set: @escaping (Value) -> Void,
    publisher: PassthroughSubject<Value, Never>)
    {
        self.label = label
        self.getValue = get
        self.setValue = set
        self.uiValue = get()

        sub = publisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] newVal in
                guard let self, !self.applyingUI else { return }
                self.applyingEngine = true
                if self.uiValue != newVal { self.uiValue = newVal }
                self.applyingEngine = false
            }
    }

    deinit { sub?.cancel() }
}

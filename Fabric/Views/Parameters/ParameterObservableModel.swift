//
//  ParameterViewModel.swift
//  Fabric
//
//  Created by Anton Marini on 10/12/25.
//

import Foundation
import Combine
import Satin
import Observation
import Satin

/// When a change made through the control becomes an undo step.
enum ParameterEditCommit
{
    /// Each change is a step of its own, except while the control reports an
    /// edit in progress, as a drag or a text field does: the edit is then one
    /// step, made when it ends.
    case eachChange

    /// The changes are one step once they pause, for a control that reports
    /// no end to an edit, such as a colour panel.
    case afterPause
}

@MainActor
@Observable
final class ParameterObservableModel<Value: Codable & Equatable>
{
    var uiValue: Value
    {
        didSet
        {
            guard !applyingEngine else { return }
            if getValue() != uiValue
            {
                if editStart == nil { editStart = oldValue }
                applyingUI = true
                setValue(uiValue)
                applyingUI = false
                self.commitUnlessEditing()
            }
        }
    }

    @ObservationIgnored let label: String
    @ObservationIgnored private let getValue: () -> Value
    @ObservationIgnored private let setValue: (Value) -> Void

    @ObservationIgnored private var publisher: PassthroughSubject<Value, Never>
    @ObservationIgnored private var sub: AnyCancellable?
    @ObservationIgnored private var applyingEngine = false
    @ObservationIgnored private var applyingUI = false

    /// The graph the control shows the parameter in, which records the edit
    /// with the document's undo manager. Without one edits are made but not
    /// recorded.
    @ObservationIgnored private weak var graph: Graph?
    /// The parameter whose value the control edits, for an undo step to find
    /// again; nil for a control whose changes are not edits, such as a
    /// momentary button.
    @ObservationIgnored private weak var undoParameter: GenericParameter<Value>?
    @ObservationIgnored private let commit: ParameterEditCommit
    @ObservationIgnored private var editStart: Value?
    @ObservationIgnored private var isEditing = false
    @ObservationIgnored private var pendingCommit: Task<Void, Never>?

    init(label: String,
         get: @escaping () -> Value,
         set: @escaping (Value) -> Void,
    publisher: PassthroughSubject<Value, Never>,
         graph: Graph? = nil,
         undoParameter: GenericParameter<Value>? = nil,
         commit: ParameterEditCommit = .eachChange)
    {
        self.label = label
        self.getValue = get
        self.setValue = set
        self.uiValue = get()
        self.publisher = publisher
        self.graph = graph
        self.undoParameter = undoParameter
        self.commit = commit
        
        self.attach()
    }
    
    func attach()
    {
        sub = publisher
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
    
    func detach()
    {
        sub?.cancel()
    }

    deinit { sub?.cancel() }

    // MARK: - Undo

    /// For a control whose edits span many changes, a drag or a text field:
    /// true as an edit starts, false as it ends, which records it. A control
    /// that goes away mid-edit ends it, so the edit is not left unrecorded.
    func setEditing(_ editing: Bool)
    {
        isEditing = editing
        if !editing { self.commitEdit() }
    }

    private func commitUnlessEditing()
    {
        guard !isEditing else { return }
        switch commit
        {
        case .eachChange:
            self.commitEdit()

        case .afterPause:
            pendingCommit?.cancel()
            pendingCommit = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.commitEdit()
            }
        }
    }

    /// Records the edit since the last commit as one undo step.
    private func commitEdit()
    {
        pendingCommit?.cancel()
        pendingCommit = nil
        guard let start = editStart else { return }
        editStart = nil
        guard start != getValue(), let graph, let undoParameter else { return }
        graph.registerValueChange(of: undoParameter, from: start, label: label)
    }
}

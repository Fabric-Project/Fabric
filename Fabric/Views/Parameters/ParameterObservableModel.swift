//
//  ParameterViewModel.swift
//  Fabric
//
//  Created by Anton Marini on 10/12/25.
//

import Foundation
import Combine
import Observation
import Satin

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
                // The parameter's value, not the mirror's: the mirror follows
                // it a frame behind.
                if editStart == nil { editStart = getValue() }
                applyingUI = true
                setValue(uiValue)
                applyingUI = false
                self.holdOrCommit()
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
    @ObservationIgnored private let commit: EditCommit
    @ObservationIgnored private var editStart: Value?
    @ObservationIgnored private var isEditing = false
    @ObservationIgnored private let pendingCommit = PendingCommit()

    init(label: String,
         get: @escaping () -> Value,
         set: @escaping (Value) -> Void,
    publisher: PassthroughSubject<Value, Never>,
         graph: Graph? = nil,
         undoParameter: GenericParameter<Value>? = nil,
         commit: EditCommit = .eachChange)
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
        if editing
        {
            // A change held for its pause is the edit's now.
            if editStart != nil { self.holdOrCommit() }
        }
        else
        {
            self.commitEdit()
        }
    }

    /// Holds the change since the edit started for Graph.undo() to commit
    /// while the control is editing, so an undo takes it back rather than
    /// passing over it, or commits it as the control's policy says. A change
    /// returned to where the edit started is not an edit.
    private func holdOrCommit()
    {
        guard let start = editStart, start != getValue(), undoParameter != nil else
        {
            editStart = nil
            pendingCommit.cancel()
            return
        }
        let undoManager = graph?.effectiveUndoManager
        let commitEdit: () -> Void = { [weak self] in self?.commitEdit() }
        if isEditing
        {
            pendingCommit.hold(on: undoManager, commitEdit)
            return
        }
        switch commit
        {
        case .eachChange:
            self.commitEdit()

        case .afterPause:
            pendingCommit.schedule(after: .milliseconds(500), undoManager: undoManager, commitEdit)
        }
    }

    /// Records the edit since the last commit as one undo step.
    private func commitEdit()
    {
        pendingCommit.cancel()
        guard let start = editStart else { return }
        editStart = nil
        guard start != getValue(), let graph, let undoParameter else { return }
        // A commit Graph.undo() makes comes ahead of the undo, as a step of
        // its own, when no event group is open.
        let undoManager = graph.effectiveUndoManager
        let opensGroup = undoManager?.groupingLevel == 0
        if opensGroup { undoManager?.beginUndoGrouping() }
        graph.registerValueChange(of: undoParameter, from: start, label: label)
        if opensGroup { undoManager?.endUndoGrouping() }
    }
}

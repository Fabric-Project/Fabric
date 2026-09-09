//
//  CloneMemberObserver.swift
//  Fabric
//
//  Created by Claude on 9/10/26.
//

import Foundation
import Combine
import Observation
import Satin

/// Watches everything inside a clone set member for edits of its design,
/// through the signals nodes, ports and parameters already publish, and
/// reports them to the member's graph so the set is synced once edits
/// pause. Owned by the member; nothing on Node or Port knows about it.
///
/// What counts as an edit: a node moved or renamed, a port published,
/// unpublished or renamed, a resting parameter value changed from the main
/// thread. Values arriving on wired or published inlets, and anything the
/// render thread writes, are runtime traffic and are ignored. Topology
/// changes reach the graph directly through its mutation API.
final class CloneMemberObserver
{
    private weak var member: SubgraphNode?
    private var cancellables: [AnyCancellable] = []
    private var userNames: [UUID: String?] = [:]
    private var active = true

    init(member: SubgraphNode)
    {
        self.member = member
        self.refresh()
    }

    /// Re-subscribes to the member's current node tree. Called after a sync,
    /// which is when nodes may have come or gone.
    func refresh()
    {
        cancellables.removeAll()
        userNames.removeAll()
        guard active, let member else { return }

        for node in member.subGraph.nodesRecursive()
        {
            self.watch(node)
        }
    }

    func stop()
    {
        active = false
        cancellables.removeAll()
    }

    private func noteEdit()
    {
        member?.subGraph.noteContentChanged()
    }

    private func watch(_ node: Node)
    {
        userNames[node.id] = node.userName

        node.offsetSubject
            .dropFirst()
            .sink { [weak self] _ in self?.noteEdit() }
            .store(in: &cancellables)

        // The subject also fires for derived subtitles, some of which follow
        // a port every frame; only the rename is an edit.
        node.subtitleSubject
            .sink { [weak self, weak node] in
                guard let self, let node else { return }
                let userName = node.userName
                guard self.userNames[node.id] != .some(userName) else { return }
                self.userNames[node.id] = userName
                self.noteEdit()
            }
            .store(in: &cancellables)

        node.portsChangedSubject
            .sink { [weak self] in self?.noteEdit() }
            .store(in: &cancellables)

        for port in node.ports
        {
            self.watchPublishedState(of: port)
            if let parameter = port.parameter
            {
                self.watchValue(of: parameter, on: port)
            }
        }
    }

    /// Port is Observable: one registration per change, renewed on each.
    private func watchPublishedState(of port: Port)
    {
        guard active else { return }
        withObservationTracking {
            _ = port.published
            _ = port.publishedName
        } onChange: { [weak self, weak port] in
            guard let self, self.active else { return }
            self.noteEdit()
            if let port { self.watchPublishedState(of: port) }
        }
    }

    private func watchValue(of parameter: any Parameter, on port: Port)
    {
        self.watchValue(parameter, on: port)
    }

    private func watchValue<P: Parameter>(_ parameter: P, on port: Port)
    {
        parameter.valuePublisher
            .sink { [weak self, weak port] _ in
                guard let self, let port,
                      Thread.isMainThread,
                      !port.published,
                      port.connections.isEmpty
                else { return }
                self.noteEdit()
            }
            .store(in: &cancellables)
    }
}

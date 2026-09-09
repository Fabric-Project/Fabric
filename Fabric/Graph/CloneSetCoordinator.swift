//
//  CloneSetCoordinator.swift
//  Fabric
//
//  Created by Claude on 9/10/26.
//

import Foundation

/// Per-document clone set state, owned by the root graph. See Graph+CloneSet.
public final class CloneSetCoordinator
{
    /// Set while a member is being brought in line with its set, so the
    /// writes that reconcile makes are never mistaken for edits of their own.
    var isReconciling = false

    private(set) weak var rootGraph: Graph?

    init(rootGraph: Graph)
    {
        self.rootGraph = rootGraph
    }
}

//
//  Node+ExecuteLookupCheck.swift
//  Fabric
//

import Foundation

extension Node
{
    private static let executingKey = "info.vade.fabric.executingNode"
    private static let lookupsKey = "info.vade.fabric.executeTimeLookups"

    /// Runs `body` as the execution of a node: a port lookup by key inside it
    /// is a defect, recorded and reported in debug builds. A node reads its
    /// ports in execute through the references bindPorts() resolved.
    @inline(__always)
    internal static func runAsExecution<Result>(_ body: () throws -> Result) rethrows -> Result
    {
#if DEBUG
        let dictionary = Thread.current.threadDictionary
        let enclosing = dictionary[executingKey]
        dictionary[executingKey] = true
        defer { dictionary[executingKey] = enclosing }
#endif
        return try body()
    }

    @inline(__always)
    internal static func checkLookupOutsideExecute(_ key: String, on node: Node)
    {
#if DEBUG
        let dictionary = Thread.current.threadDictionary
        guard dictionary[executingKey] != nil else { return }
        let lookup = "\(String(describing: type(of: node))).\(key)"
        let recorded = dictionary[lookupsKey] as? NSMutableArray ?? NSMutableArray()
        recorded.add(lookup)
        dictionary[lookupsKey] = recorded
        print("Fabric: \(lookup) looked up by key during execute; bind it in bindPorts()")
#endif
    }

    /// The lookups by key this thread made during execute since last asked, in
    /// debug builds; empty otherwise.
    internal static func takeExecuteTimeLookups() -> [String]
    {
#if DEBUG
        let dictionary = Thread.current.threadDictionary
        let recorded = dictionary[lookupsKey] as? NSMutableArray
        dictionary[lookupsKey] = nil
        return recorded?.compactMap { $0 as? String } ?? []
#else
        return []
#endif
    }
}

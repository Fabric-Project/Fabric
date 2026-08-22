//
//  NodeExecutionResult.swift
//  Fabric
//

public enum NodeExecutionResult: String, Codable
{
    case executed
    case skippedClean
    case skippedDeclined
    case error
}

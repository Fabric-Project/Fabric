//
//  FabricError.swift
//  Fabric
//
//  Created by Anton Marini on 7/24/26.
//

import Foundation

public protocol FabricErrorProtocol: Error, LocalizedError, Sendable
{
    var severity: FabricErrorSeverity { get }
}

public enum FabricErrorSeverity: Sendable, Codable, Equatable
{
    case recoverable
    case fatal
}

public struct FabricError: FabricErrorProtocol
{
    public let severity: FabricErrorSeverity
    public let kind: FabricErrorKind
    public let message: String
    public let underlyingError: (any Error)?

    public init(_ kind: FabricErrorKind,
                severity: FabricErrorSeverity,
                message: String,
                underlyingError: (any Error)? = nil)
    {
        self.kind = kind
        self.severity = severity
        self.message = message
        self.underlyingError = underlyingError
    }

    public var errorDescription: String?
    {
        message
    }
}

public enum FabricErrorKind: Sendable, Codable, Equatable
{
    case general(General)
    case loading(Loading)
    case deserialization(Deserialization)
    case execution(Execution)
    case graph(Graph)

    public enum General: Sendable, Codable, Equatable
    {
        case unknown
        case invalidState
        case unsupported
    }

    public enum Loading: Sendable, Codable, Equatable
    {
        case pluginNotFound
        case pluginLoadFailed
        case resourceNotFound
    }

    public enum Deserialization: Sendable, Codable, Equatable
    {
        case documentInvalid
        case nodeNotFound
        case nodeInvalid
    }

    public enum Execution: Sendable, Codable, Equatable
    {
        case failed
        case fileNotFound
        case deviceNotFound
        case outOfMemory
        case gpu
        case syntax
    }

    public enum Graph: Sendable, Codable, Equatable
    {
        case emptyNodeSelection
        case nodeNotInGraph
    }
}

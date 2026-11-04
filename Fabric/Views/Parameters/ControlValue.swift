//
//  ControlValue.swift
//  Fabric
//

import Foundation
import Satin

/// Where a control reads and writes its value. With a port, the port: its
/// value is canonical, and its parameter only mirrors it, for the range,
/// options and label a control draws. Without one, the parameter itself, for
/// a control over a node's own setting that no port carries.
struct ControlValue<Value: PortValueRepresentable & Codable & Hashable>
{
    let label: String
    let get: () -> Value
    let set: (Value) -> Void
    let port: NodePort<Value>?

    init(parameter: GenericParameter<Value>, port: NodePort<Value>?)
    {
        self.port = port
        guard let port else
        {
            self.label = parameter.label
            self.get = { parameter.value }
            self.set = { parameter.value = $0 }
            return
        }

        self.label = port.displayName
        self.get = { port.value ?? parameter.value }
        self.set = { value in
            if let graph = port.node?.graph { graph.setControlValue(value, on: port) } else { port.value = value }
        }
    }
}

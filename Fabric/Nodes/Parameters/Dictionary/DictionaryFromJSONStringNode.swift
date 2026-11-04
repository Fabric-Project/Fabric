//
//  DictionaryFromJSONStringNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public final class DictionaryFromJSONStringNode: Node
{
    public override class var name: String { "Dictionary From JSON String" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Dictionary) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Parses a JSON object string into a boxed dictionary." }

    public let inputJSONString = ParameterPort(parameter: StringParameter("JSON", "", .inputfield, "JSON object string to parse"))
    public let outputDictionary: Port = PortType.Dictionary(valueType: .Virtual).makeFreshPort(name: "Dictionary", kind: .Outlet, description: "Parsed dictionary")
    public let outputValid = NodePort<Bool>(name: "Valid", kind: .Outlet, description: "Whether parsing succeeded")
    public let outputError = NodePort<String>(name: "Error", kind: .Outlet, description: "Parsing error message")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputJSONString", port: self.inputJSONString),
            PortDeclaration(key: "outputDictionary", port: self.outputDictionary),
            PortDeclaration(key: "outputValid", port: self.outputValid),
            PortDeclaration(key: "outputError", port: self.outputError),
        ]
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard inputJSONString.valueDidChange else { return }
        let source = inputJSONString.value ?? ""

        guard let data = source.data(using: .utf8) else
        {
            sendInvalid("JSON string is not valid UTF-8.")
            return
        }

        do
        {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any] else
            {
                sendInvalid("JSON root must be an object.")
                return
            }

            outputDictionary.sendBoxed(.Dictionary(boxedDictionary(from: dictionary)))
            outputValid.send(true)
            outputError.send("")
        }
        catch
        {
            sendInvalid(error.localizedDescription)
        }
    }

    private func sendInvalid(_ message: String)
    {
        outputDictionary.sendBoxed(nil)
        outputValid.send(false)
        outputError.send(message)
    }

    private func boxedDictionary(from dictionary: [String: Any]) -> Dictionary<String, PortValue>
    {
        var result: Dictionary<String, PortValue> = [:]
        result.reserveCapacity(dictionary.count)

        for (key, value) in dictionary
        {
            if let boxed = boxedValue(from: value)
            {
                result[key] = boxed
            }
        }

        return result
    }

    private func boxedArray(from array: [Any]) -> ContiguousArray<PortValue>
    {
        ContiguousArray(array.compactMap { boxedValue(from: $0) })
    }

    private func boxedValue(from value: Any) -> PortValue?
    {
        if value is NSNull { return nil }

        if let number = value as? NSNumber
        {
            if CFGetTypeID(number) == CFBooleanGetTypeID()
            {
                return .Bool(number.boolValue)
            }

            return .Float(number.floatValue)
        }

        if let string = value as? String { return .String(string) }
        if let array = value as? [Any] { return .Array(boxedArray(from: array)) }
        if let dictionary = value as? [String: Any] { return .Dictionary(boxedDictionary(from: dictionary)) }

        return nil
    }
}

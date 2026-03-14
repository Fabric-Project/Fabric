//
//  JavaScriptNode.swift
//  Fabric
//
//  Created by Codex on 3/13/26.
//

import Foundation
import JavaScriptCore
import Metal
import Satin
import SwiftUI
import simd

public struct JavaScriptNodeDiagnostic: Hashable
{
    public enum Severity: String, Codable, Hashable
    {
        case error
        case warning
    }

    public let line: Int
    public let column: Int
    public let severity: Severity
    public let summary: String
    public let detail: String

    init(line: Int = 0,
         column: Int = 0,
         severity: Severity = .error,
         summary: String,
         detail: String = "")
    {
        self.line = line
        self.column = column
        self.severity = severity
        self.summary = summary
        self.detail = detail
    }
}

struct JavaScriptNodePortDefinition: Hashable
{
    enum Direction: Hashable
    {
        case input
        case output
    }

    let direction: Direction
    let name: String
    let portType: PortType

    func hash(into hasher: inout Hasher)
    {
        hasher.combine(direction)
        hasher.combine(name)
        hasher.combine(portType.rawValue)
    }
}

struct JavaScriptNodeSignature: Hashable
{
    let inputs: [JavaScriptNodePortDefinition]
    let outputs: [JavaScriptNodePortDefinition]
    let transpiledSource: String
}

private enum JavaScriptNodeParseError: LocalizedError
{
    case blockedSyntax(String)
    case missingMainSignature
    case invalidAnnotation(String)
    case duplicatePortName(String)
    case unsupportedType(String)
    case shaderUnsupported

    var errorDescription: String?
    {
        switch self
        {
        case .blockedSyntax(let token):
            return "Blocked JavaScript syntax: \(token)"
        case .missingMainSignature:
            return "Expected `function (<outputs>) main(<inputs>)` at the top level."
        case .invalidAnnotation(let annotation):
            return "Invalid port annotation `\(annotation)`."
        case .duplicatePortName(let name):
            return "Port name `\(name)` is declared more than once."
        case .unsupportedType(let type):
            return "Unsupported Fabric JavaScript type `\(type)`."
        case .shaderUnsupported:
            return "Shader ports are not supported in the JavaScript node."
        }
    }
}

private enum JavaScriptNodeExecutionError: LocalizedError
{
    case missingMainFunction
    case invalidReturnShape
    case extraOutput(String)
    case invalidOutput(name: String, expected: String)

    var errorDescription: String?
    {
        switch self
        {
        case .missingMainFunction:
            return "Compiled script does not define a callable `main` function."
        case .invalidReturnShape:
            return "JavaScript `main` must return an object containing the declared output values."
        case .extraOutput(let key):
            return "JavaScript returned undeclared output `\(key)`."
        case .invalidOutput(let name, let expected):
            return "Output `\(name)` does not match expected type `\(expected)`."
        }
    }
}

private enum JavaScriptNodeSourceParser
{
    private static let blockedPatterns: [(label: String, pattern: String)] = [
        ("import", #"(?m)^\s*import\b"#),
        ("export", #"(?m)^\s*export\b"#),
        ("require", #"\brequire\s*\("#),
        ("dynamic import", #"\bimport\s*\("#),
    ]

    private static let signaturePattern = #"function\s*\(([\s\S]*?)\)\s*main\s*\(([\s\S]*?)\)"#

    private static let typeLookup: [String: PortType] = [
        "bool": .Bool,
        "int": .Int,
        "number": .Float,
        "float": .Float,
        "string": .String,
        "vector2": .Vector2,
        "vector3": .Vector3,
        "vector4": .Vector4,
        "color": .Color,
        "quaternion": .Quaternion,
        "transform": .Transform,
        "geometry": .Geometry,
        "material": .Material,
        "image": .Image,
        "array_bool": .Array(portType: .Bool),
        "array_int": .Array(portType: .Int),
        "array_number": .Array(portType: .Float),
        "array_float": .Array(portType: .Float),
        "array_string": .Array(portType: .String),
        "array_vector2": .Array(portType: .Vector2),
        "array_vector3": .Array(portType: .Vector3),
        "array_vector4": .Array(portType: .Vector4),
        "array_color": .Array(portType: .Color),
        "array_quaternion": .Array(portType: .Quaternion),
        "array_transform": .Array(portType: .Transform),
        "array_geometry": .Array(portType: .Geometry),
        "array_material": .Array(portType: .Material),
        "array_image": .Array(portType: .Image),
    ]

    static func parse(source: String) throws -> JavaScriptNodeSignature
    {
        for blockedPattern in blockedPatterns {
            if source.range(of: blockedPattern.pattern, options: .regularExpression) != nil {
                throw JavaScriptNodeParseError.blockedSyntax(blockedPattern.label)
            }
        }

        let regex = try NSRegularExpression(pattern: signaturePattern, options: [.dotMatchesLineSeparators])
        let sourceRange = NSRange(source.startIndex..., in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: sourceRange),
              let outputsRange = Range(match.range(at: 1), in: source),
              let inputsRange = Range(match.range(at: 2), in: source),
              let fullRange = Range(match.range(at: 0), in: source) else {
            throw JavaScriptNodeParseError.missingMainSignature
        }

        let outputs = try parse(portList: String(source[outputsRange]), direction: .output)
        let inputs = try parse(portList: String(source[inputsRange]), direction: .input)

        let duplicateNames = Set(inputs.map(\.name)).intersection(outputs.map(\.name))
        if let duplicateName = duplicateNames.first {
            throw JavaScriptNodeParseError.duplicatePortName(duplicateName)
        }

        let transpiledMain = "function main(\(inputs.map(\.name).joined(separator: ", ")))"
        let transpiledSource = source.replacingCharacters(in: fullRange, with: transpiledMain)

        return JavaScriptNodeSignature(inputs: inputs,
                                       outputs: outputs,
                                       transpiledSource: transpiledSource)
    }

    private static func parse(portList: String,
                              direction: JavaScriptNodePortDefinition.Direction) throws -> [JavaScriptNodePortDefinition]
    {
        let trimmed = portList.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: true)
        var definitions: [JavaScriptNodePortDefinition] = []
        var seenNames = Set<String>()

        for rawPart in parts {
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard part.isEmpty == false else { continue }

            let tokens = part.split(whereSeparator: \.isWhitespace)
            guard tokens.count == 2 else {
                throw JavaScriptNodeParseError.invalidAnnotation(part)
            }

            let typeToken = String(tokens[0])
            let nameToken = String(tokens[1])
            guard typeToken.hasPrefix("__") else {
                throw JavaScriptNodeParseError.invalidAnnotation(part)
            }

            let normalizedType = String(typeToken.dropFirst(2)).lowercased()
            guard let portType = typeLookup[normalizedType] else {
                throw JavaScriptNodeParseError.unsupportedType(typeToken)
            }

            if portType == .Shader || portType == .Array(portType: .Shader) {
                throw JavaScriptNodeParseError.shaderUnsupported
            }

            if seenNames.contains(nameToken) {
                throw JavaScriptNodeParseError.duplicatePortName(nameToken)
            }

            seenNames.insert(nameToken)
            definitions.append(JavaScriptNodePortDefinition(direction: direction,
                                                            name: nameToken,
                                                            portType: portType))
        }

        return definitions
    }
}

private protocol JavaScriptOpaqueValueBoxing
{
    var boxedPortValue: PortValue { get }
}

@objc private protocol JavaScriptExecutionContextExports: JSExport
{
    var time: Double { get }
    var deltaTime: Double { get }
    var displayTime: Double { get }
    var systemTime: Double { get }
    var frameNumber: Int { get }
    var iterationIndex: Int { get }
    var iterationCount: Int { get }
}

@objcMembers private final class JavaScriptExecutionContextValue: NSObject, JavaScriptExecutionContextExports
{
    let time: Double
    let deltaTime: Double
    let displayTime: Double
    let systemTime: Double
    let frameNumber: Int
    let iterationIndex: Int
    let iterationCount: Int

    init(executionContext: GraphExecutionContext)
    {
        self.time = executionContext.timing.time
        self.deltaTime = executionContext.timing.deltaTime
        self.displayTime = executionContext.timing.displayTime ?? executionContext.timing.time
        self.systemTime = executionContext.timing.systemTime
        self.frameNumber = executionContext.timing.frameNumber
        self.iterationIndex = executionContext.iterationInfo?.currentIteration ?? 0
        self.iterationCount = executionContext.iterationInfo?.totalIterationCount ?? 1
    }
}

@objc private protocol JavaScriptImageExports: JSExport
{
    var type: String { get }
    var handleID: String { get }
    var width: Int { get }
    var height: Int { get }
    var isFlipped: Bool { get }
    var pixelFormat: String { get }
}

@objcMembers private final class JavaScriptImageValue: NSObject, JavaScriptImageExports, JavaScriptOpaqueValueBoxing
{
    private let image: FabricImage

    init(image: FabricImage)
    {
        self.image = image
    }

    var type: String { "Image" }
    var handleID: String { image.id.uuidString }
    var width: Int { image.texture.width }
    var height: Int { image.texture.height }
    var isFlipped: Bool { image.isFlipped }
    var pixelFormat: String { String(describing: image.texture.pixelFormat) }
    var boxedPortValue: PortValue { .Image(image) }
}

@objc private protocol JavaScriptGeometryExports: JSExport
{
    var type: String { get }
    var handleID: String { get }
    var vertexCount: Int { get }
    var indexCount: Int { get }
    var boundsMin: [Double] { get }
    var boundsMax: [Double] { get }
}

@objcMembers private final class JavaScriptGeometryValue: NSObject, JavaScriptGeometryExports, JavaScriptOpaqueValueBoxing
{
    private let geometry: SatinGeometry

    init(geometry: SatinGeometry)
    {
        self.geometry = geometry
    }

    var type: String { "Geometry" }
    var handleID: String { String(ObjectIdentifier(geometry).hashValue) }
    var vertexCount: Int { geometry.vertexCount }
    var indexCount: Int { geometry.indexCount }
    var boundsMin: [Double] { [Double(geometry.bounds.min.x), Double(geometry.bounds.min.y), Double(geometry.bounds.min.z)] }
    var boundsMax: [Double] { [Double(geometry.bounds.max.x), Double(geometry.bounds.max.y), Double(geometry.bounds.max.z)] }
    var boxedPortValue: PortValue { .Geometry(geometry) }
}

@objc private protocol JavaScriptMaterialExports: JSExport
{
    var type: String { get }
    var handleID: String { get }
    var label: String { get }
    var hasShader: Bool { get }
    var parameterCount: Int { get }
    var blending: String { get }
}

@objcMembers private final class JavaScriptMaterialValue: NSObject, JavaScriptMaterialExports, JavaScriptOpaqueValueBoxing
{
    private let material: Satin.Material

    init(material: Satin.Material)
    {
        self.material = material
    }

    var type: String { "Material" }
    var handleID: String { String(ObjectIdentifier(material).hashValue) }
    var label: String { material.label }
    var hasShader: Bool { material.shader != nil }
    var parameterCount: Int { material.parameters.params.count }
    var blending: String { String(describing: material.blending) }
    var boxedPortValue: PortValue { .Material(material) }
}

private final class JavaScriptValueBridge
{
    func javaScriptArgument(for boxedValue: PortValue?) -> Any
    {
        guard let boxedValue else { return NSNull() }

        switch boxedValue
        {
        case .Bool(let value):
            return value
        case .Int(let value):
            return value
        case .Float(let value):
            return Double(value)
        case .String(let value):
            return value
        case .Vector2(let value):
            return [Double(value.x), Double(value.y)]
        case .Vector3(let value):
            return [Double(value.x), Double(value.y), Double(value.z)]
        case .Vector4(let value):
            return [Double(value.x), Double(value.y), Double(value.z), Double(value.w)]
        case .Quaternion(let value):
            return [Double(value.vector.x), Double(value.vector.y), Double(value.vector.z), Double(value.vector.w)]
        case .Transform(let value):
            let column0 = value.columns.0
            let column1 = value.columns.1
            let column2 = value.columns.2
            let column3 = value.columns.3
            var values: [Double] = []
            values.append(Double(column0.x))
            values.append(Double(column0.y))
            values.append(Double(column0.z))
            values.append(Double(column0.w))
            values.append(Double(column1.x))
            values.append(Double(column1.y))
            values.append(Double(column1.z))
            values.append(Double(column1.w))
            values.append(Double(column2.x))
            values.append(Double(column2.y))
            values.append(Double(column2.z))
            values.append(Double(column2.w))
            values.append(Double(column3.x))
            values.append(Double(column3.y))
            values.append(Double(column3.z))
            values.append(Double(column3.w))
            return values
        case .Geometry(let value):
            return JavaScriptGeometryValue(geometry: value)
        case .Material(let value):
            return JavaScriptMaterialValue(material: value)
        case .Shader:
            return NSNull()
        case .Image(let value):
            return JavaScriptImageValue(image: value)
        case .Virtual(let value):
            return javaScriptArgument(for: value)
        case .Array(let values):
            return values.map { javaScriptArgument(for: $0) }
        }
    }

    func boxedValue(from value: JSValue?, as portType: PortType) -> PortValue?
    {
        guard let value, value.isUndefined == false, value.isNull == false else {
            return nil
        }

        switch portType
        {
        case .Bool:
            return value.toBool() ? .Bool(true) : .Bool(false)
        case .Int:
            return .Int(Int(value.toInt32()))
        case .Float:
            return .Float(Float(value.toDouble()))
        case .String:
            return .String(value.toString() ?? "")
        case .Vector2:
            guard let array = value.toArray() as? [Double], array.count == 2 else { return nil }
            return .Vector2(simd_float2(Float(array[0]), Float(array[1])))
        case .Vector3:
            guard let array = value.toArray() as? [Double], array.count == 3 else { return nil }
            return .Vector3(simd_float3(Float(array[0]), Float(array[1]), Float(array[2])))
        case .Vector4, .Color:
            guard let array = value.toArray() as? [Double], array.count == 4 else { return nil }
            return .Vector4(simd_float4(Float(array[0]), Float(array[1]), Float(array[2]), Float(array[3])))
        case .Quaternion:
            guard let array = value.toArray() as? [Double], array.count == 4 else { return nil }
            return .Vector4(simd_float4(Float(array[0]), Float(array[1]), Float(array[2]), Float(array[3])))
        case .Transform:
            guard let array = value.toArray() as? [Double], array.count == 16 else { return nil }
            return .Transform(simd_float4x4(columns: (
                simd_float4(Float(array[0]), Float(array[1]), Float(array[2]), Float(array[3])),
                simd_float4(Float(array[4]), Float(array[5]), Float(array[6]), Float(array[7])),
                simd_float4(Float(array[8]), Float(array[9]), Float(array[10]), Float(array[11])),
                simd_float4(Float(array[12]), Float(array[13]), Float(array[14]), Float(array[15]))
            )))
        case .Geometry, .Material, .Image:
            return (value.toObject() as? JavaScriptOpaqueValueBoxing)?.boxedPortValue
        case .Shader:
            return nil
        case .Virtual:
            return nil
        case .Array(portType: let elementType):
            guard let array = value.toArray() else { return nil }
            let boxedElements = array.compactMap { element -> PortValue? in
                let wrappedValue = JSValue(object: element, in: value.context)
                return boxedValue(from: wrappedValue, as: elementType)
            }
            guard boxedElements.count == array.count else { return nil }
            return .Array(ContiguousArray(boxedElements))
        }
    }
}

private final class JavaScriptNodeRuntime
{
    private let context: JSContext
    private let mainFunction: JSValue
    private let bridge = JavaScriptValueBridge()
    private(set) var latestDiagnostic: JavaScriptNodeDiagnostic?

    init(signature: JavaScriptNodeSignature) throws
    {
        let context = JSContext()!
        self.context = context
        var capturedDiagnostic: JavaScriptNodeDiagnostic?

        context.exceptionHandler = { _, exception in
            capturedDiagnostic = JavaScriptNodeRuntime.makeDiagnostic(from: exception)
        }

        let console = JSValue(newObjectIn: context)
        let logBlock: @convention(block) (JSValue) -> Void = { value in
            print("JavaScriptNode:", value)
        }
        console?.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)

        context.evaluateScript(signature.transpiledSource)
        if let diagnostic = capturedDiagnostic {
            self.latestDiagnostic = diagnostic
            throw NSError(domain: "JavaScriptNodeRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: diagnostic.summary])
        }

        guard let mainFunction = context.objectForKeyedSubscript("main"), mainFunction.isObject else {
            throw JavaScriptNodeExecutionError.missingMainFunction
        }

        self.mainFunction = mainFunction
    }

    func execute(signature: JavaScriptNodeSignature,
                 node: JavaScriptNode,
                 executionContext: GraphExecutionContext) throws -> [String: PortValue?]
    {
        self.latestDiagnostic = nil
        self.context.exception = nil
        self.context.setObject(JavaScriptExecutionContextValue(executionContext: executionContext), forKeyedSubscript: "context" as NSString)

        let arguments = signature.inputs.map { definition in
            bridge.javaScriptArgument(for: node.findPort(named: definition.name, as: Port.self)?.boxedValue())
        }

        guard let result = self.mainFunction.call(withArguments: arguments) else {
            throw JavaScriptNodeExecutionError.invalidReturnShape
        }

        if let diagnostic = self.latestDiagnostic {
            throw NSError(domain: "JavaScriptNodeRuntime", code: 2, userInfo: [NSLocalizedDescriptionKey: diagnostic.summary])
        }

        guard result.isObject else {
            throw JavaScriptNodeExecutionError.invalidReturnShape
        }

        let objectValue = self.context.objectForKeyedSubscript("Object")
        let keysValue = objectValue?.invokeMethod("keys", withArguments: [result])
        let returnedKeys = Set((keysValue?.toArray() as? [String]) ?? [])
        let declaredKeys = Set(signature.outputs.map(\.name))
        if let unexpectedKey = returnedKeys.subtracting(declaredKeys).first {
            throw JavaScriptNodeExecutionError.extraOutput(unexpectedKey)
        }

        var outputs: [String: PortValue?] = [:]
        for definition in signature.outputs {
            let outputValue = result.forProperty(definition.name)
            guard let boxedValue = bridge.boxedValue(from: outputValue, as: definition.portType) ?? nil else {
                outputs[definition.name] = nil
                continue
            }
            outputs[definition.name] = boxedValue
        }
        return outputs
    }

    private static func makeDiagnostic(from exception: JSValue?) -> JavaScriptNodeDiagnostic
    {
        guard let exception else {
            return JavaScriptNodeDiagnostic(summary: "Unknown JavaScript error.")
        }

        let summary = exception.toString() ?? "Unknown JavaScript error."
        let line = Int(exception.forProperty("line")?.toInt32() ?? 1) - 1
        let column = Int(exception.forProperty("column")?.toInt32() ?? 1) - 1
        return JavaScriptNodeDiagnostic(line: max(0, line),
                                        column: max(0, column),
                                        summary: summary,
                                        detail: summary)
    }
}

public final class JavaScriptNode: Node
{
    override public class var name: String { "JavaScript" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Live-editable QC-style JavaScript logic node with dynamic Fabric ports." }

    private enum CodingKeys: String, CodingKey
    {
        case scriptSource
        case selectedExecutionMode
        case selectedTimeMode
        case scriptSchemaVersion
    }

    private static let scriptSchemaVersion = 1

    @ObservationIgnored private(set) var scriptSource: String = JavaScriptNode.defaultScriptSource()
    @ObservationIgnored private var compiledSignature: JavaScriptNodeSignature?
    @ObservationIgnored private var runtime: JavaScriptNodeRuntime?
    @ObservationIgnored private var diagnostics: [JavaScriptNodeDiagnostic] = []

    public var selectedExecutionMode: Node.ExecutionMode = .Processor
    public var selectedTimeMode: Node.TimeMode = .None

    @ObservationIgnored override public var nodeExecutionMode: ExecutionMode { self.selectedExecutionMode }
    @ObservationIgnored override public var nodeTimeMode: TimeMode { self.selectedTimeMode }

    var portPreview: [JavaScriptNodePortDefinition]
    {
        guard let compiledSignature else { return [] }
        return compiledSignature.inputs + compiledSignature.outputs
    }

    var currentDiagnostics: [JavaScriptNodeDiagnostic] { diagnostics }

    public required init(context: Context)
    {
        super.init(context: context)
        self.compileAndSynchronizePorts(shouldSynchronizePorts: true)
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.scriptSource = try container.decodeIfPresent(String.self, forKey: .scriptSource) ?? JavaScriptNode.defaultScriptSource()
        self.selectedExecutionMode = try container.decodeIfPresent(Node.ExecutionMode.self, forKey: .selectedExecutionMode) ?? .Processor
        self.selectedTimeMode = try container.decodeIfPresent(Node.TimeMode.self, forKey: .selectedTimeMode) ?? .None
        self.compileAndSynchronizePorts(shouldSynchronizePorts: false)
    }

    override public func encode(to encoder: any Encoder) throws
    {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.scriptSource, forKey: .scriptSource)
        try container.encode(self.selectedExecutionMode, forKey: .selectedExecutionMode)
        try container.encode(self.selectedTimeMode, forKey: .selectedTimeMode)
        try container.encode(Self.scriptSchemaVersion, forKey: .scriptSchemaVersion)
    }

    override public func providesSettingsView() -> Bool
    {
        true
    }

    override public func settingsView() -> AnyView
    {
        AnyView(JavaScriptNodeSettingsView(node: self))
    }

    override public var settingsSize: SettingsViewSize
    {
        .Custom(size: CGSize(width: 980, height: 700))
    }

    @MainActor
    public func updateScriptSource(_ source: String)
    {
        self.scriptSource = source
        self.compileAndSynchronizePorts(shouldSynchronizePorts: true)
    }

    @MainActor
    public func updateModes(executionMode: Node.ExecutionMode, timeMode: Node.TimeMode)
    {
        if self.selectedExecutionMode != executionMode {
            self.selectedExecutionMode = executionMode
            self.markDirty()
        }
        if self.selectedTimeMode != timeMode {
            self.selectedTimeMode = timeMode
            self.markDirty()
        }
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let compiledSignature,
              let runtime else {
            return
        }

        do {
            let outputValues = try runtime.execute(signature: compiledSignature, node: self, executionContext: context)
            self.diagnostics = []

            for definition in compiledSignature.outputs {
                guard let port = self.findPort(named: definition.name) else { continue }
                definition.portType.send(boxedValue: outputValues[definition.name] ?? nil, on: port, force: true)
            }
        }
        catch {
            let summary = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            self.diagnostics = [JavaScriptNodeDiagnostic(summary: summary, detail: summary)]
        }
    }

    private func compileAndSynchronizePorts(shouldSynchronizePorts: Bool)
    {
        do {
            let signature = try JavaScriptNodeSourceParser.parse(source: self.scriptSource)
            let runtime = try JavaScriptNodeRuntime(signature: signature)
            self.compiledSignature = signature
            self.runtime = runtime
            self.diagnostics = []

            if shouldSynchronizePorts {
                self.synchronizeDynamicPorts(with: signature)
            }
        }
        catch {
            let summary = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            self.diagnostics = [JavaScriptNodeDiagnostic(summary: summary, detail: summary)]
        }
    }

    private func synchronizeDynamicPorts(with signature: JavaScriptNodeSignature)
    {
        let desiredPorts = signature.inputs + signature.outputs

        for port in self.ports {
            guard let definition = desiredPorts.first(where: { $0.name == port.name }) else {
                self.removePort(port)
                continue
            }

            let expectedKind: PortKind = definition.direction == .input ? .Inlet : .Outlet
            if port.kind != expectedKind || port.portType != definition.portType {
                self.removePort(port)
            }
        }

        var reorderedPorts: [Port] = []
        for definition in desiredPorts {
            let expectedKind: PortKind = definition.direction == .input ? .Inlet : .Outlet
            if let existingPort = self.ports.first(where: { $0.name == definition.name && $0.kind == expectedKind && $0.portType == definition.portType }) {
                reorderedPorts.append(existingPort)
                continue
            }

            let port = PortType.dynamicPort(for: definition.portType,
                                            name: definition.name,
                                            kind: expectedKind)
            self.addDynamicPort(port, name: definition.name)
            reorderedPorts.append(port)
        }

        self.reorderPorts(reorderedPorts)
    }

    private static func defaultScriptSource() -> String
    {
        """
        function (__number sum, __bool thresholdPassed) main(__number a, __number b, __number threshold) {
          const total = a + b
          return {
            sum: total,
            thresholdPassed: total > threshold
          }
        }
        """
    }
}

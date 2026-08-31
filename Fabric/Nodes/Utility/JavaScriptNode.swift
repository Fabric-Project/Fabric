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

    init(executionInfo: GraphExecutionInfo)
    {
        self.time = executionInfo.timing.time
        self.deltaTime = executionInfo.timing.deltaTime
        self.displayTime = executionInfo.timing.displayTime ?? executionInfo.timing.time
        self.systemTime = executionInfo.timing.systemTime
        self.frameNumber = executionInfo.timing.frameNumber
        self.iterationIndex = executionInfo.iterationInfo?.currentIteration ?? 0
        self.iterationCount = executionInfo.iterationInfo?.totalIterationCount ?? 1
    }
}

@objc private protocol JavaScriptImageExports: JSExport
{
    var type: String { get }
    var handleID: String { get }
    var width: Double { get }
    var height: Double { get }
    var textureTransform: [Double] { get }
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
    var width: Double { image.presentationSize.width }
    var height: Double { image.presentationSize.height }
    var textureTransform: [Double] {
        let matrix = image.textureTransform
        return [
            Double(matrix.columns.0.x), Double(matrix.columns.0.y), Double(matrix.columns.0.z), Double(matrix.columns.0.w),
            Double(matrix.columns.1.x), Double(matrix.columns.1.y), Double(matrix.columns.1.z), Double(matrix.columns.1.w),
            Double(matrix.columns.2.x), Double(matrix.columns.2.y), Double(matrix.columns.2.z), Double(matrix.columns.2.w),
            Double(matrix.columns.3.x), Double(matrix.columns.3.y), Double(matrix.columns.3.z), Double(matrix.columns.3.w),
        ]
    }
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
    private let geometry: Satin.Geometry

    init(geometry: Satin.Geometry)
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
        case .Image(let value):
            return JavaScriptImageValue(image: value)
        case .Array(let values):
            return values.map { javaScriptArgument(for: $0) }
        case .Dictionary(let values):
            return values.mapValues { javaScriptArgument(for: $0) }
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
            let vector = simd_float4(Float(array[0]), Float(array[1]), Float(array[2]), Float(array[3]))
            return .Quaternion(simd_quatf(vector: vector))
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
        case .NumericVirtual:
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
        case .Dictionary(valueType: let valueType):
            guard let object = value.toDictionary() as? [String: Any] else { return nil }
            var boxedValues: [String: PortValue] = [:]
            boxedValues.reserveCapacity(object.count)

            for (key, element) in object
            {
                let wrappedValue = JSValue(object: element, in: value.context)
                guard let boxedValue = boxedValue(from: wrappedValue, as: valueType) else { return nil }
                boxedValues[key] = boxedValue
            }

            return .Dictionary(boxedValues)
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
            throw FabricError(.execution(.syntax),
                              severity: .recoverable,
                              message: diagnostic.summary)
        }

        guard let mainFunction = context.objectForKeyedSubscript("main"), mainFunction.isObject else {
            throw JavaScriptNodeExecutionError.missingMainFunction
        }

        self.mainFunction = mainFunction
    }

    func execute(signature: JavaScriptNodeSignature,
                 node: JavaScriptNode,
                 executionInfo: GraphExecutionInfo) throws -> [String: PortValue?]
    {
        self.latestDiagnostic = nil
        self.context.exception = nil
        self.context.setObject(JavaScriptExecutionContextValue(executionInfo: executionInfo), forKeyedSubscript: "context" as NSString)

        let arguments = signature.inputs.map { definition in
            bridge.javaScriptArgument(for: node.findPort(named: definition.name, as: Port.self)?.snapshotValue())
        }

        guard let result = self.mainFunction.call(withArguments: arguments) else {
            throw JavaScriptNodeExecutionError.invalidReturnShape
        }

        if let diagnostic = self.latestDiagnostic {
            throw FabricError(.execution(.syntax),
                              severity: .recoverable,
                              message: diagnostic.summary)
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
        self.compileAndSynchronizePorts()
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.scriptSource = try container.decodeIfPresent(String.self, forKey: .scriptSource) ?? JavaScriptNode.defaultScriptSource()
        self.selectedExecutionMode = try container.decodeIfPresent(Node.ExecutionMode.self, forKey: .selectedExecutionMode) ?? .Processor
        self.selectedTimeMode = try container.decodeIfPresent(Node.TimeMode.self, forKey: .selectedTimeMode) ?? .None
        // Every port is dynamic, so decode must rebuild them from the restored
        // script; each recreated port adopts its persisted identity and state
        // by registry key as it registers.
        self.compileAndSynchronizePorts()
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
        self.compileAndSynchronizePorts()
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

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard let compiledSignature,
              let runtime else
        {
            if let diagnostic = self.diagnostics.first
            {
                throw FabricError(.execution(.syntax),
                                  severity: .recoverable,
                                  message: diagnostic.summary)
            }

            return
        }

        do {
            let outputValues = try runtime.execute(signature: compiledSignature, node: self, executionInfo: executionInfo)
            self.diagnostics = []

            for definition in compiledSignature.outputs {
                guard let port = self.findPort(named: definition.name) else { continue }
                port.sendBoxed(outputValues[definition.name] ?? nil, force: true)
            }
        }
        catch {
            let summary = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            self.diagnostics = [JavaScriptNodeDiagnostic(summary: summary, detail: summary)]
            throw FabricError(.execution(.syntax),
                              severity: .recoverable,
                              message: summary,
                              underlyingError: error)
        }
    }

    private func compileAndSynchronizePorts()
    {
        do {
            let signature = try JavaScriptNodeSourceParser.parse(source: self.scriptSource)
            let runtime = try JavaScriptNodeRuntime(signature: signature)
            self.compiledSignature = signature
            self.runtime = runtime
            self.diagnostics = []

            self.synchronizeDynamicPorts(with: signature)
        }
        catch {
            let summary = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            self.diagnostics = [JavaScriptNodeDiagnostic(summary: summary, detail: summary)]

            // Every port here is minted from the script's signature, so a saved
            // script that no longer parses leaves the node with none at all.
            self.adoptRemainingSnapshotPortsAsFallback()
        }
    }

    private func synchronizeDynamicPorts(with signature: JavaScriptNodeSignature)
    {
        let desiredPorts = signature.inputs + signature.outputs
        let desiredNames = Set(desiredPorts.map(\.name))

        for port in self.ports where !desiredNames.contains(port.name) {
            self.removePort(port)
        }

        var reorderedPorts: [Port] = []
        for definition in desiredPorts {
            let expectedKind: PortKind = definition.direction == .input ? .Inlet : .Outlet

            if let existingPort = self.findPort(named: definition.name, as: Port.self),
               existingPort.kind == expectedKind,
               existingPort.portType == definition.portType
            {
                reorderedPorts.append(existingPort)
                continue
            }

            let oldConnections = self.findPort(named: definition.name, as: Port.self)?.connectedPorts ?? []
            if let existingPort = self.findPort(named: definition.name, as: Port.self) {
                self.removePort(existingPort)
            }

            let replacement = definition.portType.makeFreshPort(name: definition.name, kind: expectedKind)
            self.addDynamicPort(replacement, name: definition.name)
            for connectedPort in oldConnections where replacement.canConnect(to: connectedPort) {
                if replacement.kind == .Outlet {
                    self.graph?.connect(replacement, to: connectedPort)
                } else {
                    self.graph?.connect(connectedPort, to: replacement)
                }
            }
            reorderedPorts.append(replacement)
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

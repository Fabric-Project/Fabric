//
//  LiveEffectNode.swift
//  Fabric
//
//  Created by Codex on 3/4/26.
//

import Foundation
import Metal
import Satin
import SwiftUI

public class LiveImageNode: BaseImageNode
{
    override public class var name: String { "Live Image" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .BaseEffect) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Live-editable Metal image effect with serialized shader source." }
    override public class var defaultImageInputCountHint: Int? { 1 }

    override public class var sourceShaderName: String { "LiveEffectDefaultShader" }

    enum CodingKeys: String, CodingKey {
        case shaderSource
        case shaderSchemaVersion
    }

    private static let shaderSchemaVersion = 1
    private static let rootWorkspaceURL = URL(filePath: "/tmp/fabric-live-shaders", directoryHint: .isDirectory)
    private static let staleWorkspaceTTL: TimeInterval = 24 * 60 * 60

    @ObservationIgnored private(set) var shaderSource: String = LiveImageNode.defaultShaderSource()
    @ObservationIgnored private var workspaceURL: URL?
    @ObservationIgnored private var shaderFileURL: URL?

    required init(context: Context, fileURL: URL) throws {
        try super.init(context: context, fileURL: fileURL)
        self.postInit()
    }

    required init(context: Context) {
        super.init(context: context)
        self.postInit()
    }

    required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.shaderSource = try container.decodeIfPresent(String.self, forKey: .shaderSource) ?? LiveImageNode.defaultShaderSource()
        self.postInit()
    }

    deinit {
        self.cleanupWorkspace()
    }

    override public func encode(to encoder: Encoder) throws {
        try self.captureShaderSourceFromDiskIfAvailable()
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.shaderSource, forKey: .shaderSource)
        try container.encode(Self.shaderSchemaVersion, forKey: .shaderSchemaVersion)
    }

    override public func providesSettingsView() -> Bool {
        true
    }

    override public func settingsView() -> AnyView {
        AnyView(LiveImageNodeSettingsView(node: self))
    }

    override public var settingsSize: SettingsViewSize {
        .Custom(size: CGSize(width: 900, height: 620))
    }

    @MainActor
    public func updateShaderSource(_ source: String) {
        self.shaderSource = source
        guard let shaderFileURL else { return }

        do {
            // Use non-atomic writes to preserve inode/watcher continuity for live recompiles.
            try source.write(to: shaderFileURL, atomically: false, encoding: .utf8)
            self.recompileAndResyncPorts()
        }
        catch {
            print("LiveEffect failed to write shader source: \(error.localizedDescription)")
        }
    }

    public func currentShaderErrorDescription() -> String? {
        guard let shader = self.postMaterial.shader as? SourceShader,
              let error = shader.pipelineError else {
            return nil
        }

        return error.localizedDescription
    }

    private func postInit() {
        Self.sweepStaleWorkspacesOnceIfNeeded()

        do {
            let workspaceURL = try self.makeWorkspaceURL()
            try self.ensureWorkspaceReady(at: workspaceURL)
            self.workspaceURL = workspaceURL
            self.shaderFileURL = workspaceURL.appending(path: "Shaders.metal")

            try self.shaderSource.write(to: self.shaderFileURL!, atomically: true, encoding: .utf8)
            self.retargetMaterial(to: self.shaderFileURL!)
            self.recompileAndResyncPorts()
        }
        catch {
            print("LiveEffect workspace setup failed: \(error.localizedDescription)")
        }
    }

    private func makeWorkspaceURL() throws -> URL {
        let documentID = self.graph?.id.uuidString ?? "unsaved-document"
        let nodeID = self.id.uuidString
        return Self.rootWorkspaceURL.appending(path: documentID).appending(path: nodeID, directoryHint: .isDirectory)
    }

    private func ensureWorkspaceReady(at workspaceURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let rootLygiaLink = Self.rootWorkspaceURL.appending(path: "lygia", directoryHint: .isDirectory)
        let localLygiaLink = workspaceURL.appending(path: "lygia", directoryHint: .isDirectory)
        let bundleLygia = Bundle.module.resourceURL?.appending(path: "lygia", directoryHint: .isDirectory)

        if let bundleLygia {
            try self.ensureSymlink(at: rootLygiaLink, destination: bundleLygia)
            try self.ensureSymlink(at: localLygiaLink, destination: bundleLygia)
        }
    }

    private func ensureSymlink(at linkURL: URL, destination: URL) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: linkURL.path(percentEncoded: false)) {
            var isDirectory = ObjCBool(false)
            if fileManager.fileExists(atPath: linkURL.path(percentEncoded: false), isDirectory: &isDirectory),
               isDirectory.boolValue {
                return
            }

            try fileManager.removeItem(at: linkURL)
        }

        try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: destination)
    }

    private func retargetMaterial(to shaderFileURL: URL) {
        self.postMaterial.pipelineURL = shaderFileURL
        self.postMaterial.live = true

        if let sourceShader = self.postMaterial.shader as? SourceShader {
            sourceShader.pipelineURL = shaderFileURL
            sourceShader.live = true
            sourceShader.setupShaderCompiler()
        }
    }

    private func recompileAndResyncPorts() {
        if let sourceShader = self.postMaterial.shader as? SourceShader {
            sourceShader.reloadFromSource()
            if sourceShader.pipelineError == nil {
                self.postSetupSynchronizePorts(allowReplace: false)
            }
        }
    }

    private func syncDynamicParameterPortsFromMaterial() {
        let materialParams = self.postMaterial.parameters.params
        let labels = Set(materialParams.map(\.label))

        let portsToRemove = self.ports.filter { port in
            guard let _ = port.parameter else { return false }
            return !labels.contains(port.name)
        }

        for port in portsToRemove {
            self.removePort(port)
        }

        for param in materialParams {
            if let port = self.ports.first(where: { $0.name == param.label }) {
                self.replaceParameterOfPort(port, withParam: param)
            }
            else if let dynamicPort = PortType.portForType(from: param) {
                self.addDynamicPort(dynamicPort)
            }
        }
    }

    private func captureShaderSourceFromDiskIfAvailable() throws {
        guard let shaderFileURL,
              FileManager.default.fileExists(atPath: shaderFileURL.path(percentEncoded: false)) else {
            return
        }

        self.shaderSource = try String(contentsOf: shaderFileURL, encoding: .utf8)
    }

    private func cleanupWorkspace() {
        guard let workspaceURL else { return }
        try? FileManager.default.removeItem(at: workspaceURL)
    }

    private static func defaultShaderSource() -> String {
        if let bundledTemplateURL = Bundle.module.url(forResource: Self.sourceShaderName, withExtension: "metal", subdirectory: "Shaders"),
           let source = try? String(contentsOf: bundledTemplateURL, encoding: .utf8) {
            return source
        }

        return """
        #include <metal_stdlib>
        using namespace metal;

        typedef struct {
            float amount; // slider, 0.0, 1.0, 1.0, Amount
        } PostUniforms;

        fragment half4 postFragment(VertexData in [[stage_in]],
                                    constant PostUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]],
                                    texture2d<half, access::sample> inputTexture [[texture(FragmentTextureCustom0)]]) {
            constexpr sampler s(address::clamp_to_edge, filter::linear);
            half4 color = inputTexture.sample(s, in.texcoord);
            return mix(half4(0.0), color, half(uniforms.amount));
        }
        """
    }

    private static func sweepStaleWorkspacesOnceIfNeeded() {
        struct SweepState {
            static var didSweep = false
        }

        guard SweepState.didSweep == false else { return }
        SweepState.didSweep = true

        let fileManager = FileManager.default
        let root = Self.rootWorkspaceURL
        guard fileManager.fileExists(atPath: root.path(percentEncoded: false)) else { return }

        let expirationDate = Date().addingTimeInterval(-Self.staleWorkspaceTTL)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]

        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            return
        }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isDirectory == true,
                  let modificationDate = values.contentModificationDate else {
                continue
            }

            if modificationDate < expirationDate {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}

@available(*, deprecated, message: "Use LiveImageNode")
public final class LiveEffectNode: LiveImageNode {}

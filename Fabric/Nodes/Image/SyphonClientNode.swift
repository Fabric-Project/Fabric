//
//  SyphonProviderNode.swift
//  Fabric
//
//  Created by Anton Marini on 11/27/25.
//

#if FABRIC_SYPHON_ENABLED

import Foundation
import Satin
import simd
import Metal
import SwiftUI
import Syphon

public class SyphonClientNode : Node
{
    public override class var name:String { "Syphon Client" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Image(imageType: .Loader) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Connect to a Syphon Server, providing an stream of output Images"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputEnabled", ParameterPort(parameter: BoolParameter("Enabled", true, .toggle, "Connect to a server. Off receives nothing, where an empty name receives the first server there is"))),
            ("inputServerName", ParameterPort(parameter: StringParameter("Server Name", "", [String](), .inputfield, "Name of the Syphon server to connect to. Empty takes the first server there is"))),
            ("inputServerAppName", ParameterPort(parameter: StringParameter("Application Name", "", [String](), .inputfield, "Name of the application hosting the Syphon server. Empty takes any application"))),
            ("outputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Received Syphon frame")),
        ]
    }

    public var inputEnabled:ParameterPort<Bool> { port(named: "inputEnabled") }
    public var inputServerName:ParameterPort<String>  { port(named: "inputServerName") }
    public var inputServerAppName:ParameterPort<String>  { port(named: "inputServerAppName") }
    public var outputTexturePort:NodePort<FabricImage> { port(named: "outputTexturePort") }

    private var syphonClient:SyphonMetalClient? = nil
    {
        // A frame belongs to the client it came from, so the two are dropped
        // together — taking up another server never leaves the last one's
        // frame on the outlet.
        didSet { self.heldImage = nil }
    }

    /// The frame in hand, and what the outlet carries: assigning it is what
    /// sends it, so every path that takes a frame or lets one go says so here
    /// and nowhere else.
    ///
    /// Made once per frame received rather than once per execute. A Provider
    /// executes every frame, and a client with nothing new hands back the
    /// texture it already had, so an image built each time would carry a new
    /// identity over unchanged pixels and mark the whole chain below dirty at
    /// frame rate. A feed that is still sends nothing at all.
    private var heldImage: FabricImage? = nil
    {
        didSet
        {
            guard self.heldImage !== oldValue else { return }
            self.outputTexturePort.send(self.heldImage)
        }
    }

    /// The identity of the server the client was made for. The inputs name a
    /// server, and the thing answering to that name is replaced every time its
    /// application is relaunched, so this is what says whether the client in
    /// hand is still the right one.
    private var boundServerIdentity:String? = nil

    /// The identities of servers a client went invalid on. A client
    /// goes invalid over its own channel to the server, where the directory
    /// drops the server on a notification from the publishing app — and an
    /// application that crashed or was force quit posts nothing, so the dead
    /// server stays on offer. Held so they are not taken up again, and let go
    /// of once the directory stops offering them.
    private var invalidServerIdentities: Set<String> = []

    /// The client is an open connection to another application, so it is let
    /// go of when the graph stops rather than whenever this object is released.
    /// A node outlives its place in the graph — a deleted one is held by the
    /// undo stack — and a connection left open goes on taking frames from an
    /// application the patch no longer mentions.
    ///
    /// The stopping pair rather than the disabling one: the only thing a client
    /// yields is a frame for `execute`, and a graph that is not executing has
    /// no use for one. A Syphon client is not free to the other end — the
    /// server is told it has one, and an application that publishes only while
    /// watched will go on rendering for a graph that stopped.
    override public func stopExecution(renderer: GraphRenderer) throws
    {
        self.syphonClient = nil
        self.boundServerIdentity = nil
        self.invalidServerIdentities.removeAll()
    }

    /// What tells one server from another: Syphon's identity where it offers
    /// one, and the name pair otherwise. Always something, never nothing — a
    /// server there was no identity for could not be held as invalid, and so
    /// would be taken up again on the next execute, and the one after, for as
    /// long as it stayed on offer.
    private func serverIdentity(_ description: [String: any NSCoding]) -> String
    {
        SyphonServerDescription(description).id
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        // A client whose server has gone yields nothing further, so it is
        // dropped and a server looked for again.
        if let syphonClient = self.syphonClient, !syphonClient.isValid
        {
            self.syphonClient = nil
            if let boundServerIdentity = self.boundServerIdentity
            {
                self.invalidServerIdentities.insert(boundServerIdentity)
            }
            self.boundServerIdentity = nil
        }

        // An empty name means the first server there is, which is what makes
        // the node work on being dropped into a patch. That leaves nothing to
        // say "no server at all" with, which is what this is for.
        guard self.inputEnabled.value ?? true
        else
        {
            self.syphonClient = nil
            return
        }

        // Looked up every execute rather than when a change is signalled. The
        // directory already watches for the whole process and answers from the
        // handful of servers it holds behind its own lock, so asking it costs
        // less than a node's own watching did — and leaves the node owning
        // nothing that has to be given back.
        //
        // Asked every time rather than only when there is nothing in hand: the
        // server answering to a name is a different one each time its
        // application is relaunched, and a client made for the last one can go
        // on saying it is valid.
        let matches = SyphonServerDirectory.shared().servers(matchingName: self.inputServerName.value ?? "",
                                                             appName: self.inputServerAppName.value ?? "")

        // Held only while the directory still offers the identity.
        // Syphon does not say an identity is never seen twice, and this
        // does not need it to be: one come again costs a client, found
        // invalid the next frame.
        self.invalidServerIdentities.formIntersection(matches.map(self.serverIdentity))

        // Taken past a dead server rather than stopped by it: a relaunched
        // application leaves its old entry on offer beside its new one,
        // and which of the two comes first is not ours to say.
        let match = matches.first
        { description in
            !self.invalidServerIdentities.contains(self.serverIdentity(description))
        }

        if let match
        {
            let matchIdentity = self.serverIdentity(match)

            if self.syphonClient == nil || matchIdentity != self.boundServerIdentity
            {
                self.syphonClient = SyphonMetalClient(serverDescription: match, device:renderer.device)
                self.boundServerIdentity = matchIdentity
            }
        }
        else
        {
            self.syphonClient = nil
            self.boundServerIdentity = nil
        }

        if let syphonClient = self.syphonClient, syphonClient.isValid
        {
            // `hasNewFrame` is read before the frame is asked for, never
            // after: taking a frame is what marks it seen. Nothing in hand
            // asks regardless of the flag, so a client's first frame is never
            // waited a turn for.
            if self.heldImage == nil || syphonClient.hasNewFrame,
               let texture = syphonClient.newFrameImage()
            {
                // A Syphon surface is bottom-up, and the client wraps it as it
                // stands — `newFrameImage` builds a texture straight onto the
                // IOSurface and turns nothing over. So the frame in hand is
                // upside down to Fabric's canonical top-left, and says so
                // rather than being copied the right way up: downstream samples
                // through the transform, and a frame passed back out to Syphon
                // is already in the orientation Syphon wants.
                //
                // Which way round that is was checked against an application
                // outside Fabric — see `SyphonServerNode.syphonRequiresVerticalFlip`.
                // A loop back through Fabric cannot say: a frame declared the
                // wrong way up here and turned the wrong way there comes out
                // looking right.
                let image = FabricImage.unmanaged(texture: texture)
                image.textureTransform = .textureVerticalFlip
                self.heldImage = image
            }
        }
        else
        {
            self.heldImage = nil
        }
    }

    // MARK: - Settings

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView
    {
        guard let serverNameParameter = self.inputServerName.parameter as? GenericParameter<String>,
              let appNameParameter = self.inputServerAppName.parameter as? GenericParameter<String>
        else { return AnyView(EmptyView()) }

        return AnyView(SyphonClientNodeView(serverNameParameter: serverNameParameter,
                                            appNameParameter: appNameParameter))
    }

    override public var settingsSize: SettingsViewSize { .Mini }
}

// MARK: - Settings View

/// Names a server from those publishing now. The two inputs stay the authority
/// — a name can be typed for a server that is not running, so that a patch
/// opens before the application it takes its image from — and this writes them
/// from what the directory is offering.
struct SyphonClientNodeView: View
{
    private let serverName: ParameterObservableModel<String>
    private let appName: ParameterObservableModel<String>

    init(serverNameParameter: GenericParameter<String>, appNameParameter: GenericParameter<String>)
    {
        self.serverName = ParameterObservableModel(label: serverNameParameter.label,
                                                   get: { serverNameParameter.value },
                                                   set: { serverNameParameter.value = $0 },
                                                   publisher: serverNameParameter.valuePublisher)

        self.appName = ParameterObservableModel(label: appNameParameter.label,
                                                get: { appNameParameter.value },
                                                set: { appNameParameter.value = $0 },
                                                publisher: appNameParameter.valuePublisher)
    }

    /// A server to pick, identified by the pair the node matches on rather than
    /// by Syphon's identity: what is written is a name, which outlives the
    /// server answering to it.
    private struct Row: Identifiable
    {
        let serverName: String
        let appName: String
        let title: String

        var id: String { "\(self.appName)\u{1}\(self.serverName)" }
    }

    /// Everything on offer, the row for naming nothing, and — where no server
    /// answers to what the inputs hold — that pair too, so the menu shows what
    /// the node is waiting for rather than reading as a choice it did make.
    private var rows: [Row]
    {
        var rows = [Row(serverName: "", appName: "", title: "First available")]

        // Two servers on offer can come to one row: a relaunched application
        // leaves its old entry beside its new one, and both answer to the same
        // pair. One row is all there is to pick, and identifiers a `ForEach`
        // sees twice are identifiers it does not have.
        for server in SyphonServerList.shared.servers
        {
            let row = Row(serverName: server.name, appName: server.appName, title: server.displayName)
            guard !rows.contains(where: { $0.id == row.id }) else { continue }
            rows.append(row)
        }

        let named = Row(serverName: self.serverName.uiValue, appName: self.appName.uiValue, title: "")
        if !rows.contains(where: { $0.id == named.id })
        {
            let description = [named.appName, named.serverName].filter { !$0.isEmpty }.joined(separator: " \u{2013} ")
            rows.append(Row(serverName: named.serverName,
                            appName: named.appName,
                            title: "\(description) (not publishing)"))
        }

        return rows
    }

    private var selection: Binding<Row.ID>
    {
        Binding(get: { Row(serverName: self.serverName.uiValue, appName: self.appName.uiValue, title: "").id },
                set: { picked in
                    guard let row = self.rows.first(where: { $0.id == picked }) else { return }
                    self.serverName.uiValue = row.serverName
                    self.appName.uiValue = row.appName
                })
    }

    var body: some View
    {
        VStack(alignment: .leading, spacing: 8)
        {
            Picker("", selection: self.selection)
            {
                ForEach(self.rows) { row in
                    Text(row.title).tag(row.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Text("Sets Server and Application Name")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            if SyphonServerList.shared.servers.isEmpty
            {
                Text("Nothing is publishing a Syphon server")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#endif // FABRIC_SYPHON_ENABLED

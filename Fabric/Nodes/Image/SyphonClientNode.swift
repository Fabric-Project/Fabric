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
import Synchronization
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
    private var texture: (any MTLTexture)? = nil

    /// Syphon's identity for the server the client was made for. The inputs
    /// name a server, and the thing answering to that name is replaced every
    /// time its application is relaunched, so this is what says whether the
    /// client in hand is still the right one.
    private var boundServerIdentity:String? = nil

    /// Syphon's identities for servers a client went invalid on. A client
    /// goes invalid over its own channel to the server, where the directory
    /// drops the server on a notification from the publishing app — and an
    /// application that crashed or was force quit posts nothing, so the dead
    /// server stays on offer. Held so they are not taken up again, and let go
    /// of once the directory stops offering them.
    private var invalidServerIdentities: Set<String> = []

    /// Set when the servers on offer have changed, so the next execute looks
    /// again. Written from the notifications below, read on the render thread,
    /// which is why it is a mutex and not a plain flag. Kept apart from the
    /// node so the notification blocks capture this alone.
    private final class DirectoryFlag: Sendable
    {
        private let changed = Mutex<Bool>(true)

        func set()
        {
            self.changed.withLock { $0 = true }
        }

        /// Whether to look the server up again, clearing the flag as it reads
        /// it. Read ahead of the lookup it answers, so a change arriving
        /// during that lookup is answered by the next one rather than lost.
        func take() -> Bool
        {
            self.changed.withLock
            {
                let changed = $0
                $0 = false
                return changed
            }
        }
    }

    private let directoryFlag = DirectoryFlag()

    /// Syphon's announce / retire / update notifications, by raw name.
    ///
    /// Named literally rather than through Syphon's exported constants: those
    /// are `NSString * const` ending in "Notification", so Swift imports them
    /// as members of `NSNotification.Name` under refined spellings, and the
    /// literal values are the stabler reference. They are part of Syphon's
    /// cross-process contract — every publishing app posts exactly these.
    private static let directoryNotifications: [NSNotification.Name] = [
        NSNotification.Name("SyphonServerAnnounceNotification"),
        NSNotification.Name("SyphonServerRetireNotification"),
        NSNotification.Name("SyphonServerUpdateNotification"),
    ]

    private var directoryObservers: [NSObjectProtocol] = []

    public required init(context: Context)
    {
        super.init(context: context)
        observeDirectory()
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        observeDirectory()
    }

    deinit
    {
        for observer in self.directoryObservers
        {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// A server appearing or going away is the one thing that can change what
    /// this node should be connected to without any of its inputs changing —
    /// a patch opened before the app it takes its image from, or that app
    /// quitting and coming back.
    private func observeDirectory()
    {
        // The directory keeps observers of its own, and those are what post
        // the notifications below, so it is made here — on the thread the node
        // is made on — rather than lazily from the render thread in execute.
        _ = SyphonServerDirectory.shared()

        let center = NotificationCenter.default
        let flag = self.directoryFlag
        self.directoryObservers = Self.directoryNotifications.map
        { name in
            center.addObserver(forName: name, object: nil, queue: nil)
            { _ in
                flag.set()
            }
        }
    }

    /// Syphon's identity for a server, where it offers one.
    private func serverIdentity(_ description: [String: any NSCoding]) -> String?
    {
        (description[SyphonServerDescriptionUUIDKey] as? NSString) as String?
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        // A client whose server has gone yields nothing further, so it is
        // dropped and a server looked for again.
        var clientDidInvalidate = false
        if let syphonClient = self.syphonClient, !syphonClient.isValid
        {
            self.syphonClient = nil
            if let boundServerIdentity = self.boundServerIdentity
            {
                self.invalidServerIdentities.insert(boundServerIdentity)
            }
            self.boundServerIdentity = nil
            clientDidInvalidate = true
        }

        // An empty name means the first server there is, which is what makes
        // the node work on being dropped into a patch. That leaves nothing to
        // say "no server at all" with, which is what this is for.
        let isEnabled = self.inputEnabled.value ?? true
        guard isEnabled
        else
        {
            self.syphonClient = nil
            self.outputTexturePort.send(nil)
            return
        }

        let inputsDidChange = self.inputEnabled.valueDidChange
            || self.inputServerName.valueDidChange
            || self.inputServerAppName.valueDidChange

        let inputServerName = self.inputServerName.value ?? ""
        let inputServerAppName = self.inputServerAppName.value ?? ""

        // Asked again whenever what is on offer changes, not only when there
        // is nothing in hand: the server answering to a name is a different
        // one each time its application is relaunched, and a client made for
        // the last one can go on saying it is valid. Read here, where the
        // lookup that answers it follows on unconditionally.
        let serversDidChange = self.directoryFlag.take()
        if inputsDidChange || clientDidInvalidate || serversDidChange
        {
            let matches = SyphonServerDirectory.shared().servers(matchingName: inputServerName, appName: inputServerAppName)

            // Held only while the directory still offers the identity.
            // Syphon does not say an identity is never seen twice, and this
            // does not need it to be: one come again costs a client, found
            // invalid the next frame.
            self.invalidServerIdentities.formIntersection(matches.compactMap(self.serverIdentity))

            // Taken past a dead server rather than stopped by it: a relaunched
            // application leaves its old entry on offer beside its new one,
            // and which of the two comes first is not ours to say.
            let match = matches.first
            { description in
                guard let identity = self.serverIdentity(description) else { return true }
                return !self.invalidServerIdentities.contains(identity)
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
        }

        if let syphonClient = self.syphonClient,
           syphonClient.isValid,
           let texture = syphonClient.newFrameImage()
        {
            // A Syphon surface is bottom-up, and the client wraps it as it
            // stands — `newFrameImage` builds a texture straight onto the
            // IOSurface and turns nothing over. So the frame in hand is upside
            // down to Fabric's canonical top-left, and says so rather than
            // being copied the right way up: downstream samples through the
            // transform, and a frame passed back out to Syphon is already in
            // the orientation Syphon wants.
            let image = FabricImage.unmanaged(texture: texture)
            image.textureTransform = .textureVerticalFlip
            self.outputTexturePort.send(image)
        }
        else
        {
            self.outputTexturePort.send(nil)
        }

    }

}

#endif // FABRIC_SYPHON_ENABLED

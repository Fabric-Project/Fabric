//
//  SharedModelCache.swift
//  Fabric
//

import Foundation
import Metal
import MPSMediaPipe
import MPSTAPNextPlusPlus
import MPSZipDepth

/// Frames of inference one shared model allows in flight at once, summed over
/// every node using it.
///
/// A model's in-flight slots are held from encode until the command buffer they
/// were encoded onto completes, which for a node on Fabric's shared frame
/// buffer is the end of the frame, however many frames the renderer keeps in
/// flight. A model created with the package default of 3 therefore starves as
/// soon as two nodes share it and two frames overlap (4 slots needed), and its
/// fourth node in a frame would drop every frame. Slots cost nothing until
/// used, so a shared model gets enough for many nodes.
enum SharedModelCapacity
{
    static let framesInFlight = 16
}

/// A process-wide cache of loaded, compiled models, so that any number of node
/// instances asking for the same model share one compile and one copy of its
/// weights instead of each building their own.
///
/// Re-entrant by construction:
/// - Lookup and creation happen under one lock, so two nodes asking for the same
///   model in the same frame get the same instance: the second waits for the
///   first's build, it does not build a second copy. The cost is that a build
///   (a compile, about a second) blocks other lookups while it runs.
/// - The key includes the device, since a compiled model is bound to one.
/// - Sharing a model shares no per-call state. Callers own their input and
///   output buffers, and the model's per-slot scratch is per in-flight call.
///   In-flight capacity is the one shared resource; see `SharedModelCapacity`.
///
/// `.strong` keeps a model for the life of the process, right for a small fixed
/// set of variants. `.weak` lets a model go once no node holds it, right when
/// the set is open-ended (ZipDepth's resolution), but the caller must keep its
/// own strong reference for as long as it uses the model.
final class SharedModelCache<Model: AnyObject>
{
    enum Retention
    {
        case strong
        case weak
    }

    private struct Key: Hashable
    {
        let deviceRegistryID: UInt64
        let name: String
    }

    private final class WeakReference
    {
        weak var model: Model?
        init(_ model: Model) { self.model = model }
    }

    private let retention: Retention
    private let lock = NSLock()
    private var strongModels: [Key: Model] = [:]
    private var weakModels: [Key: WeakReference] = [:]

    init(retention: Retention)
    {
        self.retention = retention
    }

    func model(named name: String, device: MTLDevice, make: () throws -> Model) throws -> Model
    {
        let key = Key(deviceRegistryID: device.registryID, name: name)
        self.lock.lock()
        defer { self.lock.unlock() }

        switch self.retention
        {
        case .strong:
            if let existing = self.strongModels[key] { return existing }
            let created = try make()
            self.strongModels[key] = created
            return created

        case .weak:
            self.weakModels = self.weakModels.filter { $0.value.model != nil }
            if let existing = self.weakModels[key]?.model { return existing }
            let created = try make()
            self.weakModels[key] = WeakReference(created)
            return created
        }
    }
}

/// The MediaPipe models every MediaPipe node loads, shared across nodes. A
/// small fixed set of variants, so they are kept for the life of the process.
enum MediaPipeSharedModels
{
    private static let cache = SharedModelCache<MediaPipeMPSGraph>(retention: .strong)

    static func model(named name: String, inputWidth: Int, inputHeight: Int, commandQueue: MTLCommandQueue) throws -> MediaPipeMPSGraph
    {
        try Self.cache.model(named: "\(name) \(inputWidth)x\(inputHeight)", device: commandQueue.device)
        {
            try MediaPipeMPSGraph.loadBundled(
                named: name,
                inputWidth: inputWidth,
                inputHeight: inputHeight,
                commandQueue: commandQueue,
                maxFramesInFlight: SharedModelCapacity.framesInFlight
            )
        }
    }
}

/// ZipDepth models, one per input resolution, shared across nodes. Resolution is
/// a user parameter, so the set is open-ended: models are held weakly, and the
/// node keeps the one it is using.
enum ZipDepthSharedModels
{
    private static let cache = SharedModelCache<ZipDepthMPSGraph>(retention: .weak)

    static func model(width: Int, height: Int, commandQueue: MTLCommandQueue) throws -> ZipDepthMPSGraph
    {
        try Self.cache.model(named: "\(width)x\(height)", device: commandQueue.device)
        {
            try ZipDepthMPSGraph(
                inputWidth: width,
                inputHeight: height,
                commandQueue: commandQueue,
                maxFramesInFlight: SharedModelCapacity.framesInFlight
            )
        }
    }
}

/// TAPIR graphs are keyed by every fixed-shape compilation choice. The cache
/// is weak because point capacity, refinement count, precision, and the chosen
/// checkpoint directory form an open-ended set; each live node retains the
/// model it is actively using.
enum TAPIRSharedModels
{
    private static let cache = SharedModelCache<TAPIROnlineModel>(retention: .weak)

    static func model(
        configuration: TAPIRConfiguration,
        commandQueue: MTLCommandQueue
    ) throws -> TAPIROnlineModel
    {
        let precision = configuration.computePrecision == .mixedFloat16 ? "mixedFloat16" : "float32"
        let cacheName = [
            "bundled-causal-bootstapir",
            "points=\(configuration.maximumPointCount)",
            "refinements=\(configuration.refinementCount)",
            "precision=\(precision)",
        ].joined(separator: "|")

        return try Self.cache.model(named: cacheName, device: commandQueue.device)
        {
            try TAPIROnlineModel.loadBundled(
                configuration: configuration,
                commandQueue: commandQueue
            )
        }
    }
}

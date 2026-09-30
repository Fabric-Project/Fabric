import MPSEfficientTAM
import MPSMediaPipe
import MPSTAPNextPlusPlus
import MPSZipDepth

/// Where an MPS model node's graph may run, one Setting shared by every MPS
/// node. MPSGraph can be allowed to use the Neural Engine but cannot be forced
/// onto it; in practice only the Fast (float16) tier of depthwise models such
/// as MediaPipe's reaches it. The raw values are the serialized form.
public enum MPSModelComputeUnits: String, Codable, CaseIterable, Sendable
{
    case gpuAndNeuralEngine
    case gpuOnly

    public var label: String
    {
        switch self
        {
        case .gpuAndNeuralEngine: "GPU + Neural Engine"
        case .gpuOnly: "GPU Only"
        }
    }

    static var labels: [String] { Self.allCases.map(\.label) }

    init?(label: String)
    {
        guard let match = Self.allCases.first(where: { $0.label == label }) else { return nil }
        self = match
    }

    var mediaPipe: MediaPipeComputeUnits
    {
        switch self
        {
        case .gpuAndNeuralEngine: .gpuAndNeuralEngine
        case .gpuOnly: .gpuOnly
        }
    }

    var zipDepth: ZipDepthComputeUnits
    {
        switch self
        {
        case .gpuAndNeuralEngine: .gpuAndNeuralEngine
        case .gpuOnly: .gpuOnly
        }
    }

    var tapir: TAPIRComputeUnits
    {
        switch self
        {
        case .gpuAndNeuralEngine: .gpuAndNeuralEngine
        case .gpuOnly: .gpuOnly
        }
    }

    var efficientTAM: EfficientTAMComputeUnits
    {
        switch self
        {
        case .gpuAndNeuralEngine: .gpuAndNeuralEngine
        case .gpuOnly: .gpuOnly
        }
    }
}

/// The two build choices a node's model is loaded and cached by. Nodes expose
/// them as separate settings (`modelPrecision`, `modelComputeUnits`) and pass
/// them to their model together as this.
struct MPSModelExecution: Equatable
{
    let precision: MPSModelPrecision
    let computeUnits: MPSModelComputeUnits

    /// A cache-key fragment naming both choices.
    var cacheName: String { "\(self.precision.rawValue) \(self.computeUnits.rawValue)" }
}

import MPSEfficientTAM
import MPSMediaPipe
import MPSTAPNextPlusPlus
import MPSZipDepth

/// The precision an MPS model node computes in, one Setting shared by every
/// MPS node. Each package offers the same three tiers; this maps them onto
/// user-facing names. The raw values are the serialized form.
public enum MPSModelPrecision: String, Codable, CaseIterable, Sendable
{
    /// Float32 throughout.
    case highQuality = "float32"
    /// Heavy layers (convolutions, matrix multiplies) in float16, the rest float32.
    case balanced = "mixedFloat16"
    /// Float16 throughout; the only tier the Neural Engine can take.
    case fast = "float16"

    public var label: String
    {
        switch self
        {
        case .highQuality: "High Quality"
        case .balanced: "Balanced"
        case .fast: "Fast"
        }
    }

    static var labels: [String] { Self.allCases.map(\.label) }

    init?(label: String)
    {
        guard let match = Self.allCases.first(where: { $0.label == label }) else { return nil }
        self = match
    }

    var mediaPipe: MediaPipePrecision
    {
        switch self
        {
        case .highQuality: .float32
        case .balanced: .mixedFloat16
        case .fast: .float16
        }
    }

    var zipDepth: ZipDepthPrecision
    {
        switch self
        {
        case .highQuality: .float32
        case .balanced: .mixedFloat16
        case .fast: .float16
        }
    }

    var tapir: TAPIRComputePrecision
    {
        switch self
        {
        case .highQuality: .float32
        case .balanced: .mixedFloat16
        case .fast: .float16
        }
    }

    var efficientTAM: EfficientTAMPrecision
    {
        switch self
        {
        case .highQuality: .float32
        case .balanced: .mixedFloat16
        case .fast: .float16
        }
    }
}

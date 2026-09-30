/// When an MPS model node's results arrive, one Setting shared by the MPS
/// nodes that read numbers back from the GPU. The raw values are the
/// serialized form.
public enum MPSInferenceTiming: String, Codable, CaseIterable, Sendable
{
    /// Inference is encoded onto Fabric's frame command buffer and results are
    /// published when the GPU finishes, so they lag the frame. Never waits.
    case asynchronous
    /// Inference runs on the node's own command buffer and the node waits for
    /// it, so results belong to the current frame at the cost of a GPU wait.
    /// The default for every MPS node.
    case synchronous

    public var label: String
    {
        switch self
        {
        case .asynchronous: "Asynchronous"
        case .synchronous: "Synchronous"
        }
    }

    static var labels: [String] { Self.allCases.map(\.label) }

    init?(label: String)
    {
        guard let match = Self.allCases.first(where: { $0.label == label }) else { return nil }
        self = match
    }
}

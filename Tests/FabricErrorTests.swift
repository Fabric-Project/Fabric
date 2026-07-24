import Testing
import Foundation
@testable import Fabric

@Suite("Fabric Error")
struct FabricErrorTests
{
    @Test("FabricError preserves author-selected severity")
    func fabricErrorPreservesSeverity()
    {
        let recoverable = FabricError(.execution(.gpu),
                                      severity: .recoverable,
                                      message: "Transient Metal command failure.")
        let fatal = FabricError(.execution(.gpu),
                                severity: .fatal,
                                message: "Metal device is unavailable.")

        #expect(recoverable.kind == .execution(.gpu))
        #expect(recoverable.severity == .recoverable)
        #expect(recoverable.errorDescription == "Transient Metal command failure.")

        #expect(fatal.kind == .execution(.gpu))
        #expect(fatal.severity == .fatal)
        #expect(fatal.errorDescription == "Metal device is unavailable.")
    }

    @Test("Plugin errors can extend the protocol")
    func pluginErrorsCanExtendProtocol()
    {
        struct PluginSpecificError: FabricErrorProtocol
        {
            let severity: FabricErrorSeverity
            let errorDescription: String?
        }

        let error: any FabricErrorProtocol = PluginSpecificError(severity: .recoverable,
                                                                 errorDescription: "Plugin-specific warning.")

        #expect(error.severity == .recoverable)
        #expect(error.errorDescription == "Plugin-specific warning.")
    }

    @Test("Plugin load errors participate in the shared error protocol")
    func pluginLoadErrorsUseSharedProtocol()
    {
        let error: any FabricErrorProtocol = PluginLoadError.classNotFound(pluginID: "test.plugin",
                                                                           className: "MissingNode")

        #expect(error.severity == .recoverable)
        #expect(error.errorDescription?.localizedStandardContains("MissingNode") == true)
    }
}

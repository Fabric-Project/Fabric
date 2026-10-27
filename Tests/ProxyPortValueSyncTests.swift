import Testing
import Foundation
@testable import Fabric
import Satin

/// `NodePort.value` is final, so a proxy keeps its own copy of the inner port's value
/// instead of reading through to it.
@Suite("Proxy port value sync")
struct ProxyPortValueSyncTests
{
    @Test("A change inside the subgraph reaches the proxy")
    func innerChangeReachesProxy()
    {
        let parameter = FloatParameter("Number", 1)
        let inner = ParameterPort(parameter: parameter)
        let proxy = ProxyPort(wrapping: inner)

        parameter.value = 4
        #expect(inner.value == 4)
        #expect(proxy.value == 4)

        inner.value = 6
        #expect(proxy.value == 6)
    }

    @Test("A value sent to the proxy reaches the inner port and its parameter")
    func proxyChangeReachesInnerPort()
    {
        let parameter = FloatParameter("Number", 1)
        let inner = ParameterPort(parameter: parameter)
        let proxy = ProxyPort(wrapping: inner)

        proxy.value = 5
        #expect(inner.value == 5)
        #expect(parameter.value == 5)
    }

    @Test("The proxy reads back the inner port's resolution of nil")
    func proxyReadsBackInnerResolution()
    {
        let parameter = FloatParameter("Number", 3)
        let inner = ParameterPort(parameter: parameter)
        let proxy = ProxyPort(wrapping: inner)

        proxy.value = nil
        #expect(inner.value == 3)
        #expect(proxy.value == 3)
    }

    @Test("A released proxy stops receiving and a replacement takes over")
    func releasedProxyIsForgotten()
    {
        let inner = NodePort<Float>(name: "Number", kind: .Inlet)
        let retired = ProxyPort(wrapping: inner)
        let replacement = ProxyPort(wrapping: inner)
        _ = consume retired

        inner.value = 8
        #expect(replacement.value == 8)
        #expect(inner.publishingProxy === replacement)

        do { _ = ProxyPort(wrapping: inner) }
        #expect(inner.publishingProxy == nil)
        inner.value = 9
    }
}

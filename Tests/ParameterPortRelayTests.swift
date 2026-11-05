import Testing
import Combine
import Satin
import Fabric

/// A ParameterPort mirrors its parameter without a Combine subscription; clients still see every
/// change on `valuePublisher`, once.
@Suite("Parameter port relay")
struct ParameterPortRelayTests {
    @Test("A parameter edit reaches the port, and a port edit reaches the parameter once")
    func bothDirections() {
        let parameter = FloatParameter("Amount", 0)
        let port = ParameterPort(parameter: parameter)
        var published: [Float] = []
        let subscription = parameter.valuePublisher.sink { published.append($0) }
        defer { subscription.cancel() }

        parameter.value = 1
        #expect(port.value == 1)
        port.value = 2
        #expect(parameter.value == 2)
        #expect(published == [1, 2])
    }

    @Test("A replaced parameter no longer drives the port")
    func replacement() {
        let original = FloatParameter("Original", 0)
        let port = ParameterPort(parameter: original)
        let replacement = FloatParameter("Replacement", 5)
        port.parameter = replacement
        original.value = 9
        #expect(port.value == 0)
        replacement.value = 3
        #expect(port.value == 3)
    }

    @Test("Ports sharing a parameter each follow it, and one going leaves the other observing")
    func sharedParameter() {
        let parameter = FloatParameter("Amount", 0)
        let kept = ParameterPort(parameter: parameter)
        do {
            let retired = ParameterPort(parameter: parameter)
            parameter.value = 1
            #expect(retired.value == 1)
        }
        parameter.value = 2
        #expect(kept.value == 2)
    }
}

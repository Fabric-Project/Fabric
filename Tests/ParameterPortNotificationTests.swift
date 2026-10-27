import Testing
import Combine
import Satin
@testable import Fabric

@Suite("Parameter port notifications")
struct ParameterPortNotificationTests {
    @Test("A port edit updates its parameter and reports one value change")
    func portEdit() {
        let parameter = FloatParameter("Value", 0)
        let port = ParameterPort(parameter: parameter)
        var portChanges = 0
        var parameterValues: [Float] = []
        port.onValueChanged = { portChanges += 1 }
        let subscription = parameter.valuePublisher.sink { parameterValues.append($0) }

        port.value = 3

        #expect(port.value == 3)
        #expect(parameter.value == 3)
        #expect(parameterValues == [3])
        #expect(portChanges == 1)
        withExtendedLifetime(subscription) {}
    }

    @Test("A parameter edit updates its port and reports one value change")
    func parameterEdit() {
        let parameter = FloatParameter("Value", 0)
        let port = ParameterPort(parameter: parameter)
        var portChanges = 0
        port.onValueChanged = { portChanges += 1 }
        port.valueDidChange = false

        parameter.value = 3

        #expect(port.value == 3)
        #expect(port.valueDidChange)
        #expect(portChanges == 1)
    }

    @Test("Force sends of an equal value still notify the port")
    func equalForcedSend() {
        let parameter = FloatParameter("Value", 3)
        let port = ParameterPort(parameter: parameter)
        var portChanges = 0
        port.onValueChanged = { portChanges += 1 }
        port.valueDidChange = false

        port.send(3, force: true)

        #expect(port.value == 3)
        #expect(port.valueDidChange)
        #expect(portChanges == 1)
    }

    @Test("An explicit parameter notification still invalidates an equal port value")
    func explicitParameterNotification() {
        let parameter = FloatParameter("Value", 3)
        let port = ParameterPort(parameter: parameter)
        var portChanges = 0
        port.onValueChanged = { portChanges += 1 }
        port.valueDidChange = false

        parameter.valuePublisher.send(3)

        #expect(port.valueDidChange)
        #expect(portChanges == 1)
    }

    @Test("Replacing a backing parameter disconnects the old subscription")
    func replacingParameter() {
        let original = FloatParameter("Original", 0)
        let replacement = FloatParameter("Replacement", 9)
        let port = ParameterPort(parameter: original)
        port.parameter = replacement
        var portChanges = 0
        port.onValueChanged = { portChanges += 1 }

        original.value = 2
        #expect(port.value == 0)
        #expect(portChanges == 0)
        replacement.value = 4
        #expect(port.value == 4)
        #expect(portChanges == 1)
    }

}

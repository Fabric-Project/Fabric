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

    @Test("Restoring a plain port notifies once, including equal values and nil",
          arguments: [Float?(3), Float?(1), nil])
    func restorePlainPort(value: Float?) {
        let port = NodePort<Float>(name: "Value", kind: .Outlet)
        port.value = 1
        port.valueDidChange = false
        var portChanges = 0
        port.onValueChanged = { portChanges += 1 }

        port.restoreValue(from: value?.toPortValue())

        #expect(port.value == value)
        #expect(port.valueDidChange)
        #expect(portChanges == 1)
    }

    @Test("Restoring a parameter-backed port notifies once and preserves its resting value",
          arguments: [Float?(3), Float?(1), nil])
    func restoreParameterPort(value: Float?) {
        let parameter = FloatParameter("Value", 1)
        let port = ParameterPort(parameter: parameter)
        port.valueDidChange = false
        var portChanges = 0
        port.onValueChanged = { portChanges += 1 }

        port.restoreValue(from: value?.toPortValue())

        #expect(port.value == (value ?? 1))
        #expect(parameter.value == (value ?? 1))
        #expect(port.valueDidChange)
        #expect(portChanges == 1)
    }

}

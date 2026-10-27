import Testing
@testable import Fabric

private final class ConversionCounts {
    var convertedTypes: [PortType] = []
    var destinationTypeReads = 0
    var failsConversion = false
}

private struct ConversionTestValue: PortValueRepresentable {
    let value: Float
    let counts: ConversionCounts
    static var defaultValue: Self? { nil }
    static var portType: PortType { .Float }
    var portType: PortType { .Float }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    func toPortValue() -> PortValue { .Float(value) }
    static func fromPortValue(_ value: PortValue) -> Self? { nil }
    func canConvertTo(other: PortType) -> Bool { value.canConvertTo(other: other) }
    func convertTo(other: PortType) -> (any PortValueRepresentable)? {
        counts.convertedTypes.append(other)
        return counts.failsConversion ? nil : value.convertTo(other: other)
    }
}

private final class ConversionDestination<Value: PortValueRepresentable>: NodePort<Value> {
    var counts: ConversionCounts?
    override var portType: PortType {
        counts?.destinationTypeReads += 1
        return super.portType
    }
}

@Suite("Port conversion delivery")
struct PortConversionTests {
    private func connect(_ output: Fabric.Port, to input: Fabric.Port) {
        let connection = Connection(outletPortID: output.id, inletPortID: input.id)
        connection.outletPortReference = output
        connection.inletPortReference = input
        output.connections.append(connection)
        input.connections.append(connection)
    }

    @Test("Mixed-type sends resolve and convert once per destination",
          arguments: [PortType.Bool, .Int, .Float, .String])
    func singleConversion(destinationType: PortType) throws {
        let counts = ConversionCounts()
        let output = NodePort<ConversionTestValue>(name: "Output", kind: .Outlet)
        let input: Fabric.Port
        let expected: PortValue
        switch destinationType {
        case .Bool:
            let destination = ConversionDestination<Bool>(name: "Input", kind: .Inlet)
            destination.counts = counts
            input = destination
            expected = .Bool(true)
        case .Int:
            let destination = ConversionDestination<Int>(name: "Input", kind: .Inlet)
            destination.counts = counts
            input = destination
            expected = .Int(1)
        case .Float:
            let destination = ConversionDestination<Float>(name: "Input", kind: .Inlet)
            destination.counts = counts
            input = destination
            expected = .Float(1.25)
        default:
            let destination = ConversionDestination<String>(name: "Input", kind: .Inlet)
            destination.counts = counts
            input = destination
            expected = .String("1.25")
        }
        connect(output, to: input)
        output.send(ConversionTestValue(value: 1.25, counts: counts))
        #expect(input.snapshotValue() == expected)
        #expect(counts.convertedTypes == [destinationType])
        #expect(counts.destinationTypeReads == 1)
    }

    @Test("Equal mixed-type sends stay suppressed unless forced")
    func forcedConversion() {
        let counts = ConversionCounts()
        let output = NodePort<ConversionTestValue>(name: "Output", kind: .Outlet)
        let input = NodePort<String>(name: "Input", kind: .Inlet)
        connect(output, to: input)
        var notifications = 0
        input.onValueChanged = { notifications += 1 }
        let value = ConversionTestValue(value: 2, counts: counts)
        output.send(value)
        output.send(value)
        output.send(value, force: true)
        #expect(input.value == "2.0")
        #expect(notifications == 2)
        #expect(counts.convertedTypes == [.String, .String])
    }

    @Test("Same-type sends bypass conversion and destination type lookup")
    func sameTypeFastPath() {
        let counts = ConversionCounts()
        let output = NodePort<ConversionTestValue>(name: "Output", kind: .Outlet)
        let input = ConversionDestination<ConversionTestValue>(name: "Input", kind: .Inlet)
        input.counts = counts
        connect(output, to: input)
        let value = ConversionTestValue(value: 2, counts: counts)
        output.send(value)
        #expect(input.value == value)
        #expect(counts.convertedTypes.isEmpty)
        #expect(counts.destinationTypeReads == 0)
    }

    @Test("A failed conversion leaves the destination untouched")
    func failedConversion() {
        let counts = ConversionCounts()
        counts.failsConversion = true
        let output = NodePort<ConversionTestValue>(name: "Output", kind: .Outlet)
        let input = NodePort<String>(name: "Input", kind: .Inlet)
        input.value = "unchanged"
        input.valueDidChange = false
        connect(output, to: input)
        output.send(ConversionTestValue(value: 2, counts: counts), force: true)
        #expect(input.value == "unchanged")
        #expect(!input.valueDidChange)
        #expect(counts.convertedTypes == [.String])
    }

    @Test("Converted floats retain their existing nonfinite-value and force behavior")
    func floatValidation() {
        let output = NodePort<PortValue>(name: "Output", kind: .Outlet)
        let input = NodePort<Float>(name: "Input", kind: .Inlet)
        input.value = 2
        connect(output, to: input)
        output.send(.Float(.infinity))
        #expect(input.value == 2)
        output.send(.Float(.infinity), force: true)
        #expect(input.value == .infinity)
    }

    @Test("Typed and virtual ports still exchange scalar and collection values")
    func virtualDelivery() {
        let scalar = NodePort<Float>(name: "Scalar", kind: .Outlet)
        let virtual = NodePort<PortValue>(name: "Virtual", kind: .Inlet)
        connect(scalar, to: virtual)
        scalar.send(3)
        #expect(virtual.value == .Float(3))
        let boxed = NodePort<PortValue>(name: "Boxed", kind: .Outlet)
        let array = NodePort<ContiguousArray<Float>>(name: "Array", kind: .Inlet)
        connect(boxed, to: array)
        boxed.send(.Array([.Float(1), .Float(2)]))
        #expect(array.value == [1, 2])
    }
}

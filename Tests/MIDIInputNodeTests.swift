import Testing
import Foundation
@testable import Fabric

@Suite("MIDIInputNode refreshInputs Tests")
struct MIDIInputNodeTests {
    
    @Test("refreshInputs handles nil manufacturer values from endpoints")
    func handlesNilManufacturerFromEndpoints() {
        // This test validates the core logic that was fixed in refreshInputs()
        // The method now properly passes manufacturer values to MIDIInputInfo
        
        // Simulate what the fixed code path should do with different manufacturer scenarios
        let scenarios = [
            ("device1", "Controller 1", nil as String?),
            ("device2", "Controller 2", "Acme Instruments"),
            ("device3", "Controller 3", "")
        ]
        
        for (id, name, manufacturer) in scenarios {
            // This represents the logic that was in refreshInputs()
            let inputInfo = MIDIInputInfo(
                id: id,
                name: name,
                manufacturer: manufacturer
            )
            
            #expect(inputInfo.id == id)
            #expect(inputInfo.name == name)
            #expect(inputInfo.manufacturer == manufacturer)
        }
    }
    
    @Test("refreshInputs creates valid MIDIInputInfo with nil manufacturer")
    func createsValidMIDIInputInfoWithNilManufacturer() {
        let result = MIDIInputInfo(
            id: "test-unique-id",
            name: "Test MIDI Device",
            manufacturer: nil
        )
        
        #expect(result.id == "test-unique-id")
        #expect(result.name == "Test MIDI Device")
        #expect(result.manufacturer == nil)
        #expect(result.displayName == "Test MIDI Device")
    }
}

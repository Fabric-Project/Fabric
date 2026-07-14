import Testing
import Foundation
@testable import Fabric

@Suite("Node Registry")
struct NodeRegistryTests {

    // Swift `lazy var` initialization is not atomic: concurrent first reads of
    // NodeRegistry's lookup tables raced on the backing store and crashed in
    // _DictionaryStorage.deinit. NodeRegistry.init now builds the render-path
    // tables eagerly, so first access from many threads at once must be safe.
    // Under Thread Sanitizer the old race is reported deterministically;
    // without TSan it was an intermittent crash, hence the loop.
    @Test("Concurrent first access to a cold registry is safe")
    func nodeRegistryConcurrentFirstAccess() async {
        for _ in 0..<100 {
            // Fresh instance so the lookup tables are cold each iteration.
            let registry = NodeRegistry()
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<16 {
                    group.addTask {
                        _ = registry.nodeClass(for: "PerspectiveCameraNode")
                    }
                }
            }
            // Compare as Bool: passing an Optional<Node.Type> through #expect's
            // generic __checkBinaryOperation crashes the runtime's metadata
            // instantiation (metatype generic argument), independent of the
            // registry race this test guards against.
            let found = registry.nodeClass(for: "PerspectiveCameraNode") != nil
            #expect(found)
        }
    }
}

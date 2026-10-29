import Testing
import Foundation
@testable import Fabric
import Satin

/// Runs after everything already queued on main has run.
@MainActor
func drainMainQueue() async
{
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

/// Runs `work` on a background thread, as the render thread would call a node.
func runOffMain(_ work: @escaping () throws -> Void) async throws
{
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        DispatchQueue.global().async
        {
            do
            {
                try work()
                continuation.resume()
            }
            catch
            {
                continuation.resume(throwing: error)
            }
        }
    }
}

@Suite("Node main-thread escape hatch")
struct NodeMainThreadTests
{
    private struct IntentionalFailure: Error {}

    @Test("Sync on main runs at once, without waiting on itself")
    @MainActor
    func syncOnMainRunsAtOnce() throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let node = Node(context: harness.context)

        var ran = false
        node.performOnMainSync { ran = true }

        #expect(ran)
    }

    @Test("Sync off main runs on main and returns its result")
    func syncOffMainRunsOnMain() async throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let node = Node(context: harness.context)

        var ranOnMain = false
        var result = 0
        try await runOffMain
        {
            result = node.performOnMainSync
            {
                ranOnMain = Thread.isMainThread
                return 42
            }
        }

        #expect(ranOnMain)
        #expect(result == 42)
    }

    @Test("Sync passes errors through, on and off main")
    func syncRethrows() async throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let node = Node(context: harness.context)

        _ = await MainActor.run
        {
            #expect(throws: IntentionalFailure.self) { try node.performOnMainSync { throw IntentionalFailure() } }
        }
        await #expect(throws: IntentionalFailure.self)
        {
            try await runOffMain { try node.performOnMainSync { throw IntentionalFailure() } }
        }
    }

    @Test("Async from main runs later, in order")
    @MainActor
    func asyncFromMainRunsLaterInOrder() async throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let node = Node(context: harness.context)

        var order: [Int] = []
        node.performOnMainAsync { order.append(1) }
        node.performOnMainAsync { order.append(2) }
        #expect(order.isEmpty, "never runs in the middle of the caller")

        await drainMainQueue()
        #expect(order == [1, 2])
    }

    @Test("Async off main runs on main, in order")
    func asyncOffMainRunsOnMainInOrder() async throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        let node = Node(context: harness.context)

        var order: [Int] = []
        var everyRunWasOnMain = true
        try await runOffMain
        {
            for index in 0..<10
            {
                node.performOnMainAsync
                {
                    everyRunWasOnMain = everyRunWasOnMain && Thread.isMainThread
                    order.append(index)
                }
            }
        }

        await drainMainQueue()
        #expect(order == Array(0..<10))
        #expect(everyRunWasOnMain)
    }
}

/// IO nodes whose lifecycle asks for no permission, so tests never prompt. Game
/// Controller starts wireless discovery, which can ask for Bluetooth.
private let ioNodeTypesWithoutPermissionPrompts: [Node.Type] = [OSCReceiveNode.self, MIDIInputNode.self]

/// IO nodes hand their device work to main. Lifecycle calls can come from the
/// render thread, and a deleted node's teardown must still run.
@Suite("IO node lifecycle on main", .serialized)
@MainActor
struct IONodeLifecycleTests
{
    @Test("A released node is kept until its queued lifecycle work runs, then freed", arguments: ioNodeTypesWithoutPermissionPrompts)
    func releasedNodeIsKeptUntilItsWorkRuns(nodeType: Node.Type) async throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        weak var releasedNode: Node?
        do
        {
            let node = nodeType.init(context: harness.context)
            releasedNode = node
            try node.enableExecution(renderer: harness.renderer)
            try node.startExecution(renderer: harness.renderer)
            try node.stopExecution(renderer: harness.renderer)
            try node.disableExecution(renderer: harness.renderer)
        }

        #expect(releasedNode != nil, "the queued teardown holds the node")
        await drainMainQueue()
        #expect(releasedNode == nil)
    }

    @Test("Lifecycle calls from another thread hand over to main", arguments: ioNodeTypesWithoutPermissionPrompts)
    func lifecycleFromAnotherThread(nodeType: Node.Type) async throws
    {
        let harness = try #require(GraphExecutionTestHarness())
        weak var releasedNode: Node?
        do
        {
            let node = nodeType.init(context: harness.context)
            releasedNode = node
            let renderer = harness.renderer
            try await runOffMain
            {
                try node.enableExecution(renderer: renderer)
                try node.startExecution(renderer: renderer)
            }
            await drainMainQueue()
            #expect(node.executionState == .started)

            try await runOffMain
            {
                try node.stopExecution(renderer: renderer)
                try node.disableExecution(renderer: renderer)
            }
            #expect(node.executionState == .disabled)
        }

        await drainMainQueue()
        #expect(releasedNode == nil)
    }
}

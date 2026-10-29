//
//  Node+MainThread.swift
//  Fabric
//

import Foundation

/// The escape hatch for node work that must run on the main thread: device setup and teardown,
/// system callbacks that require main, and settings view model updates.
///
/// Nodes call these from any thread, including execution and lifecycle callbacks, rather than
/// dispatching to main themselves. How the work reaches main is an implementation detail.
extension Node
{
    /// Runs `work` on the main thread without waiting for it.
    ///
    /// Work runs in the order it was submitted, always on a later turn of the main run loop, even
    /// when called from main, so it never runs in the middle of the caller. The closure keeps
    /// whatever it captures, including the node, alive until it has run.
    public func performOnMainAsync(_ work: @escaping @MainActor () -> Void)
    {
        DispatchQueue.main.async
        {
            MainActor.assumeIsolated(work)
        }
    }

    /// Runs `work` on the main thread and returns its result.
    ///
    /// Called from main, `work` runs immediately, so this never deadlocks main waiting on itself.
    /// Called from another thread, it blocks that thread until main has run `work`. It takes no
    /// lock, but main must not be waiting on the calling thread.
    @discardableResult
    public func performOnMainSync<Result>(_ work: @MainActor () throws -> Result) rethrows -> Result
    {
        if Thread.isMainThread
        {
            return try MainActor.assumeIsolated(work)
        }

        return try DispatchQueue.main.sync
        {
            try MainActor.assumeIsolated(work)
        }
    }
}

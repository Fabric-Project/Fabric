#if FABRIC_SYPHON_ENABLED

import Testing

/// Syphon discovery and connection messages arrive asynchronously.
@MainActor
func waitForSyphon(_ condition: () throws -> Bool) async throws
{
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while try !condition()
    {
        try #require(clock.now < deadline, "Timed out waiting for Syphon discovery, lifecycle changes, or a received frame")
        try await Task.sleep(for: .milliseconds(20))
    }
}

#endif

import Testing
@testable import Fabric

/// The One Euro filter estimates its sampling rate from timestamp gaps. Graph time can repeat (an
/// offline render of the same time, or every iteration of a frame) or start over, and neither may
/// poison the filter: it keeps its last rate and stays finite.
struct OneEuroFilterTests
{
    @Test func repeatedTimestampsStayFinite() throws
    {
        let filter = OneEuroFilter(freq: 60, mincutoff: 1, beta: 0.5)

        _ = filter.Filter(0, timestamp: 1)
        let repeated = filter.Filter(1, timestamp: 1)
        let advanced = filter.Filter(2, timestamp: 1.5)

        #expect(repeated.isFinite)
        #expect(advanced.isFinite)
    }

    @Test func timeStartingOverStaysFinite() throws
    {
        let filter = OneEuroFilter(freq: 60, mincutoff: 1, beta: 0.5)

        _ = filter.Filter(0, timestamp: 5)
        let restarted = filter.Filter(1, timestamp: 0)
        let advanced = filter.Filter(2, timestamp: 0.1)

        #expect(restarted.isFinite)
        #expect(advanced.isFinite)
    }
}

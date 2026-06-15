//
//  ContiguousArray-PadToLast.swift
//  Fabric
//

import Foundation

extension ContiguousArray
{
    /// Returns exactly `count` elements: the receiver truncated to `count`, or
    /// extended to `count` by repeating its last element. An empty receiver
    /// yields `count` copies of `fallback` (so a missing/empty input broadcasts
    /// as a constant).
    func paddedToLast(count: Int, fallback: Element) -> [Element]
    {
        guard let last = self.last else { return Array(repeating: fallback, count: count) }
        if self.count >= count { return Array(self.prefix(count)) }
        return Array(self) + Array(repeating: last, count: count - self.count)
    }
}

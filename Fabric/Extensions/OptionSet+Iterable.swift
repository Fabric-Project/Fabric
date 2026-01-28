//
//  OptionSet+Iterable.swift
//  Fabric
//
//  Created by Anton Marini on 1/21/26.
//

import Foundation

// Source - https://stackoverflow.com/a
// Posted by milo, modified by community. See post 'Timeline' for change history
// Retrieved 2026-01-21, License - CC BY-SA 4.0

extension OptionSet where Self.RawValue == Int {
   public func makeIterator() -> OptionSetIterator<Self> {
      return OptionSetIterator(element: self)
   }
}

public struct OptionSetIterator<Element: OptionSet>: IteratorProtocol where Element.RawValue == Int {
    private let value: Element

    public init(element: Element) {
        self.value = element
    }

    private lazy var remainingBits = value.rawValue
    private var bitMask = 1

    public mutating func next() -> Element? {
        while remainingBits != 0 {
            defer { bitMask = bitMask &* 2 }
            if remainingBits & bitMask != 0 {
                remainingBits = remainingBits & ~bitMask
                return Element(rawValue: bitMask)
            }
        }
        return nil
    }
}

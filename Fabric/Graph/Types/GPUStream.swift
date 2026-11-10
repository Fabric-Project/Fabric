//
//  GPUStream.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// How many elements of a stream are valid.
public enum GPUStreamCount: Equatable
{
    /// The CPU knows the count.
    case known(Int)
    /// A GPU pass wrote the count, as the vertex count of a whole draw-arguments record, which
    /// `PointsDrawArguments` checks lies inside its buffer; it is never more than `capacity`. Points
    /// draw by it directly, and `Points.drawArguments` is one as it is.
    case gpu(PointsDrawArguments, capacity: Int)

    /// The most elements the stream can hold.
    public var capacity: Int
    {
        switch self
        {
        case .known(let count): return count
        case .gpu(_, let capacity): return capacity
        }
    }

    /// Two GPU counts are the same count only when they read the same record: the same buffer at the
    /// same offset.
    public static func == (lhs: GPUStreamCount, rhs: GPUStreamCount) -> Bool
    {
        switch (lhs, rhs)
        {
        case let (.known(left), .known(right)):
            return left == right
        case let (.gpu(leftArguments, leftCapacity), .gpu(rightArguments, rightCapacity)):
            return leftArguments.isSameRecord(as: rightArguments) && leftCapacity == rightCapacity
        default:
            return false
        }
    }
}

/// A value a stream can carry: its logical type on ports and in kernels, and the storage it allows.
public protocol GPUStreamElement: PortValueRepresentable
{
    /// Components per element.
    static var streamComponents: Int { get }
    /// The scalar storage this element allows. The first is what new streams use.
    static var streamScalars: [AttributeScalar] { get }

    /// Copies `values` into a new attribute in the first of `streamScalars`. `clamped` is true when
    /// a value didn't fit that storage.
    static func publishStream(_ values: ContiguousArray<Self>, allocator: GPUAllocator) throws -> (attribute: PublishedAttribute, clamped: Bool)

    /// Reads `count` elements stored in `layout` from `bytes`, which the CPU can read.
    static func readStream(_ bytes: UnsafeRawPointer, layout: AttributeLayout, count: Int) -> ContiguousArray<Self>
}

extension GPUStreamElement
{
    /// Float elements copy as they are: float32, one element per value at the value's stride.
    public static func publishStream(_ values: ContiguousArray<Self>, allocator: GPUAllocator) throws -> (attribute: PublishedAttribute, clamped: Bool)
    {
        let attribute = try PublishedAttribute.publishing(values, scalar: .float32, components: streamComponents,
                                                          allocator: allocator, label: "Stream")
        return (attribute, false)
    }
}

extension Swift.Float: GPUStreamElement
{
    public static var streamComponents: Int { 1 }
    public static var streamScalars: [AttributeScalar] { [.float32, .float16] }

    public static func readStream(_ bytes: UnsafeRawPointer, layout: AttributeLayout, count: Int) -> ContiguousArray<Float>
    {
        ContiguousArray((0..<count).map { streamComponent(bytes, layout: layout, index: $0, component: 0) })
    }
}

/// Stored as int32. Publishing a Swift `Int` outside the int32 range clamps it.
extension Swift.Int: GPUStreamElement
{
    public static var streamComponents: Int { 1 }
    public static var streamScalars: [AttributeScalar] { [.int32] }

    public static func publishStream(_ values: ContiguousArray<Int>, allocator: GPUAllocator) throws -> (attribute: PublishedAttribute, clamped: Bool)
    {
        let range = Int(Int32.min)...Int(Int32.max)
        // Inside an Int extension, bare min and max are Int.min and Int.max.
        let stored = ContiguousArray(values.map { Int32(Swift.min(Swift.max($0, range.lowerBound), range.upperBound)) })
        let clamped = values.contains { !range.contains($0) }
        let attribute = try PublishedAttribute.publishing(stored, scalar: .int32, components: 1, allocator: allocator, label: "Stream")
        return (attribute, clamped)
    }

    public static func readStream(_ bytes: UnsafeRawPointer, layout: AttributeLayout, count: Int) -> ContiguousArray<Int>
    {
        ContiguousArray((0..<count).map { Int((bytes + layout.byteOffset + $0 * layout.byteStride).loadUnaligned(as: Int32.self)) })
    }
}

extension simd.simd_float2: GPUStreamElement
{
    public static var streamComponents: Int { 2 }
    public static var streamScalars: [AttributeScalar] { [.float32, .float16] }

    public static func readStream(_ bytes: UnsafeRawPointer, layout: AttributeLayout, count: Int) -> ContiguousArray<simd_float2>
    {
        ContiguousArray((0..<count).map {
            simd_float2(streamComponent(bytes, layout: layout, index: $0, component: 0),
                        streamComponent(bytes, layout: layout, index: $0, component: 1))
        })
    }
}

extension simd.simd_float3: GPUStreamElement
{
    public static var streamComponents: Int { 3 }
    public static var streamScalars: [AttributeScalar] { [.float32, .float16] }

    public static func readStream(_ bytes: UnsafeRawPointer, layout: AttributeLayout, count: Int) -> ContiguousArray<simd_float3>
    {
        ContiguousArray((0..<count).map {
            simd_float3(streamComponent(bytes, layout: layout, index: $0, component: 0),
                        streamComponent(bytes, layout: layout, index: $0, component: 1),
                        streamComponent(bytes, layout: layout, index: $0, component: 2))
        })
    }
}

extension simd.simd_float4: GPUStreamElement
{
    public static var streamComponents: Int { 4 }
    public static var streamScalars: [AttributeScalar] { [.float32, .float16] }

    public static func readStream(_ bytes: UnsafeRawPointer, layout: AttributeLayout, count: Int) -> ContiguousArray<simd_float4>
    {
        ContiguousArray((0..<count).map { streamFloat4(bytes, layout: layout, index: $0) })
    }
}

/// Stored as x, y, z, w.
extension simd.simd_quatf: GPUStreamElement
{
    public static var streamComponents: Int { 4 }
    public static var streamScalars: [AttributeScalar] { [.float32, .float16] }

    public static func readStream(_ bytes: UnsafeRawPointer, layout: AttributeLayout, count: Int) -> ContiguousArray<simd_quatf>
    {
        ContiguousArray((0..<count).map { simd_quatf(vector: streamFloat4(bytes, layout: layout, index: $0)) })
    }
}

/// One float or half component of one element, as a float.
private func streamComponent(_ bytes: UnsafeRawPointer, layout: AttributeLayout, index: Int, component: Int) -> Float
{
    let address = bytes + layout.byteOffset + index * layout.byteStride + component * layout.scalar.byteSize
    if layout.scalar == .float16 { return floatFromHalf(address.loadUnaligned(as: UInt16.self)) }
    return address.loadUnaligned(as: Float.self)
}

private func streamFloat4(_ bytes: UnsafeRawPointer, layout: AttributeLayout, index: Int) -> simd_float4
{
    simd_float4(streamComponent(bytes, layout: layout, index: index, component: 0),
                streamComponent(bytes, layout: layout, index: index, component: 1),
                streamComponent(bytes, layout: layout, index: index, component: 2),
                streamComponent(bytes, layout: layout, index: index, component: 3))
}

/// IEEE half to float by bits: `Float16` isn't available on Intel Macs.
private func floatFromHalf(_ bits: UInt16) -> Float
{
    let sign = UInt32(bits & 0x8000) << 16
    let exponent = UInt32(bits >> 10) & 0x1F
    let mantissa = UInt32(bits & 0x03FF)

    switch exponent
    {
    case 0:
        // Zero or subnormal: mantissa × 2⁻²⁴.
        return Float(sign: sign == 0 ? .plus : .minus, exponent: -24, significand: Float(mantissa))
    case 0x1F:
        // Infinity or NaN.
        return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13))
    default:
        return Float(bitPattern: sign | ((exponent + 112) << 23) | (mantissa << 13))
    }
}

public enum GPUStreamError: Error, Equatable
{
    /// The attribute's scalar or component count isn't one the element type allows.
    case layoutDoesNotMatchElement(PortType)
    /// The count could exceed the elements the attribute holds, or is negative.
    case countExceedsAttribute
}

/// A stream with its element type erased, as `PortValue` boxes it.
public struct AnyGPUStream: Equatable
{
    public let elementType: PortType
    public let attribute: PublishedAttribute
    public let count: GPUStreamCount

    /// The same stream: the same element type, the same attribute, the same count.
    public static func == (lhs: AnyGPUStream, rhs: AnyGPUStream) -> Bool
    {
        lhs.elementType == rhs.elementType && lhs.attribute === rhs.attribute && lhs.count == rhs.count
    }
}

/// A typed array on the GPU: indexed data, not time samples. It wraps a published attribute,
/// which never changes once published, so another node can bind its buffer without a copy. A
/// producer publishes a new attribute rather than writing into one it already sent.
public struct GPUStream<Element: GPUStreamElement>: PortValueRepresentable
{
    public let attribute: PublishedAttribute
    public let count: GPUStreamCount

    public init(attribute: PublishedAttribute, count: GPUStreamCount) throws
    {
        guard Element.streamScalars.contains(attribute.layout.scalar),
              attribute.layout.components == Element.streamComponents
        else { throw GPUStreamError.layoutDoesNotMatchElement(Element.portType) }

        // A GPU count is a UInt32, so its capacity must be one too.
        guard count.capacity >= 0, count.capacity <= attribute.count, count.capacity <= Int(UInt32.max)
        else { throw GPUStreamError.countExceedsAttribute }

        self.attribute = attribute
        self.count = count
    }

    /// A stream of every element `attribute` holds.
    public init(attribute: PublishedAttribute) throws
    {
        try self.init(attribute: attribute, count: .known(attribute.count))
    }

    /// The same stream: the same attribute and the same count.
    public static func == (lhs: GPUStream<Element>, rhs: GPUStream<Element>) -> Bool
    {
        lhs.attribute === rhs.attribute && lhs.count == rhs.count
    }

    public static var defaultValue: GPUStream<Element>? { nil }
    public static var portType: PortType { .Stream(elementType: Element.portType) }
    public var portType: PortType { Self.portType }

    public func toPortValue() -> PortValue
    {
        .Stream(AnyGPUStream(elementType: Element.portType, attribute: attribute, count: count))
    }

    public static func fromPortValue(_ value: PortValue) -> GPUStream<Element>?
    {
        guard case let .Stream(stream) = value, stream.elementType == Element.portType else { return nil }
        return try? GPUStream(attribute: stream.attribute, count: stream.count)
    }

    public func canConvertTo(other: PortType) -> Bool
    {
        false
    }

    public func convertTo(other: PortType) -> (any PortValueRepresentable)?
    {
        nil
    }
}

/// Any `GPUStream`, so code that only knows a stream at run time can make and read one.
public protocol GPUStreamValue: PortValueRepresentable
{
    init(attribute: PublishedAttribute, count: GPUStreamCount) throws
    var anyStream: AnyGPUStream { get }
}

extension GPUStream: GPUStreamValue
{
    public var anyStream: AnyGPUStream
    {
        AnyGPUStream(elementType: Element.portType, attribute: attribute, count: count)
    }
}

/// A stream port of any element type, read and written without boxing its value.
protocol GPUStreamPort: AnyObject
{
    /// The stream the port holds, if any.
    var currentStream: AnyGPUStream? { get }
    /// Sends `attribute` as a stream with `count`; throws when its layout isn't the port's element type.
    /// The same stream as the port holds, the same attribute and count, isn't sent again: a published
    /// attribute never changes, so downstream has nothing new to do.
    func sendStream(attribute: PublishedAttribute, count: GPUStreamCount) throws
    /// Sends no stream, unless the port already holds none.
    func clearStream()
}

extension NodePort: GPUStreamPort where Value: GPUStreamValue
{
    var currentStream: AnyGPUStream? { value?.anyStream }

    func sendStream(attribute: PublishedAttribute, count: GPUStreamCount) throws
    {
        send(try Value(attribute: attribute, count: count))
    }

    func clearStream()
    {
        send(nil)
    }
}

import CoreGraphics

extension CGSize {
    public func isNearlyEqual(to point: CGSize, epsilon: CGFloat) -> Bool {
        let difference = self - point
        return abs(difference.width) < epsilon && abs(difference.height) < epsilon
    }
    
    public var length: CGFloat {
        return hypot(width, height)
    }
    
    public var squareLength: CGFloat {
        return width * width + height * height
    }
    
    public var unit: CGSize {
        return self * (1.0 / length)
    }
    
    public var phase: CGFloat {
        return atan2(height, width)
    }
    
    public func distance(from point: CGSize) -> CGFloat {
        return (self - point).length
    }
    
    public func squareDistance(from point: CGSize) -> CGFloat {
        return (self - point).squareLength
    }
    
    public func angle(from point: CGSize) -> CGFloat {
        return acos(cos(from: point))
    }
    
    public func cos(from point: CGSize) -> CGFloat {
        let squareLength1 = self.squareLength
        guard squareLength1 > 0.0 else { return 1.0 }
        let squareLength2 = point.squareLength
        guard squareLength2 > 0.0 else { return 1.0 }
        return Swift.min(Swift.max(self.dot(point) / sqrt(squareLength1 * squareLength2), -1.0), 1.0)
    }
    
    public func dot(_ other: CGSize) -> CGFloat {
        return self.width * other.width + self.height * other.height
    }
}

extension CGSize: @retroactive CustomStringConvertible {
    public var description: String {
        return "(\(width), \(height))"
    }
}

extension CGSize {
    public static prefix func + (value: CGSize) -> CGSize {
        return value
    }
    
    public static prefix func - (value: CGSize) -> CGSize {
        return CGSize(width: -value.width, height: -value.height)
    }
    
    public static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        return CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
    
    public static func - (lhs: CGSize, rhs: CGSize) -> CGSize {
        return CGSize(width: lhs.width - rhs.width, height: lhs.height - rhs.height)
    }
    
    public static func * (lhs: CGSize, rhs: CGSize) -> CGSize {
        return CGSize(width: lhs.width * rhs.width, height: lhs.height * rhs.height)
    }
    
    public static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        return CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
    
    public static func * (lhs: CGFloat, rhs: CGSize) -> CGSize {
        return CGSize(width: rhs.width * lhs, height: rhs.height * lhs)
    }
    
    public static func / (lhs: CGSize, rhs: CGSize) -> CGSize {
        return CGSize(width: lhs.width / rhs.width, height: lhs.height / rhs.height)
    }
    
    public static func / (lhs: CGSize, rhs: CGFloat) -> CGSize {
        return CGSize(width: lhs.width / rhs, height: lhs.height / rhs)
    }
    
    public static func += (lhs: inout CGSize, rhs: CGSize) {
        lhs = lhs + rhs
    }
    
    public static func -= (lhs: inout CGSize, rhs: CGSize) {
        lhs = lhs - rhs
    }
    
    public static func *= (lhs: inout CGSize, rhs: CGSize) {
        lhs = lhs * rhs
    }
    
    public static func *= (lhs: inout CGSize, rhs: CGFloat) {
        lhs = lhs * rhs
    }
    
    public static func /= (lhs: inout CGSize, rhs: CGSize) {
        lhs = lhs / rhs
    }
    
    public static func /= (lhs: inout CGSize, rhs: CGFloat) {
        lhs = lhs / rhs
    }
}

extension CGSize {
    public static func + (lhs: CGSize, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.width + rhs.x, y: lhs.height + rhs.y)
    }
    
    public static func - (lhs: CGSize, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.width - rhs.x, y: lhs.height - rhs.y)
    }
    
    public static func * (lhs: CGSize, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.width * rhs.x, y: lhs.height * rhs.y)
    }
    
    public static func / (lhs: CGSize, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.width / rhs.x, y: lhs.height / rhs.y)
    }
}

import CoreGraphics

extension CGVector {
    public func isNearlyEqual(to point: CGVector, epsilon: CGFloat) -> Bool {
        let difference = self - point
        return abs(difference.dx) < epsilon && abs(difference.dy) < epsilon
    }
    
    public var length: CGFloat {
        return hypot(dx, dy)
    }
    
    public var squareLength: CGFloat {
        return dx * dx + dy * dy
    }
    
    public var unit: CGVector {
        return self * (1.0 / length)
    }
    
    public var phase: CGFloat {
        return atan2(dy, dx)
    }
    
    public func distance(from point: CGVector) -> CGFloat {
        return (self - point).length
    }
    
    public func squareDistance(from point: CGVector) -> CGFloat {
        return (self - point).squareLength
    }
    
    public func angle(from point: CGVector) -> CGFloat {
        return acos(cos(from: point))
    }
    
    public func cos(from point: CGVector) -> CGFloat {
        let squareLength1 = self.squareLength
        guard squareLength1 > 0.0 else { return 1.0 }
        let squareLength2 = point.squareLength
        guard squareLength2 > 0.0 else { return 1.0 }
        return Swift.min(Swift.max(self.dot(point) / sqrt(squareLength1 * squareLength2), -1.0), 1.0)
    }
    
    public func dot(_ other: CGVector) -> CGFloat {
        return self.dx * other.dx + self.dy * other.dy
    }
}

extension CGVector: @retroactive CustomStringConvertible {
    public var description: String {
        return "(\(dx), \(dy))"
    }
}

extension CGVector {
    public static prefix func + (value: CGVector) -> CGVector {
        return value
    }
    
    public static prefix func - (value: CGVector) -> CGVector {
        return CGVector(dx: -value.dx, dy: -value.dy)
    }
    
    public static func + (lhs: CGVector, rhs: CGVector) -> CGVector {
        return CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }
    
    public static func - (lhs: CGVector, rhs: CGVector) -> CGVector {
        return CGVector(dx: lhs.dx - rhs.dx, dy: lhs.dy - rhs.dy)
    }
    
    public static func * (lhs: CGVector, rhs: CGVector) -> CGVector {
        return CGVector(dx: lhs.dx * rhs.dx, dy: lhs.dy * rhs.dy)
    }
    
    public static func * (lhs: CGVector, rhs: CGFloat) -> CGVector {
        return CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
    }
    
    public static func * (lhs: CGFloat, rhs: CGVector) -> CGVector {
        return CGVector(dx: rhs.dx * lhs, dy: rhs.dy * lhs)
    }
    
    public static func / (lhs: CGVector, rhs: CGVector) -> CGVector {
        return CGVector(dx: lhs.dx / rhs.dx, dy: lhs.dy / rhs.dy)
    }
    
    public static func / (lhs: CGVector, rhs: CGFloat) -> CGVector {
        return CGVector(dx: lhs.dx / rhs, dy: lhs.dy / rhs)
    }
    
    public static func * (lhs: CGVector, rhs: CGAffineTransform) -> CGVector {
        let point = CGPoint(x: lhs.dx, y: lhs.dy).applying(rhs)
        return CGVector(dx: point.x, dy: point.y)
    }
    
    public static func += (lhs: inout CGVector, rhs: CGVector) {
        lhs = lhs + rhs
    }
    
    public static func -= (lhs: inout CGVector, rhs: CGVector) {
        lhs = lhs - rhs
    }
    
    public static func *= (lhs: inout CGVector, rhs: CGVector) {
        lhs = lhs * rhs
    }
    
    public static func *= (lhs: inout CGVector, rhs: CGFloat) {
        lhs = lhs * rhs
    }
    
    public static func /= (lhs: inout CGVector, rhs: CGVector) {
        lhs = lhs / rhs
    }
    
    public static func /= (lhs: inout CGVector, rhs: CGFloat) {
        lhs = lhs / rhs
    }
    
    public static func *= (lhs: inout CGVector, rhs: CGAffineTransform) {
        lhs = lhs * rhs
    }
}

extension CGVector {
    public static func + (lhs: CGVector, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.dx + rhs.x, y: lhs.dy + rhs.y)
    }
    
    public static func - (lhs: CGVector, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.dx - rhs.x, y: lhs.dy - rhs.y)
    }
    
    public static func * (lhs: CGVector, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.dx * rhs.x, y: lhs.dy * rhs.y)
    }
    
    public static func / (lhs: CGVector, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.dx / rhs.x, y: lhs.dy / rhs.y)
    }
}

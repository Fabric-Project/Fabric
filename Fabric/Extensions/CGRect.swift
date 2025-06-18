import CoreGraphics

extension CGRect {
    public func isNearlyEqual(to rect: CGRect, epsilon: CGFloat) -> Bool {
        let difference1 = self.origin - rect.origin
        let difference2 = (self.origin + self.size) - (rect.origin + rect.size)
        return abs(difference1.x) < epsilon && abs(difference1.y) < epsilon
            && abs(difference2.x) < epsilon && abs(difference2.y) < epsilon
    }
    
    public var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
}

extension CGRect: @retroactive CustomStringConvertible {
    public var description: String {
        return "(\(origin.description), \(size.description))"
    }
}

extension CGRect {
    public static func * (lhs: CGRect, rhs: CGAffineTransform) -> CGRect {
        return lhs.applying(rhs)
    }
    
    public static func *= (lhs: inout CGRect, rhs: CGAffineTransform) {
        lhs = lhs * rhs
    }
}

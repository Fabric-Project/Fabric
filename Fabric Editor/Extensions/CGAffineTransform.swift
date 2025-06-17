import CoreGraphics

extension CGAffineTransform {
    public func isNearlyEqual(to transform: CGAffineTransform, epsilon: CGFloat) -> Bool {
        return abs(a - transform.a) < epsilon && abs(b - transform.b) < epsilon && abs(c - transform.c) < epsilon && abs(d - transform.d) < epsilon && abs(tx - transform.tx) < epsilon && abs(ty - transform.ty) < epsilon
    }
}

extension CGAffineTransform: @retroactive CustomStringConvertible {
    public var description: String {
        return "(\(a), \(b), \(c), \(d), \(tx), \(ty))"
    }
}

extension CGAffineTransform {
    public static func * (lhs: CGAffineTransform, rhs: CGAffineTransform) -> CGAffineTransform {
        return lhs.concatenating(rhs)
    }
    
    public static func *= (lhs: inout CGAffineTransform, rhs: CGAffineTransform) {
        lhs = lhs * rhs
    }
}

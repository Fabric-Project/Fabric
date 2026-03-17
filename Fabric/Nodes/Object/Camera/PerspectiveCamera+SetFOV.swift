//
//  PerspectiveCamera+SetFOV.swift
//  Fabric
//

import Satin

extension PerspectiveCamera {

    /// Set the field of view for a given sizing dimension.
    ///
    /// - Parameters:
    ///   - fovDegrees: Field of view in degrees, measured along `sizingDimension`.
    ///   - sizingDimension: `"Width"` or `"Height"`. When `"Width"`, the
    ///     horizontal FOV is held constant and vertical FOV is derived from
    ///     the current ``aspect`` ratio — matching the Quartz Composer
    ///     convention where width = 2 world units.
    public func setFOV(_ fovDegrees: Float, sizing sizingDimension: String) {
        if sizingDimension == "Width" {
            let hfovRad = degToRad(fovDegrees)
            let vfovRad = 2.0 * atan(tan(hfovRad / 2.0) / aspect)
            self.fov = radToDeg(vfovRad)
        } else {
            self.fov = fovDegrees
        }
    }
}

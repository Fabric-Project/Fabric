import MPSMediaPipe
import Satin
import simd

/// The conversions from MediaPipe landmarks to Fabric scene space behind the
/// Face, Hand and Pose Landmark nodes' 3D Landmarks outputs.
enum MediaPipeLandmarkSceneSpace
{
    /// One image landmark -- x/y normalized in the full image (bottom-left
    /// origin), z a relative depth on the same scale as x -- placed in the
    /// scene. This is 2.5D: right from the camera's view, not a true shape.
    ///
    /// x/y start from the flat image remap (-1...1 horizontally,
    /// -aspect...aspect vertically), then get scaled by `depthScale` before z
    /// is added -- without that, a point pulled off the z=0 plane no longer
    /// lines up with its own 2D position once viewed through a real
    /// perspective camera (the default one, at
    /// `PerspectiveCameraNode.defaultPosition.z`): a point closer to the
    /// camera needs *less* world x/y to land at the same screen position a
    /// flat point would, one farther away needs more -- by exactly
    /// `(cameraDistance - z) / cameraDistance`, similar triangles along the
    /// camera's own viewing axis.
    ///
    /// z itself is negated relative to MediaPipe's own landmark.z: raw z gets
    /// *more negative* the closer a point is to the camera, the opposite of
    /// Fabric's own camera, which sits at positive z looking toward the
    /// origin, so *larger* z is closer. Scale factor 2 matches x's own
    /// [0,1]->[-1,1] remap, keeping z's magnitude on the same scale as x,
    /// independent of each model's own per-model depth-normalization constant
    /// (see each projection's `normalizeZ`).
    ///
    /// Depth is relative to the model's own reference point (head center,
    /// wrist, or mid-hips), which therefore sits on the image plane; the
    /// alignment holds for the default perspective camera.
    static func scenePoint(from landmark: simd_float3, aspect: Float) -> simd_float3
    {
        let flatX = remap(landmark.x, 0.0, 1.0, -1.0, 1.0)
        let flatY = remap(landmark.y, 0.0, 1.0, -aspect, aspect)
        let depth = -landmark.z * 2
        let cameraDistance = PerspectiveCameraNode.defaultPosition.z
        let depthScale = (cameraDistance - depth) / cameraDistance
        return simd_float3(flatX * depthScale, flatY * depthScale, depth)
    }

    /// How far from the camera, in meters, a subject sits when it lands
    /// exactly on the image plane. Fixes the scene's size for one meter, so
    /// the world shape keeps its metric size and its depth comes from how
    /// large it appears: nearer than this is in front of the image plane
    /// (positive z), farther is behind it.
    static let imagePlaneDistanceMeters: Float = 1

    /// The scene's size for one meter, through the default perspective camera.
    static var sceneUnitsPerMeter: Float { PerspectiveCameraNode.defaultPosition.z / Self.imagePlaneDistanceMeters }

    /// MediaPipe's own world-landmark One Euro tuning (pose's
    /// landmarks-smoothing graph); hand has no reference and reuses it.
    static let worldLandmarksSmoothingMinCutoff: Float = 0.1
    static let worldLandmarksSmoothingBeta: Float = 40

    /// World landmarks -- meters, MediaPipe axes -- temporally smoothed.
    /// `filter` must be this stream's own, built with the tuning above. The
    /// filter works in pixels scaled by subject size; passing 1 for all three
    /// makes it filter the metric values as they are, as MediaPipe does.
    static func smoothedWorldLandmarks(_ worldLandmarks: [simd_float3], filter: MediaPipeLandmarksSmoothingFilter, timestampNanoseconds: Int64) -> [simd_float3]
    {
        filter.smooth(points: worldLandmarks, timestampNanoseconds: timestampNanoseconds, objectScalePixels: 1, imageWidthPixels: 1, imageHeightPixels: 1)
    }

    /// The face's placement by the same rule as hand and pose: shape from the
    /// model, position from the default perspective camera.
    ///
    /// The canonical face model (centimeters) is fit to the 2.5D scene points
    /// for its rotation and for the face's own shape, expression included.
    /// That shape then keeps its metric size, and only its position --
    /// depth included -- is solved so the camera sees it on top of the image
    /// landmarks: a face that looks larger sits nearer.
    ///
    /// `scenePoints` are the placed landmarks; `poseTransform` maps
    /// `metricLandmarks` (canonical-model centimeters) onto them. nil when
    /// the fit or the placement fails.
    static func facePlacement(imageLandmarks: [simd_float3], aspect: Float) -> (scenePoints: ContiguousArray<simd_float3>, metricLandmarks: [simd_float3], poseTransform: simd_float4x4)?
    {
        let relativeDepthPoints = imageLandmarks.map { Self.scenePoint(from: $0, aspect: aspect) }
        guard let fit = FaceGeometrySolver.fitCanonicalModel(to: relativeDepthPoints) else { return nil }

        let fittedScale = simd_length(fit.poseTransform.columns.0)
        guard fittedScale > .ulpOfOne else { return nil }
        let sceneUnitsPerCentimeter = Self.sceneUnitsPerMeter / 100
        let metricScale = sceneUnitsPerCentimeter / fittedScale
        let rotationAtMetricSize = simd_float3x3(
            simd_make_float3(fit.poseTransform.columns.0) * metricScale,
            simd_make_float3(fit.poseTransform.columns.1) * metricScale,
            simd_make_float3(fit.poseTransform.columns.2) * metricScale
        )

        let shape = fit.metricLandmarks.map { rotationAtMetricSize * $0 }
        let imagePlanePoints = imageLandmarks.map {
            simd_float2(remap($0.x, 0.0, 1.0, -1.0, 1.0), remap($0.y, 0.0, 1.0, -aspect, aspect))
        }
        guard let shift = MediaPipeWorldLandmarkAlignment.translation(
            placing: shape,
            onto: imagePlanePoints,
            cameraDistance: PerspectiveCameraNode.defaultPosition.z
        ) else { return nil }

        var poseTransform = simd_float4x4(1)
        poseTransform.columns.0 = simd_float4(rotationAtMetricSize.columns.0, 0)
        poseTransform.columns.1 = simd_float4(rotationAtMetricSize.columns.1, 0)
        poseTransform.columns.2 = simd_float4(rotationAtMetricSize.columns.2, 0)
        poseTransform.columns.3 = simd_float4(shift, 1)
        return (ContiguousArray(shape.map { $0 + shift }), fit.metricLandmarks, poseTransform)
    }

    /// The 3D Landmarks output for a model that has world landmarks (hand,
    /// pose): its metric, view-independent world shape, placed so the default
    /// perspective camera sees it on top of the image (see
    /// `MediaPipeWorldLandmarkAlignment`). `imageLandmarks` are normalized
    /// full-image, bottom-left origin; `worldLandmarks` are in MediaPipe's own
    /// axes, index-aligned with them. Falls back to each image landmark's own
    /// `scenePoint` when the world shape is missing or cannot be placed.
    static func scenePoints(imageLandmarks: [simd_float3], worldLandmarks: [simd_float3], weights: [Float]?, aspect: Float) -> ContiguousArray<simd_float3>
    {
        let imagePlanePoints = imageLandmarks.map {
            simd_float2(remap($0.x, 0.0, 1.0, -1.0, 1.0), remap($0.y, 0.0, 1.0, -aspect, aspect))
        }
        let aligned = MediaPipeWorldLandmarkAlignment.align(
            worldLandmarks: worldLandmarks,
            imagePlanePoints: imagePlanePoints,
            weights: weights,
            cameraDistance: PerspectiveCameraNode.defaultPosition.z,
            sceneUnitsPerMeter: Self.sceneUnitsPerMeter
        )
        let fallback = imageLandmarks.map { Self.scenePoint(from: $0, aspect: aspect) }
        Self.printTemporaryDiagnostics(worldLandmarks: worldLandmarks, aligned: aligned, fallback: fallback)
        if let aligned
        {
            return ContiguousArray(aligned)
        }
        return ContiguousArray(fallback)
    }

    // TEMPORARY: remove once the world-landmark depth sign and scale are confirmed.
    private static var temporaryDiagnosticsFrame = 0

    /// Every 60th call: whether the world fit ran, its depth and width extent,
    /// the 2.5D points' depth extent, and whether the two depths agree in
    /// sign (correlation > 0) or are opposite (< 0).
    private static func printTemporaryDiagnostics(worldLandmarks: [simd_float3], aligned: [simd_float3]?, fallback: [simd_float3])
    {
        Self.temporaryDiagnosticsFrame += 1
        guard Self.temporaryDiagnosticsFrame % 60 == 0 else { return }
        func extent(_ values: [Float]) -> Float { (values.max() ?? 0) - (values.min() ?? 0) }
        let fallbackDepth = fallback.map(\.z)
        guard let aligned else
        {
            print("MediaPipe 3D landmarks (\(fallback.count) points): FALLBACK to 2.5D (world count \(worldLandmarks.count)); 2.5D depth extent \(extent(fallbackDepth))")
            return
        }
        let alignedDepth = aligned.map(\.z)
        let meanAligned = alignedDepth.reduce(0, +) / Float(alignedDepth.count)
        let meanFallback = fallbackDepth.reduce(0, +) / Float(fallbackDepth.count)
        var covariance: Float = 0
        var alignedVariance: Float = 0
        var fallbackVariance: Float = 0
        for index in aligned.indices
        {
            let a = alignedDepth[index] - meanAligned
            let b = fallbackDepth[index] - meanFallback
            covariance += a * b
            alignedVariance += a * a
            fallbackVariance += b * b
        }
        let correlation = covariance / max((alignedVariance * fallbackVariance).squareRoot(), .ulpOfOne)
        // Hand only (21 points): wrist is index 0, index fingertip is index 8.
        let fingertip = aligned.count == 21 ? "; wrist z \(aligned[0].z), index tip z \(aligned[8].z)" : ""
        print("MediaPipe 3D landmarks (\(aligned.count) points): WORLD fit; mean z \(meanAligned), width extent \(extent(aligned.map(\.x))), depth extent \(extent(alignedDepth)); depth correlation world vs 2.5D \(correlation)\(fingertip)")
    }
}

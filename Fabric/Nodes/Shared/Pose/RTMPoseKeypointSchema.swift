//
//  RTMPoseKeypointSchema.swift
//  Fabric
//

import Foundation

/// Static keypoint ordering/region tables for the RTMPose model family.
/// These indices describe how a flat, ordered keypoint array (the shape
/// SimCCDecoder.decodeAll produces) maps onto named joints/regions.
///
/// The COCO-17 and Hand5 orderings below are the well-established public
/// dataset conventions. The Face6 (106-point) and COCO-Wholebody-133 region
/// ranges are transcribed from mmpose's dataset meta files as of plan
/// authoring — verify both against the live
/// `configs/_base_/datasets/coco_wholebody.py` / `face6.py` in the
/// open-mmlab/mmpose repo before shipping, since a wrong range silently
/// mis-buckets keypoints into the wrong named port with no compiler error.
enum RTMPoseKeypointSchema
{
    /// COCO-17 body keypoint order, as produced by RTMPose body models.
    static let coco17BodyNames: [String] = [
        "nose", "leftEye", "rightEye", "leftEar", "rightEar",
        "leftShoulder", "rightShoulder", "leftElbow", "rightElbow",
        "leftWrist", "rightWrist", "leftHip", "rightHip",
        "leftKnee", "rightKnee", "leftAnkle", "rightAnkle",
    ]

    static let coco17HeadIndices = [0, 1, 2, 3, 4]
    static let coco17TorsoIndices = [5, 6, 11, 12]
    static let coco17LeftArmIndices = [5, 7, 9]
    static let coco17RightArmIndices = [6, 8, 10]
    static let coco17LeftLegIndices = [11, 13, 15]
    static let coco17RightLegIndices = [12, 14, 16]

    /// Region ranges within the 133-point COCO-Wholebody ordering RTMW
    /// produces: body (COCO-17), feet, face, then left/right hand (each in
    /// Hand5's own 21-point order).
    static let cocoWholeBody133BodyRange = 0..<17
    static let cocoWholeBody133FeetRange = 17..<23
    static let cocoWholeBody133FaceRange = 23..<91
    static let cocoWholeBody133LeftHandRange = 91..<112
    static let cocoWholeBody133RightHandRange = 112..<133

    /// Hand5's 21-keypoint order — matches Vision's legacy
    /// VNHumanHandPoseObservation.JointName ordering 1:1 (wrist, then each
    /// finger's 4 joints from base to tip), which is why HandPoseAnalysisNode
    /// can keep its existing named ports unchanged.
    static let hand21Names: [String] = [
        "wrist",
        "thumbCMC", "thumbMP", "thumbIP", "thumbTip",
        "indexMCP", "indexPIP", "indexDIP", "indexTip",
        "middleMCP", "middlePIP", "middleDIP", "middleTip",
        "ringMCP", "ringPIP", "ringDIP", "ringTip",
        "littleMCP", "littlePIP", "littleDIP", "littleTip",
    ]

    static let hand21WristIndex = 0
    static let hand21ThumbIndices = [1, 2, 3, 4]
    static let hand21IndexIndices = [5, 6, 7, 8]
    static let hand21MiddleIndices = [9, 10, 11, 12]
    static let hand21RingIndices = [13, 14, 15, 16]
    static let hand21LittleIndices = [17, 18, 19, 20]

    /// Face6's 106-point region layout. PROVISIONAL — transcribed from the
    /// commonly published 106-point face landmark convention mmpose's Face6
    /// recipe is based on; confirm exact boundaries against
    /// `configs/_base_/datasets/face6.py` before relying on these ranges.
    /// Face6 has no dedicated pupil keypoint (pupil ports fall back to eye
    /// centroid) and no explicit "median line" group (synthesized from
    /// symmetric nose/lip pairs) — see FacePoseAnalysisNode.
    static let face106ContourRange = 0..<33
    static let face106LeftEyebrowRange = 33..<42
    static let face106RightEyebrowRange = 42..<51
    static let face106NoseRange = 51..<60
    static let face106NoseCrestRange = 51..<55
    static let face106LeftEyeRange = 60..<68
    static let face106RightEyeRange = 68..<76
    static let face106OuterLipsRange = 76..<96
    static let face106InnerLipsRange = 96..<106
}

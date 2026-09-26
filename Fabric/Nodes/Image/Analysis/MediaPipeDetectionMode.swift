//
//  MediaPipeDetectionMode.swift
//  Fabric
//

/// Single/Multi detection mode shared by the MediaPipe Face/Hand/Pose
/// Detection nodes (and mirrored by their matching Landmark nodes' own
/// iterator-awareness -- see each node's header).
///
/// Single mode tracks exactly one subject and exposes the Previous Region/
/// Previous Rotation tracking fast-path plus singular Region/Rotation/
/// Keypoints outputs -- mediapipe's own pose_landmark_cpu.pbtxt is
/// genuinely single-instance-only this same way (confirmed against its
/// real source: prev_pose_rect_from_landmarks is a singular NormalizedRect,
/// no association calculator exists).
///
/// Multi mode detects up to Max Detections subjects every frame and
/// exposes plural Regions/Rotations instead, with no Previous Region input at
/// all: mediapipe's real multi-instance graphs (hand_landmark_tracking_cpu
/// .pbtxt, face_landmark_front_cpu.pbtxt) gate re-detection on a
/// std::vector<NormalizedRect> previous-rects stream plus an
/// AssociationNormRectCalculator IoU-matching step we haven't ported, so a
/// single scalar Previous Region has no sound multi-instance equivalent here
/// yet -- Multi mode always re-detects every frame instead of pretending to
/// offer a tracking optimization it can't actually provide.
public enum MediaPipeDetectionMode: String, NodeStrategyOption, CaseIterable
{
    case single = "Single"
    case multi = "Multi"
}

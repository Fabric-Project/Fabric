//
//  MediaPipeDetectionMode.swift
//  Fabric
//

import SwiftUI

/// Single/Multi detection mode shared by the MediaPipe Face/Hand/Pose
/// Detection nodes (and mirrored by their matching Landmark nodes' own
/// iterator-awareness -- see each node's header).
///
/// Single mode tracks exactly one subject and exposes the Tracked Region/
/// Tracked Rotation tracking fast-path plus singular Region/Rotation/
/// Keypoints outputs -- mediapipe's own pose_landmark_cpu.pbtxt is
/// genuinely single-instance-only this same way (confirmed against its
/// real source: prev_pose_rect_from_landmarks is a singular NormalizedRect,
/// no association calculator exists).
///
/// Multi mode detects up to Max Detections subjects every frame and
/// exposes plural Regions/Rotations instead, with no Tracked Region input at
/// all: mediapipe's real multi-instance graphs (hand_landmark_tracking_cpu
/// .pbtxt, face_landmark_front_cpu.pbtxt) gate re-detection on a
/// std::vector<NormalizedRect> previous-rects stream plus an
/// AssociationNormRectCalculator IoU-matching step we haven't ported, so a
/// single scalar Tracked Region has no sound multi-instance equivalent here
/// yet -- Multi mode always re-detects every frame instead of pretending to
/// offer a tracking optimization it can't actually provide.
public enum MediaPipeDetectionMode: String, NodeStrategyOption, CaseIterable
{
    case single = "Single"
    case multi = "Multi"
}

/// Settings for the MediaPipe detection nodes that have no other model
/// choice: the Single/Multi mode and the precision.
struct MediaPipeDetectionSettingsView: View
{
    @Bindable var strategyModel: StrategyNode.SettingsModel
    let precision: Binding<String>
    let computeUnits: Binding<String>
    let inferenceTiming: Binding<String>

    var body: some View
    {
        Form
        {
            StrategyPickerView(model: strategyModel)
            MPSModelConfigurationPicker(option: MPSModelConfigurationOption(
                label: "Precision",
                choices: MPSModelPrecision.labels,
                selection: self.precision
            ))
            MPSModelConfigurationPicker(option: MPSModelConfigurationOption(
                label: "Compute",
                choices: MPSModelComputeUnits.labels,
                selection: self.computeUnits
            ))
            MPSModelConfigurationPicker(option: MPSModelConfigurationOption(
                label: "Inference",
                choices: MPSInferenceTiming.labels,
                selection: self.inferenceTiming
            ))
        }
        .padding()
    }
}

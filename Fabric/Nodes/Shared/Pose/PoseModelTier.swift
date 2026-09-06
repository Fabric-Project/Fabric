//
//  PoseModelTier.swift
//  Fabric
//

import Foundation

/// Speed/accuracy tier for a bundled RTMPose model. Not every pose family
/// publishes every tier upstream (Hand5 and RTMW only ship "Medium") — nodes
/// that only offer one tier still use this type for API consistency across
/// the pose node family.
enum PoseModelTier: String, CaseIterable, Codable
{
    case tiny = "Tiny"
    case small = "Small"
    case medium = "Medium"
}

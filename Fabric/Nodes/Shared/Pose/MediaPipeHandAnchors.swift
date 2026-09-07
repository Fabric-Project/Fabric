//
//  MediaPipeHandAnchors.swift
//  Fabric
//

import Foundation

/// SSD anchor grid for MediaPipe's BlazePalm hand detector — ported from
/// mediapipe/calculators/tflite/ssd_anchors_calculator.cc with the hand-
/// detector graph's config (num_layers=4, strides [8,16,16,16],
/// fixed_anchor_size, interpolated_anchors), confirmed against
/// fasthands.pipeline.generate_anchors() (the same repo whose bundled
/// .mlpackage files Fabric uses here) rather than re-derived from the
/// calculator source directly.
enum MediaPipeHandAnchors
{
    static let detectSize = 192
    static let anchorCount = 2016

    /// (cx, cy, w, h), all normalized [0,1] relative to detectSize, in the
    /// same top-left-origin space the detector's raw box regression uses.
    static func generate() -> [(cx: Float, cy: Float, w: Float, h: Float)]
    {
        let numLayers = 4
        let strides = [8, 16, 16, 16]

        var anchors: [(cx: Float, cy: Float, w: Float, h: Float)] = []
        anchors.reserveCapacity(anchorCount)

        var layerIndex = 0
        while layerIndex < numLayers
        {
            var anchorsPerCell = 0
            var lastLayerIndex = layerIndex
            while lastLayerIndex < numLayers, strides[lastLayerIndex] == strides[layerIndex]
            {
                anchorsPerCell += 2 // aspect_ratio 1.0 anchor + interpolated anchor (same center)
                lastLayerIndex += 1
            }

            let featureMapSize = Int((Float(detectSize) / Float(strides[layerIndex])).rounded(.up))
            for y in 0..<featureMapSize
            {
                for x in 0..<featureMapSize
                {
                    for _ in 0..<anchorsPerCell
                    {
                        anchors.append((
                            cx: (Float(x) + 0.5) / Float(featureMapSize),
                            cy: (Float(y) + 0.5) / Float(featureMapSize),
                            w: 1.0, h: 1.0 // fixed_anchor_size
                        ))
                    }
                }
            }

            layerIndex = lastLayerIndex
        }

        return anchors
    }
}

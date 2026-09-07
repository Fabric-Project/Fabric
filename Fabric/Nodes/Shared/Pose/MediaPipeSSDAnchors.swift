//
//  MediaPipeSSDAnchors.swift
//  Fabric
//

import Foundation

/// SSD anchor grid shared by MediaPipe's "Blaze" family of detectors —
/// ported from mediapipe/calculators/tflite/ssd_anchors_calculator.cc.
/// BlazePalm (hand) and BlazeFace both use this exact algorithm with
/// `num_layers=4, strides=[8,16,16,16], fixed_anchor_size=true,
/// interpolated_scale_aspect_ratio=1.0` — confirmed for BlazePalm against
/// fasthands.pipeline.generate_anchors() (a validated third-party port) and
/// for BlazeFace directly against mediapipe/modules/face_detection/
/// face_detection_short_range.pbtxt's FaceDetectionOptions (num_layers=4,
/// strides=[8,16,16,16]) plus a hand-computed anchor-count check: this
/// formula with detectSize=128 produces exactly 512+384=896 anchors,
/// matching that config's declared num_boxes=896 exactly.
enum MediaPipeSSDAnchors
{
    /// (cx, cy, w, h), all normalized [0,1] relative to detectSize, in the
    /// same top-left-origin space the detector's raw box regression uses.
    /// `strides` defaults to the value both BlazePalm and BlazeFace use;
    /// re-check against the specific detector's own config before reusing
    /// this for a third model.
    static func generate(detectSize: Int, strides: [Int] = [8, 16, 16, 16]) -> [(cx: Float, cy: Float, w: Float, h: Float)]
    {
        let numLayers = strides.count
        var anchors: [(cx: Float, cy: Float, w: Float, h: Float)] = []

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

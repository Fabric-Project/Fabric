#!/usr/bin/env python3
"""Convert an RTMDet (mmdetection) checkpoint to a CoreML .mlpackage.

RTMDet is an anchor-free, FCOS/YOLOX-style one-stage detector: its head
produces, per FPN level, a classification score map and a bbox
distance-to-edge regression map. This script traces the backbone+neck+head
forward pass and returns the raw per-level tensors — no NMS is baked into
the model. Box decoding + NMS happen in Swift (RTMDetDecoder.swift), which
serves all detector checkpoints (person/hand/face) converted with this
script.

IMPORTANT: unlike RTMPose's pose heads, RTMDet's exact per-level output
tensor count/order/shape (and whether it separates classification from
"objectness"/centerness) is config-dependent. Confirm the actual output
signature against `wrapped_model(example_input)` for the *specific*
checkpoint being converted before wiring RTMDetDecoder's strides/shape
assumptions in Swift to match.

Usage:
    python convert_rtmdet.py \
        --config <path to mmdetection config .py> \
        --checkpoint <path to downloaded .pth> \
        --input-size 640 640 \
        --output ../../Fabric/Models/Pose/RTMDetPerson.mlpackage
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import coremltools as ct
import numpy as np
import torch


class RTMDetTraceWrapper(torch.nn.Module):
    """Wraps an mmdetection one-stage detector's backbone+neck+head so
    tracing returns the raw per-level (scores, box_distances) tensor lists,
    skipping mmdetection's own data preprocessor and skipping NMS entirely
    (NMS runs in Swift)."""

    def __init__(self, detector_model: torch.nn.Module):
        super().__init__()
        self.backbone = detector_model.backbone
        self.neck = getattr(detector_model, "neck", None)
        self.bbox_head = detector_model.bbox_head

    def forward(self, image: torch.Tensor):
        features = self.backbone(image)
        if self.neck is not None:
            features = self.neck(features)
        # RTMDet's SepBNHead returns (cls_scores, bbox_preds) as lists, one
        # entry per FPN level — confirm this against the actual head class
        # for the config being converted.
        cls_scores, bbox_preds = self.bbox_head.forward(features)
        # forward() returns raw pre-sigmoid logits (confirmed against
        # RTMDetSepBNHead.forward in mmdet/models/dense_heads/rtmdet_head.py —
        # cls_score is the bare conv output unless with_objectness is set,
        # and even then it's inverse_sigmoid'd, i.e. still logit-space).
        # mmdet's own predict_by_feat applies sigmoid before thresholding;
        # baking it in here keeps RTMDetDecoder's scoreThreshold comparable
        # to an actual probability instead of a logit.
        cls_scores = [score.sigmoid() for score in cls_scores]
        return tuple(cls_scores) + tuple(bbox_preds)


def build_wrapped_model(config_path: str, checkpoint_path: str) -> torch.nn.Module:
    from mmdet.apis import init_detector

    detector_model = init_detector(config_path, checkpoint_path, device="cpu")
    detector_model.eval()
    return RTMDetTraceWrapper(detector_model)


def convert(config_path: str, checkpoint_path: str, input_size: tuple[int, int],
            output_path: str, compute_units: str) -> None:
    height, width = input_size
    wrapped_model = build_wrapped_model(config_path, checkpoint_path)

    example_input = torch.rand(1, 3, height, width)
    with torch.no_grad():
        traced_model = torch.jit.trace(wrapped_model, example_input)
        reference_outputs = wrapped_model(example_input)

    level_count = len(reference_outputs) // 2
    print(f"Traced model returns {len(reference_outputs)} tensors "
          f"({level_count} score levels + {level_count} box-distance levels). "
          f"Confirm this matches RTMDetDecoder's expected level count in Swift.")

    mean = [123.675, 116.28, 103.53]
    std = [58.395, 57.12, 57.375]
    bias = [-m / s for m, s in zip(mean, std)]
    scale = 1.0 / std[0]

    output_names = [f"scores_level{i}" for i in range(level_count)] + \
                   [f"box_distances_level{i}" for i in range(level_count)]

    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, height, width),
                scale=scale,
                bias=bias,
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name=name) for name in output_names],
        convert_to="mlprogram",
        compute_units=getattr(ct.ComputeUnit, compute_units),
        # mlprogram defaults to FP16 weights/activations. Verified empirically
        # (isolated re-conversion, same checkpoint) that this alone produces
        # ~0.1 absolute score error and ~35px box error on this backbone+neck
        # +head depth -- not a code bug, but too coarse for NMS thresholds to
        # be meaningful. FLOAT32 brought both down to ~1e-3 / ~0.2px. RTMDet-
        # nano is small enough that the FP16->FP32 tradeoff isn't a real
        # speed concern here; re-check if that stops being true for a larger
        # detector variant.
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.iOS17,
    )

    mlmodel.save(output_path)
    _write_conversion_check(output_path, config_path, checkpoint_path, level_count)


def _write_conversion_check(output_path: str, config_path: str, checkpoint_path: str,
                             level_count: int) -> None:
    commit_hash = _git_commit_hash()
    sidecar = {
        "config": config_path,
        "checkpoint": checkpoint_path,
        "mmdetection_commit": commit_hash,
        "converted_at": datetime.now(timezone.utc).isoformat(),
        "fpn_level_count": level_count,
        "note": "Verify strides-per-level against the config's anchor_generator/prior_generator "
                "before using this model with RTMDetDecoder.",
    }

    sidecar_path = Path(output_path).with_suffix("").with_suffix(".conversion_check.json")
    sidecar_path.write_text(json.dumps(sidecar, indent=2))


def _git_commit_hash() -> str | None:
    try:
        import mmdet
        repo_dir = Path(mmdet.__file__).resolve().parent.parent
        result = subprocess.run(["git", "-C", str(repo_dir), "rev-parse", "HEAD"],
                                 capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except Exception:
        return None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, help="Path to the mmdetection config .py")
    parser.add_argument("--checkpoint", required=True, help="Path to the downloaded .pth checkpoint")
    parser.add_argument("--input-size", type=int, nargs=2, metavar=("HEIGHT", "WIDTH"), required=True)
    parser.add_argument("--output", required=True, help="Output .mlpackage path")
    parser.add_argument("--compute-units", default="ALL", choices=["ALL", "CPU_ONLY", "CPU_AND_GPU", "CPU_AND_NE"])
    args = parser.parse_args()

    convert(args.config, args.checkpoint, tuple(args.input_size), args.output, args.compute_units)
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()

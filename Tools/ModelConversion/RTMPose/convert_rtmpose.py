#!/usr/bin/env python3
"""Convert an RTMPose (SimCC-head) mmpose checkpoint to a CoreML .mlpackage.

RTMPose's body/hand/face/wholebody models all share the same shape: a
CSPNeXt-style backbone feeding two 1D "SimCC" classification heads
(simcc_x, simcc_y). This script traces just the backbone+head forward pass
(bypassing mmpose's own PoseDataPreprocessor, since resize/normalize is
baked into the CoreML model's ImageType instead) and converts it to an
mlprogram with compute_units=ALL so CoreML can place it on ANE.

The SimCC heads are left as raw MLMultiArray outputs. Decoding (argmax +
local refinement) happens in Swift (SimCCDecoder.swift), not here, so this
one script serves every RTMPose variant.

Usage:
    python convert_rtmpose.py \
        --config <path to mmpose config .py> \
        --checkpoint <path to downloaded .pth> \
        --input-size 256 192 \
        --output ../../Fabric/Models/Pose/RTMPoseBodyTiny.mlpackage \
        --compute-units ALL

Re-verify --config/--checkpoint paths against the live open-mmlab/mmpose
repo before running — RTMPose's model zoo filenames carry version suffixes
that drift over time.
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


class RTMPoseTraceWrapper(torch.nn.Module):
    """Wraps an mmpose top-down pose estimator's backbone+head so tracing
    returns only the raw (simcc_x, simcc_y) tensors, skipping mmpose's own
    data preprocessor (normalization/resize happens in the converted
    CoreML model's ImageType instead)."""

    def __init__(self, pose_model: torch.nn.Module):
        super().__init__()
        self.backbone = pose_model.backbone
        self.head = pose_model.head
        self.neck = getattr(pose_model, "neck", None)

    def forward(self, image: torch.Tensor):
        features = self.backbone(image)
        if self.neck is not None:
            features = self.neck(features)
        simcc_x, simcc_y = self.head.forward(features)
        return simcc_x, simcc_y


def build_wrapped_model(config_path: str, checkpoint_path: str) -> torch.nn.Module:
    # Imported lazily so `--help` works without mmpose installed.
    from mmpose.apis import init_model

    pose_model = init_model(config_path, checkpoint_path, device="cpu")
    pose_model.eval()
    return RTMPoseTraceWrapper(pose_model)


def convert(config_path: str, checkpoint_path: str, input_size: tuple[int, int],
            output_path: str, compute_units: str, tensor_input: bool) -> None:
    height, width = input_size
    wrapped_model = build_wrapped_model(config_path, checkpoint_path)

    example_input = torch.rand(1, 3, height, width)
    with torch.no_grad():
        traced_model = torch.jit.trace(wrapped_model, example_input)
        reference_simcc_x, reference_simcc_y = wrapped_model(example_input)

    if tensor_input:
        # Raw float16 tensor input instead of ImageType — for the
        # MLMultiArray(pixelBuffer:) IOSurface zero-copy path. No baked-in
        # normalization here: the caller (Swift side) must apply ImageNet
        # mean/std itself before feeding this model, since ImageType's
        # free preprocessing goes away with it.
        model_input = ct.TensorType(name="image", shape=(1, 3, height, width), dtype=np.float16)
    else:
        # ImageNet mean/std baked into the CoreML input so no preprocessing
        # is needed in Swift — the model accepts a plain image crop directly.
        mean = [123.675, 116.28, 103.53]
        std = [58.395, 57.12, 57.375]
        bias = [-m / s for m, s in zip(mean, std)]
        scale = 1.0 / std[0]  # coremltools ImageType supports one scalar scale; std is near-uniform across channels for ImageNet stats
        model_input = ct.ImageType(
            name="image",
            shape=(1, 3, height, width),
            scale=scale,
            bias=bias,
            color_layout=ct.colorlayout.RGB,
        )

    mlmodel = ct.convert(
        traced_model,
        inputs=[model_input],
        outputs=[
            ct.TensorType(name="simcc_x"),
            ct.TensorType(name="simcc_y"),
        ],
        convert_to="mlprogram",
        compute_units=getattr(ct.ComputeUnit, compute_units),
        minimum_deployment_target=ct.target.iOS18,
    )

    mlmodel.save(output_path)

    if tensor_input:
        print(f"Wrote {output_path} with a raw TensorType input — "
              f"no automatic sanity-check predict (that path expects a PIL image). "
              f"Verify correctness by feeding the same normalized tensor Swift-side "
              f"produces and comparing against reference_simcc_x/y by hand if needed.")
    else:
        _write_conversion_check(output_path, config_path, checkpoint_path,
                                 reference_simcc_x, reference_simcc_y,
                                 example_input, mlmodel)


def _write_conversion_check(output_path: str, config_path: str, checkpoint_path: str,
                             reference_simcc_x: torch.Tensor, reference_simcc_y: torch.Tensor,
                             example_input: torch.Tensor, mlmodel) -> None:
    from PIL import Image

    # coremltools' ImageType input expects a PIL image for prediction; build
    # one from the same random tensor used to trace, undoing the [0,1] scale
    # back to [0,255] uint8 so the sanity check exercises the *baked-in*
    # normalization inside the converted model, not a second normalization.
    array = (example_input[0].permute(1, 2, 0).numpy() * 255).astype(np.uint8)
    pil_image = Image.fromarray(array)

    prediction = mlmodel.predict({"image": pil_image})
    converted_simcc_x = prediction["simcc_x"]
    converted_simcc_y = prediction["simcc_y"]

    matches = bool(
        np.allclose(converted_simcc_x, reference_simcc_x.numpy(), atol=1e-3)
        and np.allclose(converted_simcc_y, reference_simcc_y.numpy(), atol=1e-3)
    )

    commit_hash = _git_commit_hash()
    sidecar = {
        "config": config_path,
        "checkpoint": checkpoint_path,
        "mmpose_commit": commit_hash,
        "converted_at": datetime.now(timezone.utc).isoformat(),
        "sanity_check_passed": matches,
    }

    sidecar_path = Path(output_path).with_suffix("").with_suffix(".conversion_check.json")
    sidecar_path.write_text(json.dumps(sidecar, indent=2))

    if not matches:
        print(f"WARNING: converted model output does not match traced PyTorch output within tolerance. "
              f"See {sidecar_path}", file=sys.stderr)


def _git_commit_hash() -> str | None:
    try:
        import mmpose
        repo_dir = Path(mmpose.__file__).resolve().parent.parent
        result = subprocess.run(["git", "-C", str(repo_dir), "rev-parse", "HEAD"],
                                 capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except Exception:
        return None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, help="Path to the mmpose config .py")
    parser.add_argument("--checkpoint", required=True, help="Path to the downloaded .pth checkpoint")
    parser.add_argument("--input-size", type=int, nargs=2, metavar=("HEIGHT", "WIDTH"), required=True)
    parser.add_argument("--output", required=True, help="Output .mlpackage path")
    parser.add_argument("--compute-units", default="ALL", choices=["ALL", "CPU_ONLY", "CPU_AND_GPU", "CPU_AND_NE"])
    parser.add_argument("--tensor-input", action="store_true",
                         help="Use a raw float16 TensorType input instead of ImageType, "
                              "for testing the MLMultiArray(pixelBuffer:) IOSurface path.")
    args = parser.parse_args()

    convert(args.config, args.checkpoint, tuple(args.input_size), args.output, args.compute_units, args.tensor_input)


if __name__ == "__main__":
    main()

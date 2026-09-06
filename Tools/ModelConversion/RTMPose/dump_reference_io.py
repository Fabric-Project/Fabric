#!/usr/bin/env python3
"""Dumps one fixed random input (already ImageNet-normalized, planar RGB,
matching what RTMPoseMPSGraph.run(pixels:) expects) and the corresponding
reference simcc_x/simcc_y outputs, for validating the from-scratch
MPSGraph port against the real PyTorch model.

Usage:
    python dump_reference_io.py \
        --config configs/rtmpose-m_8xb32-210e_coco-wholebody-hand-256x256.py \
        --checkpoint checkpoints/rtmpose-m_simcc-hand5_pt-aic-coco_210e-256x256-74fb594_20230320.pth \
        --output reference_io

Writes <output>_input.bin (float32, [3,256,256], normalized),
<output>_simcc_x.bin, <output>_simcc_y.bin (float32, [21,512] each).
"""

import argparse

import numpy as np
import torch


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    from mmpose.apis import init_model
    model = init_model(args.config, args.checkpoint, device="cpu")
    model.eval()

    torch.manual_seed(42)
    raw_input = torch.rand(1, 3, 256, 256)  # [0,1), matches export_weights.py's convention

    mean = torch.tensor([123.675, 116.28, 103.53]).reshape(1, 3, 1, 1)
    std = torch.tensor([58.395, 57.12, 57.375]).reshape(1, 3, 1, 1)
    normalized_input = (raw_input * 255.0 - mean) / std

    with torch.no_grad():
        features = model.backbone(normalized_input)
        # backbone returns a tuple (out_indices=(4,)) — the single feature map.
        feature_map = features[0] if isinstance(features, (tuple, list)) else features
        simcc_x, simcc_y = model.head.forward(features)

    normalized_input[0].numpy().astype(np.float32).tofile(f"{args.output}_input.bin")
    feature_map[0].numpy().astype(np.float32).tofile(f"{args.output}_backbone.bin")
    simcc_x[0].numpy().astype(np.float32).tofile(f"{args.output}_simcc_x.bin")
    simcc_y[0].numpy().astype(np.float32).tofile(f"{args.output}_simcc_y.bin")

    print(f"wrote {args.output}_input.bin, shape (3,256,256)")
    print(f"wrote {args.output}_backbone.bin, shape {tuple(feature_map[0].shape)}")
    print(f"wrote {args.output}_simcc_x.bin, shape {tuple(simcc_x[0].shape)}")
    print(f"wrote {args.output}_simcc_y.bin, shape {tuple(simcc_y[0].shape)}")
    print(f"simcc_x sample values: {simcc_x[0, 0, :5].numpy()}")


if __name__ == "__main__":
    main()

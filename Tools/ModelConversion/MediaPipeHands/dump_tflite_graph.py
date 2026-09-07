#!/usr/bin/env python3
"""Dumps a resolved TFLiteModule graph spec (from tflite_to_torch.py's .pt
output) into a generic op list + flat weight blob that
MediaPipeTFLiteMPSGraph.swift can execute directly -- a from-scratch MPSGraph
port of the exact op sequence, not a hand-identified architecture (BlazePalm/
BlazeHand's block structure is TFLiteModule's own generic interpreter's
problem to resolve, and it already does: padding, groups, and NHWC/NCHW
layout remapping are all pre-resolved by TFLiteModule.__init__, which this
script reuses directly rather than re-deriving).

Usage:
    python dump_tflite_graph.py \
        --spec .../models/hand_detector.pt \
        --output hand_detector

Writes <output>_weights.bin / <output>_weights.json (same manifest format as
RTMPoseWeights.swift already reads: name -> {offset, shape, dtype}, keyed by
the tflite tensor index as a string) and <output>_ops.json (the ops list,
input/output tensor ids -- everything MediaPipeTFLiteMPSGraph.swift needs to
walk the graph in order).
"""

import argparse
import json
import sys

import numpy as np
import torch


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", required=True, help="Path to tflite_to_torch.py's .pt output")
    parser.add_argument("--tflite-repo", default="/Users/vade/Documents/Repositories/Mediapipe-Hands-PyTorch-CoreML",
                         help="Path to the Mediapipe-Hands-PyTorch-CoreML checkout (for tflite_graph.py)")
    parser.add_argument("--output", required=True, help="Output file prefix")
    args = parser.parse_args()

    sys.path.insert(0, args.tflite_repo)
    from tflite_graph import TFLiteModule

    module = TFLiteModule(args.spec)

    # --- weights: flat float32 blob + manifest, keyed by tensor index ---
    manifest = {}
    blob = []
    offset = 0
    for tensor_id, attr_name in module.weights.items():
        tensor = getattr(module, attr_name).detach().cpu().numpy().astype(np.float32)
        flat = tensor.reshape(-1)
        manifest[str(tensor_id)] = {"offset": offset, "shape": list(tensor.shape), "dtype": "float32"}
        blob.append(flat)
        offset += flat.size

    weights_blob = np.concatenate(blob) if blob else np.array([], dtype=np.float32)
    weights_blob.tofile(f"{args.output}_weights.bin")
    with open(f"{args.output}_weights.json", "w") as f:
        json.dump(manifest, f, indent=2)

    # --- ops: fully resolved (padding/groups/layout already remapped by
    # TFLiteModule.__init__) -- json-safe (tuples -> lists) ---
    def jsonify(value):
        if isinstance(value, tuple):
            return list(value)
        if isinstance(value, list):
            return [jsonify(v) for v in value]
        return value

    ops = []
    for op in module.ops:
        ops.append({
            "type": op["type"],
            "inputs": op["inputs"],
            "outputs": op["outputs"],
            "options": {k: jsonify(v) for k, v in op["options"].items()},
        })

    graph = {
        "ops": ops,
        "inputIds": module.input_ids,
        "outputIds": module.output_ids,
    }
    with open(f"{args.output}_ops.json", "w") as f:
        json.dump(graph, f, indent=2)

    print(f"wrote {args.output}_weights.bin ({weights_blob.nbytes} bytes, {len(manifest)} tensors)")
    print(f"wrote {args.output}_weights.json")
    print(f"wrote {args.output}_ops.json ({len(ops)} ops)")


if __name__ == "__main__":
    main()

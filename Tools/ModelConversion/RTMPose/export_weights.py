#!/usr/bin/env python3
"""Export an RTMPose checkpoint's backbone+head weights to a flat binary
blob + JSON manifest, for a from-scratch MPSGraph reimplementation (no
CoreML/mmpose/mmcv at runtime — this is a one-time offline export).

BatchNorm is folded into the preceding conv's weight/bias here (standard
inference-time fusion: conv+BN with no activation in between algebraically
collapses to a single conv with adjusted weight/bias), so the exported
graph only needs plain convolutions, not separate BN ops.

Usage:
    python export_weights.py \
        --config configs/rtmpose-m_8xb32-210e_coco-wholebody-hand-256x256.py \
        --checkpoint checkpoints/rtmpose-m_simcc-hand5_pt-aic-coco_210e-256x256-74fb594_20230320.pth \
        --output RTMPoseHandMedium_weights

Writes <output>.bin (raw float32, concatenated) and <output>.json (manifest:
name -> {offset, shape, dtype}, offset/shape in float32 elements).

Any state_dict key not consumed by this script is printed as a warning —
if that list includes anything other than num_batches_tracked (a BN
bookkeeping counter, not a real parameter), the architecture assumptions
here don't match this checkpoint and need re-checking before trusting the
export.
"""

import argparse
import json

import numpy as np
import torch


def fold_conv_bn(conv_weight: torch.Tensor, bn_weight: torch.Tensor, bn_bias: torch.Tensor,
                  bn_running_mean: torch.Tensor, bn_running_var: torch.Tensor, eps: float = 1e-5):
    """conv (bias=False, since ConvModule always drops the conv bias when a
    norm follows) + BN -> single conv weight + bias."""
    scale = bn_weight / torch.sqrt(bn_running_var + eps)
    folded_weight = conv_weight * scale.reshape(-1, 1, 1, 1)
    folded_bias = bn_bias - bn_running_mean * scale
    return folded_weight, folded_bias


class WeightExporter:
    def __init__(self):
        self.blob: list[np.ndarray] = []
        self.manifest: dict[str, dict] = {}
        self.offset = 0
        self.consumed_keys: set[str] = set()

    def add(self, name: str, tensor: torch.Tensor):
        array = tensor.detach().cpu().numpy().astype(np.float32)
        flat = array.reshape(-1)
        self.manifest[name] = {
            "offset": self.offset,
            "shape": list(array.shape),
            "dtype": "float32",
        }
        self.blob.append(flat)
        self.offset += flat.size

    def add_conv_bn(self, state_dict: dict, prefix: str, export_name: str):
        """prefix e.g. 'backbone.stem.0' for a ConvModule with .conv + .bn."""
        conv_weight = state_dict[f"{prefix}.conv.weight"]
        bn_weight = state_dict[f"{prefix}.bn.weight"]
        bn_bias = state_dict[f"{prefix}.bn.bias"]
        bn_mean = state_dict[f"{prefix}.bn.running_mean"]
        bn_var = state_dict[f"{prefix}.bn.running_var"]

        for key in [f"{prefix}.conv.weight", f"{prefix}.bn.weight", f"{prefix}.bn.bias",
                    f"{prefix}.bn.running_mean", f"{prefix}.bn.running_var", f"{prefix}.bn.num_batches_tracked"]:
            self.consumed_keys.add(key)

        folded_weight, folded_bias = fold_conv_bn(conv_weight, bn_weight, bn_bias, bn_mean, bn_var)
        self.add(f"{export_name}.weight", folded_weight)
        self.add(f"{export_name}.bias", folded_bias)

    def add_raw(self, state_dict: dict, key: str, export_name: str):
        self.consumed_keys.add(key)
        self.add(export_name, state_dict[key])

    def save(self, output_prefix: str):
        blob = np.concatenate(self.blob)
        blob.tofile(f"{output_prefix}.bin")
        with open(f"{output_prefix}.json", "w") as f:
            json.dump(self.manifest, f, indent=2)
        print(f"wrote {output_prefix}.bin ({blob.nbytes} bytes, {len(self.manifest)} tensors)")
        print(f"wrote {output_prefix}.json")


def export_cspnext_block(exporter: WeightExporter, state_dict: dict, prefix: str, export_prefix: str, depthwise_conv2: bool):
    """CSPNeXtBlock: conv1 (plain ConvModule) + conv2 (DepthwiseSeparableConvModule)."""
    exporter.add_conv_bn(state_dict, f"{prefix}.conv1", f"{export_prefix}.conv1")
    if depthwise_conv2:
        # DepthwiseSeparableConvModule = depthwise_conv (ConvModule) + pointwise_conv (ConvModule)
        exporter.add_conv_bn(state_dict, f"{prefix}.conv2.depthwise_conv", f"{export_prefix}.conv2_depthwise")
        exporter.add_conv_bn(state_dict, f"{prefix}.conv2.pointwise_conv", f"{export_prefix}.conv2_pointwise")
    else:
        exporter.add_conv_bn(state_dict, f"{prefix}.conv2", f"{export_prefix}.conv2")


def export_channel_attention(exporter: WeightExporter, state_dict: dict, prefix: str, export_prefix: str):
    """ChannelAttention (SE-style): a single 1x1 conv (with bias, no BN,
    per mmdetection's se_layer.py ChannelAttention — fc is Conv2d with
    bias=True, no norm). Verify this against the actual checkpoint keys;
    flagged here since se_layer.py wasn't fetched/read this session."""
    key = f"{prefix}.fc.weight"
    if key in state_dict:
        exporter.add_raw(state_dict, key, f"{export_prefix}.fc.weight")
        exporter.add_raw(state_dict, f"{prefix}.fc.bias", f"{export_prefix}.fc.bias")
    else:
        print(f"WARNING: expected channel-attention key '{key}' not found — "
              f"ChannelAttention's actual parameter names weren't verified against "
              f"source this session. Check state_dict keys under '{prefix}' by hand.")


def export_csp_layer(exporter: WeightExporter, state_dict: dict, prefix: str, export_prefix: str,
                      num_blocks: int, add_identity: bool, has_channel_attention: bool):
    exporter.add_conv_bn(state_dict, f"{prefix}.main_conv", f"{export_prefix}.main_conv")
    exporter.add_conv_bn(state_dict, f"{prefix}.short_conv", f"{export_prefix}.short_conv")
    for i in range(num_blocks):
        export_cspnext_block(exporter, state_dict, f"{prefix}.blocks.{i}", f"{export_prefix}.block{i}", depthwise_conv2=True)
    if has_channel_attention:
        export_channel_attention(exporter, state_dict, f"{prefix}.attention", f"{export_prefix}.attention")
    exporter.add_conv_bn(state_dict, f"{prefix}.final_conv", f"{export_prefix}.final_conv")


def export_spp_bottleneck(exporter: WeightExporter, state_dict: dict, prefix: str, export_prefix: str):
    exporter.add_conv_bn(state_dict, f"{prefix}.conv1", f"{export_prefix}.conv1")
    exporter.add_conv_bn(state_dict, f"{prefix}.conv2", f"{export_prefix}.conv2")
    # poolings have no weights (nn.MaxPool2d) — kernel sizes (5,9,13) are architecture constants, not exported.


def export_backbone(exporter: WeightExporter, state_dict: dict, deepen_factor: float, num_blocks_p5: list[int]):
    exporter.add_conv_bn(state_dict, "backbone.stem.0", "backbone.stem0")
    exporter.add_conv_bn(state_dict, "backbone.stem.1", "backbone.stem1")
    exporter.add_conv_bn(state_dict, "backbone.stem.2", "backbone.stem2")

    # P5 arch_setting: [in, out, base_num_blocks, add_identity, use_spp] per stage.
    use_spp_per_stage = [False, False, False, True]
    add_identity_per_stage = [True, True, True, False]

    for stage_index in range(4):
        num_blocks = max(round(num_blocks_p5[stage_index] * deepen_factor), 1)
        stage_prefix = f"backbone.stage{stage_index + 1}"
        export_prefix = f"backbone.stage{stage_index + 1}"

        # nn.Sequential index 0 is always the downsample conv.
        exporter.add_conv_bn(state_dict, f"{stage_prefix}.0", f"{export_prefix}.downsample")

        if use_spp_per_stage[stage_index]:
            export_spp_bottleneck(exporter, state_dict, f"{stage_prefix}.1", f"{export_prefix}.spp")
            csp_index = 2
        else:
            csp_index = 1

        export_csp_layer(
            exporter, state_dict, f"{stage_prefix}.{csp_index}", f"{export_prefix}.csp",
            num_blocks=num_blocks, add_identity=add_identity_per_stage[stage_index],
            has_channel_attention=True,
        )


def export_head(exporter: WeightExporter, state_dict: dict):
    exporter.add_raw(state_dict, "head.final_layer.weight", "head.final_layer.weight")
    exporter.add_raw(state_dict, "head.final_layer.bias", "head.final_layer.bias")

    exporter.add_raw(state_dict, "head.mlp.0.g", "head.mlp_scalenorm.g")
    exporter.add_raw(state_dict, "head.mlp.1.weight", "head.mlp_linear.weight")

    exporter.add_raw(state_dict, "head.gau.ln.g", "head.gau_ln.g")
    exporter.add_raw(state_dict, "head.gau.uv.weight", "head.gau_uv.weight")
    exporter.add_raw(state_dict, "head.gau.gamma", "head.gau_gamma")
    exporter.add_raw(state_dict, "head.gau.beta", "head.gau_beta")
    exporter.add_raw(state_dict, "head.gau.o.weight", "head.gau_o.weight")
    exporter.add_raw(state_dict, "head.gau.res_scale.scale", "head.gau_res_scale")

    exporter.add_raw(state_dict, "head.cls_x.weight", "head.cls_x.weight")
    exporter.add_raw(state_dict, "head.cls_y.weight", "head.cls_y.weight")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--output", required=True, help="Output file prefix (writes <output>.bin and <output>.json)")
    parser.add_argument("--deepen-factor", type=float, default=0.67, help="Must match the config's backbone.deepen_factor")
    args = parser.parse_args()

    from mmpose.apis import init_model
    model = init_model(args.config, args.checkpoint, device="cpu")
    model.eval()
    state_dict = model.state_dict()

    exporter = WeightExporter()
    # P5 base block counts before deepen_factor scaling, from CSPNeXt.arch_settings.
    export_backbone(exporter, state_dict, deepen_factor=args.deepen_factor, num_blocks_p5=[3, 6, 6, 3])
    export_head(exporter, state_dict)
    exporter.save(args.output)

    unconsumed = set(state_dict.keys()) - exporter.consumed_keys
    unconsumed = {k for k in unconsumed if not k.endswith("num_batches_tracked")}
    if unconsumed:
        print(f"\nWARNING: {len(unconsumed)} state_dict keys were not exported — "
              f"architecture assumptions likely don't match this checkpoint:")
        for key in sorted(unconsumed):
            print(f"  {key}  shape={tuple(state_dict[key].shape)}")
    else:
        print("\nAll state_dict keys accounted for (besides BN's num_batches_tracked counters).")


if __name__ == "__main__":
    main()

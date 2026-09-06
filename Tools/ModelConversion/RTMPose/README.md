# RTMPose / RTMDet → CoreML conversion

Offline pipeline that converts open-mmlab checkpoints into the `.mlpackage`
files Fabric bundles for `RegionDetectionNode`, `HandPoseAnalysisNode`,
`FacePoseAnalysisNode`, `BodyPoseDetectionNode`, and
`WholeBodyPoseDetectionNode`. Run this once per model tier you want to ship;
it is not part of the Xcode/Swift build.

Every URL and config path below was verified against the live
open-mmlab/mmpose `main` branch and its published `.pth` checkpoints at the
time this was written. mmpose's model zoo does drift — re-check
`projects/rtmpose/README.md` in the live repo if a URL 404s.

## Environment setup

This deviates from open-mmlab's own docs in three places, each because the
straightforward path was tried and failed — see the inline notes.

```shell
conda create --name rtmpose-convert python=3.10 -y
conda activate rtmpose-convert

# PyTorch (CPU is fine for conversion — this only needs a forward pass, not training)
conda install pytorch torchvision cpuonly -c pytorch

pip install -U openmim
mim install mmengine

# mmcv publishes no macOS wheel and no matching prebuilt-wheel index for
# recent torch versions, so `mim install mmcv` falls back to building from
# source — which fails on current setuptools (>=81) with
# "ModuleNotFoundError: No module named 'pkg_resources'" (mmcv's legacy
# setup.py still imports it; setuptools has been removing it). mmcv-lite is
# a real prebuilt pure-Python wheel and is sufficient here: RTMDet's and
# RTMPose's backbone/neck/head code (verified against their actual source)
# only imports mmcv.cnn, never the compiled mmcv.ops extensions mmcv-lite
# omits — this pipeline never calls NMS/postprocessing anyway, since
# convert_rtmdet.py/convert_rtmpose.py trace the raw forward pass only.
pip install mmcv-lite

# mmdet DOES publish a real wheel (mmdet-3.3.0-py3-none-any.whl, pure
# Python) that bundles its own `.mim/configs` (verified: 1048 files),
# covering every `_base_ = 'mmdet::...'` reference RTMDet's configs make —
# no source clone needed. Pinned below mmdet's own requirements/mminstall.txt
# upper bound (`mmdet>=3.0.0,<3.3.0`), which is one version behind PyPI's
# latest.
mim install "mmdet>=3.1.0,<3.3.0"

# mmpose DOES need to come from source: its wheel bundles `mmpose/.mim/configs/`
# but not `projects/`, and every RTMPose/RTMDet config path this pipeline
# uses lives under `projects/rtmpose/`. Its requirements.txt (confirmed from
# the actual file) does not list mmcv/mmdet, so this won't disturb what was
# just installed above.
git clone https://github.com/open-mmlab/mmpose
cd mmpose && pip install -r requirements.txt && pip install -v -e . && cd ..

# This directory's conversion-specific dependencies.
pip install -r requirements.txt

# Sanity check before downloading any checkpoints.
python -c "from mmdet.apis import init_detector; from mmpose.apis import init_model; print('ok')"
```

**If the sanity check fails** with an error mentioning `mmcv.ops` (meaning
something does need the compiled extensions after all), fall back to a real
`mmcv` build with build isolation disabled — pip's build isolation always
fetches the *latest* setuptools into a throwaway env regardless of what's
installed locally, which is what triggers the `pkg_resources` failure;
`--no-build-isolation` makes it use the pinned one in your active env instead:

```shell
pip uninstall mmcv-lite -y
pip install "setuptools<81" wheel
pip install "mmcv==2.1.0" --no-build-isolation
```

Version correspondence (from mmpose's own install docs): mmdet 3.x ↔ mmpose
1.x ↔ mmcv 2.x — if you hit a version-mismatch error, `pip list | grep mm`
and align to that table.

Record the exact commit hash of each checkout used (`git -C mmpose rev-parse HEAD`,
`git -C mmdetection rev-parse HEAD`) — each conversion's `.conversion_check.json`
sidecar does this automatically when mmpose/mmdetection are importable at
conversion time.

## Pose models (`convert_rtmpose.py`)

All four share `simcc_split_ratio=2.0` and ImageNet normalization
(`mean=[123.675, 116.28, 103.53]`, `std=[58.395, 57.12, 57.375]`) baked into
every RTMPose config's data preprocessor — confirmed directly from
`rtmpose-t_8xb256-420e_coco-256x192.py`, and `convert_rtmpose.py` already
bakes these same constants into the converted CoreML model's `ImageType`.
`SimCCDecoder.swift`'s default `splitRatio: 2.0` matches this exactly — no
code changes needed for these values.

| Output | Config path (inside mmpose repo) | Checkpoint URL | Input size |
|---|---|---|---|
| `RTMPoseBodyTiny.mlpackage` | `projects/rtmpose/rtmpose/body_2d_keypoint/rtmpose-t_8xb256-420e_coco-256x192.py` | https://download.openmmlab.com/mmpose/v1/projects/rtmposev1/rtmpose-t_simcc-body7_pt-body7_420e-256x192-026a1439_20230504.pth | 256×192 |
| `RTMPoseBodySmall.mlpackage` | `projects/rtmpose/rtmpose/body_2d_keypoint/rtmpose-s_8xb256-420e_coco-256x192.py` | https://download.openmmlab.com/mmpose/v1/projects/rtmposev1/rtmpose-s_simcc-body7_pt-body7_420e-256x192-acd4a1ef_20230504.pth | 256×192 |
| `RTMPoseBodyMedium.mlpackage` | `projects/rtmpose/rtmpose/body_2d_keypoint/rtmpose-m_8xb256-420e_coco-256x192.py` | https://download.openmmlab.com/mmpose/v1/projects/rtmposev1/rtmpose-m_simcc-body7_pt-body7_420e-256x192-e48f03d0_20230504.pth | 256×192 |
| `RTMPoseFaceTiny.mlpackage` | `projects/rtmpose/rtmpose/face_2d_keypoint/rtmpose-t_8xb256-120e_lapa-256x256.py` | https://download.openmmlab.com/mmpose/v1/projects/rtmposev1/rtmpose-t_simcc-face6_pt-in1k_120e-256x256-df79d9a5_20230529.pth | 256×256 |
| `RTMPoseFaceSmall.mlpackage` | `projects/rtmpose/rtmpose/face_2d_keypoint/rtmpose-s_8xb256-120e_lapa-256x256.py` | https://download.openmmlab.com/mmpose/v1/projects/rtmposev1/rtmpose-s_simcc-face6_pt-in1k_120e-256x256-d779fdef_20230529.pth | 256×256 |
| `RTMPoseFaceMedium.mlpackage` | `projects/rtmpose/rtmpose/face_2d_keypoint/rtmpose-m_8xb256-120e_lapa-256x256.py` | https://download.openmmlab.com/mmpose/v1/projects/rtmposev1/rtmpose-m_simcc-face6_pt-in1k_120e-256x256-72a37400_20230529.pth | 256×256 |
| `RTMPoseHandMedium.mlpackage` | `projects/rtmpose/rtmpose/hand_2d_keypoint/rtmpose-m_8xb32-210e_coco-wholebody-hand-256x256.py` | https://download.openmmlab.com/mmpose/v1/projects/rtmposev1/rtmpose-m_simcc-hand5_pt-aic-coco_210e-256x256-74fb594_20230320.pth | 256×256 (only tier published — "alpha version" per mmpose's own README) |
| `RTMPoseWholeBodyMedium.mlpackage` | `projects/rtmpose/rtmpose/wholebody_2d_keypoint/rtmw-m_8xb1024-270e_cocktail14-256x192.py` | https://download.openmmlab.com/mmpose/v1/projects/rtmw/rtmw-dw-l-m_simcc-cocktail14_270e-256x192-20231122.pth | 256×192 (m is the smallest Cocktail14 tier; l/x also exist if you want higher accuracy — see the "Cocktail14" table in `projects/rtmpose/README.md`) |

```shell
python convert_rtmpose.py \
  --config ../../mmpose/projects/rtmpose/rtmpose/body_2d_keypoint/rtmpose-t_8xb256-420e_coco-256x192.py \
  --checkpoint rtmpose-t_simcc-body7_pt-body7_420e-256x192-026a1439_20230504.pth \
  --input-size 256 192 \
  --output ../../Fabric/Models/Pose/RTMPoseBodyTiny.mlpackage
```
(repeat per row above — download each `.pth` first, e.g. `curl -O <url>`)

## Detector models (`convert_rtmdet.py`)

mmpose's `projects/rtmpose/rtmdet/` only has two subfolders: `person` and
`hand`. **There is no official RTMDet face detector in this project** —
confirmed by listing that directory's contents directly. Options for the
Face node's ROI, in order of effort:

1. Use `RTMDetPerson` and approximate the face region as the upper portion
   of the person box — crude, but zero extra conversion work.
2. Convert a separately-sourced lightweight face detector (e.g. SCRFD or a
   WIDERFace-trained RTMDet from mmdetection's general model zoo) through
   `convert_rtmdet.py` — same pipeline, different config/checkpoint, and its
   own FPN stride list to confirm.
3. Skip face auto-detection for now: leave `FacePoseAnalysisNode`'s Region of
   Interest unconnected (full-frame fallback) until a face detector is
   sourced.

| Output | Config path (inside mmpose repo) | Checkpoint URL | Input size |
|---|---|---|---|
| `RTMDetPerson.mlpackage` | `projects/rtmpose/rtmdet/person/rtmdet_nano_320-8xb32_coco-person.py` | https://download.openmmlab.com/mmpose/v1/projects/rtmpose/rtmdet_nano_8xb32-100e_coco-obj365-person-05d8511e.pth | 320×320 (there's also an `rtmdet_m_640-8xb32_coco-person.py` / `rtmdet_m_8xb32-100e_coco-obj365-person-235e8209.pth` pairing at 640×640 for higher accuracy, per the Pipeline Performance table) |
| `RTMDetHand.mlpackage` | `projects/rtmpose/rtmdet/hand/rtmdet_nano_320-8xb32_hand.py` | https://download.openmmlab.com/mmpose/v1/projects/rtmposev1/rtmdet_nano_8xb32-300e_hand-267f9c8f.pth | 320×320 ("alpha version" per mmpose's own README — the only hand detector they publish) |
| `RTMDetFace.mlpackage` | *(not published by mmpose — see options above)* | — | — |

```shell
python convert_rtmdet.py \
  --config ../../mmpose/projects/rtmpose/rtmdet/person/rtmdet_nano_320-8xb32_coco-person.py \
  --checkpoint rtmdet_nano_8xb32-100e_coco-obj365-person-05d8511e.pth \
  --input-size 320 320 \
  --output ../../Fabric/Models/Pose/RTMDetPerson.mlpackage
```

Before trusting `RTMDetDecoder`'s stride assumptions (`[8, 16, 32, 64]` in
`RTMDetectionEvaluator.swift`) against these specific checkpoints, run
`convert_rtmdet.py` and read its printed tensor count — the script prints
`Traced model returns N tensors (N/2 score levels + N/2 box-distance
levels)` — and cross-check against the config's
`bbox_head.anchor_generator`/`prior_generator` strides before wiring a new
detector into `RTMModelCache`.

## After conversion

Copy the resulting `.mlpackage` directories (and their `.conversion_check.json`
sidecars, kept alongside for audit purposes but not bundled into the app) into
`Fabric/Fabric/Models/Pose/`. `Package.swift` already copies that whole
directory as a resource — no project file changes needed once the files are
in place.

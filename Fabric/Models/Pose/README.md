# Pose / detection models

Converted `.mlpackage` files land here, produced by
`Tools/ModelConversion/RTMPose/` (see that directory's README for exact
config/checkpoint pairings and conversion commands). Expected contents:

- `RTMDetPerson.mlpackage`, `RTMDetHand.mlpackage`, `RTMDetFace.mlpackage`
- `RTMPoseBodyTiny.mlpackage`, `RTMPoseBodySmall.mlpackage`, `RTMPoseBodyMedium.mlpackage`
- `RTMPoseFaceTiny.mlpackage`, `RTMPoseFaceSmall.mlpackage`, `RTMPoseFaceMedium.mlpackage`
- `RTMPoseHandMedium.mlpackage`
- `RTMPoseWholeBodyMedium.mlpackage`

`RTMModelCache` (`Fabric/Nodes/Shared/Pose/RTMModelCache.swift`) looks these
up by name via `Bundle.module.url(forResource:withExtension:"mlpackage",
subdirectory:"Models/Pose")`. Until the conversion pipeline has actually
been run and its output copied here, any node depending on these models
will throw `RTMModelCache.RTMModelCacheError.resourceNotFound` at runtime —
this is expected, not a bug, until real checkpoints are converted.

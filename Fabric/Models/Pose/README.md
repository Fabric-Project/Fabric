# Pose / detection models

Two backends live here, both produced by `Tools/ModelConversion/RTMPose/`
(see that directory's README for exact config/checkpoint pairings):

**MPSGraph (GPU, no CoreML)** — a `<name>_weights.bin` + `<name>_weights.json`
pair per model, produced by `export_weights.py`, loaded by
`RTMPoseMPSGraph`/`RTMDetMPSGraph` (`Fabric/Nodes/Shared/Pose/`). This is the
live path for hand pose (`RTMPoseHandMedium_weights.*`) and both detectors
currently bundled (`RTMDetPerson_weights.*`, `RTMDetHand_weights.*`) — built
after CoreML's automatic compute-unit placement proved slower than running
directly on GPU via MPSGraph; see `Fabric/Nodes/Shared/Pose/RTMPoseMPSGraph.swift`'s
header comment for why.

**CoreML** — a `.mlpackage` per model, loaded by `RTMModelCache`
(`Fabric/Nodes/Shared/Pose/RTMModelCache.swift`) via
`Bundle.module.url(forResource:withExtension:"mlpackage",
subdirectory:"Models/Pose")`. Still the live path for face/body/whole-body
pose: `RTMPoseBodyTiny.mlpackage`, `RTMPoseFaceTiny.mlpackage`,
`RTMPoseWholeBodyMedium.mlpackage`. `RTMDetFace.mlpackage` has never been
converted — no face-detector checkpoint has been sourced yet, so the "Face"
target on `RegionDetectionNode` throws `RTMModelCacheError.resourceNotFound`
(or the MPSGraph-loader's equivalent) until one exists — expected, not a bug.

`RTMPoseHandMedium.mlpackage` is currently unused dead weight — hand pose
was moved to the MPSGraph path but the old CoreML package was never deleted.

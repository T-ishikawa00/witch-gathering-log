#!/usr/bin/env python3
"""Assemble an off-glob AIRA BODY01/02 underlay candidate from reviewed source landmarks."""
from __future__ import annotations
import copy
import hashlib
import json
import os
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
TRIAL = ROOT / "native/Art/GeneratedCandidates/EquipmentDetails/aira_body_underlay_r007_three_frame_runtime_trial_candidate.json"
LANDMARKS = ROOT / "docs/production/current/art/aira_apron_landmark_r003_pending24/root_source_grid_r003/ROOT_SOURCE_CANDIDATE_R004.json"
OUT = ROOT / "native/Art/GeneratedCandidates/EquipmentDetails/aira_body_underlay_r008_full27_candidate.json"


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main() -> None:
    trial_bytes = TRIAL.read_bytes()
    landmarks_bytes = LANDMARKS.read_bytes()
    candidate = json.loads(trial_bytes)
    source = json.loads(landmarks_bytes)
    assert source["runtimeConsumable"] is False and source["humanApproved"] is False
    root_rows = source["rows"]
    assert len(root_rows) == 24

    new_rows: list[dict] = []
    seen: set[tuple[str, int]] = set()
    for item in root_rows:
        asset = item["bodyAssetID"]
        state = item["runtimeState"]
        frame_rows = item["runtimeRows"]
        assert len(frame_rows) == 1, (asset, frame_rows)
        frame_index = int(frame_rows[0]["frameIndex"])
        key = (asset, frame_index)
        assert key not in seen, key
        seen.add(key)
        source_path = ROOT / item["source_path"]
        assert source_path.is_file(), source_path
        actual_sha = sha(source_path)
        assert actual_sha == item["sourceSHA256"], (asset, actual_sha, item["sourceSHA256"])
        with Image.open(source_path) as im:
            assert list(im.size) == item["canvas_px"], (asset, im.size, item["canvas_px"])
        hem = [int(v) for v in item["landmarkPxTopLeftSource"]]
        w, h = item["canvas_px"]
        assert 12 <= hem[0] < w - 12 and 2 <= hem[1] < h - 6, (asset, hem, item["canvas_px"])
        new_rows.append({
            "actorID": "AIRA",
            "bodyAssetID": asset,
            "frameIndex": frame_index,
            "canvas_px": list(item["canvas_px"]),
            "source_path": item["source_path"],
            "sourceSHA256": actual_sha,
            "outerHemCandidatePx": hem,
            "sourceRowState": state,
            "visible": True,
            "occlusionReason": None,
            "placement_px_top_left": [hem[0], hem[1] + 4],
            "height": 0.12,
            "angle_degrees": 0,
            "visibilityRegion_px_top_left": [hem[0] - 12, hem[1] - 2, 24, 8],
            "placementRevision": "R008_ROOT_R004_24_SOURCE_LANDMARK_ENGINEERING_TRIAL",
            "placementInterpretation": "NEW_SMALL_UNDERLAY_BEHIND_ORIGINAL_BODY_NOT_RECOVERED_INTERIOR_SURFACE",
            "sourceEvidenceLandmarkJSON": str(LANDMARKS.relative_to(ROOT)),
            "sourceEvidenceSourceProof": item["sourceEvidenceSourceProof"],
            "landmarkName": item["landmarkName"],
            "landmarkMeasurementStatus": item["measurementStatus"],
            "landmarkMeasurementBasis": item["measurementBasis"],
            "rejectedPriorPoint": item.get("rejectedPriorPoint"),
            "pointAlphaSanityOnly": item.get("pointAlphaSanityOnly"),
            "fitVerifiedInRuntime": False,
            "humanApproved": False,
        })

    assert len(seen) == 24
    old_candidate = json.loads(trial_bytes)
    for entry_id, entry in candidate["entries"].items():
        block = entry["bodyUnderlayFrameCandidate"]
        old_rows = block["rows"]
        prior_aira = [r for r in old_rows if r["actorID"] == "AIRA"]
        assert len(prior_aira) == 27
        prior_three = [r for r in prior_aira if r.get("placementRevision") == "R007_THREE_FRAME_APRON_SOURCE_CANDIDATE_RUNTIME_TRIAL"]
        assert len(prior_three) == 3
        # Preserve the three runtime-trial rows exactly; replace only the other 24 AIRA rows.
        non_aira = [r for r in old_rows if r["actorID"] != "AIRA"]
        untouched_aira = [r for r in prior_aira if r in prior_three]
        block["rows"] = non_aira + untouched_aira + copy.deepcopy(new_rows)
        assert len(block["rows"]) == 108
        aira = [r for r in block["rows"] if r["actorID"] == "AIRA"]
        assert len(aira) == 27
        assert sum(r.get("placementRevision") == "R007_THREE_FRAME_APRON_SOURCE_CANDIDATE_RUNTIME_TRIAL" for r in aira) == 3
        assert sum(r.get("placementRevision") == "R008_ROOT_R004_24_SOURCE_LANDMARK_ENGINEERING_TRIAL" for r in aira) == 24
        block["scope"] = "AIRA full 27-frame engineering candidate: 3 R007 source-reviewed trial rows are byte-for-byte preserved from the R007 trial input; the other 24 AIRA rows come from Root R004 source landmarks. Other actors remain unchanged. No runtime visual fit or Human acceptance implied."

    candidate.update({
        "status": "UNAPPROVED_FULL27_SOURCE_LANDMARK_ENGINEERING_CANDIDATE",
        "scope": "Off-glob candidate only. AIRA BODY01 and BODY02 each contain all 27 exact runtime body frames. Preserve the prior 3 R007 trial rows exactly; add only 24 Root R004 source-reviewed rows with placement at hem+[0,4], height 0.12, angle 0, and 24x8 visibility window centered on hem. All non-AIRA rows copied from R007 unchanged. Runtime fit and Human acceptance remain pending.",
        "revision": "R008",
        "humanApproval": False,
        "runtimeConsumable": False,
        "supersedes": [str(TRIAL.relative_to(ROOT))],
        "provenance": {
            "baseTrialPath": str(TRIAL.relative_to(ROOT)),
            "baseTrialSHA256": hashlib.sha256(trial_bytes).hexdigest(),
            "rootLandmarkPath": str(LANDMARKS.relative_to(ROOT)),
            "rootLandmarkSHA256": hashlib.sha256(landmarks_bytes).hexdigest(),
            "rootLandmarkRows": 24,
            "newAiraRowsPerDetail": 24,
            "preservedR007RowsPerDetail": 3,
            "sourceImageHashesAndCanvasVerified": True,
            "originalSourcePixelsModified": False,
            "runtimeFitVerified": False,
        },
    })
    encoded = (json.dumps(candidate, ensure_ascii=False, indent=2) + "\n").encode()
    tmp = OUT.with_suffix(OUT.suffix + ".tmp")
    tmp.write_bytes(encoded)
    os.replace(tmp, OUT)
    print(f"output={OUT.relative_to(ROOT)}")
    print(f"sha256={hashlib.sha256(encoded).hexdigest()}")
    print(f"R004_source_sha256={hashlib.sha256(landmarks_bytes).hexdigest()}")
    print(f"AIRA_rows_per_detail={len(new_rows) + 3}")
    print(f"non_AIRA_rows_per_detail={len(candidate['entries']['DETAIL_EQ_BODY_01']['bodyUnderlayFrameCandidate']['rows']) - 27}")

if __name__ == "__main__":
    main()

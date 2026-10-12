#!/usr/bin/env python3
"""Build one additive runtime-index overlay from a pose-candidate manifest."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "native/Art"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest", type=Path)
    ap.add_argument("--motion-family", required=True)
    ap.add_argument("--walk-label", default="walk")
    ap.add_argument("--anchor-type", default="foot_registration_candidate")
    ap.add_argument("--anchor-px", help="visual-estimate pivot as x,y; defaults to manifest anchor")
    args = ap.parse_args()
    path = args.manifest if args.manifest.is_absolute() else ROOT / args.manifest
    manifest = json.loads(path.read_text())
    actor = manifest["actor_id"]
    candidate_states = manifest["state_frames"]
    def bundle_path(frame_path: str) -> str:
        prefix = "native/Art/"
        if not frame_path.startswith(prefix):
            raise ValueError(f"frame path is not under native/Art: {frame_path}")
        return frame_path[len(prefix):]

    get = lambda state, index=0: bundle_path(candidate_states[state][index])
    state_map = {
        "idle": [bundle_path(p) for p in candidate_states["idle"]],
        "walk": [bundle_path(p) for p in candidate_states["walk"]],
        "anticipate": [get("idle", -1), get("anticipate")],
        "execute": [get("anticipate"), get("execute")],
        "recover": [get("execute"), get("recover"), get("idle")],
        "hit": [get("hit"), get("recover")],
        "resolve": [get("hit"), get("resolve")],
    }
    # Grounded/rooted candidates use an estimated foot/base pivot; hovering
    # candidates override this when calling the tool.
    anchor = [float(v) for v in args.anchor_px.split(",")] if args.anchor_px else manifest.get("anchor_px", [256, 490])
    if len(anchor) != 2:
        raise SystemExit("--anchor-px must be x,y")
    canvas = manifest.get("canvas_px", [512, 512])
    fps_by_state = {"idle": 3, "walk": 6, "anticipate": 6, "execute": 8, "recover": 8, "hit": 8, "resolve": 3}
    clips = {}
    for state, frames in state_map.items():
        fps = fps_by_state[state]
        loop = state in {"idle", "walk"}
        clips[state] = {
            "frames": frames,
            "frame_count": len(frames),
            "fps": fps,
            "duration_seconds": len(frames) / fps,
            "loop": loop,
            "status": "DISCRETE_POSE_CANDIDATE_INBETWEENS_PENDING",
        }
    entry = {
        "kind": "enemy_actor_kit",
        "selectedPNG": state_map["idle"][0],
        "sequenceFrames": state_map,
        "states_present": list(state_map),
        "status": "SEVEN_STATE_POSE_CANDIDATE_PARTIAL_NOT_NATURAL_MOTION_COMPLETE",
        "fps": None,
        "canvas_px": canvas,
        "anchor": anchor,
        "anchor_status": "VISUAL_ESTIMATE_UNAPPROVED",
        "anchor_type": args.anchor_type,
        "partsAtlasExcluded": True,
        "clips": clips,
        "motion_family": args.motion_family,
        "walk_semantics": args.walk_label,
        "art_acceptance": "PENDING_ROOT_AND_HUMAN_REVIEW",
        "runtime_integration": "OVERLAY_CANDIDATE_ONLY",
        "continuous_animation_complete": False,
        "pose_manifest": str(path.relative_to(ROOT)),
    }
    overlay = {
        "status": "UNAPPROVED_POSE_CANDIDATE_OVERLAY",
        "complete_animation": False,
        "entries": {actor: entry},
    }
    out = ART / f"runtime_overlay_{actor.lower()}_pose_candidate_{manifest['revision']}.json"
    out.write_text(json.dumps(overlay, ensure_ascii=False, indent=2) + "\n")
    print(out)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Pack the three generated ACT_B_R01_A resolve poses as an additive state-only overlay."""
from __future__ import annotations

import hashlib
import io
import json
import os
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "native/Art"
OUT = ART / "GeneratedCandidates/ACT_B_R01_A/rest_hit_resolve_r002"
CANVAS = (512, 512)
ANCHOR = (256, 490)
FPS = 8
SOURCES = [
    Path("/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-91798e23-a15c-451e-88e5-134281d9efb0.png"),
    Path("/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-ffa0b1f2-02be-4dfc-bf83-086386646ea7.png"),
    Path("/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-a8bed39b-42a4-40ff-83da-e2121a227d81.png"),
]
STILL = ART / "ActorStills/ACT_B_R01_A/ACT_B_R01_A__still__B_R01_A_base_v2.png"


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def atomic_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    with temp.open("wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(temp, path)


def main() -> None:
    if not STILL.is_file():
        raise FileNotFoundError(STILL)
    still_sha = sha(STILL)
    OUT.mkdir(parents=True, exist_ok=True)
    frames_dir = OUT / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    records = []
    packed = []
    for i, source in enumerate(SOURCES):
        if not source.is_file():
            raise FileNotFoundError(source)
        with Image.open(source) as src:
            src.load()
            if src.mode != "RGBA" or src.width != src.height:
                raise ValueError(f"expected square generated RGBA cutout, got {src.size} {src.mode}: {source}")
            # Uniform downscale only. The generated art's alpha is retained; RGB beneath
            # transparent pixels is not thresholded or rewritten.
            reduced = src.resize(CANVAS, Image.Resampling.LANCZOS)
        bbox = reduced.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
        if bbox is None:
            raise ValueError(f"empty alpha frame: {source}")
        x0, y0, x1, y1 = bbox
        dx = ANCHOR[0] - round((x0 + x1) / 2)
        dy = ANCHOR[1] - y1
        frame = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        frame.alpha_composite(reduced, (dx, dy))
        packed_bbox = frame.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
        if not packed_bbox or packed_bbox[0] < 8 or packed_bbox[2] > CANVAS[0] - 8 or packed_bbox[1] < 4 or packed_bbox[3] > CANVAS[1] - 4:
            raise ValueError(f"packed frame lacks safe canvas gutter: {i} {packed_bbox}")
        target = frames_dir / f"resolve_{i:03d}.png"
        b = io.BytesIO()
        frame.save(b, format="PNG", optimize=True)
        atomic_bytes(target, b.getvalue())
        packed.append(target)
        records.append({
            "index": i,
            "source_path": str(source),
            "source_sha256": sha(source),
            "source_canvas_px": list(reduced.size),
            "source_alpha16_bbox_after_uniform_fit_px": list(bbox),
            "translation_px": [dx, dy],
            "packed_path": target.relative_to(ART).as_posix(),
            "packed_sha256": sha(target),
            "packed_canvas_px": list(CANVAS),
            "packed_alpha16_bbox_px": list(packed_bbox),
            "anchor_px": list(ANCHOR),
        })

    contact = Image.new("RGB", (3 * 320, 360), (37, 40, 44))
    draw = ImageDraw.Draw(contact)
    for i, path in enumerate(packed):
        with Image.open(path) as im:
            im = im.convert("RGBA")
            bg = Image.new("RGBA", im.size, (24, 27, 31, 255))
            bg.alpha_composite(im)
            bg.thumbnail((300, 320), Image.Resampling.LANCZOS)
            contact.paste(bg.convert("RGB"), (i * 320 + 10, 30))
            draw.text((i * 320 + 8, 8), f"resolve_{i:03d}", fill="white")
    qa_path = OUT / "qa_contact_dark_r002.jpg"
    b = io.BytesIO()
    contact.save(b, format="JPEG", quality=93)
    atomic_bytes(qa_path, b.getvalue())

    overlay = {
        "status": "UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY",
        "complete_animation": False,
        "human_approval": False,
        "source_art_untouched": True,
        "entries": {
            "ACT_B_R01_A": {
                "kind": "enemy_actor_kit",
                "status": "UNAPPROVED_RESOLVE_ONLY_POSE_CANDIDATE",
                "complete_animation": False,
                "clips": {
                    "resolve": {
                        "frames": [x.relative_to(ART).as_posix() for x in packed],
                        "frame_count": 3,
                        "fps": FPS,
                        "duration_seconds": 0.375,
                        "loop": False,
                        "canvas_px": list(CANVAS),
                        "anchor": list(ANCHOR),
                        "display_scale": 1.0,
                        "status": "UNAPPROVED_AUTHORED_RESOLVE_CANDIDATE",
                        "complete_animation": False,
                        "movement_semantics": "Front knees buckle, boar lowers onto its side, then settles into an eyes-closed non-gory resting hold.",
                        "anchor_status": "VISUAL_ESTIMATE_UNAPPROVED"
                    }
                },
                "sequenceFrames": {"resolve": [x.relative_to(ART).as_posix() for x in packed]}
            }
        }
    }
    overlay_path = ART / "runtime_overlay_zzzzzzzz_act_b_r01_a_resolve_candidate_r002.json"
    atomic_bytes(overlay_path, (json.dumps(overlay, ensure_ascii=False, indent=2) + "\n").encode())
    manifest = {
        "schema": "witch.enemy_resolve_pose_candidate.v1",
        "actorId": "ACT_B_R01_A",
        "revision": "resolve_r002",
        "status": "UNAPPROVED_AUTHORED_RESOLVE_ONLY_CANDIDATE",
        "referenceStill": STILL.relative_to(ART).as_posix(),
        "referenceStillSHA256": still_sha,
        "sourceRevision_r001_preserved": True,
        "rejectedPriorAtlas": {
            "path": "/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-35eb8945-8529-47c0-97f4-cba1c1ab8a38.png",
            "reason": "Two of three cells had alpha16 pixels touching the cell boundary; not packed or integrated."
        },
        "canvas_px": list(CANVAS),
        "anchor_px": list(ANCHOR),
        "fps": FPS,
        "display_scale": 1.0,
        "frames": records,
        "qa_contact_dark": qa_path.relative_to(ART).as_posix(),
        "runtime_overlay": overlay_path.relative_to(ART).as_posix(),
        "human_adoption": False,
        "natural_motion_complete": False,
        "limitations": [
            "Three authored poses are a sampled resolve candidate, not continuous animation completion.",
            "Per-frame pose size and contact must be reviewed in the native scene; actor display scale is constant.",
            "Visual review on a dark opaque composite did not show the red RGB fringes visible in the raw generator preview; original alpha remains unchanged."
        ]
    }
    atomic_bytes(OUT / "manifest_r002.json", (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({"overlay": overlay_path.relative_to(ROOT).as_posix(), "manifest": (OUT / "manifest_r002.json").relative_to(ROOT).as_posix(), "qa": qa_path.relative_to(ROOT).as_posix(), "frames": records}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

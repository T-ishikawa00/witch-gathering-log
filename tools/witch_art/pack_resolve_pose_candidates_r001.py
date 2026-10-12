#!/usr/bin/env python3
"""Pack sampled resolve-only pose candidates for the remaining root batch."""
from __future__ import annotations

import hashlib
import io
import json
import os
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "native/Art"
CANVAS = (512, 512)
ANCHOR = (256, 490)
FPS = 8
ACTORS = {
    "ACT_B_R01_B": {
        "semantics": ["Canopy and boughs start to droop; roots remain planted.", "Trunk and canopy lean lower; branches hang and roots flex.", "Tree guardian settles low with branches drooped and core dim; no broken wood."],
        "still": "ActorStills/ACT_B_R01_B/ACT_B_R01_B__still__B_R01_B_ANCIENT_TREE_base_v1.png",
        "sources": [
            "/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-645f20d3-5d76-40f5-acdf-77f580ea4c0b.png",
            "/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-14272392-7077-41fb-9a9d-1584b7832b1f.png",
            "/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-36e7fcdb-1a81-4579-969e-25b3860d8cea.png",
        ],
    },
    "ACT_B_R02_A": {
        "semantics": ["Stalk bends and cap dips; weight shifts into root feet.", "Cap lowers near the floor; stalk and root feet fold.", "Cap rests low on its side; stalk limp and root feet tucked."],
        "still": "ActorStills/ACT_B_R02_A/ACT_B_R02_A__still__r001.png",
        "sources": [
            "/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-f7e1ffec-b4a7-4ff5-8af5-22e0c2188072.png",
            "/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-67db757f-2382-4daa-a63b-cf40d776f66e.png",
            "/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-9a39e856-6fcd-4072-9f6c-24a349a042f8.png",
        ],
    },
    "ACT_B_R02_B": {
        "semantics": ["Head and belly lower; forelegs bend and tail trails down.", "Body coils lower; legs tuck and tail curls around.", "Lizard lies in a compact side coil with head low and eyes closed."],
        "still": "ActorStills/ACT_B_R02_B/ACT_B_R02_B__still__r001.png",
        "sources": [
            "/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-8e9ef002-8003-44ba-b10a-40492661c68e.png",
            "/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-b12bfb54-ee87-441f-af89-18c6ee73e38f.png",
            "/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-37c5fdf2-ac44-4141-8b05-342dea66cd47.png",
        ],
    },
}


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def atomic_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with tmp.open("wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def main() -> None:
    entries = {}
    records = []
    contact = Image.new("RGB", (len(ACTORS) * 3 * 190, len(ACTORS) * 295), (36, 39, 43))
    draw = ImageDraw.Draw(contact)
    for row, (actor, info) in enumerate(ACTORS.items()):
        if len(info["sources"]) != 3:
            raise ValueError(f"{actor} requires exactly three resolve frames")
        still = ART / info["still"]
        if not still.is_file():
            raise FileNotFoundError(still)
        actor_dir = ART / "GeneratedCandidates" / actor / "resolve_only_r001"
        frames_dir = actor_dir / "frames"
        frames_dir.mkdir(parents=True, exist_ok=True)
        frame_paths = []
        actor_records = []
        for index, source_text in enumerate(info["sources"]):
            source = Path(source_text)
            if not source.is_file():
                raise FileNotFoundError(source)
            with Image.open(source) as im:
                im.load()
                if im.mode != "RGBA":
                    raise ValueError(f"source alpha must be preserved for {actor} {index}: {im.mode}")
                reduced = im.resize(CANVAS, Image.Resampling.LANCZOS)
            source_box = reduced.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
            if source_box is None:
                raise ValueError(f"empty frame: {source}")
            x0, y0, x1, y1 = source_box
            dx = ANCHOR[0] - round((x0 + x1) / 2)
            dy = ANCHOR[1] - y1
            frame = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
            frame.alpha_composite(reduced, (dx, dy))
            packed_box = frame.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
            if not packed_box or packed_box[0] < 8 or packed_box[2] > CANVAS[0] - 8 or packed_box[1] < 4 or packed_box[3] > CANVAS[1] - 4:
                raise ValueError(f"unsafe frame gutter {actor} {index}: {packed_box}")
            target = frames_dir / f"resolve_{index:03d}.png"
            b = io.BytesIO()
            frame.save(b, format="PNG", optimize=True)
            atomic_bytes(target, b.getvalue())
            frame_paths.append(target)
            actor_records.append({
                "index": index,
                "semantic_pose": info["semantics"][index],
                "generated_source_path": str(source),
                "generated_source_sha256": sha(source),
                "source_canvas_px": list(im.size),
                "source_alpha16_bbox_after_uniform_fit_px": list(source_box),
                "translation_px": [dx, dy],
                "packed_path": target.relative_to(ART).as_posix(),
                "packed_sha256": sha(target),
                "packed_canvas_px": list(CANVAS),
                "packed_alpha16_bbox_px": list(packed_box),
                "anchor_px": list(ANCHOR),
            })
            comp = Image.new("RGBA", CANVAS, (24, 27, 31, 255))
            comp.alpha_composite(frame)
            comp.thumbnail((180, 260), Image.Resampling.LANCZOS)
            x = row * 570 + index * 190 + (190 - comp.width) // 2
            y = row * 295 + 25
            contact.paste(comp.convert("RGB"), (x, y))
            draw.text((row * 570 + index * 190 + 4, row * 295 + 6), f"{actor} R{index}", fill="white")
        overlay_actor = {
            "kind": "enemy_actor_kit",
            "status": "UNAPPROVED_RESOLVE_ONLY_POSE_CANDIDATE",
            "complete_animation": False,
            "clips": {
                "resolve": {
                    "frames": [p.relative_to(ART).as_posix() for p in frame_paths],
                    "frame_count": 3,
                    "fps": FPS,
                    "duration_seconds": 0.375,
                    "loop": False,
                    "canvas_px": list(CANVAS),
                    "anchor": list(ANCHOR),
                    "display_scale": 1.0,
                    "status": "UNAPPROVED_AUTHORED_RESOLVE_CANDIDATE",
                    "complete_animation": False,
                    "movement_semantics": " | ".join(info["semantics"]),
                    "anchor_status": "VISUAL_ESTIMATE_UNAPPROVED"
                }
            },
            "sequenceFrames": {"resolve": [p.relative_to(ART).as_posix() for p in frame_paths]}
        }
        entries[actor] = overlay_actor
        records.append({
            "actorId": actor,
            "revision": "resolve_only_r001",
            "status": "UNAPPROVED_AUTHORED_RESOLVE_ONLY_CANDIDATE",
            "referenceStill": info["still"],
            "referenceStillSHA256": sha(still),
            "canvas_px": list(CANVAS),
            "anchor_px": list(ANCHOR),
            "fps": FPS,
            "frames": actor_records,
            "natural_motion_complete": False,
        })

    overlay = {
        "status": "UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY",
        "complete_animation": False,
        "human_approval": False,
        "source_art_untouched": True,
        "entries": entries
    }
    overlay_path = ART / "runtime_overlay_zzzzzzzz_resolve_candidates_r001.json"
    atomic_bytes(overlay_path, (json.dumps(overlay, ensure_ascii=False, indent=2) + "\n").encode())
    qa_path = ART / "GeneratedCandidates/resolve_candidates_r001_contact_dark.jpg"
    b = io.BytesIO()
    contact.save(b, format="JPEG", quality=93)
    atomic_bytes(qa_path, b.getvalue())
    manifest = {
        "schema": "witch.enemy_resolve_pose_batch_candidate.v1",
        "revision": "r001",
        "status": "UNAPPROVED_CANDIDATE_ONLY",
        "overlay": overlay_path.relative_to(ART).as_posix(),
        "qa_contact_dark": qa_path.relative_to(ART).as_posix(),
        "actors": records,
        "source_assets_untouched": True,
        "human_adoption": False,
        "complete_animation": False,
        "limitations": [
            "Three frames are sampled pose candidates; they do not prove natural continuous resolve animation.",
            "Alpha-composited contact previews do not replace native screen review.",
            "Generated RGB beneath alpha 0 is preserved; only uniform resize and canvas placement were performed."
        ]
    }
    manifest_path = ART / "GeneratedCandidates/resolve_candidates_manifest_r001.json"
    atomic_bytes(manifest_path, (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({"overlay": overlay_path.relative_to(ROOT).as_posix(), "manifest": manifest_path.relative_to(ROOT).as_posix(), "qa": qa_path.relative_to(ROOT).as_posix(), "actors": [r["actorId"] for r in records]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

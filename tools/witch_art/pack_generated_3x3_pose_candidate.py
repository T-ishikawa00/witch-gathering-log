#!/usr/bin/env python3
"""Extract nine alpha-connected poses from an imagegen 3x3 atlas into equal cells.

The generated atlas is retained byte-for-byte in the external provenance path;
this script only writes a derived, versioned candidate under native/Art.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import find_objects, label

ROOT = Path(__file__).resolve().parents[2]
STATES = {
    "idle": [0, 1],
    "walk": [2, 3],
    "anticipate": [4],
    "execute": [5],
    "recover": [6],
    "hit": [7],
    "resolve": [8],
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True, type=Path)
    ap.add_argument("--actor", required=True)
    ap.add_argument("--revision", default="r002")
    ap.add_argument("--reference", required=True, type=Path)
    ap.add_argument("--review", required=True, help="concise visual assessment")
    ap.add_argument("--grid-cells", action="store_true", help="crop fixed equal 3x3 cells instead of connected components")
    args = ap.parse_args()

    dest = ROOT / "native/Art/GeneratedCandidates" / args.actor / f"pose_candidate_{args.revision}"
    if dest.exists():
        raise SystemExit(f"refusing to overwrite existing candidate: {dest}")
    dest.mkdir(parents=True)
    frames_dir = dest / "frames"
    frames_dir.mkdir()
    shutil.copy2(args.source, dest / f"imagegen_atlas_{args.revision}.png")

    sheet = Image.open(args.source).convert("RGBA")
    rgba = np.asarray(sheet)
    labels, _ = label(rgba[:, :, 3] > 8)
    stats = []
    for i, sl in enumerate(find_objects(labels), start=1):
        if sl is None:
            continue
        area = int(np.count_nonzero(labels[sl] == i))
        if area >= 1000:
            stats.append((i, sl[1].start, sl[0].start, sl[1].stop, sl[0].stop, area))
    if args.grid_cells:
        if sheet.width != sheet.height or sheet.width % 3:
            raise SystemExit("fixed-grid mode requires a square atlas divisible into thirds")
        step = sheet.width // 3
        ordered = [(0, x * step, y * step, (x + 1) * step, (y + 1) * step, 0)
                   for y in range(3) for x in range(3)]
    else:
        if len(stats) != 9:
            raise SystemExit(f"expected nine substantial alpha components, found {len(stats)}")
        # Cluster by vertical center into three rows, then sort left-to-right.
        stats.sort(key=lambda s: ((s[2] + s[4]) / 2, s[1]))
        rows: list[list[tuple]] = [[], [], []]
        for row_index, item in enumerate(stats):
            rows[row_index // 3].append(item)
        ordered = [item for row in rows for item in sorted(row, key=lambda s: s[1])]
        if len(ordered) != 9:
            raise SystemExit("component row ordering failed")

    canvas = 512
    margin = 22
    frame_records = []
    contact = Image.new("RGBA", (canvas * 3, canvas * 3), (29, 31, 37, 255))
    draw = ImageDraw.Draw(contact)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 20)
    except OSError:
        font = ImageFont.load_default()

    pose_names = ["idle_a", "idle_b", "walk_a", "walk_b", "anticipate", "execute", "recover", "hit", "resolve"]
    for pose_index, (component, x0, y0, x1, y1, _area) in enumerate(ordered):
        crop = sheet.crop((x0, y0, x1, y1))
        if not args.grid_cells:
            # Keep the dominant connected sprite only. This discards detached
            # image-generation specks/strips that otherwise survive the crop.
            component_mask = Image.fromarray((labels[y0:y1, x0:x1] == component).astype("uint8") * 255)
            crop.putalpha(Image.fromarray(np.minimum(np.asarray(crop.getchannel("A")), np.asarray(component_mask))) )
        scale = min((canvas - 2 * margin) / crop.width, (canvas - 2 * margin) / crop.height, 1.0)
        if scale < 1:
            crop = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        px = (canvas - crop.width) // 2
        # Keep feet on a consistent baseline while preserving whole sprite bounds.
        py = canvas - margin - crop.height
        frame.alpha_composite(crop, (px, py))
        name = pose_names[pose_index]
        out = frames_dir / f"{name}.png"
        frame.save(out, optimize=True)
        frame_records.append({
            "pose": name,
            "frame_path": str(out.relative_to(ROOT)),
            "sha256": sha(out),
            "canvas_px": [canvas, canvas],
            "anchor_px": [canvas / 2, canvas - margin],
            "source_bounds_xyxy": [x0, y0, x1, y1],
        })
        preview = frame.copy()
        preview.thumbnail((canvas, canvas), Image.Resampling.LANCZOS)
        contact.alpha_composite(preview, ((pose_index % 3) * canvas, (pose_index // 3) * canvas))
        draw.text(((pose_index % 3) * canvas + 10, (pose_index // 3) * canvas + 8), name, fill="white", font=font, stroke_width=2, stroke_fill=(10, 10, 10, 230))

    preview_path = dest / f"qa_contact_sheet_{args.revision}.png"
    contact.convert("RGB").save(preview_path, optimize=True)
    state_frames = {state: [frame_records[i]["frame_path"] for i in indices] for state, indices in STATES.items()}
    manifest = {
        "actor_id": args.actor,
        "revision": args.revision,
        "status": "CANDIDATE_UNAPPROVED",
        "source_reference_path": str(args.reference),
        "source_reference_sha256": sha(args.reference),
        "imagegen_atlas_path": str((dest / f"imagegen_atlas_{args.revision}.png").relative_to(ROOT)),
        "imagegen_atlas_sha256": sha(dest / f"imagegen_atlas_{args.revision}.png"),
        "pose_order": pose_names,
        "state_frames": state_frames,
        "frames": frame_records,
        "fps": 6,
        "canvas_px": [canvas, canvas],
        "anchor_px": [canvas / 2, canvas - margin],
        "review": args.review,
        "qa_contact_sheet_path": str(preview_path.relative_to(ROOT)),
        "qa_contact_sheet_sha256": sha(preview_path),
        "runtime_integration": "NOT_DONE",
        "runtime_visual_qa": "PENDING_ROOT_REVIEW",
        "human_adoption": "PENDING",
        "limitations": [
            "Each action state currently has only one authored pose; idle and walk each have two poses.",
            "This is a corrected composition/identity candidate, not evidence of natural continuous animation.",
            "All frames derive from a generated atlas and remain unapproved pending visual/runtime review.",
            "Source reference was not modified.",
        ],
    }
    manifest_path = dest / f"pose_clip_manifest_candidate_{args.revision}.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    overlay_path = ROOT / "native/Art/GeneratedCandidates" / args.actor / f"pose_candidate_overlay_{args.actor.lower()}_{args.revision}.json"
    overlay = {
        "actor_id": args.actor,
        "overlay_id": f"{args.actor}_POSE_CANDIDATE_{args.revision.upper()}",
        "status": "CANDIDATE_UNAPPROVED",
        "human_adoption": "PENDING",
        "manifest_path": str(manifest_path.relative_to(ROOT)),
        "manifest_sha256": sha(manifest_path),
        "preview_path": str(preview_path.relative_to(ROOT)),
        "preview_sha256": sha(preview_path),
        "state_frames": state_frames,
        "fps": 6,
        "runtime_integration": "NOT_DONE",
        "source_art_untouched": True,
    }
    overlay_path.write_text(json.dumps(overlay, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"manifest": str(manifest_path), "overlay": str(overlay_path), "preview": str(preview_path), "frames": 9}, ensure_ascii=False))


if __name__ == "__main__":
    main()

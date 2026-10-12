#!/usr/bin/env python3
"""Pack one imagegen 3x3 attack atlas as additive candidate clips.

Only crops/translates exact RGBA pixels into a stable runtime canvas. It does
not resize, recolor, clean alpha, or alter canonical source assets.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "native/Art"
ACTOR = "ACT_E_R01_02"
ATLAS = ART / "GeneratedCandidates/ACT_E_R01_02/spider_attack_r002/imagegen_atlas_r003.png"
BASE_OVERLAY = ART / "runtime_overlay_act_e_r01_02_walk_cycle_candidate_r001.json"
OVERLAY_OUT = ART / "runtime_overlay_act_e_r01_02_attack_cycle_candidate_r001.json"
REV = "spider_attack_cycle_r001"
REV_DIR = ART / "GeneratedCandidates/ACT_E_R01_02" / REV
CANVAS = (512, 400)
ANCHOR = (256, 344)
DISPLAY_SCALE = 380 / 341
STATES = ("anticipate", "execute", "recover")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def component_sizes(alpha: np.ndarray) -> list[int]:
    mask = alpha > 16
    h, w = mask.shape
    seen = np.zeros_like(mask)
    sizes = []
    for sy, sx in zip(*np.nonzero(mask)):
        if seen[sy, sx]:
            continue
        stack = [(int(sy), int(sx))]
        seen[sy, sx] = True
        size = 0
        while stack:
            y, x = stack.pop()
            size += 1
            for ny in range(max(0, y - 1), min(h, y + 2)):
                for nx in range(max(0, x - 1), min(w, x + 2)):
                    if mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        sizes.append(size)
    return sorted(sizes, reverse=True)


def main() -> None:
    atlas = Image.open(ATLAS).convert("RGBA")
    if atlas.width % 3:
        raise SystemExit(f"atlas width not divisible by 3 columns: {atlas.size}")
    cw = atlas.width // 3
    y_edges = [round(i * atlas.height / 3) for i in range(4)]
    base = json.loads(BASE_OVERLAY.read_text())
    entry = base["entries"][ACTOR]
    source_canvas = tuple(entry["canvas_px"])
    source_anchor = tuple(entry["anchor"])
    if source_canvas != (512, 341) or source_anchor != (256, 330):
        raise SystemExit(f"unexpected source canvas/anchor: {source_canvas}/{source_anchor}")
    REV_DIR.mkdir(parents=True, exist_ok=True)
    (REV_DIR / "imagegen_atlas_source.png").write_bytes(ATLAS.read_bytes())
    recs = []
    packed = []
    source_rgba = np.asarray(atlas)
    cw_names = [f"{state}_{i:03d}.png" for state in STATES for i in range(3)]
    for idx, name in enumerate(cw_names):
        row, col = divmod(idx, 3)
        cy0, cy1 = y_edges[row], y_edges[row + 1]
        ch = cy1 - cy0
        cell = atlas.crop((col * cw, cy0, (col + 1) * cw, cy1))
        arr = np.asarray(cell)
        alpha = arr[:, :, 3]
        yy, xx = np.where(alpha > 16)
        if not len(xx):
            raise SystemExit(f"empty cell {idx}")
        margins = [int(xx.min()), int(yy.min()), cw - 1 - int(xx.max()), ch - 1 - int(yy.max())]
        edge_pixels = int((alpha[[0, -1], :] > 16).sum() + (alpha[:, [0, -1]] > 16).sum())
        if edge_pixels:
            raise SystemExit(f"alpha>16 touches source cell edge at cell {idx}: {edge_pixels}")
        rgba_bbox = Image.fromarray(arr).getchannel("A").getbbox()
        l, t, r, b = rgba_bbox
        dx = round(CANVAS[0] / 2 - (l + r) / 2)
        dy = ANCHOR[1] - int(yy.max())
        dx = max(-l, min(dx, CANVAS[0] - r))
        dy = max(-t, min(dy, CANVAS[1] - b))
        if abs(dy - (ANCHOR[1] - int(yy.max()))) > 8:
            raise SystemExit(f"anchor correction too large in cell {idx}: {dy - (ANCHOR[1] - int(yy.max()))} px")
        if l + dx < 0 or r + dx > CANVAS[0] or t + dy < 0 or b + dy > CANVAS[1]:
            raise SystemExit(f"full-alpha pixels would clip after translation in cell {idx}: {rgba_bbox} + {(dx, dy)}")
        frame = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        frame.alpha_composite(cell, (dx, dy))
        out = REV_DIR / "frames" / name
        out.parent.mkdir(parents=True, exist_ok=True)
        frame.save(out)
        packed.append((name, frame))
        farr = np.asarray(frame)
        out_alpha = farr[:, :, 3]
        ay, ax = np.where(out_alpha > 16)
        src_pixels = int(np.count_nonzero(alpha))
        out_pixels = int(np.count_nonzero(out_alpha))
        if src_pixels != out_pixels:
            raise SystemExit(f"alpha changed while packing cell {idx}: {src_pixels} -> {out_pixels}")
        recs.append({
            "frame": name,
            "phase": STATES[idx // 3],
            "source_cell_px": [col * cw, cy0, cw, ch],
            "source_alpha16_bbox_xyxy": [int(xx.min()), int(yy.min()), int(xx.max()) + 1, int(yy.max()) + 1],
            "source_alpha16_margins_ltrb": margins,
            "source_alpha16_edge_pixels": edge_pixels,
            "translation_px": [dx, dy],
            "anchor_correction_px": [dy - (ANCHOR[1] - int(yy.max()))],
            "packed_alpha16_bbox_xyxy": [int(ax.min()), int(ay.min()), int(ax.max()) + 1, int(ay.max()) + 1],
            "packed_alpha16_pixels": out_pixels,
            "source_nonzero_alpha_pixels": src_pixels,
            "alpha_preserved_exactly": True,
            "sha256": sha(out),
        })
    panel = Image.new("RGB", (3 * CANVAS[0], 3 * (CANVAS[1] + 32)), (29, 34, 42))
    draw = ImageDraw.Draw(panel)
    for i, (name, frame) in enumerate(packed):
        x, y = (i % 3) * CANVAS[0], (i // 3) * (CANVAS[1] + 32)
        panel.paste(frame, (x, y), frame)
        draw.text((x + 8, y + 4), name, fill=(235, 239, 244))
    panel.save(REV_DIR / "qa_contact_sheet.jpg", quality=95)

    retained_sha = {state: hashlib.sha256(json.dumps(entry.get("clips", {}).get(state), sort_keys=True).encode()).hexdigest()
                    for state in ("idle", "walk", "hit", "resolve")}
    for state in STATES:
        paths = [f"GeneratedCandidates/{ACTOR}/{REV}/frames/{state}_{i:03d}.png" for i in range(3)]
        entry.setdefault("clips", {})[state] = {
            "frames": paths,
            "frame_count": 3,
            "fps": 10,
            "duration_seconds": 0.3,
            "loop": False,
            "complete_animation": False,
            "status": "UNAPPROVED_THREE_FRAME_ATTACK_PHASE_CANDIDATE_NOT_NATURAL_MOTION_COMPLETE",
            "canvas_px": list(CANVAS),
            "anchor": list(ANCHOR),
            "display_scale": DISPLAY_SCALE,
            "anchor_status": "INHERITED_VISUAL_ESTIMATE_UNAPPROVED",
        }
    entry["status"] = "UNAPPROVED_PARTIAL_ATTACK_MOTION_CANDIDATE"
    entry["complete_animation"] = False
    overlay = {
        "status": "UNAPPROVED_PARTIAL_ATTACK_MOTION_CANDIDATE_OVERLAY",
        "complete_animation": False,
        "candidate_manifest": f"GeneratedCandidates/{ACTOR}/{REV}/manifest.json",
        "entries": {ACTOR: entry},
    }
    OVERLAY_OUT.write_text(json.dumps(overlay, ensure_ascii=False, indent=2) + "\n")
    report = {
        "schema": "witch.attack_cycle_candidate.v1",
        "asset_id": ACTOR,
        "revision": REV,
        "approval": "UNAPPROVED_CANDIDATE_PENDING_ROOT_NATIVE_SCREEN_REVIEW",
        "natural_motion_complete": False,
        "source_still": "ActorStills/ACT_E_R01_02/ACT_E_R01_02__still__E_R01_02_base_v2.png",
        "source_still_sha256": sha(ART / "ActorStills/ACT_E_R01_02/ACT_E_R01_02__still__E_R01_02_base_v2.png"),
        "atlas": f"GeneratedCandidates/{ACTOR}/{REV}/imagegen_atlas_source.png",
        "atlas_sha256": sha(REV_DIR / "imagegen_atlas_source.png"),
        "atlas_px": list(atlas.size),
        "source_grid_cell_bounds_px": {"x": [0, cw, cw * 2, cw * 3], "y": y_edges},
        "source_runtime_canvas_px": list(source_canvas),
        "source_runtime_anchor_px": list(source_anchor),
        "runtime_canvas_px": list(CANVAS),
        "display_scale_candidate": DISPLAY_SCALE,
        "anchor_candidate_px": list(ANCHOR),
        "phase_order": ["anticipate_000..002", "execute_000..002", "recover_000..002"],
        "movement_semantics": "spider_crouch_then_connected_foreleg_jab_then_absorbing_recovery_no_external_web",
        "packing": "Exact alpha-preserving per-cell crop and translation only; no resize, recolor, alpha cleanup, or drawing.",
        "frames": recs,
        "retained_clip_sha256": retained_sha,
        "qa_contact_sheet": f"GeneratedCandidates/{ACTOR}/{REV}/qa_contact_sheet.jpg",
        "runtime_overlay": OVERLAY_OUT.name,
        "technical_status": "PACKED_ALPHA_EXACT_SOURCE_CELLS_NO_EDGE_CONTACT",
        "visual_status": "CANDIDATE_ONLY_PENDING_NATIVE_SCREEN_REVIEW",
        "limitations": ["Only three candidate frames for each phase; no continuous natural-motion completion claim.", "Human adoption remains pending."],
    }
    (REV_DIR / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()

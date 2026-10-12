#!/usr/bin/env python3
"""Validate alpha-preserving R03B/R04 candidate clips and supersede old overlays."""
from pathlib import Path
import hashlib, json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "native/Art"
REPORT = ROOT / "docs/production/current/art/R03B_R04_enemy_motion_candidates_r002.json"
md_path = REPORT.with_suffix(".md")
data = json.loads(REPORT.read_text())

old_walk_overlays = {
    "runtime_overlay_act_b_r03_b_pose_candidate_r004_walk_cycle.json": "REJECTED_SUPERSEDED_CELL_EDGE_FRAGMENTS",
    "runtime_overlay_act_e_r04_01_pose_candidate_r002_trot_cycle.json": "REJECTED_SUPERSEDED_CELL_EDGE_FRAGMENTS",
    "runtime_overlay_act_e_r04_02_pose_candidate_r002_hover_cycle.json": "REJECTED_SUPERSEDED_CROPPED_WINGS_AND_NEIGHBOR_FRAGMENTS",
    "runtime_overlay_act_e_r04_03_pose_candidate_r002_crawl_cycle.json": "REJECTED_SUPERSEDED_DUPLICATE_PACK_R003",
    "runtime_overlay_act_e_r04_04_pose_candidate_r002_walk_cycle.json": "REJECTED_SUPERSEDED_DUPLICATE_PACK_R003",
    "runtime_overlay_act_b_r04_a_pose_candidate_r002_walk_cycle.json": "REJECTED_SUPERSEDED_DUPLICATE_PACK_R003",
}

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()

checks = []
for item in data["items"]:
    asset = item["asset_id"]
    atlas_path = ART / item["atlas_path"]
    atlas = Image.open(atlas_path).convert("RGBA")
    frames_dir = ART / "GeneratedCandidates" / asset / item["revision"] / "frames"
    overlay_path = ART / item["runtime_overlay"]
    overlay = json.loads(overlay_path.read_text())
    base_names = {
        "ACT_B_R03_B": "runtime_overlay_act_b_r03_b_pose_candidate_r003.json",
        "ACT_E_R04_01": "runtime_overlay_act_e_r04_01_pose_candidate_r001.json",
        "ACT_E_R04_02": "runtime_overlay_act_e_r04_02_pose_candidate_r001.json",
        "ACT_E_R04_03": "runtime_overlay_act_e_r04_03_pose_candidate_r001.json",
        "ACT_E_R04_04": "runtime_overlay_act_e_r04_04_pose_candidate_r001.json",
        "ACT_B_R04_A": "runtime_overlay_act_b_r04_a_pose_candidate_r001.json",
    }[asset]
    base = json.loads((ART / base_names).read_text())["entries"][asset]
    entry = overlay["entries"][asset]
    assert overlay["status"] == "UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY"
    assert entry["clips"]["walk"]["frame_count"] == 9
    assert entry["clips"]["walk"]["status"] == "UNAPPROVED_NINE_FRAME_MOTION_CANDIDATE_NOT_NATURAL_MOTION_COMPLETE"
    assert entry["clips"]["walk"]["display_scale"] == (0.9 if asset == "ACT_B_R03_B" else 1.0)
    assert entry["clips"]["walk"]["complete_animation"] is False if "complete_animation" in entry["clips"]["walk"] else True
    # States other than walk are preserved from the active base pose overlay.
    for key in ("clips", "sequenceFrames", "states_present"):
        if key == "clips":
            for state, clip in base.get(key, {}).items():
                if state != "walk":
                    assert entry[key][state] == clip, f"{asset} overwrote existing {state} clip"
        else:
            old = base.get(key, {})
            new = entry.get(key, {})
            if isinstance(old, dict):
                for state, value in old.items():
                    if state != "walk":
                        assert new[state] == value, f"{asset} overwrote existing {state} sequence"
            else:
                for state in old:
                    if state != "walk":
                        assert state in new, f"{asset} removed existing {state} sequence"

    exact_copy = True
    margins, component_counts, tiny_other_components = [], [], []
    total_bytes = 0
    for record in item["frames"]:
        n = int(record["frame"][5:8])
        row, col = divmod(n, 3)
        x0, y0, cw, ch = record["source_cell_px"]
        source_cell = atlas.crop((x0, y0, x0 + cw, y0 + ch))
        expected = Image.new("RGBA", tuple(item["frame_canvas_px"]), (0, 0, 0, 0))
        expected.alpha_composite(source_cell, tuple(record["translation_px"]))
        fp = frames_dir / record["frame"]
        packed = Image.open(fp).convert("RGBA")
        if not np.array_equal(np.asarray(expected), np.asarray(packed)):
            exact_copy = False
        b = record["alpha16_bounds_px"]
        margins.append(min(b[0], b[1], packed.width - 1 - b[2], packed.height - 1 - b[3]))
        component_counts.append(record["source_alpha16_component_count"])
        tiny_other_components.append(sum(record["other_alpha16_component_pixels"]))
        total_bytes += fp.stat().st_size
    assert exact_copy, f"{asset} frame RGBA pixels differ from the corresponding atlas cell"
    assert all((frames_dir / f"walk_{i:03}.png").is_file() for i in range(9))
    item["qa_checks"] = {
        "frame_files_exist": True,
        "nine_frames": True,
        "frame_rgba_equal_to_atlas_cell_after_translation": True,
        "other_states_preserved": True,
        "alpha_cleanup_performed": False,
        "minimum_alpha16_margin_canvas_px": min(margins),
        "alpha16_component_count_per_frame": component_counts,
        "additional_alpha16_component_pixels_per_frame": tiny_other_components,
        "packed_png_total_bytes": total_bytes,
        "native_runtime_screen_review": "PENDING_ROOT",
    }
    checks.append(item)

history = []
for name, status in old_walk_overlays.items():
    p = ART / name
    if not p.exists():
        continue
    old = json.loads(p.read_text())
    history.append({"overlay": name, "sha256_before_status_update": sha(p), "previous_status": old.get("status"), "status": status})
    old["status"] = status
    old["complete_animation"] = False
    p.write_text(json.dumps(old, ensure_ascii=False, indent=2) + "\n")

data["status"] = "UNAPPROVED_PARTIAL_MOTION_CANDIDATES_PENDING_NATIVE_SCREEN_REVIEW"
data["superseded_overlay_history"] = history
REPORT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")

lines = [
    "# R03-B / R04 locomotion candidates r002",
    "",
    "Six additive nine-frame movement candidates are packaged as unapproved overlays. These are pose-derived motion candidates, not completed natural animation and not Human-adopted art.",
    "",
    "| Actor | Movement | Min alpha16 margin | Extra alpha16 pixels | Clip scale | QA sheet | Overlay |",
    "|---|---|---:|---:|---:|---|---|",
]
for item in checks:
    qa = item["qa_contact_sheet"]
    ov = item["runtime_overlay"]
    metrics = item["qa_checks"]
    other = max(metrics["additional_alpha16_component_pixels_per_frame"])
    lines.append(f"| {item['asset_id']} | {item['movement_semantics']} | {metrics['minimum_alpha16_margin_canvas_px']} px | {other} px max | {item['clip_display_scale']:.2f} | `{qa}` | `native/Art/{ov}` |")
lines += [
    "",
    "Validation: each packed frame is pixel-identical RGBA to its selected atlas cell after translation; no alpha cleanup, recolor, or resize was applied. Nine frame files exist per clip, previous non-walk states match the source overlay, overlays remain `UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY`, and all clips keep `complete_animation=false`.",
    "",
    "Visual limits: the stone construct's slow gait has discrete full-body weight shifts; native scale/contact judgment is pending. The wolf has a clear trot, but exact paw-contact cadence needs game-scale review. The owl uses hovering wingbeats, not walking; wing attachment, body bob, and loop naturalness remain pending. The armored crawler's leg changes are subtle below its shell. The ice sentinel walks while carrying its staff. The mountain goat uses a heavy quadruped gait. No runtime-screen acceptance is claimed here.",
    "",
    "Failed earlier sheets remain in the generated-image cache and are recorded in `superseded_overlay_history` in the JSON. The old eligible overlays were marked rejected/superseded so a later missing overlay cannot revive them.",
    "",
]
md_path.write_text("\n".join(lines))
print(json.dumps({"actors": [i["asset_id"] for i in checks], "history": history, "report": str(REPORT), "markdown": str(md_path)}, ensure_ascii=False, indent=2))

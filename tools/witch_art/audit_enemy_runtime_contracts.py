#!/usr/bin/env python3
"""Read-only mechanical audit of enemy animation contracts in a built app bundle.

This deliberately does not normalize, rewrite, or judge artwork. It compares
runtime_index declarations with referenced PNG headers and reports metadata
lineage inconsistencies as evidence for human review.
"""
from __future__ import annotations

import argparse
import json
import re
import struct
from pathlib import Path
from typing import Any

STATES = ("idle", "walk", "anticipate", "execute", "recover", "hit", "resolve")
PNG_SIG = b"\x89PNG\r\n\x1a\n"


def png_size(path: Path) -> tuple[int, int] | None:
    try:
        with path.open("rb") as f:
            header = f.read(24)
        if len(header) != 24 or header[:8] != PNG_SIG or header[12:16] != b"IHDR":
            return None
        return struct.unpack(">II", header[16:24])
    except OSError:
        return None


def revision_tokens(value: Any) -> set[str]:
    if isinstance(value, str):
        return set(re.findall(r"(?:r|R)\d{3,4}", value))
    if isinstance(value, dict):
        out: set[str] = set()
        for k, v in value.items():
            out |= revision_tokens(k)
            out |= revision_tokens(v)
        return out
    if isinstance(value, list):
        out: set[str] = set()
        for v in value:
            out |= revision_tokens(v)
        return out
    return set()


def audit(app: Path) -> dict[str, Any]:
    index_path = app / "Art" / "runtime_index.json"
    index = json.loads(index_path.read_text())
    entries = index.get("entries", {})
    actor_ids = sorted(k for k, v in entries.items()
                       if (k.startswith("ACT_E_") or k.startswith("ACT_B_")) and isinstance(v, dict)
                       and v.get("kind") == "enemy_actor_kit")
    findings: list[dict[str, Any]] = []
    actors: list[dict[str, Any]] = []
    for actor_id in actor_ids:
        entry = entries[actor_id]
        clips = entry.get("clips", {})
        states: list[dict[str, Any]] = []
        for state in STATES:
            clip = clips.get(state)
            issues: list[str] = []
            if not isinstance(clip, dict):
                states.append({"state": state, "declared": False,
                               "issues": ["frame_clip_not_declared"]})
                continue
            frames = clip.get("frames", [])
            declared_count = clip.get("frame_count")
            if declared_count is None:
                issues.append("frame_count_not_declared")
            elif declared_count != len(frames):
                issues.append("frame_count_mismatch")
            fps = clip.get("fps")
            if not isinstance(fps, (int, float)) or fps <= 0:
                issues.append("fps_missing_or_invalid")
            dims = []
            for rel in frames:
                p = app / "Art" / rel
                size = png_size(p)
                dims.append({"path": rel, "exists": p.is_file(),
                             "bytes": p.stat().st_size if p.is_file() else None,
                             "pixel_size": list(size) if size else None})
                if not p.is_file():
                    issues.append("frame_file_missing")
                elif size is None:
                    issues.append("frame_not_valid_png")
            canvas = clip.get("canvas_px", entry.get("canvas_px"))
            anchor = clip.get("anchor", entry.get("anchor"))
            canvas_source = "clip" if clip.get("canvas_px") is not None else ("entry" if entry.get("canvas_px") is not None else None)
            anchor_source = "clip" if clip.get("anchor") is not None else ("entry" if entry.get("anchor") is not None else None)
            if canvas is None:
                issues.append("canvas_missing_even_after_entry_fallback")
            if anchor is None:
                issues.append("anchor_missing_even_after_entry_fallback")
            for d in dims:
                if d["pixel_size"] and canvas and d["pixel_size"] != canvas:
                    issues.append("frame_canvas_size_mismatch")
            if len({tuple(d["pixel_size"]) for d in dims if d["pixel_size"]}) > 1:
                issues.append("inconsistent_frame_dimensions")
            states.append({"state": state, "declared": True,
                           "declared_frame_count": declared_count,
                           "actual_frame_count": len(frames), "fps": fps,
                           "duration_seconds": clip.get("duration_seconds"),
                           "canvas_px": canvas, "canvas_source": canvas_source,
                           "anchor_px": anchor, "anchor_source": anchor_source,
                           "loop": clip.get("loop"), "frames": dims,
                           "issues": sorted(set(issues))})
        art_root = app / "Art"
        missing_clip_states = [s for s in STATES if s not in clips]
        rig_path = entry.get("partRig")
        rig_evidence: dict[str, Any] = {"field_present": isinstance(rig_path, str),
                                        "manifest_path": rig_path,
                                        "manifest_exists": False,
                                        "candidate_rig_files": [],
                                        "effective_states": [],
                                        "clips": {}, "parts": []}
        rig_states: set[str] = set()
        if isinstance(rig_path, str):
            manifest_path = art_root / rig_path
            rig_evidence["manifest_exists"] = manifest_path.is_file()
            if manifest_path.is_file():
                manifest = json.loads(manifest_path.read_text())
                rig_evidence["manifest_raw"] = manifest
                rig_evidence["revision"] = manifest.get("revision")
                rig_evidence["status"] = manifest.get("status")
                rig_evidence["canvas_px"] = manifest.get("canvas_px")
                rig_evidence["anchor_px"] = manifest.get("anchor_px")
                rig_evidence["fps"] = manifest.get("fps")
                declared_parts = {p.get("id") for p in manifest.get("parts", []) if isinstance(p, dict)}
                for part in manifest.get("parts", []):
                    if not isinstance(part, dict):
                        continue
                    part_path = art_root / part.get("path", "")
                    actual_px = png_size(part_path)
                    part_issues = []
                    if not part_path.is_file():
                        part_issues.append("part_file_missing")
                    elif actual_px is None:
                        part_issues.append("part_file_not_valid_png")
                    if actual_px and part.get("part_image_px") and list(actual_px) != part.get("part_image_px"):
                        part_issues.append("part_pixel_size_mismatch")
                    pivot = part.get("pivot_in_part_px")
                    if actual_px and pivot and (pivot[0] < 0 or pivot[1] < 0 or pivot[0] > actual_px[0] or pivot[1] > actual_px[1]):
                        part_issues.append("pivot_outside_part_bounds")
                    rig_evidence["parts"].append({"id": part.get("id"), "path": part.get("path"),
                        "exists": part_path.is_file(), "bytes": part_path.stat().st_size if part_path.is_file() else None,
                        "declared_pixel_size": part.get("part_image_px"),
                        "actual_pixel_size": list(actual_px) if actual_px else None,
                        "pivot_in_part_px": pivot, "rest_position_px": part.get("rest_position_px"),
                        "z_position": part.get("z_position"), "pivot_basis": part.get("pivot_basis"),
                        "issues": part_issues})
                raw_rig_clips = manifest.get("clips", {})
                for state, rig_clip in raw_rig_clips.items():
                    if not isinstance(rig_clip, dict):
                        continue
                    rig_states.add(state)
                    keyframes = rig_clip.get("keyframes", [])
                    frame_count = rig_clip.get("frame_count")
                    rig_issues = []
                    if frame_count != len(keyframes):
                        rig_issues.append("keyframe_count_mismatch")
                    if rig_clip.get("fps", manifest.get("fps", 0)) <= 0:
                        rig_issues.append("fps_missing_or_invalid")
                    unknown_parts = sorted({part_id for kf in keyframes if isinstance(kf, dict)
                                            for part_id in (kf.get("pose_by_part") or {})
                                            if part_id not in declared_parts})
                    if unknown_parts:
                        rig_issues.append("keyframe_references_unknown_part")
                    frame_numbers = [kf.get("frame") for kf in keyframes if isinstance(kf, dict)]
                    if any(not isinstance(f, (int, float)) or f < 0 or (frame_count and f >= frame_count) for f in frame_numbers):
                        rig_issues.append("keyframe_frame_out_of_range")
                    rig_evidence["clips"][state] = {"fps": rig_clip.get("fps", manifest.get("fps")),
                        "frame_count": frame_count, "keyframe_count": len(keyframes),
                        "loop": rig_clip.get("loop"), "keyframe_part_ids": sorted({part_id for kf in keyframes if isinstance(kf, dict)
                            for part_id in (kf.get("pose_by_part") or {})}),
                        "unknown_part_ids": unknown_parts, "issues": rig_issues}
        rig_files = [str(p.relative_to(art_root)) for p in art_root.rglob("*")
                     if p.is_file() and actor_id in p.as_posix()
                     and ("rig_manifest" in p.name.lower() or "part_rig" in p.name.lower())]
        rig_evidence["candidate_rig_files"] = rig_files
        effective_states = set(clips) | rig_states
        if "flight" in rig_states:
            effective_states.add("walk")  # EnemyMotionController explicitly maps flight to walk.
        effective_missing = [s for s in STATES if s not in effective_states]
        for state_data in states:
            s = state_data["state"]
            rig_state = "flight" if s == "walk" and "flight" in rig_states else s
            state_data["effective_source"] = "frame_clip" if state_data.get("declared") else ("part_rig:" + rig_state if rig_state in rig_states else None)
        rig_evidence["raw_states"] = sorted(rig_states)
        rig_evidence["effective_states"] = sorted(effective_states)
        # Preserve independent metadata sources as authored; do not resolve conflicts.
        source_contracts = entry.get("stateFrameContracts", {})
        notes = entry.get("candidate_notes", {})
        lineage: list[dict[str, Any]] = []
        for state, clip in clips.items():
            if not isinstance(clip, dict):
                continue
            paths = clip.get("frames", [])
            path_revs = revision_tokens(paths)
            metadata = source_contracts.get(state, {}) if isinstance(source_contracts, dict) else {}
            note_value = notes.get(f"{state}_candidate") if isinstance(notes, dict) else None
            contract_revs = revision_tokens(metadata)
            note_revs = revision_tokens(note_value)
            mismatch = bool(path_revs and ((contract_revs and not (path_revs & contract_revs))
                                           or (note_revs and not (path_revs & note_revs))))
            if mismatch:
                lineage.append({"state": state, "clip_frame_revisions": sorted(path_revs),
                                "state_frame_contract_revisions": sorted(contract_revs),
                                "candidate_note_revisions": sorted(note_revs),
                                "contract_path": metadata.get("contract_path") if isinstance(metadata, dict) else None,
                                "candidate_note": note_value,
                                "issue": "clip_vs_metadata_revision_mismatch"})
        actor = {"actor_id": actor_id, "status": entry.get("status"),
                 "canvas_px": entry.get("canvas_px"), "anchor_px": entry.get("anchor"),
                 "anchor_status": entry.get("anchor_status"), "clip_state_count": len(clips),
                 "missing_clip_states": missing_clip_states, "effective_missing_states": effective_missing,
                 "effective_state_count": len(set(STATES) - set(effective_missing)), "states": states,
                 "part_rig": rig_evidence,
                 "metadata_lineage_inconsistencies": lineage}
        actors.append(actor)
        for state_data in states:
            actual_issues = [i for i in state_data.get("issues", []) if i != "frame_clip_not_declared"]
            if actual_issues:
                findings.append({"actor_id": actor_id, "state": state_data["state"],
                                 "category": "runtime_contract_or_file", "issues": actual_issues})
        for issue in lineage:
            findings.append({"actor_id": actor_id, "state": issue["state"],
                             "category": "metadata_lineage", "issue": issue["issue"],
                             "evidence": issue})
        if missing_clip_states:
            findings.append({"actor_id": actor_id, "category": "missing_state_clips",
                             "states": missing_clip_states,
                             "resolved_by_part_rig": sorted(set(missing_clip_states) - set(effective_missing)),
                             "note": "Frame-clip absence is a coverage-layer fact; effective availability is reported separately."})
        for part in rig_evidence["parts"]:
            if part["issues"]:
                findings.append({"actor_id": actor_id, "category": "part_rig_part_contract",
                                 "part_id": part["id"], "issues": part["issues"]})
        for state, clip in rig_evidence["clips"].items():
            if clip["issues"]:
                findings.append({"actor_id": actor_id, "state": state,
                                 "category": "part_rig_clip_contract", "issues": clip["issues"]})
        if effective_missing:
            findings.append({"actor_id": actor_id, "category": "effective_state_missing", "states": effective_missing})
    return {"report_schema": "enemy_runtime_contract_audit_r001",
            "audit_kind": "read_only_mechanical_contract_check",
            "correction_note": "Supersedes the initial R001 result: the first pass omitted the runtime entry partRig field and therefore misreported ACT_B_R04_B as having no rig and no effective state coverage. This corrected pass counts explicit frame clips and part-rig states separately, then computes runtime-effective coverage using EnemyMotionController's flight-to-walk alias.",
            "runtime_resolution_evidence": {"source_file": "native/build/source_20261010T145113/EnemyMotion.swift",
                "part_rig_source_file": "native/build/source_20261010T145113/PartRig.swift",
                "rules": ["EnemyMotionController reads entry.partRig before clipMap.",
                          "EnemyPartRig.availableStates is the manifest clips key set.",
                          "EnemyMotionController maps rig state flight to runtime state walk and dispatches walk requests to flight clip when present."]},
            "formal_art_acceptance": "NOT_ASSESSED",
            "human_design_approval": "NOT_ASSESSED",
            "app_bundle": str(app), "runtime_index": str(index_path),
            "runtime_index_status": index.get("status"),
            "expected_states": list(STATES), "enemy_actor_count": len(actor_ids),
            "declared_clip_state_count": sum(a["clip_state_count"] for a in actors),
            "effective_state_count": sum(a["effective_state_count"] for a in actors),
            "actors": actors, "finding_count": len(findings), "findings": findings}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True, type=Path, help="Built .app bundle")
    ap.add_argument("--json-out", type=Path)
    ap.add_argument("--md-out", type=Path)
    args = ap.parse_args()
    result = audit(args.app.resolve())
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(encoded)
    else:
        print(encoded)
    if args.md_out:
        lines = ["# Enemy Runtime Contract Audit R001", "",
                 "> Correction to the initial R001 pass: it overlooked the `partRig` field. ACT_B_R04_B has a rig manifest; this corrected report separates frame-clip coverage from rig coverage and computes effective runtime states using the controller alias.", "",
                 f"- App bundle: `{result['app_bundle']}`",
                 f"- Runtime index status: `{result['runtime_index_status']}`",
                 f"- Enemy actor units: {result['enemy_actor_count']} (expected 30)",
                 f"- Explicit frame-clip states: {result['declared_clip_state_count']}/210; effective clip+rig states: {result['effective_state_count']}/210",
                 f"- Mechanical findings: {result['finding_count']}",
                 "- Formal art acceptance / Human design approval: **not assessed**", "",
                 "This report checks declarations and file headers only. It does not normalize pixels, assess motion quality, or confer art approval.", "",
                 "## Findings", ""]
        if not result["findings"]:
            lines.append("No mechanical discrepancies were detected by this checker.")
        for f in result["findings"]:
            lines.append(f"- `{f.get('actor_id')}` / `{f.get('state', 'all')}` — `{f['category']}`: `{f.get('issues', f.get('issue', f.get('states', '')) )}`")
        lines += ["", "## Per-enemy clip and rig inventory", "",
                 "| Enemy | Frame clips | Rig states | Effective states | Clips missing canvas/anchor inheritance | Metadata lineage conflicts |",
                  "|---|---:|---:|---:|---:|---:|"]
        for a in result["actors"]:
            missing_geom = sum(1 for s in a["states"] if s.get("declared") and (s.get("canvas_px") is None or s.get("anchor_px") is None))
            rig = f"{len(a['part_rig']['raw_states'])}/7 ({a['part_rig']['revision']})" if a['part_rig'].get("manifest_exists") else "none"
            lines.append(f"| {a['actor_id']} | {a['clip_state_count']}/7 | {len(a['part_rig']['raw_states'])}/7 | {a['effective_state_count']}/7 | {missing_geom} | {len(a['metadata_lineage_inconsistencies'])} |")
        args.md_out.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Audit candidate equipment-frame rows against the frames runtime actually records.

This derives expected tuples from shipped source manifests and Luna's current
motion record source. It intentionally does not treat an index that merely
exists in a registration row as proof that the runtime can reach it.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
ACTORS = ("ERNA", "LUNA", "AIRA", "NOIR")


@dataclass(frozen=True, order=True)
class RuntimeTuple:
    actor: str
    asset_id: str
    frame_index: int
    canvas: tuple[int, int]
    state: str


def read_json(path: Path) -> Any:
    return json.loads(path.read_text())


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_dimensions(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"not a PNG with IHDR: {path}")
    return struct.unpack(">II", data[16:24])


def assert_png_canvas(path: Path, canvas: tuple[int, int]) -> None:
    actual = png_dimensions(path)
    if actual != canvas:
        raise ValueError(f"manifest/runtime canvas mismatch: {path}: {actual} != {canvas}")


def runtime_tuples(root: Path = ROOT) -> dict[str, set[RuntimeTuple]]:
    """Build tuples from the same arrays that the SpriteKit runtime enumerates."""
    result: dict[str, set[RuntimeTuple]] = {actor: set() for actor in ACTORS}
    for directory, prefix in (("party_rest_r001", "GeneratedArt/PartyRest/"),
                              ("party_attack_r001", "GeneratedArt/PartyAttack/")):
        manifest = read_json(root / "native/GeneratedArt" / directory / "MANIFEST.json")
        for actor in ACTORS:
            entry = manifest[actor]
            canvas = tuple(int(v) for v in entry["canvas"])
            for state, clip in entry["clips"].items():
                # PartyAuthoredMotion.play enumerates this selected clip, so index is local.
                for index, filename in enumerate(clip["frames"]):
                    assert_png_canvas(root / "native/GeneratedArt" / directory / filename, canvas)
                    result[actor].add(RuntimeTuple(actor, prefix + filename, index, canvas, state))

    walk = read_json(root / "native/GeneratedArt/party_walk_r001/MANIFEST.json")
    for actor in ACTORS:
        entry = walk[actor]
        canvas = tuple(int(v) for v in entry["canvas"])
        # CharacterLocomotion.play enumerates `frames`; rejected source cells are absent.
        for index, filename in enumerate(entry["frames"]):
            assert_png_canvas(root / "native/GeneratedArt/party_walk_r001" / filename, canvas)
            result[actor].add(RuntimeTuple(actor, "GeneratedArt/PartyWalk/" + filename,
                                          index, canvas, "walk"))

    layered = read_json(root / "native/GeneratedArt/layered_motion_r001/MANIFEST.json")
    for costume, entry in layered.items():
        canvas = tuple(int(v) for v in entry["canvas"])
        for state, clip in entry.items():
            if not isinstance(clip, dict) or not isinstance(clip.get("frames"), list):
                continue
            for index, frame in enumerate(clip["frames"]):
                assert_png_canvas(root / "native/GeneratedArt/layered_motion_r001" / frame["path"], canvas)
                result["ERNA"].add(RuntimeTuple(
                    "ERNA", "GeneratedArt/LayeredMotion/" + frame["path"], index,
                    canvas, costume + ":" + state))

    # LunaBookSpriteMotion records LunaBookMotion's bodyAssetID/frameIndex.
    data_path = root / "native/WitchGameCore/Sources/WitchGameCore/LunaBookMotionDataR001.swift"
    source = data_path.read_text()
    record_re = re.compile(
        r'LunaBookMotionFrameRecord\(poseState:\s*"([^"]+)"\s*,\s*'
        r'frameIndex:\s*(\d+)\s*,\s*bodyAssetID:\s*"([^"]+)"')
    for state, index, asset_id in record_re.findall(source):
        assert_png_canvas(root / "native/GeneratedArt/r001" / (asset_id + ".png"), (256, 256))
        result["LUNA"].add(RuntimeTuple("LUNA", asset_id, int(index), (256, 256),
                                         "book:" + state))
    return result


def _candidate_tuple(row: dict[str, Any], actor: str) -> tuple[str, int, tuple[int, int]] | None:
    asset = row.get("runtimeBodyAssetID", row.get("bodyAssetID"))
    index = row.get("runtimeFrameIndex", row.get("frameIndex"))
    canvas = row.get("canvas_px", row.get("canvas"))
    if not isinstance(asset, str) or not isinstance(index, int) or not isinstance(canvas, list) or len(canvas) != 2:
        return None
    return asset, index, (int(canvas[0]), int(canvas[1]))


def registration_sources(root: Path = ROOT) -> list[tuple[str, str, list[dict[str, Any]]]]:
    """Return latest candidate tables and the historical NOIR R001 table."""
    sources: list[tuple[str, str, list[dict[str, Any]]]] = []
    aira_path = root / "native/Art/runtime_overlay_zzzzzzzzzzzzz_aira_body03_frame_registration_candidate_r004.json"
    aira = read_json(aira_path)["entries"]["DETAIL_EQ_BODY_03"]["frameRegistrationCandidate"]["rows"]
    sources.append(("AIRA", str(aira_path.relative_to(root)), aira))

    # These measured files are candidate tables, even when not yet merged into the app index.
    erna_path = root / "native/Art/GeneratedCandidates/EquipmentDetails/erna_standard_travel_landmarks_r002.json"
    erna_doc = read_json(erna_path)
    erna = [frame for costume in erna_doc["states"].values()
            for state in costume.values() for frame in state["frames"]]
    sources.append(("ERNA", str(erna_path.relative_to(root)), erna))

    noir_path = root / "native/Art/GeneratedCandidates/EquipmentDetails/noir_frame_landmarks_r002.json"
    noir_doc = read_json(noir_path)
    noir = [frame for state in noir_doc["states"].values() for frame in state["frames"]]
    sources.append(("NOIR", str(noir_path.relative_to(root)), noir))

    luna_path = root / "native/Art/runtime_overlay_zzzzzzzzzzzzzzzz_equipment_frame_landmarks_candidate_r001.json"
    luna_doc = read_json(luna_path)
    luna = luna_doc["entries"]["LUNA"]["semanticFrameLandmarksCandidate"]["rows"]
    sources.append(("LUNA", str(luna_path.relative_to(root)), luna))

    old_noir_path = root / "native/Art/GeneratedCandidates/EquipmentDetails/noir_frame_landmarks_r001.json"
    old_noir_doc = read_json(old_noir_path)
    old_noir = [frame for state in old_noir_doc["states"].values() for frame in state["frames"]]
    sources.append(("NOIR_R001_ERRATUM", str(old_noir_path.relative_to(root)), old_noir))
    return sources


def audit(root: Path = ROOT) -> dict[str, Any]:
    expected = runtime_tuples(root)
    output = []
    for actor, source, rows in registration_sources(root):
        expected_for_actor = expected["NOIR" if actor == "NOIR_R001_ERRATUM" else actor]
        missing_fields: list[int] = []
        invalid: list[dict[str, Any]] = []
        for position, row in enumerate(rows):
            parsed = _candidate_tuple(row, actor)
            if parsed is None:
                missing_fields.append(position)
                continue
            asset, index, canvas = parsed
            matches = [item for item in expected_for_actor
                       if item.asset_id == asset and item.frame_index == index and item.canvas == canvas]
            if not matches:
                # Preserve diagnostic distinction: same asset/canvas is present but its index is not reachable.
                alternatives = sorted({item.frame_index for item in expected_for_actor
                                       if item.asset_id == asset and item.canvas == canvas})
                invalid.append({"row": position, "assetID": asset, "registeredIndex": index,
                                "canvas": list(canvas), "reachableIndicesForAsset": alternatives,
                                "state": row.get("state", row.get("sourceRowState"))})
        known_erratum = actor == "NOIR_R001_ERRATUM"
        output.append({"actor": actor, "source": source, "rows": len(rows),
                       "missingRequiredFields": missing_fields, "unreachableRows": invalid,
                       "status": ("KNOWN_ERRATUM" if known_erratum and invalid else
                                  "PASS" if not missing_fields and not invalid else "FAIL")})

    # Check that source code still uses the enumerated clip-local index contracts audited above.
    contracts = {
        "PartyAuthoredMotion": ("native/WitchApp/PartyAuthoredMotion.swift", "frames.enumerated()", "index:index"),
        "CharacterLocomotion": ("native/WitchApp/CharacterLocomotion.swift", "frames.enumerated()", "index:index"),
        "LayeredWitchMotion": ("native/WitchApp/LayeredWitchMotion.swift", "poses.enumerated()", "index:index"),
        "LunaBookSpriteMotion": ("native/WitchApp/LunaBookSpriteMotion.swift", "frames.enumerated()", "frame.frameIndex"),
    }
    callsite_checks = []
    for name, (relative, loop, index_expression) in contracts.items():
        text = (root / relative).read_text()
        callsite_checks.append({"runtime": name, "source": relative,
                               "enumeratesFrames": loop in text,
                               "usesLocalIndex": index_expression in text,
                               "status": "PASS" if loop in text and index_expression in text else "FAIL"})
    return {"schema": "runtime_frame_registration_audit_r001", "status": "CANDIDATE_QA_ONLY",
            "humanApproval": False, "runtimeCallsiteChecks": callsite_checks,
            "tables": output,
            "runtimeTupleCounts": {actor: len(rows) for actor, rows in expected.items()},
            "sourcesSHA256": {
                path: sha256(root / path) for path in sorted({
                    "native/GeneratedArt/party_rest_r001/MANIFEST.json",
                    "native/GeneratedArt/party_attack_r001/MANIFEST.json",
                    "native/GeneratedArt/party_walk_r001/MANIFEST.json",
                    "native/GeneratedArt/layered_motion_r001/MANIFEST.json",
                    "native/WitchGameCore/Sources/WitchGameCore/LunaBookMotionDataR001.swift",
                })}}


def audit_runtime_index(root: Path, index_path: Path) -> dict[str, Any]:
    """Compare any merged frame-registration rows in a bundle index to source tuples.

    Existing indexes may only describe static actor stills. In that case report
    the absent registration contract explicitly; never infer clip coverage from
    `states_present` or selected still images.
    """
    index = read_json(index_path)
    expected = runtime_tuples(root)
    candidate_expected: set[tuple[str, str, int, tuple[int, int]]] = set()
    for actor, _source, rows in registration_sources(root):
        if actor == "NOIR_R001_ERRATUM":
            continue
        for row in rows:
            parsed = _candidate_tuple(row, actor)
            if parsed:
                asset, frame_index, canvas = parsed
                candidate_expected.add((actor, asset, frame_index, canvas))
    tuples: list[dict[str, Any]] = []

    def walk(value: Any, path: str = "$", actor_hint: str | None = None) -> None:
        if isinstance(value, dict):
            hint = value.get("actorID", value.get("actor", actor_hint))
            if not isinstance(hint, str) or hint.upper() not in ACTORS:
                hint = actor_hint
            actor = hint.upper() if isinstance(hint, str) and hint.upper() in ACTORS else None
            parsed = _candidate_tuple(value, actor or "")
            if actor and parsed:
                asset, frame_index, canvas = parsed
                tuples.append({"actor": actor, "assetID": asset, "frameIndex": frame_index,
                               "canvas": list(canvas), "jsonPath": path})
            for key, child in value.items():
                child_hint = key.upper() if key.upper() in ACTORS else actor
                walk(child, f"{path}.{key}", child_hint)
        elif isinstance(value, list):
            for i, child in enumerate(value):
                walk(child, f"{path}[{i}]", actor_hint)

    walk(index)
    keys: list[tuple[str, str, int, tuple[int, int]]] = []
    for item in tuples:
        key = (item["actor"], item["assetID"], item["frameIndex"], tuple(item["canvas"]))
        keys.append(key)
    counts: dict[tuple[str, str, int, tuple[int, int]], int] = {}
    for key in keys:
        counts[key] = counts.get(key, 0) + 1
    actual_keys = set(keys)
    missing = sorted(candidate_expected - actual_keys)
    unreachable = []
    for item, key in zip(tuples, keys):
        runtime_expected = expected[item["actor"]]
        if not any(row.asset_id == item["assetID"] and row.frame_index == item["frameIndex"]
                   and row.canvas == tuple(item["canvas"]) for row in runtime_expected):
            reachable = sorted({row.frame_index for row in expected[item["actor"]]
                                if row.asset_id == item["assetID"] and row.canvas == tuple(item["canvas"])})
            unreachable.append({**item, "reachableIndicesForAsset": reachable})
    duplicates = [{"actor": k[0], "assetID": k[1], "frameIndex": k[2], "canvas": list(k[3]), "count": n}
                  for k, n in sorted(counts.items()) if n > 1]
    index_absolute = index_path.resolve()
    return {
        "path": str(index_absolute),
        "sha256": sha256(index_absolute),
        "schema": index.get("schema"),
        "registrationRows": len(tuples),
        "expectedCandidateTupleCount": len(candidate_expected),
        "reachableCandidateTupleCount": len(candidate_expected & actual_keys),
        "missingExpectedCandidates": len(missing),
        "missingExamples": [{"actor": k[0], "assetID": k[1], "frameIndex": k[2], "canvas": list(k[3])}
                            for k in missing[:25]],
        "duplicateTupleCount": len(duplicates),
        "duplicateTuples": duplicates,
        "unreachableRows": unreachable,
        "unexpectedIndexTuples": len(actual_keys - candidate_expected),
        "status": "NO_REGISTRATION_ROWS" if not tuples else "PASS" if not missing and not duplicates and not unreachable and actual_keys == candidate_expected else "PARTIAL_OR_INVALID",
        "interpretation": "Index states/stills do not count as frame-registration rows; this is bundle-index coverage, not proof of visual fit.",
    }


def markdown(report: dict[str, Any]) -> str:
    version = "R002" if "bundleRuntimeIndexAudit" in report else "R001"
    lines = [f"# Runtime frame registration audit {version}", "",
             "Candidate-only data/runtime contract audit. It does not accept artwork or landmark quality.", "",
             "Expected frame tuples come from the current PartyRest, PartyAttack, PartyWalk, and LayeredMotion manifests; LUNA book records are read from the Swift data consumed by LunaBookSpriteMotion.", "",
             "| Candidate table | Rows | Unreachable | Status |", "|---|---:|---:|---|"]
    for row in report["tables"]:
        lines.append(f"| `{row['source']}` | {row['rows']} | {len(row['unreachableRows'])} | {row['status']} |")
    if "bundleRuntimeIndexAudit" in report:
        index = report["bundleRuntimeIndexAudit"]
        lines += ["", "## Merged bundle runtime index", "",
                  f"Index: `{index['path']}` (SHA-256 `{index['sha256']}`)", "",
                  f"Candidate tuples expected from source tables: {index['expectedCandidateTupleCount']}; reachable in the merged index: {index['reachableCandidateTupleCount']}; missing: {index['missingExpectedCandidates']}; duplicate tuples: {index['duplicateTupleCount']}; invalid runtime tuples: {len(index['unreachableRows'])}; unexpected index tuples: {index['unexpectedIndexTuples']}. Status: **{index['status']}**.", "",
                  index["interpretation"]]
        if index["missingExamples"]:
            lines += ["", "Missing candidate tuple examples:", ""]
            for item in index["missingExamples"]:
                lines.append(f"- `{item['actor']}` `{item['assetID']}` local index {item['frameIndex']} canvas {item['canvas']}")
        if index["duplicateTuples"]:
            lines += ["", "Duplicate tuples:", ""]
            for item in index["duplicateTuples"]:
                lines.append(f"- `{item['actor']}` `{item['assetID']}` local index {item['frameIndex']} repeated {item['count']} times")
    lines += ["", "## Runtime record contracts", ""]
    for check in report["runtimeCallsiteChecks"]:
        lines.append(f"- `{check['runtime']}`: {check['status']} (`{check['source']}`)")
    for row in report["tables"]:
        if row["unreachableRows"]:
            lines += ["", f"## Unreachable rows: {row['actor']}", ""]
            for bad in row["unreachableRows"]:
                lines.append(f"- Row {bad['row']}: `{bad['assetID']}` registered index {bad['registeredIndex']}, reachable {bad['reachableIndicesForAsset']}; canvas {bad['canvas']}")
    lines += ["", "## Erratum: NOIR landmark R001", "",
              "`noir_frame_landmarks_r001.json` stores source suffix/global pose numbering as `runtimeFrameIndex` for rest and attack, although `PartyAuthoredMotion.play` records each three-frame clip-local index (0–2). For example, `GeneratedArt/PartyAttack/NOIR__attack_04.png` is execute clip index 1, not 4. This yields 12 unreachable rest/attack rows. Its walk rows already distinguish source suffix from runtime enumeration (`NOIR__walk_2.png` is runtime index 1), so walk is not part of this erratum. Strict `(assetID, frameIndex, canvas)` lookup falls through to the unverified fallback for the 12 bad rows. R002 is audited separately and this tool does not rewrite it.", "",
              "The status measures tuple reachability only. It does not prove visual fit, masking quality, completeness, or Human approval.", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", type=Path)
    parser.add_argument("--markdown", type=Path)
    parser.add_argument("--runtime-index", type=Path,
                        help="also compare merged frame-registration tuples in this bundle Art/runtime_index.json")
    args = parser.parse_args()
    report = audit()
    if args.runtime_index:
        report["bundleRuntimeIndexAudit"] = audit_runtime_index(ROOT, args.runtime_index)
        report["schema"] = "runtime_frame_registration_audit_r002"
    text = markdown(report)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if args.markdown:
        args.markdown.parent.mkdir(parents=True, exist_ok=True)
        args.markdown.write_text(text)
    print(text)
    failures = any(t["status"] == "FAIL" for t in report["tables"]) or any(c["status"] == "FAIL" for c in report["runtimeCallsiteChecks"])
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

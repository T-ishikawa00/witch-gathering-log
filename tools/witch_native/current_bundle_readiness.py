#!/usr/bin/env python3
"""Build a read-only, current-bundle asset path/hash/clip ledger.

This describes files in one supplied .app bundle. Presence, valid bytes, and
runtime-index declarations are technical checks only; they do not imply visual
quality, animation acceptance, Human approval, or player-facing integration.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import wave
from collections import Counter
from pathlib import Path
from typing import Any

STATES = ("idle", "walk", "anticipate", "execute", "recover", "hit", "resolve")
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".gif"}
ROOT = Path(__file__).resolve().parents[2]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def resolve_asset(app: Path, rel: str) -> Path | None:
    normalized = rel.replace("\\", "/").lstrip("/")
    for candidate in (app / "Art" / normalized, app / normalized):
        if candidate.is_file():
            return candidate
    return None


def unique_refs(value: Any, prefix: str = ""):
    if isinstance(value, dict):
        for key, child in value.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            if isinstance(child, str) and Path(child).suffix.lower() in IMAGE_SUFFIXES:
                yield path, child
            else:
                yield from unique_refs(child, path)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from unique_refs(child, f"{prefix}[{index}]")
    elif isinstance(value, str) and Path(value).suffix.lower() in IMAGE_SUFFIXES:
        # Animation frame arrays contain strings directly. Omitting this branch
        # hid most clip references and actors without a separate still image.
        yield prefix, value


def decode_image(path: Path) -> dict[str, Any]:
    try:
        from PIL import Image
    except ImportError:
        return {"status": "UNKNOWN_PIL_UNAVAILABLE"}
    try:
        with Image.open(path) as image:
            image.verify()
        with Image.open(path) as image:
            image.load()
            return {"status": "PASS", "format": image.format, "width": image.width, "height": image.height, "mode": image.mode}
    except Exception as exc:  # preserve error class/message as technical evidence
        return {"status": "FAIL", "error": f"{type(exc).__name__}: {exc}"}


def state_frames(entry: dict[str, Any] | None, state: str) -> list[str]:
    if not isinstance(entry, dict):
        return []
    clips = entry.get("clips") if isinstance(entry.get("clips"), dict) else {}
    clip = clips.get(state)
    if isinstance(clip, dict) and isinstance(clip.get("frames"), list):
        return [path for path in clip["frames"] if isinstance(path, str)]
    sequence = entry.get("sequenceFrames") if isinstance(entry.get("sequenceFrames"), dict) else {}
    frames = sequence.get(state)
    if isinstance(frames, list):
        return [path for path in frames if isinstance(path, str)]
    poses = entry.get("selectedPNG") if isinstance(entry.get("selectedPNG"), dict) else {}
    pose_path = poses.get(state)
    return [pose_path] if isinstance(pose_path, str) else []


def is_supporting_reference(field: str, path: str) -> bool:
    # Renderer-selected fields remain runtime inputs even if the historical
    # filename contains "review". R015 routes the existing area previews.
    if field == "selectedPNG" or field.startswith(("selectedPNG.", "sceneLayers[", "layers[")):
        return False
    # S02's replacement preserves old selection and source-frame provenance in
    # metadata. The renderer consumes the root selectedPNG and runtimeBodyAssetID,
    # not the superseded PNG or source-workspace path.
    if field.startswith("supersedesCandidate.") or field.rsplit(".", 1)[-1] == "sourcePath":
        return True
    value = (field + " " + path).lower()
    # These fields are source-review photographs/zooms, never renderer paths.
    # Match the metadata field, not an arbitrary filename containing evidence.
    if any(token in field.lower() for token in ("sourceevidence", "sourcemarkerevidence")):
        return True
    return any(token in value for token in ("qa", "review", "contact", "sourcepng", "source_path", "originalsource", "parts.files")) or Path(path).is_absolute()


def registered_pose_contracts(app: Path, entry: dict[str, Any] | None) -> dict[str, Any]:
    """Report the selected pose override, not an older rig clip hidden beneath it.

    This is declaration and resource evidence only. Runtime/visual acceptance
    remains a separate Simulator and Human review obligation.
    """
    out = {}
    if not isinstance(entry, dict):
        return out
    for state, clip in (entry.get("clips") or {}).items():
        if not isinstance(clip, dict) or clip.get("mode") != "registered_keyposes_v1":
            continue
        poses = clip.get("registeredPoses", [])
        paths = [pose.get("path") for pose in poses if isinstance(pose, dict)]
        timeline = clip.get("poseTimeline", [])
        assets = []
        for path in paths:
            asset = resolve_asset(app, path) if isinstance(path, str) else None
            assets.append({"path":path,"present":asset is not None,
                           "sha256":sha256(asset) if asset else None})
        out[state] = {"mode":"registered_keyposes_v1", "declaredPoseCount":len(poses),
                      "timelineKeyCount":len(timeline), "duration":clip.get("duration"),
                      "dissolveSeconds":clip.get("dissolveSeconds"), "poseAssets":assets,
                      "declaredAndFilesPresent":bool(poses) and len(paths)==len(poses)
                        and bool(timeline) and all(row["present"] for row in assets),
                      "runtimePlaybackVerifiedByThisAudit":False, "naturalMotionApproved":False}
    return out


def effective_enemy_states(app: Path, entry: dict[str, Any] | None) -> tuple[dict[str, bool], dict[str, Any] | None]:
    result = {state: bool(state_frames(entry, state)) for state in STATES}
    if not isinstance(entry, dict) or not isinstance(entry.get("partRig"), str):
        return result, None
    rig_path = resolve_asset(app, entry["partRig"])
    if not rig_path:
        return result, {"path": entry["partRig"], "present": False}
    try:
        document = read_json(rig_path)
    except Exception as exc:
        return result, {"path": entry["partRig"], "present": True, "parseError": f"{type(exc).__name__}: {exc}"}
    clips = document.get("clips", {}) if isinstance(document.get("clips"), dict) else {}
    registered = registered_pose_contracts(app, entry)
    for state in STATES:
        result[state] = (registered[state]["declaredAndFilesPresent"] if state in registered
                         else state in clips or (state == "walk" and "flight" in clips))
    part_rows = []
    for part in document.get("parts", []):
        if not isinstance(part, dict) or not isinstance(part.get("path"), str):
            continue
        asset = resolve_asset(app, part["path"])
        part_rows.append({"id": part.get("id"), "path": part["path"], "present": asset is not None, "bundlePath": asset.relative_to(app).as_posix() if asset else None, "sha256": sha256(asset) if asset else None})
    walk_override = (entry.get("clips") or {}).get("walk", {})
    walk_contract = None
    if walk_override.get("mode") == "part_rig_leg_overlay_candidate_v1":
        paths = walk_override.get("frame_paths", [])
        walk_contract = {
            "mode": walk_override["mode"], "status": walk_override.get("status"),
            "bodyPartID": walk_override.get("body_part_id"),
            "fps": walk_override.get("fps"), "canvas": walk_override.get("canvas_px"),
            "framePaths": paths, "allFrameFilesPresent": bool(paths) and all(resolve_asset(app, p) for p in paths),
            "maskPolygonCount": len(walk_override.get("mask_polygons_px", [])),
            "scope": "Declaration and file presence only; mask fit, state routing and naturalness require runtime review.",
        }
    return result, {
        "path": entry["partRig"],
        "present": True,
        "status": document.get("status"),
        "humanApproval": document.get("human_approval", document.get("humanApproval")),
        "fps": document.get("fps"),
        "clipNames": sorted(clips),
        "partAssets": part_rows,
        "walkLegOverlay": walk_contract,
    }


def file_category(rel: str) -> str:
    parts = rel.split("/")
    low = rel.lower()
    if "audio" in low or Path(rel).suffix.lower() in {".caf", ".wav", ".mp3", ".m4a", ".aiff"}:
        return "audio"
    if any(f"generatedart/{name}" in low for name in ("partywalk", "partyrest", "partyattack", "partymotion")):
        return "party_animation"
    if "generatedart/layeredmotion" in low or "generatedart/weaponlayers" in low:
        return "layered_character_or_weapon"
    if "background" in low or "scene" in low or "area" in low:
        return "background_or_scene"
    if "effect" in low:
        return "effect"
    if "gearicon" in low or "materialicon" in low:
        return "inventory_icon"
    if "furniture" in low:
        return "furniture"
    if "costume" in low or "appearance" in low or "wardrobe" in low:
        return "appearance"
    if "generatedcandidates" in low or "actorstills" in low or "characters/" in low:
        return "character_or_enemy_art"
    if parts[0] == "GeneratedArt":
        return "generated_art_other"
    return "other"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True, help="Current .app bundle to audit")
    parser.add_argument("--out", type=Path, required=True, help="JSON output path")
    parser.add_argument("--label", default=None, help="Optional build label; never used as evidence")
    args = parser.parse_args()
    app = args.app.resolve()
    if not app.is_dir() or app.suffix != ".app":
        raise SystemExit(f"--app must name an existing .app bundle: {app}")
    index_path = app / "Art" / "runtime_index.json"
    catalog_path = app / "catalog_overlay.json"
    if not index_path.is_file():
        raise SystemExit(f"runtime index missing: {index_path}")
    runtime = read_json(index_path)
    catalog = read_json(catalog_path) if catalog_path.is_file() else {}
    receipt_path = app.parent / "BUILD_RECEIPT.json"
    receipt = read_json(receipt_path) if receipt_path.is_file() else {}
    declared_hashes = receipt.get("resource_sha256", {})

    inventory: list[dict[str, Any]] = []
    by_rel: dict[str, dict[str, Any]] = {}
    for path in sorted(p for p in app.rglob("*") if p.is_file()):
        rel = path.relative_to(app).as_posix()
        if rel.startswith("_CodeSignature/"):
            continue
        row: dict[str, Any] = {
            "path": rel,
            "bytes": path.stat().st_size,
            "sha256": sha256(path),
            "category": file_category(rel),
        }
        if path.suffix.lower() in IMAGE_SUFFIXES:
            row["image"] = decode_image(path)
        receipt_digest = declared_hashes.get(rel)
        if receipt_digest:
            row["buildReceiptSHA256"] = receipt_digest
            row["matchesBuildReceipt"] = row["sha256"] == receipt_digest
        inventory.append(row)
        by_rel[rel] = row

    entry_rows: list[dict[str, Any]] = []
    missing_refs: list[dict[str, str]] = []
    unresolved_supporting_refs: list[dict[str, str]] = []
    png_refs = 0
    for stable_id, entry in sorted(runtime.get("entries", {}).items()):
        refs = []
        for location, source_path in unique_refs(entry):
            resolved = resolve_asset(app, source_path)
            row = {
                "field": location,
                "indexPath": source_path,
                "bundlePath": resolved.relative_to(app).as_posix() if resolved else None,
                "present": resolved is not None,
                "referenceRole": "supporting_or_source_reference" if is_supporting_reference(location, source_path) else "runtime_asset_candidate",
            }
            if resolved:
                row["sha256"] = by_rel[resolved.relative_to(app).as_posix()]["sha256"]
                row["bytes"] = by_rel[resolved.relative_to(app).as_posix()]["bytes"]
                if resolved.suffix.lower() == ".png":
                    row["pngDecode"] = by_rel[resolved.relative_to(app).as_posix()].get("image", {}).get("status", "UNKNOWN")
                    png_refs += 1
                else:
                    row["imageDecode"] = by_rel[resolved.relative_to(app).as_posix()].get("image", {}).get("status", "UNKNOWN")
            else:
                unresolved = {"stableID": stable_id, "field": location, "indexPath": source_path}
                if row["referenceRole"] == "supporting_or_source_reference":
                    unresolved_supporting_refs.append(unresolved)
                else:
                    missing_refs.append(unresolved)
            refs.append(row)
        if isinstance(entry.get("partRig"), str):
            rig_path = resolve_asset(app, entry["partRig"])
            rig_row = {"field": "partRig", "indexPath": entry["partRig"], "bundlePath": rig_path.relative_to(app).as_posix() if rig_path else None, "present": rig_path is not None, "referenceRole": "runtime_asset_candidate"}
            if rig_path:
                rig_row.update({"sha256": sha256(rig_path), "bytes": rig_path.stat().st_size})
                try:
                    rig_document = read_json(rig_path)
                    for index, part in enumerate(rig_document.get("parts", [])):
                        part_path = part.get("path") if isinstance(part, dict) else None
                        if not isinstance(part_path, str):
                            continue
                        asset = resolve_asset(app, part_path)
                        part_row = {"field": f"partRig.parts[{index}].path", "indexPath": part_path, "bundlePath": asset.relative_to(app).as_posix() if asset else None, "present": asset is not None, "referenceRole": "runtime_asset_candidate"}
                        if asset:
                            part_row.update({"sha256": by_rel[asset.relative_to(app).as_posix()]["sha256"], "bytes": asset.stat().st_size, "pngDecode": by_rel[asset.relative_to(app).as_posix()].get("image", {}).get("status", "UNKNOWN")})
                        else:
                            missing_refs.append({"stableID": stable_id, "field": part_row["field"], "indexPath": part_path})
                        refs.append(part_row)
                except Exception:
                    pass
            else:
                missing_refs.append({"stableID": stable_id, "field": "partRig", "indexPath": entry["partRig"]})
            refs.append(rig_row)
        clips = entry.get("clips", {}) if isinstance(entry.get("clips"), dict) else {}
        state_rows = {}
        for state in STATES:
            clip = clips.get(state)
            frames = clip.get("frames", []) if isinstance(clip, dict) else (entry.get("sequenceFrames", {}).get(state, []) if isinstance(entry.get("sequenceFrames"), dict) else [])
            if not frames and isinstance(entry.get("selectedPNG"), dict):
                pose = entry["selectedPNG"].get(state)
                frames = [pose] if isinstance(pose, str) else []
            state_rows[state] = {
                "declared": bool(frames),
                "frameCountDeclared": clip.get("frame_count", len(frames)) if isinstance(clip, dict) else len(frames),
                "fps": clip.get("fps") if isinstance(clip, dict) else entry.get("fps"),
                "durationSeconds": clip.get("duration_seconds") if isinstance(clip, dict) else None,
                "loop": clip.get("loop") if isinstance(clip, dict) else None,
                "clipStatus": clip.get("status") if isinstance(clip, dict) else None,
                "referencedPathCount": len(frames),
                "allReferencedPathsPresent": bool(frames) and all(resolve_asset(app, f) is not None for f in frames),
                "distinctSHA256Count": len({by_rel[resolve_asset(app, f).relative_to(app).as_posix()]["sha256"] for f in frames if resolve_asset(app, f)}),
            }
        entry_rows.append({
            "id": stable_id,
            "kind": entry.get("kind"),
            "runtimeStatus": entry.get("status"),
            "selectedPNG": entry.get("selectedPNG"),
            "declaredStates": entry.get("states_present", []),
            "stateCoverage": state_rows,
            "pathReferences": refs,
        })

    enemies = catalog.get("enemies", [])
    gear = catalog.get("gear", [])
    materials = catalog.get("materialIDs", [])
    regions = catalog.get("regions", [])
    appearances = catalog.get("appearances", [])
    furniture_ids = catalog.get("furnitureIDs", [])
    entries = runtime.get("entries", {})
    runtime_counts = Counter(entry.get("kind", "unknown") for entry in entries.values())
    required_by_enemy = []
    for enemy in enemies:
        actor_id = "ACT_" + enemy["id"]
        entry = entries.get(actor_id)
        effective_states, part_rig = effective_enemy_states(app, entry)
        required_by_enemy.append({
            "enemyID": enemy["id"], "regionID": enemy.get("regionID"), "boss": enemy.get("boss", False),
            "runtimeEntryPresent": entry is not None,
            "stateCoverage": effective_states,
            "partRigContract": part_rig,
            "registeredPoseOverrides": registered_pose_contracts(app, entry),
            "entryStatus": (entry or {}).get("status"),
        })
    backgrounds = []
    for region in regions:
        rid = region["id"]
        for kind in ("FIELD", "BOSS"):
            stable_id = f"BG_{rid}_{kind}"
            entry = entries.get(stable_id)
            refs = [row for row in (entry_rows and next((x["pathReferences"] for x in entry_rows if x["id"] == stable_id), []))]
            backgrounds.append({"regionID": rid, "kind": kind.lower(), "entryID": stable_id, "entryPresent": entry is not None, "selectedPNG": (entry or {}).get("selectedPNG"), "pathReferences": refs, "runtimeStatus": (entry or {}).get("status")})

    index_refs = [
        {"stableID": row["id"], "kind": row["kind"], **ref}
        for row in entry_rows for ref in row["pathReferences"]
    ]
    generated_manifests = []
    generated_motion_clips = []
    for manifest in sorted((app / "GeneratedArt").rglob("MANIFEST.json")):
        try:
            document = read_json(manifest)
            manifest_rel = manifest.relative_to(app).as_posix()
            generated_manifests.append({"path": manifest_rel, "sha256": sha256(manifest), "document": document})
            folder = manifest.parent.name.lower()
            if folder not in {"partyattack", "partyrest", "layeredmotion"} or not isinstance(document, dict):
                continue
            for entity_id, entity in sorted(document.items()):
                if not isinstance(entity, dict):
                    continue
                if folder == "layeredmotion":
                    clips = {key: value for key, value in entity.items() if isinstance(value, dict) and isinstance(value.get("frames"), list)}
                else:
                    clips = entity.get("clips", {}) if isinstance(entity.get("clips"), dict) else {}
                for state, clip in sorted(clips.items()):
                    if not isinstance(clip, dict) or not isinstance(clip.get("frames"), list):
                        continue
                    frame_rows = []
                    for index, frame in enumerate(clip["frames"]):
                        frame_path = frame.get("path") if isinstance(frame, dict) else frame
                        asset = manifest.parent / frame_path if isinstance(frame_path, str) else None
                        frame_row = {"index": index, "path": frame_path, "present": bool(asset and asset.is_file())}
                        if asset and asset.is_file():
                            frame_row.update({"bundlePath": asset.relative_to(app).as_posix(), "bytes": asset.stat().st_size, "sha256": sha256(asset), "pngDecode": decode_image(asset).get("status") if asset.suffix.lower() == ".png" else None})
                        frame_rows.append(frame_row)
                    generated_motion_clips.append({
                        "manifest": manifest_rel,
                        "manifestSHA256": sha256(manifest),
                        "entityID": entity_id,
                        "state": state,
                        "candidateStatus": clip.get("status", entity.get("status")),
                        "humanApproval": entity.get("humanApproval", entity.get("human_approval")),
                        "naturalMotionComplete": entity.get("naturalMotionComplete", False),
                        "frameCountDeclared": len(clip["frames"]),
                        "fps": clip.get("fps", entity.get("fps")),
                        "durations": clip.get("durations"),
                        "loop": clip.get("loop"),
                        "allFramesPresent": bool(frame_rows) and all(row["present"] for row in frame_rows),
                        "allPNGFramesDecode": bool(frame_rows) and all(row.get("pngDecode") == "PASS" for row in frame_rows),
                        "frames": frame_rows,
                    })
        except Exception as exc:
            generated_manifests.append({"path": manifest.relative_to(app).as_posix(), "sha256": sha256(manifest), "parseError": f"{type(exc).__name__}: {exc}"})

    def file_matches(token: str) -> list[str]:
        needle = re.sub(r"[^a-z0-9]", "", token.lower())
        return [row["path"] for row in inventory if needle and needle in re.sub(r"[^a-z0-9]", "", row["path"].lower())]

    candidate_products = {
        "appearances": [{"id": row.get("id"), "kind": row.get("kind"), "catalogStatus": row.get("status"), "matchingBundlePaths": file_matches(row.get("id", ""))} for row in appearances],
        "furniture": [{"id": fid, "matchingBundlePaths": file_matches(fid)} for fid in furniture_ids],
    }
    music_coverage=[]
    music_manifest=app/'Music/MANIFEST.json'
    if music_manifest.is_file():
        for track in read_json(music_manifest).get('tracks',[]):
            path=app/'Music'/str(track.get('file',''))
            row={'id':track.get('id'),'path':path.relative_to(app).as_posix(),
                 'present':path.is_file(),'humanApproval':False,'runtimeVerifiedByThisAudit':False}
            if path.is_file():
                row['sha256']=sha256(path)
                row['matchesScoreManifest']=row['sha256']==track.get('sha256')
                try:
                    with wave.open(str(path),'rb') as wav:
                        row['pcm']={'channels':wav.getnchannels(),'sampleRate':wav.getframerate(),
                                    'sampleWidthBytes':wav.getsampwidth(),'frames':wav.getnframes(),
                                    'durationSeconds':wav.getnframes()/wav.getframerate()}
                except Exception as exc:row['decodeError']=str(exc)
            music_coverage.append(row)
    png_rows = [row for row in inventory if row["path"].lower().endswith(".png")]
    receipt_mismatches = [row["path"] for row in inventory if row.get("matchesBuildReceipt") is False]
    summary = {
        "bundleFileCount": len(inventory),
        "resourceReceiptPathCount": len(declared_hashes),
        "pngCount": len(png_rows),
        "pngDecodePassCount": sum(row.get("image", {}).get("status") == "PASS" for row in png_rows),
        "pngDecodeFailureCount": sum(row.get("image", {}).get("status") == "FAIL" for row in png_rows),
        "pngDecodeUnknownCount": sum(row.get("image", {}).get("status", "").startswith("UNKNOWN") for row in png_rows),
        "buildReceiptHashMismatchCount": len(receipt_mismatches),
        "runtimeEntryCount": len(entries),
        "runtimeCountsByKind": dict(runtime_counts),
        "runtimePNGReferenceCount": png_refs,
        "missingRuntimePathReferenceCount": len(missing_refs),
        "unresolvedSupportingReferenceCount": len(unresolved_supporting_refs),
        "enemyCatalogCount": len(enemies),
        "enemyRuntimeEntryCount": sum(row["runtimeEntryPresent"] for row in required_by_enemy),
        "enemySevenStateDeclaredCount": sum(all(row["stateCoverage"].values()) for row in required_by_enemy),
        "gearCatalogCount": len(gear),
        "gearRuntimeIconEntryCount": sum(f"ICO_{row['id']}" in entries for row in gear),
        "materialCatalogCount": len(materials),
        "materialRuntimeIconEntryCount": sum(f"ICO_{mid}" in entries for mid in materials),
        "regionCount": len(regions),
        "regionFieldBossEntriesPresentCount": sum(row["entryPresent"] for row in backgrounds),
        "appearanceCandidateCount": len(appearances),
        "furnitureCatalogCount": len(furniture_ids),
        "bundledAudioFileCount": sum(row["category"] == "audio" for row in inventory),
        "musicCandidateTrackCount": len(music_coverage),
        "musicCandidateHashMatchCount": sum(row.get('matchesScoreManifest') is True for row in music_coverage),
        "generatedMotionClipCount": len(generated_motion_clips),
        "generatedMotionFrameCount": sum(row["frameCountDeclared"] for row in generated_motion_clips),
        "generatedMotionClipsAllFramesPresentCount": sum(row["allFramesPresent"] for row in generated_motion_clips),
        "generatedMotionClipsAllPNGDecodeCount": sum(row["allPNGFramesDecode"] for row in generated_motion_clips),
        "generatedMotionHumanApprovedClipCount": sum(row["humanApproval"] is True for row in generated_motion_clips),
        "generatedMotionNaturallyCompleteClipCount": sum(row["naturalMotionComplete"] is True for row in generated_motion_clips),
        "missingRuntimeExamples": missing_refs[:100],
        "unresolvedSupportingReferenceExamples": unresolved_supporting_refs[:100],
        "receiptMismatchExamples": receipt_mismatches[:100],
        "interpretation": "File and metadata evidence only. It cannot certify quality, animation readability, runtime use, user approval, rights, store readiness, or Human playtesting.",
    }
    exe = app / "WitchGathering"
    app_hash = sha256(exe) if exe.is_file() else None
    receipt_hash_match = bool(app_hash and app_hash == receipt.get("executable_sha256"))
    output = {
        "schema": "current_bundle_readiness_r003",
        "auditMode": "READ_ONLY_CURRENT_APP_BUNDLE_INVENTORY",
        "authority": "TECHNICAL_BUNDLE_PRESENCE_AND_METADATA_ONLY_NOT_APPROVAL",
        "target": {"label": args.label, "app": str(app), "buildReceipt": str(receipt_path) if receipt_path.is_file() else None, "executableSHA256": app_hash, "executableMatchesBuildReceipt": receipt_hash_match, "runtimeIndexSHA256": sha256(index_path), "catalogSHA256": sha256(catalog_path) if catalog_path.is_file() else None, "runtimeIndexStatus": runtime.get("status"), "catalogAuthority": catalog.get("authority")},
        "summary": summary,
        "catalogCoverage": {"regions": regions, "enemies": required_by_enemy, "gear": gear, "materials": materials, "partyActorIDs": catalog.get("actors", []), "backgroundFieldBossEntries": backgrounds, "candidateProducts": candidate_products},
        "runtimeEntries": entry_rows,
        "indexedPathReferences": index_refs,
        "generatedAnimationManifests": generated_manifests,
        "generatedMotionClips": generated_motion_clips,
        "musicCandidateCoverage": music_coverage,
        "bundleFiles": inventory,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"out": str(args.out), "target": output["target"], "summary": summary}, ensure_ascii=False, indent=2))
    return 0 if receipt_hash_match and summary["pngDecodeFailureCount"] == 0 and not receipt_mismatches else 1


if __name__ == "__main__":
    raise SystemExit(main())

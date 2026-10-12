#!/usr/bin/env python3
"""Pinned AIRA held-frame captures with fixed-receipt preservation.

This driver deliberately requires --execute. It captures only the six named
single-detail frames, and is not a motion/naturalness acceptance test.
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib
import json
import os
import shutil
import stat
import subprocess
import sys
import time
import uuid
from pathlib import Path

BUNDLE_ID = "local.witch.autonomous.r1"
DEVICE_ID = "1D034CC3-9259-4AEE-A21D-E6E88D242ACF"
OVERLAY_POINT_EXPECTATIONS = {
    "runtime_overlay_aira_attack05_boot_r013.json": {
        ("GeneratedArt/PartyAttack/AIRA__attack_04.png", 1): [148, 210],
        ("GeneratedArt/PartyAttack/AIRA__attack_05.png", 2): [155, 223],
        ("GeneratedArt/PartyAttack/AIRA__attack_06.png", 0): [144, 210],
    },
    "runtime_overlay_aira_attack04_06_boot_r014.json": {
        ("GeneratedArt/PartyAttack/AIRA__attack_04.png", 1): [155, 223],
        ("GeneratedArt/PartyAttack/AIRA__attack_05.png", 2): [155, 223],
        ("GeneratedArt/PartyAttack/AIRA__attack_06.png", 0): [154, 222],
    },
}
EXPECTED_CASES = [
    ("FEET01_execute2", "EQ_FEET_01", "execute:2"),
    ("FEET02_execute2", "EQ_FEET_02", "execute:2"),
    ("FEET03_execute2", "EQ_FEET_03", "execute:2"),
    ("FEET03_execute1", "EQ_FEET_03", "execute:1"),
    ("FEET03_recover0", "EQ_FEET_03", "recover:0"),
    ("AMU03_execute2_control", "EQ_AMU_03", "execute:2"),
]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def fixed_receipt_paths(support: Path) -> list[Path]:
    paths = {p for p in support.glob("last_*.json") if p.is_file()}
    for name in ("battle_before.json", "runtime_metrics.json"):
        path = support / name
        if path.is_file():
            paths.add(path)
    return sorted(paths)


def file_record(path: Path) -> dict:
    before = path.stat()
    content = path.read_bytes()
    # Read-only inspection should not leave an atime delta in the Simulator's
    # fixed receipt directory.
    os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
    return {
        "name": path.name,
        "size": len(content),
        "sha256": sha256_bytes(content),
        "mode": stat.S_IMODE(before.st_mode),
        "mtime_ns": before.st_mtime_ns,
        "atime_ns": before.st_atime_ns,
    }


def snapshot_support(support: Path, destination: Path) -> dict:
    destination.mkdir(parents=True, exist_ok=True)
    items = []
    for path in fixed_receipt_paths(support):
        record = file_record(path)
        shutil.copy2(path, destination / path.name)
        os.utime(path, ns=(record["atime_ns"], record["mtime_ns"]))
        items.append(record)
    return {"support": str(support), "files": items}


def restore_file(source: Path, target: Path, record: dict) -> dict:
    raw = source.read_bytes()
    temp = target.with_name(target.name + ".restore-" + uuid.uuid4().hex)
    try:
        temp.write_bytes(raw)
        os.chmod(temp, record["mode"])
        os.replace(temp, target)
        os.utime(target, ns=(record["atime_ns"], record["mtime_ns"]))
        content_hash = sha256_file(target)
        os.chmod(target, record["mode"])
        os.utime(target, ns=(record["atime_ns"], record["mtime_ns"]))
        observed = target.stat()
        restored_hash = content_hash == record["sha256"]
        restored_metadata = (
            stat.S_IMODE(observed.st_mode) == record["mode"]
            and observed.st_mtime_ns == record["mtime_ns"]
            and observed.st_atime_ns == record["atime_ns"]
        )
        return {
            "name": target.name,
            "sha256": content_hash,
            "shaMatches": restored_hash,
            "mode": stat.S_IMODE(observed.st_mode),
            "modeMatches": stat.S_IMODE(observed.st_mode) == record["mode"],
            "mtime_ns": observed.st_mtime_ns,
            "mtimeMatches": observed.st_mtime_ns == record["mtime_ns"],
            "atime_ns": observed.st_atime_ns,
            "atimeMatches": observed.st_atime_ns == record["atime_ns"],
            "metadataMatches": restored_metadata,
        }
    finally:
        if temp.exists():
            temp.unlink()


def inspect_app(app: Path, expected_executable: str, expected_runtime_index: str,
                expected_build_receipt: str, overlay_path: Path,
                expected_overlay: str) -> dict:
    receipt_path = app.parent / "BUILD_RECEIPT.json"
    receipt_raw = receipt_path.read_bytes()
    receipt = json.loads(receipt_raw)
    executable = app / "WitchGathering"
    runtime_index = app / "Art/runtime_index.json"
    overlay_path = overlay_path.resolve()
    actual_executable = sha256_file(executable)
    actual_runtime_index = sha256_file(runtime_index)
    actual_overlay = sha256_file(overlay_path)
    if sha256_bytes(receipt_raw) != expected_build_receipt:
        raise ValueError("BUILD_RECEIPT SHA does not match supplied frozen pin")
    if receipt.get("status") != "SIMULATOR_BUILD_PASS" or Path(receipt.get("bundle", "")).resolve() != app:
        raise ValueError("App bundle is not the bundle in a passing simulator build receipt")
    if actual_executable != expected_executable or receipt.get("executable_sha256") != expected_executable:
        raise ValueError("Executable SHA differs from expected and receipt pins")
    if actual_runtime_index != expected_runtime_index or receipt.get("resource_sha256", {}).get("Art/runtime_index.json") != expected_runtime_index:
        raise ValueError("Runtime index SHA differs from expected and receipt pins")
    if actual_overlay != expected_overlay:
        raise ValueError("AIRA source overlay SHA differs from supplied pin")
    expected_points = OVERLAY_POINT_EXPECTATIONS.get(overlay_path.name)
    if expected_points is None:
        raise ValueError("Unsupported AIRA overlay revision; refusing unreviewed point expectations")
    index = json.loads(runtime_index.read_text())
    rows = index["entries"]["AIRA"]["semanticFrameLandmarksCandidate"]["rows"]
    selected_rows = []
    for (body_asset_id, frame_index), expected_point in expected_points.items():
        selected = [r for r in rows if r.get("bodyAssetID") == body_asset_id and r.get("frameIndex") == frame_index]
        if len(selected) != 1:
            raise ValueError(f"Frozen runtime index must contain exactly one {body_asset_id} frameIndex={frame_index} row")
        landmark = selected[0].get("landmarks_px_top_left", {}).get("screenRightBootCuff")
        if landmark != expected_point:
            raise ValueError(f"Frozen runtime point mismatch for {body_asset_id} frameIndex={frame_index}: {landmark}")
        selected_rows.append({"bodyAssetID": body_asset_id, "frameIndex": frame_index,
                              "screenRightBootCuff": landmark})
    return {
        "buildReceiptPath": str(receipt_path),
        "buildReceiptSHA256": sha256_bytes(receipt_raw),
        "buildReceiptStatus": receipt["status"],
        "executableSHA256": actual_executable,
        "runtimeIndexSHA256": actual_runtime_index,
        "overlayPath": str(overlay_path),
        "overlaySHA256": actual_overlay,
        "expectedOverlayPoints": selected_rows,
        "sourceSHA256MapSHA256": sha256_bytes(json.dumps(receipt.get("source_sha256", {}), sort_keys=True, separators=(",", ":")).encode()),
    }


def container_support(device: str) -> Path:
    container = Path(run("xcrun", "simctl", "get_app_container", device, BUNDLE_ID, "data"))
    return container / "Library/Application Support/Witch03to05R1"


def execute_case(a, audit_module, case_dir: Path, gear: str, frame: str) -> dict:
    fixture = "detail-item-C_SMITH-" + gear
    original_argv = sys.argv
    args = [
        "party_frame_audit.py", "--app", str(a.app), "--output", str(case_dir),
        "--device", a.device, "--fixture", fixture, "--actor", "AIRA", "--frames", frame,
    ]
    # Keep the helper's per-case output directory absent so its own
    # `mkdir(exist_ok=False)` remains a useful freshness guard.
    output_path = case_dir.parent / (case_dir.name + ".driver.log")
    exit_code = 0
    started = time.time()
    try:
        # The wrapper has already installed and pinned the app. Bypass only the
        # helper's repeated install call so fixed receipts cannot migrate again.
        helper_run = audit_module.run
        def no_reinstall(*cmd):
            if tuple(cmd[:3]) == ("xcrun", "simctl", "install"):
                return "INSTALL_SKIPPED_AFTER_PINNED_WRAPPER_INSTALL"
            return helper_run(*cmd)
        audit_module.run = no_reinstall
        sys.argv = args
        with output_path.open("w", encoding="utf-8") as stream, contextlib.redirect_stdout(stream), contextlib.redirect_stderr(stream):
            try:
                audit_module.main()
            except SystemExit as exc:
                exit_code = int(exc.code or 0)
    finally:
        audit_module.run = helper_run
        sys.argv = original_argv
    result_path = case_dir / "RUN.json"
    result = json.loads(result_path.read_text()) if result_path.exists() else None
    return {
        "fixture": fixture,
        "frame": frame,
        "exitCode": exit_code,
        "startedAtEpoch": started,
        "log": output_path.name,
        "runReceiptPresent": result is not None,
        "runStatus": result.get("status") if result else None,
        "case": result.get("cases", [None])[0] if result and result.get("cases") else None,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--expected-executable-sha256", required=True)
    parser.add_argument("--expected-runtime-index-sha256", required=True)
    parser.add_argument("--expected-build-receipt-sha256", required=True)
    parser.add_argument("--overlay-path", type=Path, required=True,
                        help="Exact workspace overlay path (R013 or R014 reviewed candidate only)")
    parser.add_argument("--expected-overlay-sha256", required=True)
    parser.add_argument("--execute", action="store_true", help="Explicitly permit the six Simulator launches after parent releases the device")
    a = parser.parse_args()
    if not a.execute:
        parser.error("refusing to launch Simulator without explicit --execute")
    if a.device != DEVICE_ID:
        parser.error("this bounded capture is pinned to the released 1D Simulator only")
    app = a.app.resolve()
    output = a.output.resolve()
    if output.exists():
        parser.error("output path must be new; prior attempts are preserved")
    output.mkdir(parents=True, exist_ok=False)
    run_id = str(uuid.uuid4())
    report = {
        "runID": run_id,
        "startedAtUTC": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "scope": "SINGLE_DETAIL_EXACT_HELD_FRAMES; NOT_MOTION_OR_NATURALNESS_ACCEPTANCE",
        "device": a.device,
        "app": str(app),
        "cases": [],
        "fixedReceiptSnapshots": [],
        "retainedNewReceipts": [],
    }
    failure = None
    restoration_errors = []
    snapshots: dict[str, dict] = {}
    backup_roots: dict[str, Path] = {}
    try:
        report["appPins"] = inspect_app(app, a.expected_executable_sha256,
                                        a.expected_runtime_index_sha256,
                                        a.expected_build_receipt_sha256,
                                        a.overlay_path,
                                        a.expected_overlay_sha256)
        audit_module = importlib.import_module("party_frame_audit")
        # Preserve currently installed app receipts before replacement, then
        # install the frozen app and snapshot its active container as well.
        try:
            previous = container_support(a.device)
            key = str(previous.resolve())
            backup = output / "fixed_receipts_before" / hashlib.sha256(key.encode()).hexdigest()[:12]
            snapshots[key] = snapshot_support(previous, backup)
            backup_roots[key] = backup
        except subprocess.CalledProcessError:
            report["preInstallContainer"] = "NO_INSTALLED_CONTAINER"
        run("xcrun", "simctl", "install", a.device, str(app))
        active = container_support(a.device)
        active_key = str(active.resolve())
        if active_key not in snapshots:
            backup = output / "fixed_receipts_before" / hashlib.sha256(active_key.encode()).hexdigest()[:12]
            snapshots[active_key] = snapshot_support(active, backup)
            backup_roots[active_key] = backup
        report["supportDirAfterInstall"] = active_key
        report["fixedReceiptSnapshots"] = list(snapshots.values())
        (output / "RUN.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
        for case_name, gear, frame in EXPECTED_CASES:
            # Re-snapshot any active app container before each QA invocation.
            support = container_support(a.device)
            support_key = str(support.resolve())
            if support_key not in snapshots:
                backup = output / "fixed_receipts_before" / hashlib.sha256(support_key.encode()).hexdigest()[:12]
                snapshots[support_key] = snapshot_support(support, backup)
                backup_roots[support_key] = backup
            result = execute_case(a, audit_module, output / case_name, gear, frame)
            report["cases"].append({"id": case_name, "gearID": gear, "result": result})
            (output / "RUN.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
            print(case_name, "PASS" if result["exitCode"] == 0 and result["runStatus"] == "CAPTURED_REQUIRES_VISUAL_FIT_REVIEW" else "FAIL", flush=True)
    except Exception as exc:
        failure = repr(exc)
        report["driverError"] = failure
    finally:
        # Preserve every receipt now present before restoring old fixed values.
        post_snapshots = {}
        try:
            active_after = container_support(a.device)
            active_after_key = str(active_after.resolve())
        except Exception as exc:
            active_after = None
            active_after_key = None
            restoration_errors.append("could not identify active post-run support directory: " + repr(exc))
        support_targets = {str(Path(key)): Path(key) for key in snapshots}
        if active_after is not None:
            support_targets[active_after_key] = active_after
        for support_key, support in support_targets.items():
            post_dir = output / "fixed_receipts_after" / hashlib.sha256(support_key.encode()).hexdigest()[:12]
            post = snapshot_support(support, post_dir) if support.exists() else {"support": support_key, "files": []}
            post_snapshots[support_key] = post
        # Restore each original snapshot to its existing container when it
        # remains. If iOS replaced the data-container UUID during install,
        # redirect the old snapshot to the active container instead of
        # recreating an obsolete container directory. Earliest (pre-install)
        # values win for duplicate names; post-install-only values fill gaps.
        restore_jobs = {}
        original_support_keys = list(snapshots)
        for support_key in original_support_keys:
            before = snapshots[support_key]
            original_support = Path(support_key)
            target_support = original_support if original_support.exists() else active_after
            if target_support is None:
                restoration_errors.append("no valid restore target for support directory " + support_key)
                continue
            target_key = str(target_support.resolve())
            if target_key != support_key:
                report.setdefault("containerMigration", []).append({
                    "fromSupport": support_key,
                    "toActiveSupport": target_key,
                    "reason": "original data-container path no longer exists after app install",
                })
            for record in before["files"]:
                restore_jobs.setdefault((target_key, record["name"]), (backup_roots[support_key] / record["name"], target_support, record, support_key))
        for support_key, post in post_snapshots.items():
            for record in post["files"]:
                restore_jobs.setdefault((support_key, record["name"]), (None, Path(support_key), record, support_key))
        for (target_key, name), (backup, support, record, origin_key) in restore_jobs.items():
            target = support / name
            try:
                if backup is None:
                    # Post-install-only file: it was not present in any
                    # preflight snapshot and must remain untouched.
                    report["retainedNewReceipts"].append({"support": target_key, **file_record(target)})
                    continue
                if not target.parent.exists():
                    # Do not recreate an obsolete simulator UUID container.
                    restoration_errors.append("restore target directory vanished: " + str(target.parent))
                    continue
                restored = restore_file(backup, target, record)
                report.setdefault("restoration", []).append({
                    "support": target_key,
                    "restoredFromSupport": origin_key,
                    **restored,
                })
            except Exception as exc:
                restoration_errors.append(str(target) + ": " + repr(exc))
        report["postRunFixedReceiptSnapshots"] = list(post_snapshots.values())
        report["restorationErrors"] = restoration_errors
        report["fixedReceiptRestorePass"] = not restoration_errors and bool(report.get("restoration")) and all(item.get("shaMatches") and item.get("metadataMatches") for item in report.get("restoration", []))
        report["status"] = "CAPTURED_REQUIRES_VISUAL_FIT_REVIEW" if not failure and len(report["cases"]) == len(EXPECTED_CASES) and all(c["result"]["exitCode"] == 0 and c["result"]["runStatus"] == "CAPTURED_REQUIRES_VISUAL_FIT_REVIEW" for c in report["cases"]) and report["fixedReceiptRestorePass"] else "FAILED"
        report["humanApproved"] = False
        report["naturalMotionComplete"] = False
        (output / "RUN.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["status"] == "CAPTURED_REQUIRES_VISUAL_FIT_REVIEW" else 1


if __name__ == "__main__":
    raise SystemExit(main())

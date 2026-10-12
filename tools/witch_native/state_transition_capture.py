#!/usr/bin/env python3
"""Capture the existing native seven-state enemy art-audit route safely.

This is an isolated iOS Simulator capture only. It does not synthesize states,
change the QA route, or establish naturalness/product acceptance.
"""
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time
import uuid

from loop_boundary_capture import inspect_build_receipt

BUNDLE = "local.witch.autonomous.r1"
DEVICE = "1D034CC3-9259-4AEE-A21D-E6E88D242ACF"
STATES = ("idle", "walk", "anticipate", "execute", "recover", "hit", "resolve")
FIXED_GLOBS = ("last_art*.json",)
FIXED_NAMES = ("last_registered_render_preparation.json", "runtime_metrics.json")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def atomic_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp-" + uuid.uuid4().hex)
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    os.replace(tmp, path)


def command(*args: str, timeout: float = 30) -> str:
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"command exit {result.returncode}: {args!r}\n{result.stdout[-4000:]}")
    return result.stdout.strip()


def final_screenshot_command(device: str, destination: Path) -> list[str]:
    """Use simctl's device-scoped screenshot subcommand, like per-state captures."""
    return ["xcrun", "simctl", "io", device, "screenshot", str(destination)]


def completion_checks(actors: list[str], cases: list[dict], captures: dict[str, dict],
                      receipts_restored: bool) -> dict[str, object]:
    expected = len(actors)
    cases_complete = (expected > 0 and len(cases) == expected and
                      [row.get("actorID") for row in cases] == actors and
                      all(row.get("status") == "CAPTURED_REQUIRES_HOST_AND_VISUAL_REVIEW"
                          for row in cases))
    media_complete = (cases_complete and all(
        isinstance(captures.get(actor, {}).get("recorderExitCode"), int) and
        captures[actor]["recorderExitCode"] == 0 and
        captures[actor].get("videoHasFrames") is True and
        captures[actor].get("videoDecodePass") is True and
        isinstance(captures[actor].get("videoSHA256"), str) and
        isinstance(captures[actor].get("finalScreenshotSHA256"), str)
        for actor in actors))
    return {"expectedCaseCount": expected, "actualCaseCount": len(cases),
            "allCasesComplete": cases_complete, "allCaseMediaComplete": media_complete,
            "fixedReceiptsRestored": receipts_restored,
            "success": bool(cases_complete and media_complete and receipts_restored)}


def validate_source_snapshot(receipt: dict) -> dict[str, bool]:
    """The build receipt's frozen source map must still resolve byte-for-byte."""
    snapshot_value = receipt.get("source_snapshot")
    source_map = receipt.get("source_sha256")
    if not isinstance(snapshot_value, str) or not isinstance(source_map, dict) or not source_map:
        return {"source_snapshot_present": False, "source_snapshot_hashes_match": False}
    snapshot = Path(snapshot_value)
    checks = {"source_snapshot_present": snapshot.is_dir()}
    matched = snapshot.is_dir()
    basenames = [Path(key).name for key in source_map]
    if len(basenames) != len(set(basenames)):
        matched = False
    for relative, expected in source_map.items():
        source = snapshot / Path(relative).name
        if not source.is_file() or sha(source) != expected:
            matched = False
    checks["source_snapshot_hashes_match"] = matched
    return checks


def validate_normal_build(app: Path, build_path: Path) -> dict:
    info = inspect_build_receipt(app, build_path, False)
    receipt = info["receipt"]
    checks = dict(info["checks"])
    checks.update(validate_source_snapshot(receipt))
    checks["unsigned_local_simulator_build"] = (receipt.get("physical_device") is False and
                                                 receipt.get("signing") is False and
                                                 receipt.get("upload") is False)
    checks["resource_capture_before_compile"] = receipt.get("resource_snapshot_before_compile") is True
    checks["resource_decode_and_stability_pass"] = (receipt.get("png_decode_validation") == "PASS" and
                                                     receipt.get("source_stability") == "PASS")
    return {**info, "checks": checks}


def fixed_receipt_files(folder: Path) -> list[Path]:
    found: set[Path] = set()
    for pattern in FIXED_GLOBS:
        found.update(p for p in folder.glob(pattern) if p.is_file())
    found.update(p for name in FIXED_NAMES if (p := folder / name).is_file())
    return sorted(found)


def snapshot_fixed_receipts(folder: Path) -> dict[str, dict[str, object]]:
    snapshot: dict[str, dict[str, object]] = {}
    for path in fixed_receipt_files(folder):
        stat = path.stat()
        data = path.read_bytes()
        # Reading a fixed receipt can update atime. Preserve the observed
        # pre-read timestamp immediately and record that original value.
        os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        snapshot[path.name] = {"bytes": data, "atime_ns": stat.st_atime_ns,
                               "mtime_ns": stat.st_mtime_ns,
                               "mode": stat.st_mode & 0o777}
    return snapshot


def restore_fixed_receipts(folder: Path, snapshot: dict[str, dict[str, object]]) -> dict[str, bool]:
    """Restore prior global receipts exactly, leaving run-created names untouched."""
    restored: dict[str, bool] = {}
    for name, record in snapshot.items():
        path = folder / name
        tmp = path.with_name(path.name + ".restore-" + uuid.uuid4().hex)
        tmp.write_bytes(record["bytes"])
        os.chmod(tmp, int(record["mode"]))
        os.replace(tmp, path)
        # Verify bytes before the final timestamp restoration: reading may
        # update atime on filesystems using relatime/strictatime.
        bytes_match = path.read_bytes() == record["bytes"]
        os.utime(path, ns=(int(record["atime_ns"]), int(record["mtime_ns"])))
        stat = path.stat()
        restored[name] = (bytes_match and stat.st_mtime_ns == record["mtime_ns"] and
                          stat.st_atime_ns == record["atime_ns"] and (stat.st_mode & 0o777) == record["mode"])
    return restored


def parse_art_payload(receipt_path: Path, launched_unix: float, actor: str,
                      expected_state: str | None,
                      requested_state: str | None = None) -> tuple[dict, dict] | None:
    try:
        if receipt_path.stat().st_mtime < launched_unix:
            return None
        receipt = json.loads(receipt_path.read_text())
        if receipt.get("kind") != receipt_path.stem.removeprefix("last_"):
            return None
        payload = json.loads(receipt["value"])
        if payload.get("actorIDs") != [actor]:
            return None
        presentation = payload.get("enemyPresentation", {}).get(actor)
        if not isinstance(presentation, dict):
            return None
        audited_request = requested_state or expected_state
        if audited_request is not None:
            if payload.get("states", {}).get(actor + ":" + audited_request) is not True:
                return None
        if expected_state is not None:
            if presentation.get("state") != expected_state:
                return None
        return receipt, payload
    except (OSError, ValueError, TypeError, KeyError):
        return None


def wait_art_payload(path: Path, launched_unix: float, actor: str,
                     expected_state: str | None, deadline: float,
                     requested_state: str | None = None):
    while time.monotonic() < deadline:
        value = parse_art_payload(path, launched_unix, actor, expected_state, requested_state)
        if value is not None:
            return value
        time.sleep(.05)
    raise TimeoutError(f"fresh matching art receipt timed out: {path.name}, state={expected_state}")


def expected_late_state(requested: str, clips: dict[str, dict], sample_elapsed: float = 0.4) -> str:
    """Exact next clip at the viewer's nominal 400ms late sample."""
    return expected_state_at(requested, clips, sample_elapsed)


def presentation_matches_clip(presentation: dict, expected_state: str,
                              clips: dict[str, dict]) -> bool:
    """Bind a sprite sample to an actual path/index from the expected clip."""
    if presentation.get("state") != expected_state:
        return False
    clip = clips.get(expected_state, {})
    paths = clip.get("frames")
    if presentation.get("isPartRig") is True:
        # Rig telemetry has a different schema and cannot be passed off as a
        # sprite frame-path match by this state-capture runner.
        return False
    index = presentation.get("frameIndex")
    if not isinstance(index, int) or isinstance(index, bool) or not isinstance(paths, list):
        return False
    return 0 <= index < len(paths) and presentation.get("framePath") == paths[index]


def presentation_matches_timed_sample(presentation: dict, requested: str,
                                      clips: dict[str, dict], elapsed: float) -> bool:
    """Match the expected clip, with a bounded duration-boundary observation window.

    SpriteKit starts/completes actions on scene updates. Receipt timestamps are
    written outside that render tick, so a sample can be just past the authored
    duration while the terminal texture is still the current rendered frame.
    The 33.3 ms window is an explicit conservative QA cap, not a measured or
    configured simulator refresh rate. Only the exact terminal frame qualifies;
    arbitrary stale frames remain failures. This is a boundary observation, not
    proof of the automatic return: capture_actor also requires settled readback.
    """
    expected = expected_state_at(requested, clips, elapsed)
    if presentation_matches_clip(presentation, expected, clips):
        return True
    requested_clip = clips.get(requested, {})
    paths = requested_clip.get("frames")
    fps = requested_clip.get("fps")
    if (requested_clip.get("loop") is True or requested == "resolve"
            or not isinstance(paths, list) or not paths
            or not isinstance(fps, (int, float)) or isinstance(fps, bool)
            or not math.isfinite(float(fps)) or fps <= 0):
        return False
    requested_duration = len(paths) / float(fps)
    handoff_grace_seconds = 1.0 / 30.0
    if not (requested_duration <= elapsed < requested_duration + handoff_grace_seconds):
        return False
    terminal = {"state": requested, "isPartRig": False,
                "frameIndex": len(paths) - 1, "framePath": paths[-1]}
    return all(presentation.get(key) == value for key, value in terminal.items())


def clip_duration_seconds(clips: dict[str, dict], name: str) -> float:
    row = clips.get(name, {})
    frames, fps = row.get("frames"), row.get("fps")
    if (not isinstance(frames, list) or not frames
            or not isinstance(fps, (int, float)) or isinstance(fps, bool)
            or not math.isfinite(float(fps)) or fps <= 0):
        raise ValueError(f"missing or invalid frozen clip timing: {name}")
    return len(frames) / float(fps)


def settled_expectation(requested: str, clips: dict[str, dict]) -> tuple[float, str, str]:
    """Return clip-time plus QA margin, settled state, and transition contract."""
    requested_clip = clips.get(requested, {})
    total = clip_duration_seconds(clips, requested) + 0.10
    if requested == "execute":
        total += clip_duration_seconds(clips, "recover")
        expected, contract = "idle", "execute_then_recover_to_idle"
    elif requested == "resolve":
        expected, contract = "resolve", "terminal_resolve_holds"
    elif requested_clip.get("loop") is True:
        expected, contract = requested, "loop_remains_active"
    else:
        expected, contract = "idle", "nonloop_returns_to_idle"
    if not math.isfinite(total) or total <= 0 or total > 10:
        raise ValueError(f"settled timing outside bounded QA range: {requested}")
    return total, expected, contract


def receipt_matches_state_request(receipt: dict, request_id: str, requested: str,
                                  request_uptime: float) -> bool:
    if (not isinstance(request_uptime, (int, float)) or isinstance(request_uptime, bool)
            or not math.isfinite(float(request_uptime))):
        return False
    if (receipt.get("qaStateRequestID") != request_id
            or receipt.get("qaRequestedState") != requested):
        return False
    recorded_request = receipt.get("qaRequestUptime")
    sample_uptime = receipt.get("qaSampleUptime")
    if (not isinstance(recorded_request, (int, float)) or isinstance(recorded_request, bool)
            or not math.isfinite(float(recorded_request))
            or abs(float(recorded_request) - request_uptime) > 1e-6
            or not isinstance(sample_uptime, (int, float)) or isinstance(sample_uptime, bool)
            or not math.isfinite(float(sample_uptime)) or float(sample_uptime) < request_uptime):
        return False
    return True


def verify_settled_observation(receipt: dict, payload: dict, actor: str,
                               requested: str, request_id: str,
                               request_uptime: float, clips: dict[str, dict]) -> list[str]:
    failures: list[str] = []
    if (not isinstance(request_uptime, (int, float)) or isinstance(request_uptime, bool)
            or not math.isfinite(float(request_uptime))):
        return ["settled_request_uptime_invalid"]
    try:
        delay, expected_state, contract = settled_expectation(requested, clips)
    except ValueError as error:
        return [f"settled_contract_invalid:{error}"]
    if receipt.get("kind") != f"art_sample_{requested}_settled":
        failures.append("settled_wrong_receipt_kind")
    if receipt.get("qaStateRequestID") != request_id:
        failures.append("settled_request_id_mismatch")
    if receipt.get("qaRequestedState") != requested:
        failures.append("settled_requested_state_mismatch")
    if receipt.get("qaExpectedSettledState") != expected_state:
        failures.append("settled_expected_state_metadata_mismatch")
    if receipt.get("qaSettleContract") != contract:
        failures.append("settled_contract_metadata_mismatch")
    actual_delay = receipt.get("qaSettleDelaySeconds")
    if (not isinstance(actual_delay, (int, float)) or isinstance(actual_delay, bool)
            or not math.isfinite(float(actual_delay)) or abs(float(actual_delay) - delay) > 1e-6):
        failures.append("settled_delay_metadata_mismatch")
    recorded_request_uptime = receipt.get("qaRequestUptime")
    if (not isinstance(recorded_request_uptime, (int, float)) or isinstance(recorded_request_uptime, bool)
            or not math.isfinite(float(recorded_request_uptime))
            or abs(float(recorded_request_uptime) - request_uptime) > 1e-6):
        failures.append("settled_request_uptime_mismatch")
    sample_uptime = receipt.get("qaSampleUptime")
    if (not isinstance(sample_uptime, (int, float)) or isinstance(sample_uptime, bool)
            or not math.isfinite(float(sample_uptime))):
        failures.append("settled_sample_uptime_missing")
    else:
        elapsed = float(sample_uptime) - request_uptime
        if elapsed < delay:
            failures.append("settled_sample_too_early")
        elif elapsed > delay + 0.5:
            failures.append("settled_sample_too_late")
    if payload.get("actorIDs") != [actor]:
        failures.append("settled_wrong_actor_ids")
    if payload.get("states", {}).get(actor + ":" + requested) is not True:
        failures.append("settled_requested_state_not_audited")
    presentation = payload.get("enemyPresentation", {}).get(actor)
    if not isinstance(presentation, dict) or not presentation_matches_clip(presentation, expected_state, clips):
        failures.append("settled_presentation_path_or_state_mismatch")
    elif contract == "terminal_resolve_holds":
        paths = clips["resolve"]["frames"]
        if presentation.get("frameIndex") != len(paths) - 1:
            failures.append("settled_resolve_not_on_terminal_frame")
    return failures


def expected_state_at(requested: str, clips: dict[str, dict], elapsed: float) -> str:
    if not math.isfinite(elapsed) or elapsed < 0:
        raise ValueError("invalid sample offset")
    clip = clips.get(requested, {})
    if clip.get("loop") is True or requested == "resolve":
        return requested
    requested_duration = clip_duration_seconds(clips, requested)
    if elapsed < requested_duration:
        return requested
    if requested == "execute":
        return "recover" if elapsed - requested_duration < clip_duration_seconds(clips, "recover") else "idle"
    return "idle"


def runtime_clips(app: Path, actor: str) -> dict[str, dict]:
    index_path = app / "Art" / "runtime_index.json"
    index = json.loads(index_path.read_text())
    entry = index.get("entries", {}).get(actor)
    if not isinstance(entry, dict) or not isinstance(entry.get("clips"), dict):
        raise ValueError(f"actor has no runtime clip contract in frozen index: {actor}")
    return entry["clips"]


def wait_art_state_request(path: Path, launched_unix: float, actor: str, state: str,
                           deadline: float) -> tuple[dict, float]:
    expected = actor + ":" + state
    while time.monotonic() < deadline:
        try:
            if path.stat().st_mtime >= launched_unix:
                receipt = json.loads(path.read_text())
                if receipt.get("kind") == "art_state" and receipt.get("value") == expected:
                    return receipt, path.stat().st_mtime
        except (OSError, ValueError, TypeError):
            pass
        time.sleep(.025)
    raise TimeoutError(f"fresh art-state request timed out: {expected}")


def verify_final_payload(receipt: dict, payload: dict, actor: str) -> list[str]:
    failures = []
    if receipt.get("kind") != "art_audit":
        failures.append("wrong_final_receipt_kind")
    if payload.get("actorIDs") != [actor]:
        failures.append("wrong_final_actor_ids")
    for state in STATES:
        if payload.get("states", {}).get(actor + ":" + state) is not True:
            failures.append("state_not_rendered:" + state)
    if payload.get("enemyPresentation", {}).get(actor, {}).get("state") != "resolve":
        failures.append("final_presentation_not_resolve")
    return failures


def capture_actor(app: Path, actor: str, device: str,
                  save_folder: Path, case: Path, clips: dict[str, dict],
                  screenshot_each_state: bool = True) -> dict:
    key = "state-audit-" + uuid.uuid4().hex
    report = {"status": "RUNNING", "actorID": actor, "saveKey": key,
              "device": device, "app": str(app),
              "runtimeClipContract": {state: {"frameCount": len(clip.get("frames", [])),
                  "fps": clip.get("fps"), "loop": clip.get("loop"),
                  "durationSeconds": len(clip.get("frames", [])) / float(clip.get("fps", 1))}
                  for state, clip in clips.items()},
              "scope": "existing --art-audit seven-state viewer; no combat/reward progression",
              "candidateAdopted": False, "states": []}
    video = case / "states.mp4"
    video_log = (case / "record_video.log").open("w")
    recorder = subprocess.Popen(["xcrun", "simctl", "io", device, "recordVideo", "--codec=h264", str(video)],
                                stdout=video_log, stderr=subprocess.STDOUT)
    report["recorderPID"] = recorder.pid
    launched_ok = False
    failure = None
    try:
        time.sleep(.4)
        launch_command = ["xcrun", "simctl", "launch", "--terminate-running-process", device,
                          BUNDLE, "--qa-isolated", "--qa-save-key=" + key, "--art-audit=" + actor]
        report["launchCommand"] = launch_command
        report["launchStartedUnix"] = time.time()
        report["launchResult"] = command(*launch_command)
        launched_ok = True
        deadline = time.monotonic() + 90

        preparation_path = save_folder / "last_registered_render_preparation.json"
        prep_deadline = time.monotonic() + 25
        while time.monotonic() < prep_deadline and not (preparation_path.exists() and preparation_path.stat().st_mtime >= report["launchStartedUnix"]):
            time.sleep(.05)
        if not preparation_path.exists() or preparation_path.stat().st_mtime < report["launchStartedUnix"]:
            raise TimeoutError("fresh registered-render preparation receipt missing")
        shutil.copy2(preparation_path, case / "registered_render_preparation.json")
        report["registeredRenderPreparationSHA256"] = sha(case / "registered_render_preparation.json")

        for state in STATES:
            state_row = {"state": state}
            request_path = save_folder / "last_art_state.json"
            request_receipt, request_unix = wait_art_state_request(
                request_path, report["launchStartedUnix"], actor, state, deadline)
            request_copy = case / f"{state}_request_receipt.json"
            shutil.copy2(request_path, request_copy)
            request_id = request_receipt.get("qaStateRequestID")
            request_uptime = request_receipt.get("qaRequestUptime")
            if (not isinstance(request_id, str) or not request_id
                    or request_receipt.get("qaRequestedState") != state
                    or not isinstance(request_uptime, (int, float)) or isinstance(request_uptime, bool)
                    or not math.isfinite(float(request_uptime))):
                raise RuntimeError(f"state request lacks valid unique timing metadata: {state}")
            state_row["request"] = {"sourceReceipt": "last_art_state.json",
                                    "receiptSHA256": sha(request_copy),
                                    "receiptDate": request_receipt.get("date"),
                                    "requestedValue": request_receipt.get("value"),
                                    "mtimeUnix": request_unix,
                                    "requestID": request_id,
                                    "requestUptime": request_uptime}
            for phase in ("early", "late"):
                receipt_name = f"last_art_sample_{state}_{phase}.json"
                copied = case / f"{state}_{phase}_receipt.json"
                source = save_folder / receipt_name
                receipt, payload = wait_art_payload(source, report["launchStartedUnix"], actor,
                                                    None, deadline, requested_state=state)
                sample_unix = source.stat().st_mtime
                sample_uptime = receipt.get("qaSampleUptime")
                sample_offset = float(sample_uptime) - float(request_uptime)
                expected_presentation_state = expected_state_at(state, clips, sample_offset)
                phase_bounds = (0.05, 0.30) if phase == "early" else (0.30, 0.70)
                if not phase_bounds[0] <= sample_offset <= phase_bounds[1]:
                    raise RuntimeError(f"{phase} sample outside request-relative window: {sample_offset:.3f}s")
                if not receipt_matches_state_request(receipt, request_id, state, float(request_uptime)):
                    raise RuntimeError(f"{phase} receipt belongs to a different state request: {state}")
                shutil.copy2(source, copied)
                presentation = payload["enemyPresentation"][actor]
                if not presentation_matches_timed_sample(presentation, state, clips, sample_offset):
                    raise RuntimeError(f"presentation frame path/index does not belong to expected clip: requested={state}, phase={phase}, expected={expected_presentation_state}")
                item = {"phase": phase, "sourceReceipt": receipt_name, "receiptSHA256": sha(copied),
                        "receiptDate": receipt.get("date"), "presentation": presentation,
                        "requestedState": state,
                        "expectedPresentationState": expected_presentation_state,
                        "handoffPending": presentation.get("state") != expected_presentation_state,
                        "requestToSampleSeconds": sample_offset,
                        "receiptMtimeUnix": sample_unix,
                        "receiptMtimeOffsetSeconds": sample_unix - request_unix,
                        "stateAudit": payload.get("states", {}).get(actor + ":" + state)}
                if phase == "late" and screenshot_each_state:
                    screenshot = case / f"{state}_late.png"
                    screenshot_unix = time.time()
                    command("xcrun", "simctl", "io", device, "screenshot", str(screenshot))
                    item["screenshot"] = screenshot.name
                    item["screenshotSHA256"] = sha(screenshot)
                    item["screenshotUnix"] = screenshot_unix
                state_row[phase] = item

            settle_path = save_folder / f"last_art_sample_{state}_settled.json"
            settle_receipt, settle_payload = wait_art_payload(
                settle_path, report["launchStartedUnix"], actor, None, deadline,
                requested_state=state)
            settle_copy = case / f"{state}_settled_receipt.json"
            shutil.copy2(settle_path, settle_copy)
            settle_presentation = settle_payload.get("enemyPresentation", {}).get(actor, {})
            settle_failures = verify_settled_observation(
                settle_receipt, settle_payload, actor, state, request_id,
                float(request_uptime), clips)
            state_row["settled"] = {
                "sourceReceipt": settle_path.name,
                "receiptSHA256": sha(settle_copy),
                "receiptDate": settle_receipt.get("date"),
                "presentation": settle_presentation,
                "expectedSettledState": settle_receipt.get("qaExpectedSettledState"),
                "settleContract": settle_receipt.get("qaSettleContract"),
                "settleDelaySeconds": settle_receipt.get("qaSettleDelaySeconds"),
                "requestToSampleSeconds": (settle_receipt.get("qaSampleUptime", 0) - request_uptime
                                           if isinstance(settle_receipt.get("qaSampleUptime"), (int, float))
                                           and not isinstance(settle_receipt.get("qaSampleUptime"), bool) else None),
                "failures": settle_failures,
                "status": "PASS" if not settle_failures else "FAIL"
            }
            if settle_failures:
                raise RuntimeError(f"settled state transition was not observed for {state}: {settle_failures}")
            report["states"].append(state_row)

        final_path = save_folder / "last_art_audit.json"
        receipt, payload = wait_art_payload(final_path, report["launchStartedUnix"], actor, None, deadline)
        failures = verify_final_payload(receipt, payload, actor)
        shutil.copy2(final_path, case / "final_art_audit.json")
        report["finalReceiptSHA256"] = sha(case / "final_art_audit.json")
        report["finalPresentationState"] = payload.get("enemyPresentation", {}).get(actor, {}).get("state")
        if failures:
            raise RuntimeError("final seven-state receipt invalid: " + ", ".join(failures))
        final_screenshot = case / "final_state.png"
        command(*final_screenshot_command(device, final_screenshot))
        if not final_screenshot.is_file() or final_screenshot.stat().st_size == 0:
            raise RuntimeError("final screenshot command returned without a non-empty image")
        report["finalScreenshotSHA256"] = sha(final_screenshot)
        report["status"] = "CAPTURED_REQUIRES_HOST_AND_VISUAL_REVIEW"
    except Exception as exc:
        failure = repr(exc)
        report["status"] = "CAPTURE_FAILED"
        report["error"] = failure
        for p in [save_folder / "last_art_audit.json", save_folder / "last_art_state.json",
                  save_folder / "last_registered_render_preparation.json"]:
            if p.exists() and p.stat().st_mtime >= report["launchStartedUnix"]:
                target = case / ("failure_" + p.name)
                shutil.copy2(p, target)
    finally:
        if recorder.poll() is None:
            recorder.send_signal(signal.SIGINT)
        try:
            report["recorderExitCode"] = recorder.wait(timeout=25)
        except subprocess.TimeoutExpired:
            recorder.kill()
            report["recorderExitCode"] = recorder.wait(timeout=5)
            report["recorderStop"] = "timeout_killed_after_grace"
            report["status"] = "CAPTURE_FAILED"
            report["error"] = report.get("error", "") + " recorder_timeout"
        video_log.close()
        if launched_ok:
            terminated = subprocess.run(["xcrun", "simctl", "terminate", device, BUNDLE],
                                        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
            report["terminateExitCode"] = terminated.returncode
            report["terminateOutput"] = terminated.stdout[-1000:]
        copied_receipts = {}
        fixed_output = case / "fixed_receipts_after"
        for source in fixed_receipt_files(save_folder):
            if source.stat().st_mtime < report["launchStartedUnix"]:
                continue
            fixed_output.mkdir(exist_ok=True)
            target = fixed_output / source.name
            shutil.copy2(source, target)
            copied_receipts[source.name] = {"sha256": sha(target), "mtimeNs": target.stat().st_mtime_ns}
        report["freshFixedReceiptCopies"] = copied_receipts
        if video.is_file():
            report["videoSHA256"] = sha(video)
            report["videoBytes"] = video.stat().st_size
            ffprobe = shutil.which("ffprobe")
            ffmpeg = shutil.which("ffmpeg")
            if ffprobe:
                probe = subprocess.run([ffprobe,"-v","error","-show_streams","-show_format","-of","json",str(video)],
                                       text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
                (case/"video_probe.json").write_text(probe.stdout+"\n")
                report["ffprobeExitCode"] = probe.returncode
                if probe.returncode == 0:
                    try:
                        parsed=json.loads(probe.stdout); videos=[s for s in parsed.get("streams",[]) if s.get("codec_type")=="video"]
                        report["videoDurationSeconds"]=float(parsed.get("format",{}).get("duration",0))
                        report["videoDimensions"]=[[s.get("width"),s.get("height")] for s in videos]
                        report["videoHasFrames"] = bool(videos) and report["videoDurationSeconds"] > 0
                    except (ValueError,TypeError):
                        report["videoHasFrames"] = False
                else:
                    report["videoHasFrames"] = False
            else:
                report["ffprobeUnavailable"] = True
                report["videoHasFrames"] = False
            if ffmpeg:
                decoded=subprocess.run([ffmpeg,"-v","error","-i",str(video),"-f","null","-"],
                                       text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
                report["ffmpegDecodeExitCode"] = decoded.returncode
                report["ffmpegDecodeStderr"] = decoded.stderr[-2000:]
                report["videoDecodePass"] = decoded.returncode == 0
            else:
                report["ffmpegUnavailable"] = True
                report["videoDecodePass"] = False
        report["finishedAt"] = dt.datetime.now().astimezone().isoformat()
        report["failure"] = failure
        report["caseFilesSHA256BeforeReceipt"] = {p.name: sha(p) for p in sorted(case.iterdir()) if p.is_file()}
        atomic_json(case/"CAPTURE.json", report)
    return report


def main() -> int:
    if not __debug__:
        raise RuntimeError("capture refuses optimized Python interpreter")
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--app",type=Path,required=True)
    ap.add_argument("--output",type=Path,required=True)
    ap.add_argument("--device",choices=[DEVICE],default=DEVICE)
    ap.add_argument("--actor",action="append",required=True,help="ACT_E_/ACT_B_ actor ID; repeat for a batch")
    a=ap.parse_args()
    if any(not re.fullmatch(r"ACT_[EB]_R0[1-5]_[0-9AB]{1,2}", actor) for actor in a.actor):
        ap.error("actors must be explicit enemy art IDs such as ACT_E_R05_04 or ACT_B_R05_B")
    if len(set(a.actor)) != len(a.actor):
        ap.error("duplicate actor IDs are not accepted")
    app=a.app.resolve();out=a.output.resolve()
    if out.exists():
        ap.error("output must be a new, exclusive directory")
    build_path=app.parent/"BUILD_RECEIPT.json"
    build_info=validate_normal_build(app,build_path)
    if build_info["status"]!="SIMULATOR_BUILD_PASS" or not all(build_info["checks"].values()):
        raise RuntimeError("frozen normal build receipt validation failed")
    build=build_info["receipt"]
    lock_path=Path("/tmp")/f"witch-loop-qa-{a.device}.lock"
    lock=lock_path.open("a")
    try:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError as exc:
        raise RuntimeError("exclusive simulator capture lock is held") from exc
    out.mkdir(parents=True,exist_ok=False)
    shutil.copy2(build_path,out/"BUILD_RECEIPT.json")

    run={"status":"RUNNING","app":str(app),"device":a.device,"actors":a.actor,
         "executableSHA256":sha(app/"WitchGathering"),"buildReceiptSHA256":build_info["receiptSHA256"],
         "buildReceiptStatus":build_info["status"],"sourceSHA256":build.get("source_sha256"),
         "sourceSnapshotPath":build.get("source_snapshot"),"sourceSnapshotChecks":validate_source_snapshot(build),
         "resourceSHA256":build.get("resource_sha256"),"fixedReceiptSnapshot":None,
         "captureStartedAt":dt.datetime.now().astimezone().isoformat(),"cases":[],
         "scope":"existing isolated art-audit route; all seven required enemy motion states; no battle/reward claims"}
    atomic_json(out/"RUN.json",run)
    before={}
    support=None
    try:
        command("xcrun","simctl","install",a.device,str(app))
        container=Path(command("xcrun","simctl","get_app_container",a.device,BUNDLE,"data"))
        installed=Path(command("xcrun","simctl","get_app_container",a.device,BUNDLE,"app"))
        support=container/"Library/Application Support/Witch03to05R1"
        before=snapshot_fixed_receipts(support)
        before_meta={name:{"sha256":hashlib.sha256(row["bytes"]).hexdigest(),"atimeNs":row["atime_ns"],
                           "mtimeNs":row["mtime_ns"],"mode":row["mode"]}
                     for name,row in before.items()}
        (out/"prior_fixed_receipts").mkdir()
        for name,row in before.items():
            prior=out/"prior_fixed_receipts"/name
            prior.write_bytes(row["bytes"]);os.chmod(prior,int(row["mode"]))
            os.utime(prior,ns=(int(row["atime_ns"]),int(row["mtime_ns"])))
        atomic_json(out/"PRIOR_FIXED_RECEIPTS.json",before_meta)
        run["dataContainer"]=str(container)
        run["installedBundle"]=str(installed)
        run["fixedReceiptSnapshot"]=before_meta
        installed_sha=sha(installed/"WitchGathering")
        if installed_sha != build["executable_sha256"]:
            raise RuntimeError("installed executable SHA does not match frozen build")
        run["installedExecutableSHA256"]=installed_sha
        for actor in a.actor:
            case=out/actor
            case.mkdir()
            result=capture_actor(app,actor,a.device,support,case,runtime_clips(app,actor))
            run["cases"].append({"actorID":actor,"status":result["status"],"captureSHA256":sha(case/"CAPTURE.json"),"failure":result.get("failure")})
            atomic_json(out/"RUN.json",run)
            if result["status"] != "CAPTURED_REQUIRES_HOST_AND_VISUAL_REVIEW":
                break
    except Exception as exc:
        run["status"]="CAPTURE_FAILED"
        run["failure"]=repr(exc)
    finally:
        # Stop any leftover app before restoring global last_* receipts.
        subprocess.run(["xcrun","simctl","terminate",a.device,BUNDLE],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=20)
        restored=restore_fixed_receipts(support,before) if support is not None else {}
        post_restore={}
        if support is not None:
            for path in fixed_receipt_files(support):
                stat_before_read=path.stat()
                digest=sha(path)
                prior=before.get(path.name)
                if prior is not None:
                    os.chmod(path,int(prior["mode"]))
                    os.utime(path,ns=(int(prior["atime_ns"]),int(prior["mtime_ns"])))
                else:
                    # Retain and pin newly-created global receipts; restore
                    # their observed metadata after hashing as hashing reads them.
                    os.utime(path,ns=(stat_before_read.st_atime_ns,stat_before_read.st_mtime_ns))
                stat_after=path.stat()
                post_restore[path.name]={"sha256":digest,"atimeNs":stat_after.st_atime_ns,
                                         "mtimeNs":stat_after.st_mtime_ns,"mode":stat_after.st_mode & 0o777}
        expected_after={name:{"sha256":hashlib.sha256(row["bytes"]).hexdigest(),"atimeNs":row["atime_ns"],
                              "mtimeNs":row["mtime_ns"],"mode":row["mode"]}
                        for name,row in before.items()}
        retained_new={name:row for name,row in post_restore.items() if name not in expected_after}
        exact_post=(set(expected_after).issubset(post_restore) and
                    all(post_restore.get(name)==value for name,value in expected_after.items()))
        run["fixedReceiptRestore"]={"allExact":support is not None and all(restored.values()) and exact_post,
                                    "results":restored,"retainedNewReceipts":retained_new,
                                    "postRestore":post_restore}
        run["finishedAt"]=dt.datetime.now().astimezone().isoformat()
        media_rows = {}
        for actor in a.actor:
            capture_path = out / actor / "CAPTURE.json"
            try:
                media_rows[actor] = json.loads(capture_path.read_text())
            except (OSError, json.JSONDecodeError):
                media_rows[actor] = {}
        checks = completion_checks(a.actor, run.get("cases", []), media_rows,
                                   run["fixedReceiptRestore"]["allExact"])
        run["completionChecks"] = checks
        failed=(run.get("failure") or not checks["success"] or
                any(c.get("status")!="CAPTURED_REQUIRES_HOST_AND_VISUAL_REVIEW" for c in run["cases"]) or
                not run["fixedReceiptRestore"]["allExact"])
        run["status"]="CAPTURE_FAILED" if failed else "CAPTURED_REQUIRES_HOST_AND_VISUAL_REVIEW"
        atomic_json(out/"RUN.json",run)
    print(json.dumps(run,ensure_ascii=False,indent=2))
    return 1 if run["status"]=="CAPTURE_FAILED" else 0


if __name__=="__main__":
    raise SystemExit(main())

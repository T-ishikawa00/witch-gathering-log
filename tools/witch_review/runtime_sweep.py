#!/usr/bin/env python3
"""Capture real iOS Simulator enemy state presentation for a supplied .app.

This never builds, resets, or edits the project. It installs only the caller-
provided app on the dedicated Witch QA simulator and uses isolated QA saves.
Every state result comes from the running app's last_art_audit.json; screenshots
are separately OCR-matched to the app's visible state label.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
EXPECTED_DEVICE = "9A067715-7CF3-40D3-9064-38423223959B"
# Root explicitly created this second isolated QA simulator for the later
# overlay delta sweep. Keep this allowlist closed; never accept arbitrary UDIDs.
AUTHORIZED_DEVICES = frozenset({
    EXPECTED_DEVICE,
    "1D034CC3-9259-4AEE-A21D-E6E88D242ACF",
})
STATES = ("idle", "walk", "anticipate", "execute", "recover", "hit", "resolve")
SAMPLE_INTERVAL = 0.45
SETTLE_AFTER_LAST = 1.0


def run(args: list[str], *, check: bool = True, capture: bool = True) -> str:
    p = subprocess.run(args, text=True, stdout=subprocess.PIPE if capture else None,
                       stderr=subprocess.STDOUT if capture else None)
    out = p.stdout or ""
    if check and p.returncode:
        raise RuntimeError(f"command failed ({p.returncode}): {' '.join(args)}\n{out[-4000:]}")
    return out


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def app_identity(app: Path) -> tuple[str, Path, str]:
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError(f"--app must be a built .app directory: {app}")
    with (app / "Info.plist").open("rb") as f:
        info = plistlib.load(f)
    bundle = info.get("CFBundleIdentifier")
    executable = app / info.get("CFBundleExecutable", "")
    if not bundle or not executable.is_file():
        raise ValueError("built app lacks CFBundleIdentifier or executable")
    return bundle, executable, str(info.get("CFBundleVersion", "UNKNOWN"))


def unique_resource(app: Path, filename: str) -> Path:
    found = list(app.rglob(filename))
    if len(found) != 1:
        raise ValueError(f"expected exactly one bundled {filename}, found {len(found)}")
    return found[0]


def load_plan(app: Path) -> dict[str, Any]:
    catalog_path = unique_resource(app, "catalog_overlay.json")
    index_path = unique_resource(app, "runtime_index.json")
    catalog = json.loads(catalog_path.read_text())
    index = json.loads(index_path.read_text())
    enemies = catalog.get("enemies", [])
    if len(enemies) != 30:
        raise ValueError(f"bundled candidate catalog has {len(enemies)} enemies; expected 30")
    entries = index.get("entries", {})
    targets = []
    for enemy in enemies:
        source_id = enemy.get("id")
        if not isinstance(source_id, str):
            raise ValueError(f"catalog enemy missing id: {enemy}")
        actor_id = source_id if source_id.startswith("ACT_") else "ACT_" + source_id
        if actor_id not in entries:
            raise ValueError(f"effective bundled art index has no {actor_id}")
        targets.append({"catalogID": source_id, "actorID": actor_id,
                        "regionID": enemy.get("regionID", enemy.get("region_id")),
                        "catalogName": enemy.get("name")})
    return {"catalogPath": str(catalog_path.relative_to(app)),
            "catalogSHA256": sha256(catalog_path),
            "effectiveIndexPath": str(index_path.relative_to(app)),
            "effectiveIndexSHA256": sha256(index_path),
            "targets": targets}


def simulator_state(udid: str) -> dict[str, Any]:
    raw = json.loads(run(["xcrun", "simctl", "list", "devices", "--json"]))
    for runtime_devices in raw.get("devices", {}).values():
        for dev in runtime_devices:
            if dev.get("udid") == udid:
                return dev
    raise ValueError(f"simulator not found: {udid}")


def container(udid: str, bundle: str, which: str) -> Path:
    return Path(run(["xcrun", "simctl", "get_app_container", udid, bundle, which]).strip())


def write_swift_ocr(temp: Path, samples: list[Path]) -> dict[str, str]:
    """OCR sampled screen labels in one Vision process; return path -> text."""
    helper = temp / "ocr.swift"
    helper.write_text(r'''import Foundation
import Vision
import ImageIO
let paths = Array(CommandLine.arguments.dropFirst())
var result: [String:String] = [:]
for path in paths {
    let url = URL(fileURLWithPath: path)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP", "en-US"]
    request.usesLanguageCorrection = false
    do {
        try VNImageRequestHandler(url: url, options: [:]).perform([request])
        result[path] = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    } catch { result[path] = "OCR_ERROR: \(error)" }
}
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
''', encoding="utf-8")
    completed = subprocess.run(["swift", str(helper), *map(str, samples)], text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if completed.returncode:
        raise RuntimeError("Vision OCR helper failed: " + completed.stderr[-3000:])
    return json.loads(completed.stdout)


def parse_receipt(data: dict[str, Any], actor: str) -> dict[str, Any]:
    value = data.get("value")
    audit = json.loads(value) if isinstance(value, str) else value
    if not isinstance(audit, dict):
        raise ValueError(f"invalid art audit receipt for {actor}")
    if actor not in audit.get("actorIDs", []):
        raise ValueError(f"art audit receipt does not list {actor}: {audit}")
    states = audit.get("states", {})
    result = {}
    for state in STATES:
        key = f"{actor}:{state}"
        result[state] = {"runtimePlayAccepted": states.get(key) is True,
                         "runtimePlayReturned": states.get(key),
                         "screenshot": None, "visibleStateOCRMatched": False,
                         "cropReview": "PENDING_CONTACT_SHEET_REVIEW"}
    load_key = f"load_{actor}"
    load_status = states.get(load_key)
    return {"actorIDs": audit.get("actorIDs", []), "states": result,
            "loadError": load_status is False, "loadReturned": load_status,
            "frames": audit.get("frames"), "maxFrameDeltaSeconds": audit.get("maxFrameDeltaSeconds"),
            "rawStates": states}


def make_contact_sheets(records: list[dict[str, Any]], out: Path) -> None:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError as e:
        raise RuntimeError("Pillow is required for contact sheet generation") from e
    font = ImageFont.load_default()
    for state in STATES:
        thumbs = []
        for rec in records:
            item = rec["audit"]["states"][state]
            p = out / rec["actorID"] / item["screenshot"] if item["screenshot"] else None
            if not p or not p.is_file():
                continue
            im = Image.open(p).convert("RGB")
            im.thumbnail((196, 420), Image.Resampling.LANCZOS)
            card = Image.new("RGB", (212, 458), (20, 25, 31))
            card.paste(im, ((212 - im.width) // 2, 8))
            d = ImageDraw.Draw(card)
            d.text((8, 433), f"{rec['actorID']}  {state}", font=font, fill=(245, 232, 192))
            thumbs.append(card)
        if not thumbs:
            continue
        cols = 5
        rows = (len(thumbs) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * 212, rows * 458), (8, 12, 17))
        for i, im in enumerate(thumbs):
            sheet.paste(im, ((i % cols) * 212, (i // cols) * 458))
        sheet.save(out / f"contact_{state}.jpg", quality=88, optimize=True)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--app", required=True, type=Path, help="exact built .app supplied for this run")
    p.add_argument("--device", default=EXPECTED_DEVICE,
                   help=f"authorized QA simulator UDID (default {EXPECTED_DEVICE})")
    p.add_argument("--output", type=Path, help="new/empty output directory")
    p.add_argument("--qa-save-key", default="art-sweep-r001")
    p.add_argument("--capture-interval", type=float, default=SAMPLE_INTERVAL)
    p.add_argument("--dry-run", action="store_true", help="validate app/catalog/index; do not install or launch")
    args = p.parse_args()

    app = args.app.expanduser().resolve()
    bundle, executable, bundle_version = app_identity(app)
    plan = load_plan(app)
    if args.device not in AUTHORIZED_DEVICES:
        allowed = ", ".join(sorted(AUTHORIZED_DEVICES))
        raise ValueError(f"this procedure is authorized only for QA simulators: {allowed}")
    dev = simulator_state(args.device)
    if dev.get("state") != "Booted":
        raise ValueError(f"dedicated simulator must already be booted; no simulator reset/boot is performed ({dev.get('state')})")
    summary = {"app": str(app), "bundleID": bundle, "bundleVersion": bundle_version,
               "executable": str(executable), "executableSHA256": sha256(executable),
               "device": dev, **plan, "stateOrder": list(STATES),
               "captureIntervalSeconds": args.capture_interval}
    build_receipt_path = ROOT / "native/build/BUILD_RECEIPT.json"
    if build_receipt_path.is_file():
        build_receipt = json.loads(build_receipt_path.read_text())
        if Path(build_receipt.get("bundle", "")).resolve() == app:
            summary["buildReceiptPath"] = str(build_receipt_path)
            summary["buildReceiptSHA256"] = sha256(build_receipt_path)
            summary["buildReceiptStatus"] = build_receipt.get("status")
            summary["sourceSnapshot"] = build_receipt.get("source_snapshot")
            summary["sourceSHA256"] = build_receipt.get("source_sha256", {})
    if args.dry_run:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0
    out = (args.output or ROOT / "docs/production/current/review/runtime/art_sweep_r001").expanduser().resolve()
    if out.exists() and any(out.iterdir()):
        raise ValueError(f"refusing to overwrite non-empty evidence directory: {out}")
    out.mkdir(parents=True, exist_ok=True)
    run_start = dt.datetime.now(dt.timezone.utc)
    run_start_mono = time.monotonic()
    run_meta = {**summary, "startedAtUTC": run_start.isoformat(), "status": "RUNNING",
                "stateEvidencePolicy": "OCR label + runtime receipt; missing screenshot/unsupported state is never promoted to pass"}
    (out / "RUN.json").write_text(json.dumps(run_meta, ensure_ascii=False, indent=2) + "\n")
    run(["xcrun", "simctl", "install", args.device, str(app)])
    records: list[dict[str, Any]] = []
    try:
        for idx, target in enumerate(plan["targets"], start=1):
            actor = target["actorID"]
            actor_dir = out / actor
            actor_dir.mkdir(parents=True, exist_ok=True)
            launch_args = ["--qa-isolated", f"--qa-save-key={args.qa_save_key}", f"--art-audit={actor}"]
            launch_started_ns = time.time_ns()
            launch_output = run(["xcrun", "simctl", "launch", "--terminate-running-process",
                                 args.device, bundle, *launch_args])
            data_dir = container(args.device, bundle, "data")
            support = data_dir / "Library/Application Support/Witch03to05R1"
            state_path = support / "last_art_state.json"
            launched = time.monotonic()
            screenshot_paths: list[Path] = []
            state_receipts: dict[str, dict[str, Any]] = {}
            captured_states: set[str] = set()
            # The app writes last_art_state.json immediately after triggering
            # each state. Capture on that receipt transition; OCR independently
            # corroborates the visible Japanese label in that exact screenshot.
            total_seconds = len(STATES) * 2.0 + SETTLE_AFTER_LAST + 1.0
            while time.monotonic() - launched < total_seconds:
                current_state_receipt = None
                try:
                    if state_path.is_file() and state_path.stat().st_mtime_ns >= launch_started_ns:
                        current_state_receipt = json.loads(state_path.read_text())
                except (RuntimeError, OSError, json.JSONDecodeError):
                    current_state_receipt = None
                state_value = current_state_receipt.get("value") if current_state_receipt else None
                if isinstance(state_value, str) and state_value.startswith(actor + ":"):
                    state_name = state_value.split(":", 1)[1]
                    if state_name in STATES and state_name not in captured_states:
                        # Let SwiftUI commit the notice and state change before
                        # taking the screenshot, while retaining receipt timing.
                        time.sleep(0.12)
                        path = actor_dir / f"{state_name}.png"
                        run(["xcrun", "simctl", "io", args.device, "screenshot", str(path)])
                        screenshot_paths.append(path)
                        state_receipts[state_name] = {"value": state_value,
                                                      "date": current_state_receipt.get("date"),
                                                      "revision": current_state_receipt.get("revision"),
                                                      "screenshot": path.name}
                        captured_states.add(state_name)
                time.sleep(0.05)

            audit_path = support / "last_art_audit.json"
            metrics_path = support / "runtime_metrics.json"
            deadline = time.monotonic() + 5.0
            while not audit_path.is_file() and time.monotonic() < deadline:
                time.sleep(0.2)
            if not audit_path.is_file():
                audit_summary = {"error": "last_art_audit.json not produced", "states": {s: {"runtimePlayAccepted": False, "runtimePlayReturned": None, "screenshot": None, "visibleStateOCRMatched": False, "cropReview": "UNAVAILABLE"} for s in STATES}}
                receipt = None
            else:
                receipt = json.loads(audit_path.read_text())
                audit_summary = parse_receipt(receipt, actor)
                shutil.copy2(audit_path, actor_dir / "last_art_audit.json")
            metrics = None
            if metrics_path.is_file():
                metrics = json.loads(metrics_path.read_text())
                shutil.copy2(metrics_path, actor_dir / "runtime_metrics.json")
            else:
                metrics = {"error": "runtime_metrics.json unavailable"}
            ocr = write_swift_ocr(actor_dir, screenshot_paths)
            (actor_dir / "state_receipts.json").write_text(json.dumps(state_receipts, ensure_ascii=False, indent=2) + "\n")
            for state in STATES:
                receipt = state_receipts.get(state)
                if receipt:
                    shot = actor_dir / receipt["screenshot"]
                    audit_summary["states"][state]["screenshot"] = shot.name
                    recognized = ocr.get(str(shot), "")
                    audit_summary["states"][state]["visibleStateOCRMatched"] = (
                        "美術検証" in recognized and state.lower() in re.sub(r"\s+", " ", recognized.lower()))
                    audit_summary["states"][state]["ocrText"] = recognized
                else:
                    audit_summary["states"][state]["ocrObservedSamples"] = 0
            (actor_dir / "ocr_samples.json").write_text(json.dumps({p.name: ocr.get(str(p), "") for p in screenshot_paths}, ensure_ascii=False, indent=2) + "\n")
            rec = {**target, "launchOutput": launch_output.strip(), "receiptFile": "last_art_audit.json" if receipt else None,
                   "audit": audit_summary, "runtimeMetrics": metrics,
                   "classifications": {s: ("LOADED" if audit_summary["states"][s]["runtimePlayAccepted"] else "UNSUPPORTED") for s in STATES},
                   "visualClassification": "PENDING_CONTACT_SHEET_REVIEW",
                   "performanceAssessment": "OBSERVED_ONLY_NO_ACCEPTANCE_THRESHOLD",
                   "cropReview": "PENDING_CONTACT_SHEET_REVIEW"}
            (actor_dir / "RESULT.json").write_text(json.dumps(rec, ensure_ascii=False, indent=2) + "\n")
            records.append(rec)
            run_meta["completedActors"] = idx
            run_meta["updatedAtUTC"] = dt.datetime.now(dt.timezone.utc).isoformat()
            (out / "RUN.json").write_text(json.dumps(run_meta, ensure_ascii=False, indent=2) + "\n")
            print(f"[{idx}/30] {actor}: " + ", ".join(f"{s}={'loaded' if rec['audit']['states'][s]['runtimePlayAccepted'] else 'unsupported'}" for s in STATES), flush=True)
        make_contact_sheets(records, out)
        run_meta["status"] = "COMPLETED_CAPTURE; CROP_REVIEW_REQUIRED"
    except KeyboardInterrupt:
        run_meta["status"] = "INTERRUPTED"
        raise
    except Exception as exc:
        run_meta["status"] = "FAILED"
        run_meta["error"] = repr(exc)
        raise
    finally:
        run_meta["endedAtUTC"] = dt.datetime.now(dt.timezone.utc).isoformat()
        run_meta["elapsedSeconds"] = time.monotonic() - run_start_mono
        (out / "RUN.json").write_text(json.dumps(run_meta, ensure_ascii=False, indent=2) + "\n")
    if run_meta["status"].startswith("COMPLETED"):
        print(f"Evidence saved: {out}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"runtime_sweep: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)

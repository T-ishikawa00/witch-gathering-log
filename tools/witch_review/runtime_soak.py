#!/usr/bin/env python3
"""Run an interruptible simulator home/field soak and sample app metrics.

The default is 30 minutes at home followed by 30 minutes in Explore. This is
local simulator QA only; elapsed duration is measured from monotonic time and
an interrupted run is never represented as a one-hour pass.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import time
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
EXPECTED_DEVICE = "9A067715-7CF3-40D3-9064-38423223959B"
stop_requested = False


def run(args: list[str]) -> str:
    p = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if p.returncode:
        raise RuntimeError(f"command failed ({p.returncode}): {' '.join(args)}\n{p.stdout[-3000:]}")
    return p.stdout


def file_sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def device_state(udid: str) -> dict[str, Any]:
    raw = json.loads(run(["xcrun", "simctl", "list", "devices", "--json"]))
    for group in raw.get("devices", {}).values():
        for device in group:
            if device.get("udid") == udid:
                return device
    raise ValueError(f"simulator not found: {udid}")


def app_identity(app: Path) -> tuple[str, Path]:
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError(f"--app must be a built .app directory: {app}")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    bundle = info.get("CFBundleIdentifier")
    executable = app / info.get("CFBundleExecutable", "")
    if not bundle or not executable.is_file():
        raise ValueError("built app lacks bundle identifier or executable")
    return bundle, executable


def app_data(udid: str, bundle: str) -> Path:
    return Path(run(["xcrun", "simctl", "get_app_container", udid, bundle, "data"]).strip())


def main() -> int:
    global stop_requested
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="exact built .app supplied for this run")
    parser.add_argument("--device", default=EXPECTED_DEVICE)
    parser.add_argument("--output", type=Path, help="new or empty output directory")
    parser.add_argument("--duration-seconds", type=int, default=3600,
                        help="total duration; default 3600 (30m home + 30m Explore)")
    parser.add_argument("--sample-seconds", type=float, default=15)
    parser.add_argument("--qa-save-key", default="soak-r001")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.duration_seconds < 60 or args.sample_seconds < 1:
        raise ValueError("duration must be >=60 seconds and sample interval >=1 second")
    app = args.app.expanduser().resolve()
    bundle, executable = app_identity(app)
    if args.device != EXPECTED_DEVICE:
        raise ValueError(f"only dedicated QA simulator is allowed: {EXPECTED_DEVICE}")
    device = device_state(args.device)
    if device.get("state") != "Booted":
        raise ValueError(f"simulator must already be booted; no boot/reset is performed ({device.get('state')})")
    phases = [{"name": "home", "screen": "家", "seconds": args.duration_seconds // 2},
              {"name": "field", "screen": "探索", "seconds": args.duration_seconds - args.duration_seconds // 2}]
    plan = {"app": str(app), "bundleID": bundle, "executableSHA256": file_sha(executable),
            "device": device, "phases": phases, "sampleIntervalSeconds": args.sample_seconds,
            "durationTargetSeconds": args.duration_seconds,
            "metricsSource": "Witch03to05R1/runtime_metrics.json; app's QA-only frame sampler"}
    if args.dry_run:
        print(json.dumps(plan, ensure_ascii=False, indent=2))
        return 0

    out = (args.output or ROOT / "docs/production/current/review/runtime/soak_r001").expanduser().resolve()
    if out.exists() and any(out.iterdir()):
        raise ValueError(f"refusing to overwrite non-empty evidence directory: {out}")
    out.mkdir(parents=True, exist_ok=True)
    start_utc, start_mono = dt.datetime.now(dt.timezone.utc), time.monotonic()
    record: dict[str, Any] = {**plan, "startedAtUTC": start_utc.isoformat(), "status": "RUNNING", "samples": []}
    (out / "RUN.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    (out / "samples.jsonl").write_text("")

    def request_stop(_sig: int, _frame: Any) -> None:
        global stop_requested
        stop_requested = True

    old_handler = signal.signal(signal.SIGINT, request_stop)
    try:
        run(["xcrun", "simctl", "install", args.device, str(app)])
        for phase in phases:
            if stop_requested:
                break
            phase_started_utc = dt.datetime.now(dt.timezone.utc)
            run(["xcrun", "simctl", "launch", "--terminate-running-process", args.device, bundle,
                 "--qa-isolated", f"--qa-save-key={args.qa_save_key}", f"--screen={phase['screen']}"])
            phase_start = time.monotonic()
            next_sample = phase_start
            last_metric_hash = None
            while time.monotonic() - phase_start < phase["seconds"] and not stop_requested:
                now = time.monotonic()
                if now >= next_sample:
                    elapsed = now - start_mono
                    timestamp = dt.datetime.now(dt.timezone.utc).isoformat()
                    support = app_data(args.device, bundle) / "Library/Application Support/Witch03to05R1"
                    metric_path = support / "runtime_metrics.json"
                    sample: dict[str, Any] = {"atUTC": timestamp, "elapsedSeconds": elapsed,
                                              "phase": phase["name"], "metrics": None}
                    if metric_path.is_file():
                        raw = metric_path.read_bytes()
                        last_metric_hash = hashlib.sha256(raw).hexdigest()
                        sample["metricSHA256"] = last_metric_hash
                        try:
                            metrics = json.loads(raw)
                            metric_time = dt.datetime.fromisoformat(metrics["date"].replace("Z", "+00:00"))
                            sample["metricFreshForPhase"] = metric_time >= phase_started_utc
                            if sample["metricFreshForPhase"]:
                                sample["metrics"] = metrics
                            else:
                                sample["metricReadError"] = "metric payload predates this phase/app launch"
                        except json.JSONDecodeError as exc:
                            sample["metricReadError"] = str(exc)
                        except (KeyError, TypeError, ValueError) as exc:
                            sample["metricReadError"] = f"metric timestamp invalid: {exc}"
                    else:
                        sample["metricReadError"] = "runtime_metrics.json not present yet"
                    record["samples"].append(sample)
                    with (out / "samples.jsonl").open("a") as f:
                        f.write(json.dumps(sample, ensure_ascii=False) + "\n")
                    next_sample += args.sample_seconds
                    print(f"{phase['name']}: elapsed={elapsed:.1f}s metric={'yes' if sample['metrics'] else 'no'}", flush=True)
                    record["lastMetricSHA256"] = last_metric_hash
                    (out / "RUN.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
                time.sleep(min(0.5, max(0.0, next_sample - time.monotonic())))
        record["status"] = "INTERRUPTED" if stop_requested else "COMPLETED_TARGET_DURATION"
    except KeyboardInterrupt:
        record["status"] = "INTERRUPTED"
    except Exception as exc:
        record["status"] = "FAILED"
        record["error"] = repr(exc)
        raise
    finally:
        signal.signal(signal.SIGINT, old_handler)
        end = time.monotonic()
        record["endedAtUTC"] = dt.datetime.now(dt.timezone.utc).isoformat()
        record["observedElapsedSeconds"] = end - start_mono
        record["observedElapsedMinutes"] = (end - start_mono) / 60
        record["durationTargetMet"] = end - start_mono >= args.duration_seconds
        (out / "RUN.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    print(f"{record['status']}: observed {record['observedElapsedSeconds']:.1f}s; evidence {out}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"runtime_soak: ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)

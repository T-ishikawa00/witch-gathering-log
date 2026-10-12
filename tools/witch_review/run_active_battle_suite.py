#!/usr/bin/env python3
"""Observe a bounded real-time battle suite on Root's isolated simulator.

The native app commits and plays each battle, verifies its terminal HP receipt,
and reloads its file save. This observer never edits game saves or grants items.
"""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import time
import uuid


DEVICE = "1D034CC3-9259-4AEE-A21D-E6E88D242ACF"


def command(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--cycles", type=int, choices=(1, 2, 3), default=3)
    args = parser.parse_args()
    app = args.app.resolve()
    info = plistlib.loads((app / "Info.plist").read_bytes())
    bundle = info["CFBundleIdentifier"]
    receipt = json.loads((app.parent / "BUILD_RECEIPT.json").read_text())
    executable_sha = sha(app / info["CFBundleExecutable"])
    assert receipt["status"] == "SIMULATOR_BUILD_PASS"
    assert receipt["executable_sha256"] == executable_sha
    assert bundle == "local.witch.autonomous.r1"
    out = args.output.resolve()
    if out.exists() and any(out.iterdir()):
        raise ValueError("Refusing to overwrite nonempty evidence directory")
    out.mkdir(parents=True, exist_ok=True)
    key = "active-r021-" + uuid.uuid4().hex
    run = {"status": "RUNNING", "app": str(app), "executableSHA256": executable_sha,
           "buildReceiptSHA256": sha(app.parent / "BUILD_RECEIPT.json"),
           "device": DEVICE, "saveKey": key, "cyclesRequested": args.cycles,
           "startedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
           "scope": "ISOLATED_FIXTURE_REAL_TIME_SIMULATOR_NOT_DEVICE_OR_BALANCE_APPROVAL"}
    start = time.monotonic()

    def persist():
        run["elapsedSeconds"] = time.monotonic() - start
        (out / "RUN.json").write_text(json.dumps(run, indent=2))

    persist()
    shutil.copy2(app.parent / "BUILD_RECEIPT.json", out / "BUILD_RECEIPT.json")
    command("xcrun", "simctl", "install", DEVICE, str(app))
    support = Path(command("xcrun", "simctl", "get_app_container", DEVICE, bundle, "data")) / "Library/Application Support/Witch03to05R1"
    save = support / ("qa-" + key + "-save.json")
    assert not save.exists()
    launch = command("xcrun", "simctl", "launch", "--terminate-running-process", DEVICE, bundle,
                     "--qa-isolated", "--qa-save-key=" + key, "--qa-fixture=challenge",
                     "--qa-active-battle-suite=" + str(args.cycles), "--screen=探索")
    run["launchResult"] = launch
    seen = -1
    last = None
    try:
        while time.monotonic() - start < 3600:
            report = support / "active_battle_qa.json"
            if report.exists():
                candidate = json.loads(report.read_text())
                if candidate.get("saveFile") == save.name:
                    last = candidate
                    count = len(last.get("cases", []))
                    if count != seen or last["status"] != "RUNNING":
                        shutil.copy2(report, out / "PROGRESS.json")
                        run["nativeStatus"] = last["status"]
                        run["completedCases"] = count
                        persist()
                        print(f"cases={count}/{args.cycles * 30} native={last['status']} elapsed={run['elapsedSeconds']:.1f}s", flush=True)
                        seen = count
                    if last["status"] != "RUNNING":
                        run["status"] = last["status"]
                        shutil.copy2(report, out / "FINAL.json")
                        break
            time.sleep(5)
        else:
            run["status"] = "OBSERVER_TIMEOUT_NATIVE_STATE_UNKNOWN"
    except KeyboardInterrupt:
        run["status"] = "OBSERVER_INTERRUPTED_NATIVE_MAY_CONTINUE"
    finally:
        for name in [save.name, "active_battle_initial_snapshot.json", "runtime_metrics.json",
                     "last_battle.json", "last_battle_art.json", "last_presentation_hp.json"]:
            source = support / name
            if source.exists():
                shutil.copy2(source, out / name)
        run["endedAt"] = dt.datetime.now(dt.timezone.utc).isoformat()
        persist()
    if run["status"] == "PASS":
        assert last is not None and len(last["cases"]) == args.cycles * 30
        rows = last["cases"]
        run["allSavedSnapshotsMatch"] = all(r["reopenedSnapshotEqual"] for r in rows)
        run["allRevisionsIncrementOnce"] = all(r["revisionDelta"] == 1 for r in rows)
        run["allTerminalHPMatched"] = all(not r["hpMismatches"] for r in rows)
        run["uniqueOperationIDs"] = len({r["operationID"] for r in rows}) == len(rows)
        persist()
        assert all(run[k] for k in ["allSavedSnapshotsMatch", "allRevisionsIncrementOnce", "allTerminalHPMatched", "uniqueOperationIDs"])
    return 0 if run["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())

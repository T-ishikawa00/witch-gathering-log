#!/usr/bin/env python3
"""Observe three real isolated battle presentations on the reserved QA Simulator."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import signal
import subprocess
import time
import uuid

DEVICE = "F843518C-7377-434C-A960-B26FB7F34C4B"
BUNDLE = "local.witch.autonomous.r1"


def command(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--device", default=DEVICE)
    parser.add_argument("--require-party-hold", action="store_true")
    args = parser.parse_args()
    device = args.device
    app = args.app.resolve()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    run = {"started": datetime.datetime.now().astimezone().isoformat(),
           "app": str(app), "appSHA256": sha(app / "WitchGathering"),
           "device": device, "scope": "Isolated candidate battle presentation, not balance or device acceptance",
           "cases": [], "status": "RUNNING"}
    def persist():
        (out / "RUN.json").write_text(json.dumps(run, indent=2) + "\n")
    persist()
    command("xcrun", "simctl", "install", device, str(app))
    data = Path(command("xcrun", "simctl", "get_app_container", device, BUNDLE, "data").stdout.strip())
    folder = data / "Library/Application Support/Witch03to05R1"
    for name, fixture, enemy, expected in [
        ("r03a_victory", "challenge", "B_R03_A", True),
        ("dragon_victory", "challenge", "B_R04_B", True),
        ("dragon_defeat", "area-routing", "B_R04_B", False),
    ]:
        case = out / name
        case.mkdir()
        key = "resolution-" + name.replace("_", "-") + "-" + uuid.uuid4().hex
        save_name = "qa-" + key + "-save.json"
        if (folder / save_name).exists():
            raise RuntimeError("Refuse a reused save")
        command("xcrun", "simctl", "terminate", device, BUNDLE, check=False)
        with (case / "record.log").open("w") as log:
            video = subprocess.Popen(["xcrun", "simctl", "io", device, "recordVideo", "--codec=h264", str(case / "BATTLE.mp4")], stdout=log, stderr=log)
            began = time.monotonic()
            receipt = None
            try:
                time.sleep(0.4)
                launch = command("xcrun", "simctl", "launch", device, BUNDLE,
                                 "--qa-isolated", "--qa-save-key=" + key,
                                 "--qa-fixture=" + fixture, "--qa-persist-fixture",
                                 "--qa-encounter=" + enemy)
                (case / "launch.log").write_text(launch.stdout + launch.stderr)
                while time.monotonic() - began < 180:
                    path = folder / "last_battle_resolution.json"
                    if path.exists():
                        try:
                            wrapper = json.loads(path.read_text())
                            value = json.loads(wrapper["value"])
                            if value.get("saveFile") == save_name:
                                receipt = (wrapper, value)
                                break
                        except (OSError, ValueError, KeyError):
                            pass
                    time.sleep(0.1)
                elapsed = time.monotonic() - began
                time.sleep(0.35)
                command("xcrun", "simctl", "io", device, "screenshot", str(case / "AFTER.png"))
            finally:
                video.send_signal(signal.SIGINT)
                try:
                    video.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    video.terminate()
                    video.wait(timeout=5)
        if receipt is None:
            raise RuntimeError("No fresh result receipt for " + name)
        wrapper, value = receipt
        for filename in ["last_battle_resolution.json", "last_battle.json", "last_battle_art.json",
                         "last_presentation_hp.json", "battle_before.json", save_name]:
            path = folder / filename
            if path.exists():
                shutil.copy2(path, case / filename)
        before = json.loads((case / "battle_before.json").read_text())
        envelope = json.loads((case / save_name).read_text())
        after = envelope.get("snapshot")
        if not isinstance(after, dict) or not isinstance(after.get("revision"), int):
            raise RuntimeError("SaveRepository envelope has no snapshot revision")
        hp_wrapper = json.loads((case / "last_presentation_hp.json").read_text())
        row = {"name": name, "fixture": fixture, "enemy": enemy, "expectedWon": expected,
               "won": value["won"], "saveFile": save_name, "observedVideoSecondsAtReceipt": elapsed,
               "requestedSeconds": value["requestedSeconds"], "renderedSeconds": value["renderedSeconds"],
               "cancelled": value["cancelled"], "samples": len(value["samples"]),
               "revisionBefore": before["revision"], "revisionAfter": after["revision"],
               "hpMismatches": json.loads(hp_wrapper["value"]), "files": {p.name: sha(p) for p in case.iterdir() if p.is_file()}}
        row["checks"] = {"expectedResult": value["won"] == expected,
                         "renderedDuration": value["renderedSeconds"] >= value["requestedSeconds"],
                         "notCancelled": not value["cancelled"], "samplesExist": bool(value["samples"]),
                         "revisionOnce": after["revision"] - before["revision"] == 1,
                         "freshHP": hp_wrapper["revision"] == after["revision"] and not row["hpMismatches"],
                         "freshResolution": wrapper["revision"] == after["revision"] and value["enemyID"] == enemy}
        if args.require_party_hold:
            samples = value["samples"]
            initial_poses = samples[0]["party"] if samples else {}
            row["checks"]["partyResultHeld"] = (len(initial_poses) == 4
                and all(pose in ("hit", "resolve") for pose in initial_poses.values())
                and all(s.get("holdingBattleResult") is True and s["party"] == initial_poses for s in samples))
        row["status"] = "PASS" if all(row["checks"].values()) else "FAIL"
        run["cases"].append(row)
        persist()
        print(name, row["status"], "won=" + str(value["won"]), "hold=" + str(value["renderedSeconds"]), flush=True)
    run["status"] = "PASS" if all(row["status"] == "PASS" for row in run["cases"]) else "FAIL"
    persist()
    return 0 if run["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())

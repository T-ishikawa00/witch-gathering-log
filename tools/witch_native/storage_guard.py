#!/usr/bin/env python3
"""Measure capacity before work; record growth without deleting anything."""
import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import shutil
import time

# R187: direct Human resumption instruction supersedes the fixed R184 50 GB
# gate. Reserve both the task's maximum additional output and safety headroom.
WARN_BYTES = 20_000_000_000
HOLD_BYTES = 10_000_000_000
SAFETY_BYTES = 2_000_000_000


class StorageCapacityError(RuntimeError):
    pass


def capacity_budget(free_bytes, heavy=False, expected_bytes=None, *,
                    safety_bytes=SAFETY_BYTES, minimum_remaining_bytes=HOLD_BYTES):
    values = [free_bytes, safety_bytes, minimum_remaining_bytes]
    if expected_bytes is not None:
        values.append(expected_bytes)
    if any(isinstance(v, bool) or not isinstance(v, int) or v < 0 for v in values):
        raise ValueError("Capacity, estimate and reserves must be nonnegative integer bytes")
    estimate_known = expected_bytes is not None
    expected = expected_bytes or 0
    floor = max(HOLD_BYTES, minimum_remaining_bytes)
    reserve = safety_bytes if heavy else 0
    projected = free_bytes - expected
    required = floor + expected + reserve
    reason = None
    if heavy and not estimate_known:
        reason = "EXPECTED_MAXIMUM_NOT_SUPPLIED"
    elif heavy and free_bytes < required:
        reason = "TASK_MAXIMUM_AND_RESERVE_WOULD_BREACH_FLOOR"
    status = ("HOLD_LARGE_OUTPUT" if reason else
              "WARN_LOW_CAPACITY" if min(free_bytes, projected-reserve) < WARN_BYTES else "READY")
    return {"status": status, "holdReason": reason, "estimateKnown": estimate_known,
            "expectedAdditionalBytes": expected_bytes, "safetyReserveBytes": reserve,
            "minimumRemainingBytes": floor, "requiredStartBytes": required,
            "projectedFreeBytes": projected, "projectedFreeAfterSafetyBytes": projected-reserve}


def capacity_state(free_bytes, heavy=False, expected_bytes=None, *,
                   safety_bytes=SAFETY_BYTES, minimum_remaining_bytes=HOLD_BYTES):
    return capacity_budget(free_bytes, heavy, expected_bytes, safety_bytes=safety_bytes,
                           minimum_remaining_bytes=minimum_remaining_bytes)["status"]


def measure_artifacts(paths):
    """Only explicit paths; do not traverse symlinks or count hard links twice."""
    seen = set()
    results = []
    for raw in paths:
        path = Path(raw).absolute()
        logical = allocated = files = symlinks = errors = 0
        pending = [path]
        while pending:
            current = pending.pop()
            try:
                if current.is_symlink():
                    symlinks += 1
                    continue
                info = current.lstat()
                identity = (info.st_dev, info.st_ino)
                if identity in seen:
                    continue
                seen.add(identity)
                if current.is_dir():
                    pending.extend(current.iterdir())
                elif current.is_file():
                    files += 1
                    logical += info.st_size
                    allocated += info.st_blocks * 512
            except FileNotFoundError:
                if current != path:
                    errors += 1
            except OSError:
                errors += 1
        results.append({"path": str(path), "files": files, "logicalBytes": logical,
                        "allocatedBytes": allocated, "symlinksSkipped": symlinks,
                        "scanErrors": errors})
    return results


def check_capacity(root, phase, *, heavy=False, expected_bytes=None, artifact_paths=(),
                   safety_bytes=SAFETY_BYTES, minimum_remaining_bytes=HOLD_BYTES):
    root = Path(root).resolve()
    free = shutil.disk_usage(root).free
    budget = capacity_budget(free, heavy, expected_bytes, safety_bytes=safety_bytes,
                             minimum_remaining_bytes=minimum_remaining_bytes)
    state = budget["status"]
    now = time.time()
    record = {"schemaVersion": 2, "at": dt.datetime.now().astimezone().isoformat(),
              "epochSeconds": now, "phase": phase, "root": str(root),
              "freeBytes": free, "warnBelowBytes": WARN_BYTES,
              "holdLargeBelowBytes": HOLD_BYTES, **budget,
              "heavy": heavy, "status": state, "deletion": False,
              "artifacts": measure_artifacts(artifact_paths),
              "caveat": "Filesystem free-space delta includes other processes; APFS shared blocks are not measured by per-file allocated bytes."}
    directory = root / "docs/production/current/storage_management_r001"
    directory.mkdir(parents=True, exist_ok=True)
    journal = directory / "CAPACITY_EVENTS_R002.jsonl"
    with journal.open("a+") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        handle.seek(0)
        last = None
        for line in handle:
            if line.strip():
                last = json.loads(line)
        if last:
            seconds = now - last["epochSeconds"]
            record["sincePreviousSeconds"] = seconds
            record["freeDeltaBytes"] = free - last["freeBytes"]
            if seconds > 0:
                record["observedConsumptionGBPerHour"] = (last["freeBytes"] - free) / seconds * 3600 / 1e9
            previous = {item["path"]: item for item in last.get("artifacts", [])}
            for item in record["artifacts"]:
                if item["path"] in previous:
                    item["allocatedDeltaBytes"] = item["allocatedBytes"] - previous[item["path"]]["allocatedBytes"]
        handle.seek(0, os.SEEK_END)
        handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    print(f"Storage {state}: {free / 1e9:.2f} GB free ({phase})", flush=True)
    if state == "HOLD_LARGE_OUTPUT":
        raise StorageCapacityError("Large output held: "+budget["holdReason"]+"; no automatic cleanup is authorized")
    return record


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--phase", required=True)
    parser.add_argument("--heavy", action="store_true")
    parser.add_argument("--expected-bytes", type=int)
    parser.add_argument("--safety-bytes", type=int, default=SAFETY_BYTES)
    parser.add_argument("--minimum-free-bytes", type=int, default=HOLD_BYTES)
    parser.add_argument("--artifact", type=Path, action="append", default=[])
    args = parser.parse_args()
    check_capacity(args.root, args.phase, heavy=args.heavy,
                   expected_bytes=args.expected_bytes, artifact_paths=args.artifact,
                   safety_bytes=args.safety_bytes, minimum_remaining_bytes=args.minimum_free_bytes)

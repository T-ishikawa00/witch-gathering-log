"""Read-only verification of delivered evidence and executable reference checks.

Does not install dependencies, access the network, modify Mac settings, or change
project game files. Python bytecode writes are disabled for subprocess tests.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_files() -> None:
    rows = json.loads((ROOT / "PACKAGE_MANIFEST.json").read_text(encoding="utf-8"))["files"]
    for row in rows:
        path = (ROOT / row["path"]).resolve()
        if not path.is_relative_to(ROOT):
            raise RuntimeError(f"Unsafe manifest path: {row['path']}")
        if not path.is_file() or path.stat().st_size != row["size_bytes"] or digest(path) != row["sha256"]:
            raise RuntimeError(f"Package integrity mismatch: {row['path']}")
    originals = json.loads((ROOT / "data/SOURCE_HASHES.json").read_text(encoding="utf-8"))
    for row in originals:
        if digest(ROOT / row["to"]) != row["sha256"]:
            raise RuntimeError(f"Original source changed: {row['to']}")
    print(f"Package hashes: {len(rows)} verified; source copies: {len(originals)} verified.", flush=True)


def run_tests() -> None:
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    suites = [
        ("source/growth_r2/validation", "test_reference.py"),
        ("source/economy_r3/tools", "test_economy.py"),
        ("tools", "test_integration.py"),
    ]
    for folder, name in suites:
        print(f"\nRunning {folder}/{name}", flush=True)
        result = subprocess.run([sys.executable, "-B", name], cwd=ROOT / folder, env=env, check=False)
        if result.returncode:
            raise RuntimeError(f"Test failure: {folder}/{name}")


def reproduce_golden_logs() -> None:
    from progression_bridge import Battle, LOCAL, intro_state, prepared
    intro = intro_state()
    actual_a = Battle(intro.loadout(), LOCAL["bosses"]["B_R01_A"], 1001, True).run()
    prepared_state = prepared()
    prepared_state.advance(12 * 3600000 - prepared_state.eco.last_wall_ms)
    actual_b = Battle(prepared_state.loadout(), LOCAL["bosses"]["B_R01_B"], 1001, True).run()
    for name, actual in [("GOLDEN_BOAR_LOG.json", actual_a), ("GOLDEN_TREE_LOG.json", actual_b)]:
        expected = json.loads((ROOT / "results" / name).read_text(encoding="utf-8"))
        # JSON round-trip normalizes tuples and dictionary keys; preserves values.
        if json.loads(json.dumps(actual, ensure_ascii=False)) != expected:
            raise RuntimeError(f"Golden log mismatch: {name}")
        print(f"Exact golden replay: {name}", flush=True)


if __name__ == "__main__":
    try:
        verify_files()
        run_tests()
        reproduce_golden_logs()
        print("\nPASS: delivered bytes, source copies, 3 test suites, 2 golden logs.")
        print("This is not production gameplay, balance, device, or human-approval acceptance.")
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)

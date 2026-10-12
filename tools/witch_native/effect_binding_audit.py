#!/usr/bin/env python3
"""Run isolated normal battle playback for three candidate R4 effect contracts."""
from pathlib import Path
import collections, hashlib, json, subprocess, time

DEVICE = "9A067715-7CF3-40D3-9064-38423223959B"
BUNDLE = "local.witch.autonomous.r1"
CASES = {
    "E_R01_02": {"effect": "ACT_E_R01_02_silk", "impact": "enemy_hit", "status": "party_slow"},
    "E_R01_03": {"effect": "ACT_E_R01_03_double_leaf", "impact": "enemy_hit"},
    "E_R02_01": {"effect": "ACT_E_R02_01_spore", "impact": "enemy_hit", "status": "party_drowse"},
    "E_R02_04": {"effect": "ACT_E_R02_04_support_arc", "impact": "enemy_magic_support"},
    "E_R05_03": {"effect": "ACT_E_R05_03_light_transfer", "impact": "enemy_light_transfer"},
}

def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()

def read(path):
    try:
        return json.loads(path.read_text())
    except Exception:
        return None

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--timeout", type=int, default=120)
    ap.add_argument("--only", action="append", choices=sorted(CASES), help="Run one or more selected candidate actors")
    args = ap.parse_args()
    app = args.app.resolve(); out = args.output.resolve()
    if out.exists():
        raise SystemExit(f"Refusing to overwrite existing evidence: {out}")
    exe = app / "WitchGathering"
    report = {"status": "RUNNING", "app": str(app), "executableSHA256": sha(exe),
              "simulator": DEVICE, "fixture": "isolated challenge endgame QA fixture; not natural progression",
              "cases": []}
    out.mkdir(parents=True)
    run("xcrun", "simctl", "install", DEVICE, str(app))
    data = Path(run("xcrun", "simctl", "get_app_container", DEVICE, BUNDLE, "data"))
    support = data / "Library/Application Support/Witch03to05R1"
    for enemy in (args.only or list(CASES)):
        contract = CASES[enemy]
        case_dir = out / enemy; case_dir.mkdir()
        key = f"effect-bind-{out.name.replace('_','-')}-{enemy.lower().replace('_','-')}"
        save = support / f"qa-{key}-save.json"
        battle, art, hp = (support / name for name in ("last_battle.json", "last_battle_art.json", "last_presentation_hp.json"))
        pre_mtime = battle.stat().st_mtime_ns if battle.exists() else 0
        started = time.time()
        launch = run("xcrun", "simctl", "launch", "--terminate-running-process", DEVICE, BUNDLE,
                     "--qa-isolated", "--qa-save-key="+key, "--qa-fixture=challenge",
                     "--qa-encounter="+enemy, "--qa-slow-battle")
        deadline = time.monotonic() + args.timeout
        fresh = None
        while time.monotonic() < deadline:
            if battle.exists() and battle.stat().st_mtime_ns > pre_mtime and battle.stat().st_mtime >= started:
                obj = read(battle)
                if obj and enemy in str(obj.get("value", "")):
                    fresh = obj; break
            time.sleep(.35)
        time.sleep(1.2)
        run("xcrun", "simctl", "io", DEVICE, "screenshot", str(case_dir / "screen.png"))
        row = {"enemyID": enemy, "saveKey": key, "launch": launch, "receiptFresh": fresh is not None}
        if fresh:
            for source, name in ((battle,"last_battle.json"),(art,"last_battle_art.json"),(hp,"last_presentation_hp.json")):
                if source.exists() and source.stat().st_mtime >= started:
                    dest = case_dir / name; dest.write_bytes(source.read_bytes()); row[name+"SHA256"] = sha(dest)
            snap = read(save) if save.exists() else None
            value = fresh.get("value", "")
            row["battleReceipt"] = value
            if snap:
                snapshot = snap.get("snapshot", {})
                result = snapshot.get("lastCombatResult") or {}
                events = result.get("events", [])
                (case_dir / "save.json").write_bytes(save.read_bytes())
                row.update({"won": result.get("won"), "revision": snapshot.get("revision"),
                            "eventKinds": dict(collections.Counter(e.get("kind","?") for e in events)),
                            "impactEvents": [e for e in events if e.get("sourceID")==enemy and e.get("kind")==contract["impact"]],
                            "saveSHA256": sha(save)})
                if "status" in contract:
                    row["statusEvents"] = [e for e in events if e.get("sourceID")==enemy and e.get("kind")==contract["status"]]
            art_obj = read(art) if art.exists() else None
            row["artReceipt"] = art_obj
            row["expectedEffectCount"] = (art_obj or {}).get("value", "")
        row["screenshotSHA256"] = sha(case_dir / "screen.png")
        report["cases"].append(row)
        report["status"] = "RUNNING"
        (out / "RUN.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n")
        if not row["receiptFresh"]:
            report["status"] = "INCOMPLETE_RECEIPT_TIMEOUT"; break
    else:
        report["status"] = "CAPTURED_REQUIRES_CONTRACT_ASSERTION"
    (out / "RUN.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n")
    print(json.dumps({"status": report["status"], "cases": [(c["enemyID"], c["receiptFresh"]) for c in report["cases"]]}))

if __name__ == "__main__": main()

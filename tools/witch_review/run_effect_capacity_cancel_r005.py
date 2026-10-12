#!/usr/bin/env python3
"""Run bounded R005 effect QA only on its assigned F843 simulator."""
from pathlib import Path
import hashlib
import json
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
DEVICE = "F843518C-7377-434C-A960-B26FB7F34C4B"
BUNDLE_ID = "local.witch.autonomous.r1"
APP = ROOT / "native/build/app_20261011T002604/WitchGathering.app"
OUT = ROOT / "docs/production/current/native/effect_capacity_cancel_r005/run_001"


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def load(path):
    try:
        return json.loads(path.read_text())
    except Exception:
        return None


def parse_art(path):
    value = (load(path) or {}).get("value")
    if isinstance(value, str):
        try:
            return json.loads(value)
        except Exception:
            return None
    return value if isinstance(value, dict) else None


def capture_case(name, key, args, output_file, expected_receipt_kind, expected_save_name):
    case = OUT / name
    case.mkdir()
    support = Path(run("xcrun", "simctl", "get_app_container", DEVICE, BUNDLE_ID, "data")) / "Library/Application Support/Witch03to05R1"
    report_file = support / output_file if output_file else None
    receipt_path = support / expected_receipt_kind
    save_path = support / expected_save_name
    began = time.time()
    receipt_mtime = receipt_path.stat().st_mtime if receipt_path.exists() else 0
    report_mtime = report_file.stat().st_mtime if report_file and report_file.exists() else 0
    launch = run("xcrun", "simctl", "launch", "--terminate-running-process", DEVICE, BUNDLE_ID,
                 "--qa-isolated", "--qa-fixture=challenge", "--qa-persist-fixture",
                 "--qa-save-key=" + key, "--qa-slow-battle", *args)
    screenshots = []
    next_capture = time.monotonic() + 2
    deadline = time.monotonic() + 420
    observed = None
    while time.monotonic() < deadline:
        if time.monotonic() >= next_capture:
            dest = case / f"screen_{len(screenshots):03d}.png"
            run("xcrun", "simctl", "io", DEVICE, "screenshot", str(dest))
            screenshots.append(dest.name)
            next_capture += 10
        current = None
        if report_file and report_file.exists() and report_file.stat().st_mtime > report_mtime and report_file.stat().st_mtime >= began:
            current = load(report_file)
        if current and current.get("status"):
            observed = current
            break
        receipt = load(receipt_path) if receipt_path.exists() and receipt_path.stat().st_mtime > receipt_mtime and receipt_path.stat().st_mtime >= began else None
        if receipt and receipt.get("kind") == expected_receipt_kind.removeprefix("last_").removesuffix(".json"):
            observed = receipt
            # Battle itself may still be animating; the final art receipt is the completion signal.
            art_kind = expected_receipt_kind.replace("last_", "last_").replace(".json", "_art.json")
            art_path = support / art_kind
            if art_path.exists() and art_path.stat().st_mtime >= began:
                observed = {"receipt": receipt, "art": load(art_path)}
                break
        time.sleep(0.2)
    run("xcrun", "simctl", "io", DEVICE, "screenshot", str(case / "result.png"))
    if observed is None:
        (case / "TIMEOUT.json").write_text(json.dumps({"status":"TIMEOUT","launch":launch,"screenshots":screenshots},indent=2)+"\n")
        return {"name":name,"status":"TIMEOUT","launch":launch,"casePath":str(case)}

    for name_to_copy in (output_file, expected_receipt_kind, expected_receipt_kind.replace(".json", "_art.json"),
                         "last_presentation_hp.json", "battle_before.json", "last_battle.json", "last_battle_art.json",
                         "last_challenge.json", "last_challenge_art.json"):
        if not name_to_copy:
            continue
        source = support / name_to_copy
        if source.exists() and source.stat().st_mtime >= began:
            (case / name_to_copy).write_bytes(source.read_bytes())

    if not save_path.exists():
        raise RuntimeError(f"expected isolated save missing: {save_path}")
    before = save_path.read_bytes()
    snap_obj = load(save_path) or {}
    snapshot = snap_obj.get("snapshot", {})
    battle = snapshot.get("lastCombatResult") or {}
    events = battle.get("events", [])
    art_path = case / expected_receipt_kind.replace(".json", "_art.json")
    art = parse_art(art_path) if art_path.exists() else None
    cue_trace = ((art or {}).get("effects") or {}).get("cueTrace", [])

    # Restart the same isolated file without any fixture or battle arguments.
    restart = run("xcrun", "simctl", "launch", "--terminate-running-process", DEVICE, BUNDLE_ID,
                  "--qa-isolated", "--qa-save-key=" + key, "--screen=探索")
    time.sleep(2)
    run("xcrun", "simctl", "io", DEVICE, "screenshot", str(case / "restart.png"))
    after = save_path.read_bytes()
    (case / "save_before_restart.json").write_bytes(before)
    (case / "save_after_restart.json").write_bytes(after)

    kinds = {}
    for event in events:
        kind = event.get("kind", "?")
        kinds[kind] = kinds.get(kind, 0) + 1
    row = {
        "name": name, "launch": launch, "restart": restart,
        "fixtureScope": "isolated QA challenge fixture; committed command path, not natural progression",
        "battleWon": battle.get("won"), "revision": snapshot.get("revision"),
        "eventCount": len(events), "eventKinds": kinds,
        "eventRoots": sorted({e.get("rootActionID") for e in events if e.get("rootActionID")}),
        "cueTrace": cue_trace, "screenshots": screenshots + ["result.png", "restart.png"],
        "saveSHA256BeforeRestart": sha(before), "saveSHA256AfterRestart": sha(after),
        "saveByteIdenticalAfterRestart": before == after,
        "isolatedSave": save_path.name, "casePath": str(case),
    }
    if "enemy_armor" in kinds:
        armor_roots = {e.get("rootActionID") for e in events if e.get("kind") == "enemy_armor"}
        armor_cues = [e for e in cue_trace if e.get("step") in ("direct_full:enemy_armor", "coalesced:enemy_armor")]
        row["armorAssertions"] = {
            "eventCount14": kinds["enemy_armor"] == 14,
            "all14EventRootsRepresented": len(armor_roots) == 14 and armor_roots.issubset({e.get("rootActionID") for e in armor_cues}),
            "allVisualTargetsEnemy": len(armor_cues) == 14 and all(e.get("targetIDs") in ("E_R02_02", "ACT_E_R02_02") for e in armor_cues),
            "allHavePlacement": len(armor_cues) == 14 and all(all(e.get("placement."+k) is not None for k in ("sourceAnchor","targetAnchor","impactX","impactY")) for e in armor_cues),
            "effectRows": armor_cues,
        }
    if "cast_interrupt" in kinds:
        tool_rows = [e for e in cue_trace if e.get("sourceID") == "E_R03_03" and e.get("effectID") == "ACT_E_R03_03_tool_combo"]
        casts = [e for e in events if e.get("sourceID") == "E_R03_03" and e.get("kind") == "enemy_cast_start"]
        impacts = [e for e in events if e.get("sourceID") == "E_R03_03" and e.get("kind") == "enemy_hit"]
        interrupts = [e for e in events if e.get("kind") == "cast_interrupt" and e.get("targetID") == "E_R03_03"]
        cue_targets = [e for e in tool_rows if e.get("step") == "cue_placement"]
        canceled_trace_roots = {e.get("rootActionID") for e in tool_rows if str(e.get("step", "")).startswith("cue_cancel:cast_interrupt")}
        interrupt_roots = {e.get("rootActionID") for e in interrupts}
        row["toolCastAssertions"] = {
            "fiveTellStarts": len(casts) == 5,
            "twoVisualImpactRoots": len({e.get("rootActionID") for e in tool_rows if e.get("step") == "impact_advance"}) == 2,
            "threeInterrupts": len(interrupts) == 3,
            "cancelTraceRootsMatchInterruptRoots": canceled_trace_roots == interrupt_roots and len(interrupt_roots) == 3,
            "threeCanceledRootsNoImpact": len(interrupts) == 3 and all(
                not any(h.get("kind") == "enemy_hit" and h.get("rootActionID") == i.get("rootActionID") and h.get("sourceID") == "E_R03_03" for h in events)
                for i in interrupts
            ),
            "fiveCueTargetsMatchAuthoredTelegraph": len(cue_targets) == 5 and all(
                e.get("targetIDs") == {"C_WITCH":"ERNA","C_APPRENTICE":"LUNA","C_SMITH":"AIRA","C_FAMILIAR":"NOIR"}.get(
                    next((t.get("targetID") for t in events if t.get("kind")=="enemy_telegraph" and t.get("sourceID")=="E_R03_03" and t.get("rootActionID")==e.get("rootActionID")), "")
                ) for e in cue_targets
            ),
            "cancelCount": sum(str(e.get("step", "")).startswith("cue_cancel:cast_interrupt") for e in tool_rows),
            "effectRows": tool_rows,
        }
    (case / "SUMMARY.json").write_text(json.dumps(row, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    return row


def main():
    if not APP.is_dir() or OUT.exists():
        raise SystemExit(f"App missing or output exists: app={APP.is_dir()} output={OUT.exists()}")
    OUT.mkdir(parents=True)
    receipt = ROOT / "native/build/app_20261011T002604/BUILD_RECEIPT.json"
    exe = APP / "WitchGathering"
    metadata = {
        "status":"RUNNING", "device":DEVICE, "bundle":str(APP),
        "executableSHA256":sha(exe.read_bytes()), "buildReceiptSHA256":sha(receipt.read_bytes()),
        "effectBudgetSourceSHA256":json.loads(receipt.read_text())["source_sha256"]["native/WitchApp/EffectBudgetRegressionQA.swift"],
        "coordinatorSourceSHA256":json.loads(receipt.read_text())["source_sha256"]["native/WitchApp/EffectCueCoordinator.swift"],
        "startedAt":time.strftime("%Y-%m-%dT%H:%M:%S%z"), "cases":[]
    }
    (OUT / "RUN.json").write_text(json.dumps(metadata,indent=2)+"\n")
    run("xcrun","simctl","install",DEVICE,str(APP))
    cases = [
        ("synthetic_budget","fxr005-synthetic",["--qa-effect-budget-regression"],"effect_budget_regression_fxr005-synthetic.json","effect_budget_regression_fxr005-synthetic.json","qa-fxr005-synthetic-save.json"),
        ("e_r02_02_armor","fxr005-armor",["--qa-encounter=E_R02_02"],None,"last_battle.json","qa-fxr005-armor-save.json"),
        ("ch_r03_03_tool_combo","fxr005-toolcombo",["--qa-challenge=CH_R03_03"],None,"last_challenge.json","qa-fxr005-toolcombo-save.json"),
    ]
    rows=[]
    for name,key,args,report_file,receipt_kind,save_name in cases:
        row=capture_case(name,key,args,report_file,receipt_kind,save_name)
        rows.append(row)
        metadata["cases"]=rows
        metadata["status"]="RUNNING"
        (OUT / "RUN.json").write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+"\n")
        print(json.dumps({"case":name,"status":row.get("status","CAPTURED"),"events":row.get("eventCount"),"savedRestartSame":row.get("saveByteIdenticalAfterRestart")}),flush=True)
    metadata["status"]="CAPTURED_REQUIRES_REVIEW"
    (OUT / "RUN.json").write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+"\n")
    print("CAPTURED",OUT,flush=True)


if __name__=="__main__":
    main()

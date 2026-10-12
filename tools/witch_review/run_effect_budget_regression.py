#!/usr/bin/env python3
"""Run the current isolated simulator presentation regressions, preserving raw evidence."""
import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
BUNDLE = "local.witch.autonomous.r1"
EXPECTED = {
    "armor_three_roots_coalesce",
    "tool_combo_two_impacts_three_cancels",
    "enemy_to_party_interrupt_does_not_cancel",
    "unmatched_tell_without_impact_or_interrupt_stays_effect_free",
    "expired_duplicate_at_capacity_does_not_evict",
    "two_held_cues_suppress_third_with_trace",
    "mixed_root_B_R02_B_enemy_scale_opening",
    "mixed_root_B_R02_A_enemy_rest",
    "mixed_root_B_R03_A_enemy_rest",
    "mixed_root_B_R03_B_enemy_heat_release",
    "mixed_root_E_R05_04_enemy_regen",
    "untold_poison_pressure_keeps_four_recipients",
    "self_support_is_not_discarded",
    "zero_guard_suppressed_positive_targets_defender",
    "unknown_explicit_target_never_falls_back",
    "partly_missing_aoe_is_not_silently_reduced",
    "hit_target_dominates_distinct_status_recipient",
    "magnet_mark_and_cover_have_distinct_recipients",
    "magnet_cancel_enemy_magnet_target_lost",
    "magnet_cancel_cast_interrupt",
    "magnet_terminal_mark_is_not_retrospectively_hidden",
    "magnet_legacy_heavy_does_not_invent_mark",
    "magnet_suppressed_mark_uses_real_hit_fallback",
    "magnet_suppressed_cancel_cast_interrupt",
    "magnet_suppressed_cancel_enemy_magnet_target_lost",
    "r04_followup_suppression_notice_tracks_hit",
    "r04_followup_suppression_notice_clears_on_cancel",
    "r04_followup_missing_recipient_has_no_warning",
    "r04_ordinary_suppressed_cue_does_not_spam_notice",
    "r04_followup_suppression_notice_clears_at_result",
    "r02_magic_support_arc_recipient_path",
    "r05_light_transfer_recipient_path",
    "r02_magic_support_arc_missing_recipient_no_fallback",
    "unrelated_effect_placement_unchanged",
    "transfer_notice_lifetime_pause_and_expiry",
    "transfer_notice_cancelled_cue_never_arrives",
}


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def fresh_json(path, after, timeout=120):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists() and path.stat().st_mtime >= after:
            try:
                return json.loads(path.read_text())
            except (OSError, ValueError):
                pass
        time.sleep(0.2)
    raise RuntimeError(f"No fresh receipt: {path.name}")


def canonical(snapshot):
    value = json.loads(json.dumps(snapshot))
    for key in ("unlockedRegionIDs", "completedEncounterIDs"):
        if isinstance(value.get(key), list):
            value[key] = sorted(value[key])
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--app", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    app = args.app.resolve()
    out = args.output.resolve()
    if out.exists():
        raise SystemExit("Evidence directory already exists; choose a new version.")
    receipt_path = app.parent / "BUILD_RECEIPT.json"
    receipt = json.loads(receipt_path.read_text())
    pins = {}
    for filename in ("EffectBudgetRegressionQA", "EffectCueCoordinator", "LivingScene", "QASaveReadback", "PursuitSuppressionNotice", "TransferPathGeometry"):
        relative = f"native/WitchApp/{filename}.swift"
        digest = sha((ROOT / relative).read_bytes())
        if digest != receipt["source_sha256"].get(relative):
            raise SystemExit(f"Source differs from frozen app: {relative}")
        pins[relative] = digest
    executable_sha = sha((app / "WitchGathering").read_bytes())
    if executable_sha != receipt["executable_sha256"]:
        raise SystemExit("Frozen executable hash mismatch")
    out.mkdir(parents=True)
    meta = {"status": "RUNNING", "scope": "SYNTHETIC_PRESENTATION_ONLY_NO_ENGINE_NO_REWARD",
            "device": args.device, "app": str(app), "sourceHashes": pins,
            "executableSHA256": executable_sha, "buildReceiptSHA256": sha(receipt_path.read_bytes())}
    def save_meta():
        (out / "RUN.json").write_text(json.dumps(meta, indent=2) + "\n")
    save_meta()
    prior_readback = None
    readback_path = None
    try:
        run("xcrun", "simctl", "install", args.device, str(app))
        container = pathlib.Path(run("xcrun", "simctl", "get_app_container", args.device, BUNDLE, "data"))
        support = container / "Library/Application Support/Witch03to05R1"
        readback_path = support / "last_qa_save_readback.json"
        if readback_path.exists():
            stat = readback_path.stat()
            prior_readback = (readback_path.read_bytes(), stat.st_atime_ns, stat.st_mtime_ns)
            (out / "prior_readback_receipt.json").write_bytes(prior_readback[0])
        key = "fx-regression-" + uuid.uuid4().hex[:12]
        report_path = support / f"effect_budget_regression_{key}.json"
        save_path = support / f"qa-{key}-save.json"
        began = time.time()
        meta["saveKey"] = key
        meta["launch"] = run("xcrun", "simctl", "launch", "--terminate-running-process", args.device, BUNDLE,
                             "--qa-isolated", "--qa-fixture=challenge", "--qa-persist-fixture",
                             "--qa-save-key=" + key, "--qa-effect-budget-regression")
        result = fresh_json(report_path, began)
        (out / "raw_report.json").write_bytes(report_path.read_bytes())
        run("xcrun", "simctl", "io", args.device, "screenshot", str(out / "after.png"))
        before_restart = save_path.read_bytes()
        (out / "save_before_restart.json").write_bytes(before_restart)
        restart_at = time.time()
        meta["restartLaunch"] = run("xcrun", "simctl", "launch", "--terminate-running-process", args.device, BUNDLE,
                                    "--qa-isolated", "--qa-save-key=" + key, "--qa-readback-save")
        readback_path = support / "last_qa_save_readback.json"
        readback_raw = fresh_json(readback_path, restart_at, 30)
        (out / "readback_receipt.json").write_bytes(readback_path.read_bytes())
        readback = json.loads(readback_raw["value"])
        after_restart = save_path.read_bytes()
        (out / "save_after_restart.json").write_bytes(after_restart)
        saved = json.loads(after_restart)["snapshot"]
        rows = result.get("cases", [])
        checks = {
            "exactExpectedCaseSet": len(rows) == len(EXPECTED) and {r.get("name") for r in rows} == EXPECTED,
            "allExplicitAssertionsPass": all(r.get("assertions") and r.get("passed") is True
                and all(v is True for v in r["assertions"].values()) for r in rows),
            "rendererBudgetAndCleanup": all(type(r.get("peakCombat")) is int and 0 <= r["peakCombat"] <= 2
                and r.get("assertions", {}).get("activeEffectsCleaned") is True for r in rows),
            "noSnapshotRevisionOrSaveMutation": all(result.get("checks", {}).get(k) is True
                for k in ("snapshotUnchanged", "revisionUnchanged", "saveBytesUnchanged")),
            "syntheticCasesPass": result.get("checks", {}).get("allCasesPass") is True,
            "allFallbackNoticesCleaned": all(r.get("assertions", {}).get("pursuitNoticesCleanedAtResultOrReset") is True for r in rows),
            "reportedSaveHashMatchesExternalFile": result.get("saveSHA256Before") == result.get("saveSHA256After") == sha(before_restart),
            "restartBytesIdentical": before_restart == after_restart,
            "loadedExistingSave": readback.get("loadedExistingSave") is True,
            "readbackFileHashMatches": readback.get("saveFileSHA256") == sha(after_restart),
            "readbackSnapshotMatches": canonical(readback.get("snapshot", {})) == canonical(saved),
            "readbackRevisionMatches": readback.get("revision") == saved.get("revision") == result.get("snapshotRevisionBefore"),
        }
        meta.update(status="PASS" if all(checks.values()) else "FAIL", checks=checks,
                    reportStatus=result.get("status"), caseCount=len(rows),
                    failedCases=[r.get("name") for r in rows if r.get("passed") is not True],
                    rawReportSHA256=sha(report_path.read_bytes()), saveSHA256=sha(after_restart))
        save_meta()
        print(json.dumps({"status": meta["status"], "checks": checks, "output": str(out)}, indent=2))
        if meta["status"] != "PASS":
            raise SystemExit(1)
    except Exception as error:
        meta.update(status="HARNESS_ERROR", error=repr(error))
        save_meta()
        raise
    finally:
        if prior_readback is not None and readback_path is not None:
            readback_path.write_bytes(prior_readback[0])
            os.utime(readback_path, ns=(prior_readback[1], prior_readback[2]))
            meta["priorReadbackRestored"] = {
                "sha256": sha(readback_path.read_bytes()), "expectedSHA256": sha(prior_readback[0]),
                "mtimeNs": readback_path.stat().st_mtime_ns, "expectedMtimeNs": prior_readback[2]}
            save_meta()


if __name__ == "__main__":
    main()

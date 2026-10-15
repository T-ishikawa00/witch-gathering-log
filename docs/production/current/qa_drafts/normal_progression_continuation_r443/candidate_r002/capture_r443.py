#!/usr/bin/env python3
"""R443 read-only evidence helper for Root-operated R420 ordinary UI.

This helper never launches/terminates the game, changes time, edits saves, or
copies/restores app data. It archives support files and optional screenshots.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time

ROOT = Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
BASE = ROOT / "docs/production/current/qa_drafts/normal_progression_continuation_r443/candidate_r002"
if Path(__file__).resolve().parents[6] != ROOT:
    raise RuntimeError("Runner is outside its fixed worktree")
OUT = BASE / "execution_r001"
DEVICE = "9A067715-7CF3-40D3-9064-38423223959B"
BUNDLE = "local.witch.autonomous.r1.completion.r420"
EXPECTED_SAVE = "51c07a8d8c262f930bda41728b2775ac1338187644ed3a60fda05fbf24786475"
EXPECTED_REVISION = 75
MAX_SECONDS = 40 * 60
MAX_BYTES = 40_000_000
MAX_SCREENSHOTS = 10
MIN_FREE_BYTES = 10_000_000_000

R436 = ROOT / "docs/production/current/qa_drafts/normal_progression_continuation_r436/candidate_r001/execution_r001"
R436_START = R436 / "START.json"
R436_START_SHA = "86399c79e03902ad4316be5b04590f9cab44e9a4a12d55be25c64f5d3c1ba627"
R436_CLOSE = R436 / "CLOSURE.json"
R436_CLOSE_SHA = "ed4aba8954483fbc78812d0026c376edcf2a054e3ad6a05fb59c7f2aa343b5de"
R436_SAVE = R436 / "checkpoints/final/files/save.json"
R437_INSTALL = ROOT / "docs/production/current/qa_drafts/native_completion_r437/install_release_r001/RESULT.json"
R437_INSTALL_SHA = "081ce8d4034f24364303ef3df34f30e48138fc8c3ae0ca926a5927f7808ed5a8"
R437_BUILD_SHA = "2db7cf6c2f50f28ce3e07aa8b0a621deccc7859e09eff6eda660f53c6026a138"
R441_CLOSEOUT = ROOT / "docs/production/current/qa_drafts/native_reading_mantle_r441/candidate_r002/execution_r002/CLOSURE.json"
R441_CLOSEOUT_SHA = "5e522b01960c016662181831eb83650f6d464df32704eb3fb6ec8d894e046153"
R441_READBACK = ROOT / "docs/production/current/qa_drafts/native_reading_mantle_r441/candidate_r002/ROOT_SCOPED_READBACK_R001.json"
R441_READBACK_SHA = "e80457a375aaa209b60135574ea76c3bd9f10e32ad0f5f41fad6936a3f6228fc"
R437_ROOT_BASELINE = ROOT / "docs/production/current/qa_drafts/normal_progression_continuation_r443/ROOT_R437_BASELINE_AFTER_R441_R001.json"
R437_ROOT_BASELINE_SHA = "6a8fc8b7e5d6fc1e266d56b03c43239d6d4de6b4c62411e4df0d60a50cdd4041"
R441_CACHE_ONLY = sorted([
    "Library/Caches/local.witch.autonomous.r1.completion.r437/com.apple.metal/functions.data",
    "Library/Caches/local.witch.autonomous.r1.completion.r437/com.apple.metal/functions.list",
])
R421_HELPER = ROOT / "docs/production/current/qa_drafts/normal_progression_r421/snapshot_r421_r002.py"
R421_HELPER_SHA = "6fe314a33ce19de71af8b21cec035070ee0a3a54c54434a7d460dfd315d9b9bd"


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_file(path: Path) -> str:
    return sha_bytes(path.read_bytes())


def stamp() -> str:
    return dt.datetime.now().astimezone().isoformat()


def write_exclusive(path: Path, value: object) -> None:
    data = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "wb", closefd=False) as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
    finally:
        os.close(fd)


def load_readonly_helper():
    if sha_file(R421_HELPER) != R421_HELPER_SHA:
        raise RuntimeError("Pinned R421 read-only snapshot helper changed")
    spec = importlib.util.spec_from_file_location("r436_r421_readonly", R421_HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load the pinned read-only helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


H = load_readonly_helper()


def tree(path: Path) -> dict[str, str]:
    if path.is_symlink() or not path.is_dir():
        raise RuntimeError("Protected tree missing or symlinked: " + str(path))
    result: dict[str, str] = {}
    for entry in path.rglob("*"):
        if entry.is_symlink():
            raise RuntimeError("Symlink in protected tree: " + str(entry))
        if entry.is_file():
            result[str(entry.relative_to(path))] = sha_file(entry)
    return result


def pinned_baseline() -> tuple[dict, dict]:
    if sha_file(R436_START) != R436_START_SHA or sha_file(R436_CLOSE) != R436_CLOSE_SHA:
        raise RuntimeError("R436 sealed start/closure changed")
    start=json.loads(R436_START.read_bytes()); close=json.loads(R436_CLOSE.read_bytes())
    if close.get("status") != "CLOSED_PRESERVATION_EXACT" or close.get("finalRevision") != EXPECTED_REVISION or close.get("finalSaveSHA256") != EXPECTED_SAVE:
        raise RuntimeError("R436 revision-75 closeout mismatch")
    if len(start.get("baselineProtectedTrees", {})) != 14 or len(start.get("baselineAppInventory", {})) != 1925:
        raise RuntimeError("R436 baseline shape mismatch")
    if sha_file(R436_SAVE) != EXPECTED_SAVE:
        raise RuntimeError("R436 archived final save changed")
    return start, close

def inputs(require_starting_save: bool = False) -> tuple[dict, dict, dict]:
    old_start,old_close=pinned_baseline(); live=H.fixed_inputs()
    if str(live["app"]) != old_start.get("app") or str(live["data"]) != old_start.get("data"):
        raise RuntimeError("Current R420 app/data path differs from R436")
    if live["install"].get("bundleID") != BUNDLE or live["install"].get("device") != DEVICE:
        raise RuntimeError("R420 bundle/device mismatch")
    save=live["data"] / H.SUPPORT_REL / "save.json"
    if require_starting_save:
        if save.is_symlink() or not save.is_file() or sha_file(save) != EXPECTED_SAVE: raise RuntimeError("R436 revision-75 save SHA mismatch")
        if json.loads(save.read_bytes()).get("snapshot",{}).get("revision") != EXPECTED_REVISION:
            raise RuntimeError("Starting R420 save is not revision 75")
    return live,old_start,old_close

def canonical_sha(value: object) -> str:
    raw=json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(",",":"))+"\n"
    return sha_bytes(raw.encode())
def data_inventory(path: Path) -> dict[str,dict]:
    if path.is_symlink() or not path.is_dir(): raise RuntimeError("R437 data tree missing/unsafe")
    rows={}
    for p in path.rglob("*"):
        if p.is_symlink(): raise RuntimeError("Symlink in R437 data tree")
        if p.is_file():
            st=p.stat(); rows[str(p.relative_to(path))]={"sha256":sha_file(p),"sizeBytes":st.st_size,"mode":st.st_mode&0o777}
    return rows
def r437_baseline(path: Path, expected_sha: str) -> tuple[dict,dict,dict]:
    if not re.fullmatch(r"[0-9a-f]{64}",expected_sha) or path.is_symlink() or sha_file(path)!=expected_sha:
        raise RuntimeError("Root-sealed R437 baseline path/SHA mismatch")
    if ROOT not in path.resolve(strict=True).parents or path.resolve(strict=True)!=path.absolute(): raise RuntimeError("R437 baseline must be a non-symlinked worktree file")
    m=json.loads(path.read_bytes())
    if m.get("schema")!="r443-r437-protection-baseline-v1" or m.get("status")!="ROOT_SEALED_AFTER_R441": raise RuntimeError("Missing Root-sealed post-R441 baseline")
    cp=Path(m.get("r441CloseoutPath",""))
    if cp.is_symlink() or ROOT not in cp.resolve(strict=True).parents or sha_file(cp)!=m.get("r441CloseoutSHA256"): raise RuntimeError("R441 closeout pin mismatch")
    close=json.loads(cp.read_bytes())
    common=(close.get("installedAppExact") is True and close.get("protectedTreesExact") is True
            and close.get("appPIDsStillRunning")==[] and close.get("withinBudgets") is True
            and close.get("missingLabels")==[] and close.get("archiveMismatches")==[]
            and close.get("screenshotMismatches")==[] and close.get("dataInventoryError") is None
            and close.get("coldBeforeAfterSaveSHAEqual") is True
            and close.get("currentLiveSaveMatchesColdAfter") is True
            and close.get("coldRestartDistinctObservedPIDs") is True)
    if not common: raise RuntimeError("R441 closure fails mandatory preservation/cold conditions")
    # Require Root's independently sealed readback that the original capture's
    # only mismatch was these two cache paths. Do not rewrite the R441 receipt.
    if sha_file(R441_READBACK) != R441_READBACK_SHA:
        raise RuntimeError("Pinned R441 scoped readback changed")
    readback=json.loads(R441_READBACK.read_bytes())
    if (readback.get("closureSHA256") != R441_CLOSEOUT_SHA
        or readback.get("originalCloseoutStatus") != "INCOMPLETE_RETAINED"
        or readback.get("onlyUnexpectedChanges") != R441_CACHE_ONLY
        or readback.get("allUIStateSnapshotsAndColdRawBytesExact") is not True
        or readback.get("installedAppAnd16ProtectedTreesExact") is not True):
        raise RuntimeError("R441 independent scoped readback does not support the narrow cache exception")
    if sha_file(R437_ROOT_BASELINE) != R437_ROOT_BASELINE_SHA:
        raise RuntimeError("Pinned Root post-R441 R437 baseline changed")
    root_baseline=json.loads(R437_ROOT_BASELINE.read_bytes())
    if (root_baseline.get("r441ScopedReadbackPath") != str(R441_READBACK)
        or root_baseline.get("r441ScopedReadbackSHA256") != R441_READBACK_SHA
        or root_baseline.get("r441CloseoutPath") != str(R441_CLOSEOUT)
        or root_baseline.get("r441CloseoutSHA256") != R441_CLOSEOUT_SHA):
        raise RuntimeError("Root R437 baseline does not bind exact R441 evidence")
    status=close.get("status")
    if status=="INCOMPLETE_RETAINED":
        # The only accepted incompleteness is the two named Metal cache files;
        # all other missing/new/changed files and all visual/preservation checks stay strict.
        if (close.get("unexpectedDataChanged")!=R441_CACHE_ONLY or close.get("unexpectedDataNew")!=[]
            or close.get("unexpectedDataMissing")!=[] or set(close.get("actualScreenshots",[]))!=set(close.get("requiredScreenshots",[]))):
            raise RuntimeError("R441 incomplete state exceeds the two pinned Metal cache deltas")
    elif status!="CLOSED_CAPTURE_RECORDED":
        raise RuntimeError("R441 closeout status is not an accepted closed state")
    if sha_file(R437_INSTALL)!=R437_INSTALL_SHA: raise RuntimeError("Pinned R437 install receipt changed")
    install=json.loads(R437_INSTALL.read_bytes())
    if install.get("status")!="PASS_NEW_BUNDLE_INSTALLED" or install.get("launch") is not False or install.get("bundleID")!="local.witch.autonomous.r1.completion.r437" or install.get("device")!=DEVICE or install.get("receiptSHA256")!=R437_BUILD_SHA: raise RuntimeError("Unexpected R437 installation")
    app=Path(install["installedApp"]).resolve(strict=True); data=Path(install["data"]).resolve(strict=True)
    buildp=Path(install["receipt"]).resolve(strict=True)
    if sha_file(buildp)!=R437_BUILD_SHA: raise RuntimeError("R437 build receipt changed")
    build=json.loads(buildp.read_bytes())
    if tree(app)!=build.get("appFiles"): raise RuntimeError("R437 app differs from build receipt")
    if m.get("r437AppPath")!=str(app) or m.get("r437DataPath")!=str(data) or m.get("r437BundleID")!=install["bundleID"]: raise RuntimeError("R437 paths do not match the sealed baseline")
    expected=m.get("r437DataInventory")
    if not isinstance(expected,dict) or not expected or m.get("r437DataInventorySHA256")!=canonical_sha(expected): raise RuntimeError("R437 sealed data inventory invalid")
    if data_inventory(data)!=expected: raise RuntimeError("R437 data changed since Root baseline")
    return m,install,{"app":app,"data":data,"appInventory":build["appFiles"],"dataInventory":expected}
def current_session_baseline() -> tuple[dict,dict,dict]:
    sess=json.loads((OUT/"START.json").read_bytes())
    return r437_baseline(Path(sess["r437BaselinePath"]),sess["r437BaselineSHA256"])
def free_and_budget() -> None:
    if shutil.disk_usage(ROOT).free < MIN_FREE_BYTES + MAX_BYTES:
        raise RuntimeError("Free-space floor/reserve not met")


def run_size() -> int:
    total = 0
    if not OUT.exists():
        return 0
    for path in OUT.rglob("*"):
        if path.is_symlink():
            raise RuntimeError("Symlink in evidence output")
        if path.is_file():
            total += path.stat().st_size
    return total


def gate(allow_overrun: bool = False) -> tuple[dict,dict,dict]:
    if not allow_overrun: free_and_budget()
    if not OUT.is_dir() or not (OUT/"START.json").is_file(): raise RuntimeError("R443 session not started")
    started=json.loads((OUT/"START.json").read_bytes())
    if not allow_overrun and time.time()-float(started["startedEpoch"])>MAX_SECONDS: raise RuntimeError("40-minute wall cap reached")
    if not allow_overrun and run_size()+5_000_000>MAX_BYTES: raise RuntimeError("Evidence budget reserve exceeded")
    live,baseline,close=inputs(require_starting_save=False)
    # Every operation rechecks Root's separately pinned post-R441 protection baseline.
    _,_,r437=r437_baseline(Path(started["r437BaselinePath"]),started["r437BaselineSHA256"])
    if H.process_rows(r437["app"] / "WitchGathering"): raise RuntimeError("R437 process became active; retain evidence and stop")
    return live,baseline,close

def app_and_protected_check(live: dict, baseline: dict) -> dict:
    session=json.loads((OUT/"START.json").read_bytes())
    app_now=tree(live["app"]); old_exact=app_now==session["baselineAppInventory"]
    protected=[]
    for raw,expected in session["baselineProtectedTrees"].items():
        observed=tree(Path(raw)); protected.append({"path":raw,"expectedFiles":len(expected),"exact":observed==expected})
    _,_,r437=current_session_baseline()
    r437_app=tree(r437["app"])==r437["appInventory"]
    r437_data=data_inventory(r437["data"])==r437["dataInventory"]
    return {"r420AppExact":old_exact,"r420AppFileCount":len(app_now),"historicalR436Trees":protected,"historicalR436OtherTreesExact":all(x["exact"] for x in protected),"r437AppExact":r437_app,"r437DataExact":r437_data,"allProtectedExact":old_exact and all(x["exact"] for x in protected) and r437_app and r437_data}

def snapshot(label: str, screenshot: bool = False, require_live: bool = True, allow_overrun: bool = False) -> dict:
    live, baseline, _ = gate(allow_overrun=allow_overrun)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,47}", label):
        raise RuntimeError("Invalid checkpoint label")
    if require_live:
        rows = H.process_rows(live["executable"])
        if not rows:
            raise RuntimeError("Pinned R420 app process is not running")
    if sha_file(live["executable"]) != live["executableSHA256"]:
        raise RuntimeError("Installed executable changed")
    shot_count = len(list(OUT.glob("checkpoints/*/screen.png")))
    if screenshot and shot_count >= MAX_SCREENSHOTS:
        raise RuntimeError("12 screenshot cap reached")
    target = OUT / "checkpoints" / label
    target.parent.mkdir(exist_ok=True)
    target.mkdir(exist_ok=False)
    files = H.support_files(live["data"])
    archive = target / "files"
    archive.mkdir()
    entries = {}
    total_payload = 0
    for name, src in sorted(files.items()):
        raw, meta = H.stable_read(src)
        total_payload += len(raw)
        if total_payload > 2_000_000:
            raise RuntimeError("Support snapshot exceeds 2MB")
        dst = archive / name
        fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(raw); stream.flush(); os.fsync(stream.fileno())
        raw_after, meta_after = H.stable_read(src)
        if dst.read_bytes() != raw or raw_after != raw or meta_after["sha256"] != meta["sha256"]:
            raise RuntimeError("Support file changed during read-only archival: " + name)
        entries[name] = {**meta, "archiveSHA256": sha_file(dst),
                         "archivePath": str(dst.relative_to(OUT))}
    save_doc = json.loads((archive / "save.json").read_bytes())
    snap = save_doc.get("snapshot", {})
    shot = None
    if screenshot:
        if run_size() + 5_000_000 > MAX_BYTES:
            raise RuntimeError("Insufficient reserved space before screenshot")
        shot_path = target / "screen.png"
        H.run_read(["xcrun", "simctl", "io", DEVICE, "screenshot", str(shot_path)], timeout=20)
        if not shot_path.is_file() or shot_path.stat().st_size <= 0:
            raise RuntimeError("Screenshot command produced no file")
        shot = {"path": str(shot_path.relative_to(OUT)), "bytes": shot_path.stat().st_size,
                "sha256": sha_file(shot_path)}
    if run_size() > MAX_BYTES:
        raise RuntimeError("50MB evidence cap reached; retain all files and stop")
    row = {"schema": "r443-checkpoint-v1", "label": label, "at": stamp(),
           "revision": snap.get("revision"), "saveSHA256": entries["save.json"]["sha256"],
           "completedEncounterIDs": snap.get("completedEncounterIDs", []),
           "completedResearchIDs": snap.get("completedResearchIDs", []),
           "unlockedRegionIDs": snap.get("unlockedRegionIDs", []),
           "completedChallengeIDs": sorted(x.split("|",1)[1] for x in snap.get("completedEncounterIDs", [])
                                            if x.startswith("CHALLENGE_CLEAR|")),
           "activeRegionID": snap.get("activeRegionID"),
           "gatherTargetMaterialID": snap.get("gatherTargetMaterialID"),
           "partyWorkTargetR144": snap.get("partyWorkTargetR144"),
           "lastClaimAtRawDateNumber": snap.get("lastClaimAt"),
           "offlineRemainderSeconds": snap.get("offlineRemainderSeconds"),
           "materials": snap.get("materials", {}), "currency": snap.get("currency", {}),
           "characterXP": snap.get("characterXP", {}), "gear": snap.get("gear", []),
           "equippedGearIDs": snap.get("equippedGearIDs", {}),
           "receiptsCount": len(save_doc.get("receipts", {})), "files": entries,
           "matchingAppProcesses": H.process_rows(live["executable"]) if require_live else [],
           "r437ProcessAbsent": not bool(H.process_rows(current_session_baseline()[2]["app"] / "WitchGathering")),
           "screenshot": shot, "gameDataWritten": False,
           "clockValueInterpretedOrChanged": False, "appLaunchedOrTerminated": False}
    write_exclusive(target / "CHECKPOINT.json", row)
    if run_size() > MAX_BYTES:
        raise RuntimeError("50MB evidence cap reached after checkpoint; retain evidence")
    return row



def start(screenshot: bool, baseline_path: Path, baseline_sha: str) -> None:
    free_and_budget()
    if OUT.exists(): raise RuntimeError("R443 output already exists; no overwrite/retry")
    old,oldclose=pinned_baseline(); live,_,_=inputs(require_starting_save=True)
    _,install,r437=r437_baseline(baseline_path,baseline_sha)
    # Do not freeze a moving R437 tree. It must be stopped after R441, and its
    # complete inventory must match a separately Root-sealed post-closeout manifest.
    if H.process_rows(r437["app"] / "WitchGathering"):
        raise RuntimeError("R437 process is active; refusing to start")
    r437_data_path=str(r437["data"])
    historical={p:files for p,files in old["baselineProtectedTrees"].items() if p!=r437_data_path}
    preservation={"r420AppExact":tree(live["app"])==old["baselineAppInventory"],"r436OtherTreesExact":all(tree(Path(p))==files for p,files in historical.items()),"r437AppExact":tree(r437["app"])==r437["appInventory"],"r437DataExact":data_inventory(r437["data"])==r437["dataInventory"],"historicalR437DataPathRebased":r437_data_path in old["baselineProtectedTrees"]}
    if not all(preservation[k] for k in ("r420AppExact","r436OtherTreesExact","r437AppExact","r437DataExact")): raise RuntimeError("Pre-run preservation mismatch; no capture start")
    if not H.process_rows(live["executable"]): raise RuntimeError("Root-operated R420 app is not running")
    OUT.mkdir(exist_ok=False); (OUT/"checkpoints").mkdir()
    protected=dict(historical)
    write_exclusive(OUT/"START.json",{"schema":"r443-session-v1","status":"ACTIVE_ROOT_OPERATED_CAPTURE","startedAt":stamp(),"startedEpoch":time.time(),"device":DEVICE,"bundleID":BUNDLE,"r420App":str(live["app"]),"r420Data":str(live["data"]),"r420ExecutableSHA256":live["executableSHA256"],"r436StartSHA256":R436_START_SHA,"r436CloseSHA256":R436_CLOSE_SHA,"r436SaveSHA256":EXPECTED_SAVE,"r436Revision":EXPECTED_REVISION,"r437BaselinePath":str(baseline_path.resolve()),"r437BaselineSHA256":baseline_sha,"r437InstallReceiptSHA256":R437_INSTALL_SHA,"r441CloseoutPath":json.loads(baseline_path.read_bytes())["r441CloseoutPath"],"r441CloseoutSHA256":json.loads(baseline_path.read_bytes())["r441CloseoutSHA256"],"r441CloseoutStatus":json.loads(R441_CLOSEOUT.read_bytes())["status"],"r441KnownCacheOnlyException":json.loads(R441_CLOSEOUT.read_bytes())["status"]=="INCOMPLETE_RETAINED","baselineAppInventory":old["baselineAppInventory"],"baselineProtectedTrees":protected,"historicalR437DataPathRebased":r437_data_path if r437_data_path in old["baselineProtectedTrees"] else None,"baselineR437DataInventory":r437["dataInventory"],"baselineR437AppInventory":r437["appInventory"],"baselineCheck":preservation,"maxWallSeconds":MAX_SECONDS,"maxEvidenceBytes":MAX_BYTES,"maxScreenshots":MAX_SCREENSHOTS,"video":False,"flags":[],"UIOnly":True,"saveInjection":False,"timeChanges":False,"build":False,"purchase":False,"deletion":False,"restore":False})
    snapshot("before",screenshot=screenshot,require_live=True)

def cold(label: str, reference: str, screenshot: bool) -> dict:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,47}", reference):
        raise RuntimeError("Invalid cold reference label")
    ref_path = OUT / "checkpoints" / reference / "CHECKPOINT.json"
    if not ref_path.is_file():
        raise RuntimeError("Cold reference checkpoint not found")
    ref = json.loads(ref_path.read_bytes())
    before_pids = {row["pid"] for row in ref.get("matchingAppProcesses", [])}
    after = snapshot(label, screenshot=screenshot, require_live=True)
    after_pids = {row["pid"] for row in after.get("matchingAppProcesses", [])}
    if not after_pids or before_pids & after_pids:
        raise RuntimeError("No fresh app process observed after Root-operated cold reopen")
    exact = after["saveSHA256"] == ref["saveSHA256"]
    result = {"schema": "r443-cold-readback-v1", "reference": reference,
              "after": label, "beforeSaveSHA256": ref["saveSHA256"],
              "afterSaveSHA256": after["saveSHA256"], "saveBytesExact": exact,
              "beforePIDs": sorted(before_pids), "afterPIDs": sorted(after_pids),
              "appRestartObservedByPIDChange": True,
              "appWasLaunchedByHelper": False, "saveWasRewrittenByHelper": False}
    write_exclusive(OUT / (label + "_COLD.json"), result)
    if not exact:
        raise RuntimeError("Save changed across cold reopen; retain evidence")
    return result


def close() -> dict:
    live, baseline, _ = gate(allow_overrun=True)
    if H.process_rows(live["executable"]):
        raise RuntimeError("Root must stop its own app process before close; helper will not terminate it")
    final_snapshot_omitted = run_size() + 2_000_000 > MAX_BYTES
    final = (snapshot("final", screenshot=False, require_live=False, allow_overrun=True)
             if not final_snapshot_omitted else {"revision": None, "saveSHA256": None})
    preservation = app_and_protected_check(live, baseline)
    start_row = json.loads((OUT / "START.json").read_bytes())
    r420_absent=not bool(H.process_rows(live["executable"]))
    r437_absent=not bool(H.process_rows(current_session_baseline()[2]["app"] / "WitchGathering"))
    status = "CLOSED_PRESERVATION_EXACT" if preservation["allProtectedExact"] and r420_absent and r437_absent else "CLOSED_PRESERVATION_MISMATCH"
    row = {"schema": "r443-closeout-v1", "status": status, "closedAt": stamp(),
           "finalRevision": final["revision"], "finalSaveSHA256": final["saveSHA256"],
           "finalSnapshotOmittedForEvidenceCap": final_snapshot_omitted,
           "protectedCheck": preservation,
           "elapsedSeconds": time.time() - float(start_row["startedEpoch"]),
           "evidenceBytes": run_size(), "screenshotCount": len(list(OUT.glob("checkpoints/*/screen.png"))),
           "r420ProcessesAbsent": r420_absent,
           "r437ProcessesAbsent": r437_absent,
           "withinWallCap": time.time() - float(start_row["startedEpoch"]) <= MAX_SECONDS,
           "withinEvidenceCap": run_size() <= MAX_BYTES,
           "gameplayResultReview": "PENDING_ROOT_REVIEW",
           "build": False, "saveInjection": False, "clockChanges": False,
           "purchase": False, "deletion": False, "restore": False}
    write_exclusive(OUT / "CLOSURE.json", row)
    if status != "CLOSED_PRESERVATION_EXACT":
        raise RuntimeError("Protected app/tree comparison failed; preserve all evidence")
    return row


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="phase", required=True)
    begin = sub.add_parser("start"); begin.add_argument("--r437-baseline", required=True); begin.add_argument("--r437-baseline-sha256", required=True); begin.add_argument("--screenshot", action="store_true")
    cp = sub.add_parser("checkpoint"); cp.add_argument("label"); cp.add_argument("--screenshot", action="store_true")
    cl = sub.add_parser("cold"); cl.add_argument("label"); cl.add_argument("--reference", required=True); cl.add_argument("--screenshot", action="store_true")
    sub.add_parser("close")
    args = parser.parse_args()
    if args.phase == "start":
        start(args.screenshot, Path(args.r437_baseline), args.r437_baseline_sha256); print("R443_STARTED_CAPTURE_ONLY"); return 0
    if args.phase == "checkpoint":
        row = snapshot(args.label, args.screenshot, require_live=True)
        print(json.dumps({"label": args.label, "revision": row["revision"], "saveSHA256": row["saveSHA256"]}, sort_keys=True)); return 0
    if args.phase == "cold":
        row = cold(args.label, args.reference, args.screenshot)
        print(json.dumps(row, sort_keys=True)); return 0
    row = close(); print(json.dumps(row, sort_keys=True)); return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print("HOLD: {}: {}".format(type(exc).__name__, exc), file=sys.stderr)
        raise SystemExit(2)

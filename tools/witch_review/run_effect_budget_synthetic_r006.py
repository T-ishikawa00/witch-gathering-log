#!/usr/bin/env python3
"""Run only the six synthetic presentation checks on the assigned F843 simulator."""
from pathlib import Path
import hashlib, json, subprocess, time

ROOT=Path(__file__).resolve().parents[2]
DEVICE="F843518C-7377-434C-A960-B26FB7F34C4B"
BUNDLE_ID="local.witch.autonomous.r1"
APP=ROOT/"native/build/app_20261011T003315/WitchGathering.app"
OUT=ROOT/"docs/production/current/native/effect_capacity_cancel_r006_synthetic"
KEY="fxr006-synthetic"

def run(*args): return subprocess.check_output(args,text=True,stderr=subprocess.STDOUT).strip()
def sha(data): return hashlib.sha256(data).hexdigest()
def load(path):
    try:return json.loads(path.read_text())
    except Exception:return None

def main():
    if not APP.is_dir() or OUT.exists(): raise SystemExit("missing build or existing evidence folder")
    OUT.mkdir(parents=True)
    receipt=ROOT/"native/build/app_20261011T003315/BUILD_RECEIPT.json"
    exe=APP/"WitchGathering"
    meta={"status":"RUNNING","device":DEVICE,"app":str(APP),"executableSHA256":sha(exe.read_bytes()),
          "buildReceiptSHA256":sha(receipt.read_bytes()),"startedAt":time.strftime("%Y-%m-%dT%H:%M:%S%z")}
    (OUT/"RUN.json").write_text(json.dumps(meta,indent=2)+"\n")
    run("xcrun","simctl","install",DEVICE,str(APP))
    support=Path(run("xcrun","simctl","get_app_container",DEVICE,BUNDLE_ID,"data"))/"Library/Application Support/Witch03to05R1"
    report=support/f"effect_budget_regression_{KEY}.json"
    save=support/f"qa-{KEY}-save.json"
    old_mtime=report.stat().st_mtime if report.exists() else 0
    began=time.time()
    launch=run("xcrun","simctl","launch","--terminate-running-process",DEVICE,BUNDLE_ID,
               "--qa-isolated","--qa-fixture=challenge","--qa-persist-fixture","--qa-save-key="+KEY,
               "--qa-effect-budget-regression")
    (OUT/"launch.txt").write_text(launch+"\n")
    screens=[];next_screen=time.monotonic()+2
    result=None
    deadline=time.monotonic()+90
    while time.monotonic()<deadline:
        if time.monotonic()>=next_screen:
            name=f"screen_{len(screens):02d}.png";run("xcrun","simctl","io",DEVICE,"screenshot",str(OUT/name));screens.append(name);next_screen+=8
        if report.exists() and report.stat().st_mtime>old_mtime and report.stat().st_mtime>=began:
            result=load(report)
            if result:break
        time.sleep(.2)
    if result is None: raise SystemExit("no fresh synthetic regression report observed")
    raw=report.read_bytes();(OUT/report.name).write_bytes(raw)
    run("xcrun","simctl","io",DEVICE,"screenshot",str(OUT/"result.png"))
    if not save.exists(): raise SystemExit("isolated save missing")
    save_before=save.read_bytes()
    (OUT/"save_before_restart.json").write_bytes(save_before)
    restart=run("xcrun","simctl","launch","--terminate-running-process",DEVICE,BUNDLE_ID,
                "--qa-isolated","--qa-save-key="+KEY,"--screen=探索")
    time.sleep(2)
    run("xcrun","simctl","io",DEVICE,"screenshot",str(OUT/"restart.png"))
    save_after=save.read_bytes()
    (OUT/"save_after_restart.json").write_bytes(save_after)
    (OUT/"restart.txt").write_text(restart+"\n")
    rows=result.get("cases",[])
    checks={"allSixCasesPass":result.get("status")=="PASS_SYNTHETIC_PRESENTATION_ONLY" and len(rows)==6 and all(c.get("passed") for c in rows),
            "noGameStateChange":result.get("checks",{}).get("snapshotUnchanged") is True and result.get("checks",{}).get("revisionUnchanged") is True,
            "saveBytesUnchangedInRunner":result.get("checks",{}).get("saveBytesUnchanged") is True,
            "externalRestartSaveBytesStable":save_before==save_after,
            "displayAliasRegressionPass":next((c.get("assertions",{}).get("cancelledCueTargetsRemainOriginalVictim") for c in rows if c.get("name")=="tool_combo_two_impacts_three_cancels"),False) is True}
    meta.update({"status":"PASS" if all(checks.values()) else "FAIL","launch":launch,"restart":restart,
                 "reportStatus":result.get("status"),"checks":checks,"caseCount":len(rows),"caseNames":[r.get("name") for r in rows],
                 "syntheticReportSHA256":sha(raw),"saveSHA256BeforeRestart":sha(save_before),"saveSHA256AfterRestart":sha(save_after),
                 "screenshots":screens+["result.png","restart.png"],"scope":"synthetic renderer QA only; no commands, rewards, or natural battle"})
    (OUT/"RUN.json").write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps({"status":meta["status"],"checks":checks,"output":str(OUT)},ensure_ascii=False),flush=True)
    if not all(checks.values()):raise SystemExit(1)

if __name__=="__main__":main()

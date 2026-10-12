#!/usr/bin/env python3
"""Run the isolated real-AVAudioPlayer probe on one explicit Simulator bundle."""
import argparse,datetime,hashlib,json,math,pathlib,shutil,subprocess,time

def main():
    runner_hash=hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--app',type=pathlib.Path,required=True)
    p.add_argument('--device',required=True)
    p.add_argument('--key',required=True)
    p.add_argument('--out',type=pathlib.Path,required=True)
    p.add_argument('--freeze',required=True)
    args=p.parse_args()
    if args.device=='A8E9E99B-F6DC-4EF0-90D8-CB1C4202D514':p.error('StoreKit evidence Simulator is protected')
    if not args.key or len(args.key)>64 or any(not(c.isascii() and (c.isalnum() or c in '-_')) for c in args.key):p.error('Use a unique ASCII QA key of 1–64 letters/digits/hyphens/underscores')
    if args.out.exists():p.error('Output directory must be new; retain earlier raw failures')
    args.out.mkdir(parents=True)
    app=args.app.resolve();bundle='local.witch.autonomous.r1'
    subprocess.run(['xcrun','simctl','install',args.device,str(app)],check=True,capture_output=True,text=True)
    command=['xcrun','simctl','launch','--terminate-running-process',args.device,bundle,'--qa-isolated','--qa-save-key='+args.key,'--qa-audio-suite='+args.key,'--qa-music-probe','--qa-music-diagnostics']
    started=datetime.datetime.now().astimezone().isoformat()
    process=subprocess.run(command,check=True,capture_output=True,text=True)
    container=pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',args.device,bundle,'data'],text=True).strip())
    folder=container/'Documents/WitchMusicQA';receipt=None
    for _ in range(100):
        path=folder/'probe_receipt.json'
        if path.exists():
            candidate=json.loads(path.read_text())
            if candidate.get('settingsSuite')=='WitchMusicQA-'+args.key:receipt=candidate;break
        time.sleep(.5)
    for name in ['probe_receipt.json','latest_diagnostic.json','history.json']:
        if (folder/name).exists():shutil.copy2(folder/name,args.out/name)
    checks=receipt.get('checks',{}) if receipt else {}
    history=json.loads((args.out/'history.json').read_text()).get('records',[]) if (args.out/'history.json').exists() else []
    observed=[r['snapshot']['diagnostics'].get('lastRetiringCleanupDelaySeconds') for r in history if r.get('event')=='qa_cleanup_observed']
    cleanup_delay=observed[-1] if observed else None
    # .40s scheduled cleanup plus .20s development scheduling tolerance.
    # The in-app 1s limit is observation time, not the harness PASS budget.
    cleanup_pass=type(cleanup_delay) in (int,float) and math.isfinite(cleanup_delay) and 0<=cleanup_delay<=.600
    passed=bool(checks) and all(checks.values()) and receipt.get('final',{}).get('diagnostics',{}).get('qaProbePassed') is True and cleanup_pass
    result={'startedAt':started,'finishedAt':datetime.datetime.now().astimezone().isoformat(),'app':str(app),'runnerSHA256':runner_hash,
            'executableSHA256':hashlib.sha256((app/'WitchGathering').read_bytes()).hexdigest(),'sourceFreeze':args.freeze,
            'device':args.device,'saveKey':args.key,'command':command,'launchOutput':process.stdout.strip(),
            'status':'PASS' if passed else 'FAIL','checkCount':len(checks),'failedChecks':[k for k,v in checks.items() if not v],
            'cleanupDelaySeconds':cleanup_delay,'cleanupPassBudgetSeconds':.600,'cleanupWithinBudget':cleanup_pass,
            'harnessFailedChecks':[] if cleanup_pass else ['cleanupDelayMissingInvalidOrOutsideBudget'],
            'limits':'Real AVAudioPlayer in Simulator with injected interruption branches. Not physical OS interruption or listening approval.'}
    (args.out/'RUN.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:result[k] for k in ['status','checkCount','failedChecks','executableSHA256']}))
    return 0 if passed else 1

if __name__=='__main__':raise SystemExit(main())

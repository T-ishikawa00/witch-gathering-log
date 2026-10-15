#!/usr/bin/env python3
"""One-shot, isolated R371 Core suite runner. Preparation only until explicitly invoked."""
from __future__ import annotations
import argparse, datetime as dt, hashlib, importlib.util, json, os, shutil, subprocess, sys, time, uuid
from pathlib import Path
sys.dont_write_bytecode = True
ROOT = Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
RUNNER = ROOT/'docs/production/current/qa_drafts/research_mechanic_closure_r371/execution_r001'
INPUT = RUNNER/'RUN_INPUT_MANIFEST_R001.json'
LOCK = RUNNER/'execution_started.json'
MAX_SECONDS, OUTPUT_CAP, MIN_FREE = 120, 350_000_000, 12_000_000_000
HELPER_PATH = ROOT/'docs/production/current/qa_drafts/migration_receipt_reconciliation_r356/runner_r003/run_core_r356.py'
HELPER_SHA = '5430a5f6b1cbdebddd2929648908a8b5cb9e052bfd54bc2daee9326ef49ba875'
TRACE_IDS = ['CH_R01_01','CH_R01_02','CH_R01_03','CH_R02_01','CH_R02_03','CH_R03_01','CH_R03_02','CH_R03_03','CH_R04_01','CH_R04_02','CH_R04_03','CH_R05_01','CH_R05_02','CH_R05_03']
TEST_NAMES = [
    'testCH_R01_01HeavyTellHitLifecycleAndLedger','testCH_R01_02ThreeEnemySupportAndSlow','testCH_R01_03AlternatingSingleHeavyAndMultihitTargets','testCH_R02_01DotAndHealCycleEventsAreRooted','testCH_R02_02ReusesPinnedR359MembranePassWithoutReplaying','testCH_R02_03SupportWaveHasFourActorsAndSupportEvent','testCH_R03_01AlternatesSingleHeavyAndThreeLinkedHits','testCH_R03_02HeatThresholdShiftAndPostShiftAOEAccounting','testCH_R03_03CastInterruptLinksToBossCast','testCH_R04_01HeavyAndOrdinarySingleTargetCycles','testCH_R04_02BuffWeakenAndDamageShareActionRoot','testCH_R04_03AlternatingSingleTargetAndPartyAOE','testCH_R05_01HeavyExecutionHasAuthoredRecoveryGap','testCH_R05_02LampSupportLinkedToLivingGuardian','testCH_R05_03ComboMultihitAndAOESequence']
def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()
def sha_bytes(b): return hashlib.sha256(b).hexdigest()
def load_helper():
    if sha(HELPER_PATH)!=HELPER_SHA: raise RuntimeError('pinned shared process helper mismatch')
    spec=importlib.util.spec_from_file_location('r356_safe_runner_helpers_r371',HELPER_PATH)
    mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod
def verify_inputs(h,m):
    if Path(os.path.realpath(ROOT)) != ROOT: raise RuntimeError('worktree path did not resolve exactly')
    if m.get('schema')!='r371-candidate-input-v2' or m.get('status')!='PREPARED_NOT_RUN' or m.get('fixedWorktree')!=str(ROOT): raise RuntimeError('unsupported input manifest')
    if m.get('limits')!={'maxInvocations':1,'maxWallSeconds':120,'maxAllocatedBytes':350000000,'minimumFreeBytes':12000000000,'maxConcurrentJobs':2}: raise RuntimeError('execution limits are not the reviewed fixed budget')
    if m.get('ownedProcessHelper')!={'path':'docs/production/current/qa_drafts/migration_receipt_reconciliation_r356/runner_r003/run_core_r356.py','sha256':HELPER_SHA}: raise RuntimeError('shared process helper pin differs')
    def pinned(row):
        p=ROOT/row['path']; h.no_symlink(p)
        if sha(p)!=row['sha256']: raise RuntimeError('input hash mismatch: '+row['path'])
        return p
    r368m=pinned(m['r368InputManifest']); upstream=json.loads(r368m.read_text())
    candidate_manifest=pinned(m['candidateManifest']); cm=json.loads(candidate_manifest.read_text())
    candidate_input=pinned(m['candidateInputManifest'])
    if cm.get('schema')!='r371-research-mechanic-closure-candidate-v2' or cm.get('inputManifestSHA256')!=sha(candidate_input) or cm.get('inputManifestPath')!=m['candidateInputManifest']['path']: raise RuntimeError('candidate source/input manifest join failed')
    if cm.get('testSourceSHA256')!=m['test']['sha256'] or cm.get('testSourcePath')!=m['test']['path']: raise RuntimeError('candidate manifest does not bind the test bytes')
    expected_rows=[r for r in upstream['stagedFiles'] if r['role'] in ('core','override','candidate_helper','resource')]
    if m['r368StagedRows']!=expected_rows or len(expected_rows)!=57: raise RuntimeError('R368 rows differ from exact 54-source+helper+2-resource manifest')
    staged=[]
    core=resources=0
    for row in m['r368StagedRows']:
        src=pinned({'path':row['sourcePath'],'sha256':row['sha256']})
        if src.stat().st_size!=row['sizeBytes']: raise RuntimeError('R368 source size mismatch')
        if row['role']=='resource': resources+=1
        else: core+=1
        staged.append(row)
    if (core,resources)!=(55,2): raise RuntimeError('exact R368 package is 55 Swift inputs including override/helper plus two resources')
    test=pinned(m['test']); r359=pinned(m['r359Run'])
    if test.stat().st_size!=m['test']['sizeBytes'] or m['test']['testCount']!=15: raise RuntimeError('candidate test size/count mismatch')
    if m['packageTemplate']!=upstream['packageTemplate'] or sha_bytes(m['packageTemplate'].encode())!=m['packageTemplateSHA256']: raise RuntimeError('Package.swift text/hash is not the pinned R368 template')
    package_template=m['packageTemplate']
    if m['test']['testIdentifiers']!=[f"ResearchMechanicClosureR371Tests/{n}" for n in TEST_NAMES]: raise RuntimeError('15 exact test IDs differ')
    if m.get('r368PackagePath')!='docs/production/current/qa_drafts/normal_onboarding_progression_r368/candidate_r001/runner_r001/runs/36800000-0001-4001-8000-000000000001/package': raise RuntimeError('R368 package path is not the reviewed successful payload')
    rr=json.loads(r359.read_text())
    if rr.get('status')!='CORE_TESTS_PASSED_REVIEW_REQUIRED' or rr.get('testVerdict',{}).get('passed')!=[m['r359Run']['expectedTest']] or rr.get('testVerdict',{}).get('failed') or rr.get('testVerdict',{}).get('skipped'): raise RuntimeError('R359 prior evidence receipt is not the exact accepted pass')
    if sha_bytes(upstream['packageTemplate'].encode())!=m['packageTemplateSHA256']: raise RuntimeError('Package.swift template pin mismatch')
    return staged,test,r359,package_template
def atomic(path,obj,first=False):
    data=(json.dumps(obj,ensure_ascii=False,sort_keys=True,indent=2)+'\n').encode()
    if first:
        fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        try: os.write(fd,data); os.fsync(fd)
        finally: os.close(fd)
    else:
        tmp=path.with_name(path.name+f'.tmp-{os.getpid()}')
        fd=os.open(tmp,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        try: os.write(fd,data); os.fsync(fd)
        finally: os.close(fd)
        os.replace(tmp,path)
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--input-manifest',required=True); ap.add_argument('--input-sha256',required=True); ap.add_argument('--runner-sha256',required=True); ap.add_argument('--execute',action='store_true'); ap.add_argument('--run-id'); ap.add_argument('--limit-seconds',type=int,default=MAX_SECONDS); a=ap.parse_args()
    if Path(a.input_manifest).resolve(strict=True)!=INPUT or sha(INPUT)!=a.input_sha256: raise RuntimeError('fixed input manifest pin mismatch')
    if sha(Path(__file__))!=a.runner_sha256 or a.runner_sha256!=json.loads(INPUT.read_text()).get('runnerSHA256'): raise RuntimeError('runner source SHA mismatch')
    h=load_helper(); m=json.loads(INPUT.read_text()); staged,test,r359,package_template=verify_inputs(h,m)
    if not a.execute:
        print(json.dumps({'status':'PREFLIGHT_ONLY_NOT_RUN','r368SwiftInputs':55,'r368Resources':2,'testCount':15,'execution':'NOT_RUN','saveWrites':'NONE','simulator':'NONE'},indent=2)); return 0
    if a.limit_seconds!=MAX_SECONDS or shutil.disk_usage(ROOT).free<MIN_FREE: raise RuntimeError('fixed 120s/12GB start gate failed')
    h.ensure_no_competing_swift()
    rid=str(uuid.UUID(a.run_id or ''))
    if rid!=(a.run_id or '').lower(): raise RuntimeError('execution needs a canonical UUID')
    RUNS=RUNNER/'runs'; h.no_symlink(RUNS,allow_missing_leaf=True); RUNS.mkdir(mode=0o700,exist_ok=True)
    h.no_symlink(LOCK,allow_missing_leaf=True)
    fd=os.open(LOCK,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f: json.dump({'runID':rid,'startedAt':dt.datetime.now().astimezone().isoformat(),'inputSHA256':a.input_sha256,'runnerSHA256':a.runner_sha256},f); f.write('\n'); f.flush(); os.fsync(f.fileno())
    out=RUNS/rid; out.mkdir(mode=0o700,exist_ok=False); pkg=out/'package'; scratch=out/'scratch'; traces=out/'traces'; traces.mkdir(mode=0o700)
    (pkg/'Sources/WitchGameCore').mkdir(parents=True,mode=0o700); (pkg/'Tests/WitchGameCoreTests').mkdir(parents=True,mode=0o700)
    rec={'schema':'r371-core-run-v1','status':'PREPARING_RETAINED','runID':rid,'inputManifestSHA256':a.input_sha256,'runnerSHA256':a.runner_sha256,'r368InputManifestSHA256':m['r368InputManifest']['sha256'],'testSHA256':m['test']['sha256'],'r359RunSHA256':m['r359Run']['sha256'],'expectedTests':m['test']['testIdentifiers'],'limits':m['limits'],'fixtureClass':'MECHANISM_ONLY','simulator':'NONE','saveMutation':'NONE'}
    receipt=out/'RUN.json'; log=out/'swift_test.log'; atomic(receipt,rec,first=True)
    proc=None; observed={}; errors=[]; status='INCOMPLETE_RETAINED'; started=time.monotonic()
    try:
        for row in staged:
            src=ROOT/row['sourcePath']; dst=pkg/row['destinationPath']; dst.parent.mkdir(parents=True,exist_ok=True,mode=0o700); shutil.copyfile(src,dst); os.chmod(dst,row['mode'])
            if sha(dst)!=row['sha256']: raise RuntimeError('staged copy mismatch: '+row['destinationPath'])
        shutil.copyfile(test,pkg/m['test']['destinationPath'])
        (pkg/'Package.swift').write_text(package_template)
        if sha(pkg/m['test']['destinationPath'])!=m['test']['sha256'] or sha(pkg/'Package.swift')!=m['packageTemplateSHA256']: raise RuntimeError('candidate/package staging mismatch')
        scratch.mkdir(mode=0o700)
        for n in ('tmp','cache','config','security','build'): (scratch/n).mkdir(mode=0o700)
        swift=Path('/usr/bin/swift'); ver=subprocess.run([str(swift),'--version'],capture_output=True,text=True,timeout=8,check=True).stdout.strip()
        if ver!=m['swiftToolchain']['version']: raise RuntimeError('toolchain drift')
        env=os.environ.copy(); env['TMPDIR']=str(scratch/'tmp'); env['WITCH_R371_EVIDENCE_ROOT']=str(traces); env['WITCH_R371_R359_RUN']=str(r359)
        cmd=[str(swift),'test','--package-path',str(pkg),'--scratch-path',str(scratch/'build'),'--cache-path',str(scratch/'cache'),'--config-path',str(scratch/'config'),'--security-path',str(scratch/'security'),'--jobs','2','--filter','ResearchMechanicClosureR371Tests']
        if h.usage(out)[1]>OUTPUT_CAP: raise RuntimeError('output cap exceeded before Swift launch')
        with log.open('xb') as lf:
            proc=subprocess.Popen(cmd,cwd=ROOT,env=env,stdout=lf,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,start_new_session=True,close_fds=True)
            rec.update(status='RUNNING',command=cmd,runnerPID=proc.pid); atomic(receipt,rec)
            deadline=started+MAX_SECONDS
            while proc.poll() is None:
                if time.monotonic()>deadline: raise RuntimeError('120-second wall cap exceeded')
                if shutil.disk_usage(ROOT).free<MIN_FREE: raise RuntimeError('12GB free-space floor breached')
                if h.usage(out)[1]>OUTPUT_CAP: raise RuntimeError('350MB allocated-output cap breached')
                rows_now=h.process_rows()
                for row in h.descendants(rows_now,proc.pid): observed[row['pid']]=row
                for row in h.owned_test_processes(rows_now,list(scratch.rglob('*.xctest'))): observed[row['pid']]=row
                time.sleep(.2)
            code=proc.wait(timeout=2); rec['returnCode']=code
        expected=[x.rsplit('/',1)[-1] for x in m['test']['testIdentifiers']]
        verdict=h.verify_log(log,m['test']['testIdentifiers']); rec['testVerdict']=verdict
        trace_files=sorted(traces.glob('*.json')); rec['traceFiles']=[{'path':p.name,'sha256':sha(p),'sizeBytes':p.stat().st_size} for p in trace_files]
        trace_names={p.stem for p in trace_files}
        trace_payloads=[json.loads(p.read_text()) for p in trace_files]
        traces_valid=(trace_names=={f'{cid}_seed_371001' for cid in TRACE_IDS} and len(trace_payloads)==14 and all(t.get('challengeID') in TRACE_IDS and t.get('fixtureClass')=='MECHANISM_ONLY' and t.get('assertions',{}).get('hpLedger')=='PASS' for t in trace_payloads))
        if code==0 and verdict.get('accepted') and traces_valid: status='CORE_TESTS_PASSED_REVIEW_REQUIRED'
        else: errors.append('XCTest exact 15-case verdict or 14 exact truthful trace outputs did not pass')
    except BaseException as e:
        errors.append(f'{type(e).__name__}: {e}')
        if proc is not None: h.stop_owned(proc,list(scratch.rglob('*.xctest')) if scratch.exists() else [],observed)
    finally:
        if proc is not None:
            cleanup=h.stop_owned(proc,list(scratch.rglob('*.xctest')) if scratch.exists() else [],observed); rec['ownedCleanup']=cleanup
            rows_now=h.process_rows(); descendants=h.descendants(rows_now,proc.pid); children=h.owned_test_processes(rows_now,list(scratch.rglob('*.xctest')) if scratch.exists() else [])
            alive={x['pid']:x for x in descendants+children}
            if proc.poll() is None: alive[proc.pid]={'pid':proc.pid,'command':'owned swift test process'}
            rec['ownedProcessesAfter']=list(alive.values()); rec['ownedProcessesAbsent']=not alive
        rec['finishedAt']=dt.datetime.now().astimezone().isoformat(); rec['elapsedSeconds']=round(time.monotonic()-started,3)
        try:
            rec['sourceInputsUnchanged']=all(sha(ROOT/x['sourcePath'])==x['sha256'] for x in staged)
            rec['candidateAndManifestUnchanged']=sha(test)==m['test']['sha256'] and sha(INPUT)==a.input_sha256 and sha(Path(__file__))==a.runner_sha256 and sha(r359)==m['r359Run']['sha256'] and sha(ROOT/m['r368InputManifest']['path'])==m['r368InputManifest']['sha256'] and sha(ROOT/m['candidateManifest']['path'])==m['candidateManifest']['sha256'] and sha(ROOT/m['candidateInputManifest']['path'])==m['candidateInputManifest']['sha256'] and sha(HELPER_PATH)==HELPER_SHA
            rec['outputUsage']={'logicalBytes':h.usage(out)[0],'allocatedBytes':h.usage(out)[1]}; rec['freeBytesAfter']=shutil.disk_usage(ROOT).free
            if log.exists(): rec['testVerdict']=h.verify_log(log,m['test']['testIdentifiers'])
        except BaseException as e: errors.append(f'closeout verification failed: {type(e).__name__}: {e}')
        rec['errors']=errors
        if rec['elapsedSeconds']>MAX_SECONDS or rec.get('outputUsage',{}).get('allocatedBytes',OUTPUT_CAP+1)>OUTPUT_CAP or not rec.get('sourceInputsUnchanged',False) or not rec.get('candidateAndManifestUnchanged',False) or (proc is not None and not rec.get('ownedProcessesAbsent',False)): status='INCOMPLETE_RETAINED'
        rec['status']=status; atomic(receipt,rec)
    print(json.dumps({'status':status,'receipt':str(receipt)},indent=2)); return 0 if status=='CORE_TESTS_PASSED_REVIEW_REQUIRED' else 2
if __name__=='__main__':
    try: sys.exit(main())
    except BaseException as e: print('HOLD:',type(e).__name__,str(e),file=sys.stderr); sys.exit(2)

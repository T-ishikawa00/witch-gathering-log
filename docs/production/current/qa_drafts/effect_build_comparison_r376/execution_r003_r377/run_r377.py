#!/usr/bin/env python3
"""Single-run isolated R377 preview runner. Preparation only unless --execute is supplied."""
from __future__ import annotations
import argparse, datetime as dt, hashlib, importlib.util, json, os, shutil, subprocess, sys, time, uuid
from pathlib import Path
sys.dont_write_bytecode = True
ROOT=Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
RUNNER=ROOT/'docs/production/current/qa_drafts/effect_build_comparison_r376/execution_r003_r377'
INPUT=RUNNER/'RUN_INPUT_MANIFEST_R001.json'
LOCK=RUNNER/'execution_started.json'
MAX_SECONDS,OUTPUT_CAP,MIN_FREE=300,500_000_000,12_000_000_000
HELPER_PATH=ROOT/'docs/production/current/qa_drafts/migration_receipt_reconciliation_r356/runner_r003/run_core_r356.py'
HELPER_SHA='5430a5f6b1cbdebddd2929648908a8b5cb9e052bfd54bc2daee9326ef49ba875'
TEST_ID='EffectBuildComparisonR377Tests/testFourEarnedEffectFamiliesAcrossThreeSeeds'
R368_ROLES={'core','override','candidate_helper','resource'}
def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()
def sha_bytes(b): return hashlib.sha256(b).hexdigest()
def load_helper():
    if sha(HELPER_PATH)!=HELPER_SHA: raise RuntimeError('pinned shared process helper mismatch')
    spec=importlib.util.spec_from_file_location('r356_safe_runner_helpers_r376',HELPER_PATH)
    mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod
def pinned(root,row,h):
    p=root/row['path']; h.no_symlink(p)
    if sha(p)!=row['sha256']: raise RuntimeError('input SHA mismatch: '+row['path'])
    if 'sizeBytes' in row and p.stat().st_size!=row['sizeBytes']: raise RuntimeError('input size mismatch: '+row['path'])
    return p
def verify_inputs(h,m):
    if Path(os.path.realpath(ROOT))!=ROOT: raise RuntimeError('fixed worktree resolved unexpectedly')
    if m.get('schema')!='r377-core-run-input-r001' or m.get('status')!='PREPARED_NOT_RUN_R001' or m.get('fixedWorktree')!=str(ROOT): raise RuntimeError('unsupported run manifest')
    if m.get('limits')!={'maxInvocations':1,'maxWallSeconds':300,'maxAllocatedBytes':500000000,'minimumFreeBytes':12000000000,'maxConcurrentJobs':2}: raise RuntimeError('execution budget differs from reviewed cap')
    if m.get('ownedProcessHelper')!={'path':'docs/production/current/qa_drafts/migration_receipt_reconciliation_r356/runner_r003/run_core_r356.py','sha256':HELPER_SHA}: raise RuntimeError('shared process helper pin differs')
    r368m=pinned(ROOT,m['r368InputManifest'],h); upstream=json.loads(r368m.read_text())
    cman=pinned(ROOT,m['candidateManifest'],h); cm=json.loads(cman.read_text())
    cinput=pinned(ROOT,m['candidateInputManifest'],h); candidate_test=pinned(ROOT,m['test'],h)
    if cm.get('schema')!='effect-build-comparison-r377-candidate-manifest-r001' or cm.get('status')!='SOURCE_ONLY_NOT_COMPILED_OR_RUN': raise RuntimeError('R377 candidate manifest schema/status mismatch')
    expected_candidate={r['path']:r for r in cm.get('files',[])}
    for row in (m['test'],m['candidateInputManifest'],m['readme'],m['pairLedger']):
        cr=expected_candidate.get(row['path'])
        if cr is None or cr.get('sha256')!=row['sha256'] or cr.get('sizeBytes')!=row.get('sizeBytes'): raise RuntimeError('candidate file is not cross-bound by R377 manifest: '+row['path'])
    if cm.get('boundInputs',{}).get('r368InputManifestSHA256')!=m['r368InputManifest']['sha256']: raise RuntimeError('R368 input manifest is not cross-bound')
    if m.get('r368StagedRows')!=[r for r in upstream['stagedFiles'] if r.get('role') in R368_ROLES]: raise RuntimeError('staged package rows differ from pinned R368 manifest')
    rows=m['r368StagedRows']; core=sum(r['role']!='resource' for r in rows); resources=sum(r['role']=='resource' for r in rows)
    if (len(rows),core,resources)!=(57,55,2): raise RuntimeError('expected exact 55 Swift source/helper + 2 resource R368 payload')
    for row in rows:
        src=ROOT/row['sourcePath']; h.no_symlink(src)
        if sha(src)!=row['sha256'] or src.stat().st_size!=row['sizeBytes']: raise RuntimeError('R368 staged source changed: '+row['sourcePath'])
    if m['packageTemplate']!=upstream['packageTemplate'] or sha_bytes(m['packageTemplate'].encode())!=m['packageTemplateSHA256'] or m['packageTemplateSHA256']!=upstream['packageTemplateSHA256']: raise RuntimeError('pinned R368 Package.swift template mismatch')
    for key in ('save','report','appIdentity'):
        p=pinned(ROOT,m[key])
        if key=='save' and p.stat().st_size!=m[key]['sizeBytes']: raise RuntimeError('R368 save size mismatch')
    r368=cm.get('boundInputs',{})
    for key,field in [('r368EarnedSaveSHA256','save'),('r368FreeRunReportSHA256','report')]:
        if r368.get(key)!=m[field]['sha256']: raise RuntimeError('candidate manifest does not bind '+field)
    if m['test'].get('testIdentifier')!=TEST_ID or m['test'].get('previewCount')!=24: raise RuntimeError('test filter/preview contract mismatch')
    if m['test'].get('runtimeHelperPath') not in [r['sourcePath'] for r in rows if r['role']=='candidate_helper']: raise RuntimeError('required integrated runtime helper is not staged')
    tool=m.get('swiftToolchain',{})
    version=subprocess.run([tool['executable'],'--version'],capture_output=True,text=True,timeout=8,check=True).stdout.strip()
    if version!=tool['version']: raise RuntimeError('Swift toolchain drift')
    return rows,candidate_test,r368m,cman,cinput

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
def validate_report(path,m):
    obj=json.loads(path.read_text())
    if obj.get('schema')!='effect-build-comparison-r377-v1' or obj.get('status')!='OBSERVATIONAL_OWNED_EFFECT_PREVIEWS_NOT_BALANCE_ACCEPTANCE': raise RuntimeError('R377 report schema/status mismatch')
    if obj.get('sourceSaveSHA256')!=m['save']['sha256'] or obj.get('sourceReportSHA256')!=m['report']['sha256'] or obj.get('r368InputManifestSHA256')!=m['r368InputManifest']['sha256']: raise RuntimeError('report not joined to pinned earned snapshot')
    if obj.get('previewCount')!=24 or len(obj.get('previews',[]))!=24: raise RuntimeError('expected exactly 24 R377 previews')
    expected={ (pair['family'],pair['challengeID'],seed,arm) for pair in m['pairs'] for seed in m['seeds'] for arm in ('candidate_effect','control') }
    actual={(row['family'],row['challengeID'],row['seed'],row['arm']) for row in obj['previews']}
    if actual!=expected: raise RuntimeError('R377 family/challenge/seed/arm matrix mismatch')
    for pair in m['pairs']:
        cand=[x for x in obj['previews'] if x['family']==pair['family'] and x['arm']=='candidate_effect']
        if len(cand)!=3: raise RuntimeError('R377 candidate arm count mismatch')
        if not any(any(x['eventCounts'].get(k,0)>0 for k in pair['expectedEffectKinds']) for x in cand): raise RuntimeError('expected effect was not observed: '+pair['family'])
        for row in obj['previews']:
            if row['family']!=pair['family']: continue
            g=row['gear']
            if (g['qualityID'],g['enhancement'],g['refinement'],g['investmentDust'])!=(pair['qualityID'],pair['enhancement'],pair['refinement'],pair['investmentDust']): raise RuntimeError('R377 paired gear metadata mismatch')
    return obj

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--input-manifest',required=True); ap.add_argument('--input-sha256',required=True); ap.add_argument('--runner-sha256',required=True); ap.add_argument('--execute',action='store_true'); ap.add_argument('--run-id'); ap.add_argument('--limit-seconds',type=int,default=MAX_SECONDS); a=ap.parse_args()
    if Path(a.input_manifest).resolve(strict=True)!=INPUT or sha(INPUT)!=a.input_sha256: raise RuntimeError('fixed input manifest pin mismatch')
    if sha(Path(__file__))!=a.runner_sha256 or a.runner_sha256!=json.loads(INPUT.read_text()).get('runnerSHA256'): raise RuntimeError('runner source SHA mismatch')
    h=load_helper(); m=json.loads(INPUT.read_text()); staged,test,r368m,cman,cinput=verify_inputs(h,m)
    if not a.execute:
        print(json.dumps({'status':'PREFLIGHT_ONLY_NOT_RUN','r368SwiftInputs':55,'r368Resources':2,'expectedXCTest':1,'expectedPreviews':24,'execution':'NOT_RUN','sourceSaveWrites':'NONE','simulator':'NONE'},indent=2)); return 0
    if a.limit_seconds!=MAX_SECONDS or shutil.disk_usage(ROOT).free<MIN_FREE: raise RuntimeError('fixed 300-second / 12GB start gate failed')
    h.ensure_no_competing_swift(); rid=str(uuid.UUID(a.run_id or ''))
    if rid!=(a.run_id or '').lower(): raise RuntimeError('execution needs canonical UUID')
    runs=RUNNER/'runs'; h.no_symlink(runs,allow_missing_leaf=True); runs.mkdir(mode=0o700,exist_ok=True)
    h.no_symlink(LOCK,allow_missing_leaf=True); fd=os.open(LOCK,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f: json.dump({'runID':rid,'startedAt':dt.datetime.now().astimezone().isoformat(),'inputSHA256':a.input_sha256,'runnerSHA256':a.runner_sha256},f); f.write('\n'); f.flush(); os.fsync(f.fileno())
    out=runs/rid; out.mkdir(mode=0o700,exist_ok=False); pkg=out/'package'; scratch=out/'scratch'; evidence=out/'evidence'; evidence.mkdir(mode=0o700)
    (pkg/'Sources/WitchGameCore').mkdir(parents=True,mode=0o700); (pkg/'Tests/WitchGameCoreTests').mkdir(parents=True,mode=0o700)
    rec={'schema':'r377-core-run-v1','status':'PREPARING_RETAINED','runID':rid,'inputManifestSHA256':a.input_sha256,'runnerSHA256':a.runner_sha256,'r368InputManifestSHA256':m['r368InputManifest']['sha256'],'candidateManifestSHA256':m['candidateManifest']['sha256'],'testSHA256':m['test']['sha256'],'expectedTests':[TEST_ID],'limits':m['limits'],'simulator':'NONE','sourceSaveMutation':'NONE'}
    receipt=out/'RUN.json'; log=out/'swift_test.log'; atomic(receipt,rec,first=True)
    proc=None; observed={}; errors=[]; status='INCOMPLETE_RETAINED'; started=time.monotonic()
    try:
        for row in staged:
            src=ROOT/row['sourcePath']; dst=pkg/row['destinationPath']; dst.parent.mkdir(parents=True,exist_ok=True,mode=0o700); shutil.copyfile(src,dst); os.chmod(dst,row['mode'])
            if sha(dst)!=row['sha256']: raise RuntimeError('staged copy mismatch '+row['destinationPath'])
        testdest=pkg/m['test']['destinationPath']; testdest.parent.mkdir(parents=True,exist_ok=True,mode=0o700); shutil.copyfile(test,testdest)
        (pkg/'Package.swift').write_text(m['packageTemplate'])
        if sha(testdest)!=m['test']['sha256'] or sha(pkg/'Package.swift')!=m['packageTemplateSHA256']: raise RuntimeError('staged test/package mismatch')
        scratch.mkdir(mode=0o700)
        for n in ('tmp','cache','config','security','build'): (scratch/n).mkdir(mode=0o700)
        env=os.environ.copy(); env['TMPDIR']=str(scratch/'tmp'); env['WITCH_R377_INPUT_MANIFEST']=str(m['candidateInputManifest']['absolutePath']); env['WITCH_R377_INPUT_MANIFEST_SHA256']=m['candidateInputManifest']['sha256']; env['WITCH_R377_WORKTREE']=str(ROOT); env['WITCH_R377_OUTPUT']=str(evidence/'report.json')
        cmd=[m['swiftToolchain']['executable'],'test','--package-path',str(pkg),'--scratch-path',str(scratch/'build'),'--cache-path',str(scratch/'cache'),'--config-path',str(scratch/'config'),'--security-path',str(scratch/'security'),'--jobs','2','--filter',TEST_ID]
        if h.usage(out)[1]>OUTPUT_CAP: raise RuntimeError('output cap exceeded before Swift launch')
        with log.open('xb') as lf:
            proc=subprocess.Popen(cmd,cwd=ROOT,env=env,stdout=lf,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,start_new_session=True,close_fds=True)
            rec.update(status='RUNNING',command=cmd,runnerPID=proc.pid); atomic(receipt,rec)
            deadline=started+MAX_SECONDS
            while proc.poll() is None:
                if time.monotonic()>deadline: raise RuntimeError('300-second wall cap exceeded')
                if shutil.disk_usage(ROOT).free<MIN_FREE: raise RuntimeError('12GB free-space floor breached')
                if h.usage(out)[1]>OUTPUT_CAP: raise RuntimeError('500MB allocated-output cap breached')
                rows=h.process_rows()
                for row in h.descendants(rows,proc.pid): observed[row['pid']]=row
                for row in h.owned_test_processes(rows,list(scratch.rglob('*.xctest'))): observed[row['pid']]=row
                time.sleep(.2)
            code=proc.wait(timeout=2); rec['returnCode']=code
        verdict=h.verify_log(log,[TEST_ID]); rec['testVerdict']=verdict
        reportpath=evidence/'report.json'
        if code==0 and verdict.get('accepted') and reportpath.is_file():
            report=validate_report(reportpath,m)
            rec['previewRows']=len(report['previews']); rec['reportSHA256']=sha(reportpath); rec['reportBytes']=reportpath.stat().st_size
            status='CORE_TEST_PASSED_REVIEW_REQUIRED'
        else: errors.append('one exact XCTest and 24-row structured preview report did not pass')
    except BaseException as e:
        errors.append(f'{type(e).__name__}: {e}')
        if proc is not None: h.stop_owned(proc,list(scratch.rglob('*.xctest')) if scratch.exists() else [],observed)
    finally:
        if proc is not None:
            rec['ownedCleanup']=h.stop_owned(proc,list(scratch.rglob('*.xctest')) if scratch.exists() else [],observed)
            rows=h.process_rows(); descendants=h.descendants(rows,proc.pid); children=h.owned_test_processes(rows,list(scratch.rglob('*.xctest')) if scratch.exists() else [])
            alive={x['pid']:x for x in descendants+children}
            if proc.poll() is None: alive[proc.pid]={'pid':proc.pid,'command':'owned swift test process'}
            rec['ownedProcessesAfter']=list(alive.values()); rec['ownedProcessesAbsent']=not alive
        rec['finishedAt']=dt.datetime.now().astimezone().isoformat(); rec['elapsedSeconds']=round(time.monotonic()-started,3)
        try:
            rec['stagedInputsUnchanged']=all(sha(ROOT/x['sourcePath'])==x['sha256'] for x in staged)
            rec['candidateInputsUnchanged']=sha(test)==m['test']['sha256'] and sha(INPUT)==a.input_sha256 and sha(Path(__file__))==a.runner_sha256 and sha(r368m)==m['r368InputManifest']['sha256'] and sha(cman)==m['candidateManifest']['sha256'] and sha(cinput)==m['candidateInputManifest']['sha256'] and all(sha(ROOT/m[k]['path'])==m[k]['sha256'] for k in ('save','report','appIdentity')) and all(sha(ROOT/m[k]['path'])==m[k]['sha256'] for k in ('candidateManifest','candidateInputManifest','test','readme','pairLedger')) and sha(HELPER_PATH)==HELPER_SHA
            rec['outputUsage']={'logicalBytes':h.usage(out)[0],'allocatedBytes':h.usage(out)[1]}; rec['freeBytesAfter']=shutil.disk_usage(ROOT).free
            if log.exists(): rec['testVerdict']=h.verify_log(log,[TEST_ID])
            if (evidence/'report.json').exists(): rec['reportSHA256']=sha(evidence/'report.json')
        except BaseException as e: errors.append(f'closeout verification failed: {type(e).__name__}: {e}')
        rec['errors']=errors
        if rec['elapsedSeconds']>MAX_SECONDS or rec.get('outputUsage',{}).get('allocatedBytes',OUTPUT_CAP+1)>OUTPUT_CAP or not rec.get('stagedInputsUnchanged',False) or not rec.get('candidateInputsUnchanged',False) or (proc is not None and not rec.get('ownedProcessesAbsent',False)): status='INCOMPLETE_RETAINED'
        rec['status']=status; atomic(receipt,rec)
    print(json.dumps({'status':status,'receipt':str(receipt)},indent=2)); return 0 if status=='CORE_TEST_PASSED_REVIEW_REQUIRED' else 2
if __name__=='__main__':
    raise SystemExit(main())

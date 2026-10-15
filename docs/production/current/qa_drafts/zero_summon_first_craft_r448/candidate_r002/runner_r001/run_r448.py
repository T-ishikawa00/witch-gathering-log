#!/usr/bin/env python3
"""R448 one-case zero-summon first-craft Core pilot. Preparation only; never touches app or live saves."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, os, re, shutil, stat, subprocess, sys, time
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
HERE = ROOT / 'docs/production/current/qa_drafts/zero_summon_first_craft_r448/candidate_r002/runner_r001'
MANIFEST = HERE / 'INPUT_MANIFEST_R001.json'
RUNS = HERE / 'runs'
LOCK = HERE / 'EXECUTION_STARTED_R001.json'
R445_STATE = ROOT / 'docs/production/current/qa_drafts/native_completion_r445/build_tools_r001/BUILD_STATE_R001.json'
R445_MAP = ROOT / 'docs/production/current/qa_drafts/native_completion_r445/build_tools_r001/NATIVE_SOURCE_MAP_R001.json'
R368_SUPPORT = ROOT / 'docs/production/current/qa_drafts/normal_onboarding_progression_r368/candidate_r001/runner_r001/INPUT_MANIFEST_R001.json'
PRODUCT_INPUTS = ROOT / 'docs/production/current/qa_drafts/economy_cohorts_r195/candidate_r004/PRODUCT_INPUTS_R001.json'
HELPER = ROOT / 'docs/production/current/qa_drafts/migration_receipt_reconciliation_r356/runner_r002/run_core_r356.py'
HELPER_SHA = 'f5771645bfc9ee46645a9951443b7cd3de0d1fe262a9dfb86dcb3cb88b03cc5b'
MAX_WALL = 600
MAX_CASE = 90
MAX_BUILD_ALLOCATED = 500_000_000
MAX_EVIDENCE_ALLOCATED = 50_000_000
MIN_FREE = 12_000_000_000
RUN_ID = '44800000-0001-4002-8000-000000000001'
TEST_FILTER = 'EconomyCohortProgressionR355Tests/testR448FreeNoAdZeroSummonFirstCraftProgression'
RUNNER_SCHEMA = 'r448-zero-summon-first-craft-runner-v1'

class Hold(RuntimeError): pass

def sha_bytes(b: bytes) -> str: return hashlib.sha256(b).hexdigest()
def sha_file(p: Path) -> str:
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()
def no_link(p: Path, missing_leaf=False) -> None:
    p=Path(os.path.abspath(p)); cur=Path(p.anchor)
    for i,name in enumerate(p.parts[1:]):
        cur=cur/name
        if missing_leaf and i==len(p.parts[1:])-1 and not cur.exists() and not cur.is_symlink(): continue
        if cur.is_symlink(): raise Hold(f'symlink rejected: {cur}')
def read_json(p: Path):
    no_link(p)
    if not p.is_file(): raise Hold(f'missing input: {p}')
    return json.loads(p.read_text(encoding='utf-8'))
def file_row(source: str, dest: str, role: str) -> dict:
    if source.startswith('/') or dest.startswith('/') or '..' in Path(source).parts or '..' in Path(dest).parts:
        raise Hold('manifest paths must be contained relative paths')
    p=ROOT/source; no_link(p)
    if not p.is_file(): raise Hold(f'not a regular source: {source}')
    st=p.stat()
    return {'sourcePath':source,'destinationPath':dest,'role':role,'sizeBytes':st.st_size,
            'mode':stat.S_IMODE(st.st_mode),'sha256':sha_file(p)}
def load_helper():
    if sha_file(HELPER)!=HELPER_SHA: raise Hold('pinned process/output helper changed')
    spec=importlib.util.spec_from_file_location('r356_pinned_helpers',HELPER)
    mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod

def verify_inputs(manifest_sha: str, runner_sha: str, require_sealed: bool=False):
    if ROOT.resolve()!=ROOT or Path(__file__).resolve()!=HERE/'run_r448.py': raise Hold('fixed worktree or runner path mismatch')
    if sha_file(MANIFEST)!=manifest_sha or sha_file(Path(__file__))!=runner_sha: raise Hold('manifest or runner pin mismatch')
    m=read_json(MANIFEST)
    if m.get('schema')!='r448-zero-summon-first-craft-input-v1' or m.get('fixedWorktree')!=str(ROOT): raise Hold('R448 input schema/worktree mismatch')
    if m.get('runnerPath')!='docs/production/current/qa_drafts/zero_summon_first_craft_r448/candidate_r002/runner_r001/run_r448.py' or m.get('runnerSHA256')!=runner_sha: raise Hold('R448 runner path/hash does not cross-join to manifest')
    if m.get('status') not in ('PREPARED_UNSEALED_ROOT_IDENTITY','PREPARED_NOT_RUN'): raise Hold('candidate status is not prepared')
    if m.get('limits')!={'compileInvocations':1,'maxAttempts':1,'maxWallSeconds':MAX_WALL,'maxCaseSeconds':MAX_CASE,'maxBuildAllocatedBytes':MAX_BUILD_ALLOCATED,'maxEvidenceAllocatedBytes':MAX_EVIDENCE_ALLOCATED,'minimumFreeBytes':MIN_FREE,'jobs':2}:
        raise Hold('fixed R448 caps changed')
    for p in (R445_STATE,R445_MAP,R368_SUPPORT,PRODUCT_INPUTS,HELPER): no_link(p)
    if m.get('r445BuildStatePath')!='docs/production/current/qa_drafts/native_completion_r445/build_tools_r001/BUILD_STATE_R001.json' or m.get('r445SourceMapPath')!='docs/production/current/qa_drafts/native_completion_r445/build_tools_r001/NATIVE_SOURCE_MAP_R001.json' or m.get('r368SupportManifestPath')!='docs/production/current/qa_drafts/normal_onboarding_progression_r368/candidate_r001/runner_r001/INPUT_MANIFEST_R001.json':
        raise Hold('upstream source/build/support path identity differs from the exact reviewed inputs')
    if sha_file(R445_STATE)!=m['r445BuildStateSHA256'] or sha_file(R445_MAP)!=m['r445SourceMapSHA256']:
        raise Hold('R445 frozen source receipt/map changed')
    if sha_file(R368_SUPPORT)!=m['r368SupportManifestSHA256'] or sha_file(PRODUCT_INPUTS)!=m['productInputs']['sha256']:
        raise Hold('R368 support/product input changed')
    state=read_json(R445_STATE); source_map=read_json(R445_MAP); support=read_json(R368_SUPPORT)
    if state.get('phase')!='PASS_RELEASE_ONLY' or state.get('sourceMapSHA256')!=m['r445SourceMapSHA256'] or state.get('sourceMap')!=source_map:
        raise Hold('R445 receipt is not the pinned successful frozen Release build')
    frozen=Path(state.get('frozen',''))
    if not frozen.is_absolute() or not frozen.is_dir() or frozen.is_symlink(): raise Hold('R445 frozen source root is unavailable')
    rows=m.get('stagedFiles',[])
    snap=m.get('stagedRowsSnapshot',{})
    if snap.get('path')!='docs/production/current/qa_drafts/zero_summon_first_craft_r448/candidate_r002/staged_rows.tmp.json': raise Hold('staged-row review snapshot path mismatch')
    snap_path=ROOT/snap['path']; no_link(snap_path)
    if not snap_path.is_file() or snap_path.stat().st_size!=snap.get('sizeBytes') or sha_file(snap_path)!=snap.get('sha256') or json.loads(snap_path.read_text())!=rows: raise Hold('staged-row review snapshot differs from manifest row table')
    if not rows or rows!=sorted(rows,key=lambda x:x['destinationPath']): raise Hold('staged rows are empty or not canonical')
    if len({r['destinationPath'] for r in rows})!=len(rows): raise Hold('duplicate package destination')
    by_dest={r['destinationPath']:r for r in rows}
    source_rows=[r for r in rows if r['role'] in ('core','resource')]
    expected=[]
    for key,digest in sorted(source_map.items()):
        if not key.startswith('WitchGameCore/Sources/WitchGameCore/'): continue
        role='resource' if '/Resources/' in key else ('core' if key.endswith('.swift') else None)
        if role:
            source=(frozen/key).relative_to(ROOT).as_posix()
            expected.append(file_row(source,key[len('WitchGameCore/'):],role))
    if source_rows!=sorted(expected,key=lambda x:x['destinationPath']): raise Hold('R445 current Core/resource stage does not exactly match frozen source map')
    if sum(r['role']=='core' for r in rows)!=56 or sum(r['role']=='resource' for r in rows)!=2:
        raise Hold('R445 source/resource count mismatch')
    support_rows=[r for r in rows if r['role'] in ('candidate_helper','test_support')]
    old_support=[r for r in support.get('stagedFiles',[]) if r['role'] in ('candidate_helper','test_support')]
    if len(support_rows)!=len(old_support): raise Hold('R368 helper/support row count changed')
    expected_support=[]
    for r in old_support: expected_support.append(file_row(r['sourcePath'],r['destinationPath'],r['role']))
    if support_rows!=sorted(expected_support,key=lambda x:x['destinationPath']): raise Hold('R368 helper/support bytes differ from exact existing pins')
    test_rows=[r for r in rows if r['role']=='pilot_test']
    if len(test_rows)!=1 or test_rows[0]!=m['pilotTestOverride']: raise Hold('R448 test override row mismatch')
    if test_rows[0]!=file_row(m['candidateTestPath'], 'Tests/WitchGameCoreTests/EconomyCohortProgressionR355Tests.swift','pilot_test'):
        raise Hold('R448 test source bytes/mode differ from candidate pin')
    if len(rows)!=56+2+len(support_rows)+1: raise Hold('unexpected staged row count')
    test_text=(ROOT/m['candidateTestPath']).read_text(encoding='utf-8')
    pilot=m.get('pilot',{})
    if pilot!={'cohort':'free_no_ad','horizonDays':30,'seed':100049,'attempt':1,'caseID':'R448-free_no_ad-30-seed100049','runID':RUN_ID,'suite':'EconomyCohortProgressionR355Tests','testMethod':'testR448FreeNoAdZeroSummonFirstCraftProgression','testFilter':TEST_FILTER}:
        raise Hold('R448 exact single-case identity changed')
    if m.get('pilotRunID')!=RUN_ID or m.get('candidateTestSHA256')!=test_rows[0]['sha256']:
        raise Hold('R448 test/run pin mismatch')
    if not re.search(r'func\s+'+re.escape(pilot['testMethod'])+r'\s*\(',test_text) or '.mockSummon(' in test_text:
        raise Hold('exact selected test absent or contains a summon dispatch call')
    match=re.search(r'let sourcePaths\s*=\s*\[(.*?)\]',test_text,re.S)
    if not match: raise Hold('Core input digest contract sourcePaths not found')
    for sp in re.findall(r'"([^"]+)"',match.group(1)):
        if sp.startswith(('Sources/WitchGameCore/','Tests/WitchGameCoreTests/')) and sp not in by_dest:
            raise Hold(f'XCTest source digest path has no staged file row: {sp}')
    product=m['productInputs']; pp=ROOT/product['path']
    if product!=support.get('productInputs') or pp.is_symlink() or not pp.is_file() or pp.stat().st_size!=product['sizeBytes'] or sha_file(pp)!=product['sha256']:
        raise Hold('R368 product inputs are not exact')
    identity=m.get('appRuntimeIdentity')
    sealed=bool(identity and identity.get('path') and identity.get('sha256') and identity.get('sizeBytes'))
    if require_sealed and (m.get('status')!='PREPARED_NOT_RUN' or not sealed): raise Hold('Root must bind current R447-compatible app identity before execution')
    if sealed:
        ip=ROOT/identity['path']; no_link(ip)
        if identity['path'].startswith('/') or ip.is_symlink() or not ip.is_file() or ip.stat().st_size!=identity['sizeBytes'] or sha_file(ip)!=identity['sha256']:
            raise Hold('Root-sealed app runtime identity pin mismatch')
    if m.get('packageTemplateSHA256')!=sha_bytes(m.get('packageTemplate','').encode()): raise Hold('Package.swift digest mismatch')
    helper=load_helper()
    return m,helper,state,source_map,support

def verify_stage(helper,package: Path,m: dict):
    allowed={'Package.swift'}|{x['destinationPath'] for x in m['stagedFiles']}; seen=set()
    for p in package.rglob('*'):
        if p.is_symlink(): raise Hold(f'staged package symlink: {p}')
        if p.is_file():
            rel=p.relative_to(package).as_posix()
            if rel not in allowed: raise Hold(f'unexpected package file: {rel}')
            seen.add(rel)
    expected={'Package.swift'}|{x['destinationPath'] for x in m['stagedFiles']}
    if seen!=expected: raise Hold(f'stage mismatch missing={sorted(expected-seen)} extra={sorted(seen-expected)}')
    for x in m['stagedFiles']:
        p=package/x['destinationPath']
        if p.stat().st_size!=x['sizeBytes'] or stat.S_IMODE(p.stat().st_mode)!=x['mode'] or sha_file(p)!=x['sha256']:
            raise Hold(f'post-stage hash/size/mode mismatch: {x["destinationPath"]}')
    staged_test=package/'Tests/WitchGameCoreTests/EconomyCohortProgressionR355Tests.swift'
    if not re.search(r'func\s+testR448FreeNoAdZeroSummonFirstCraftProgression\s*\(',staged_test.read_text()):
        raise Hold('staged R448 test method missing')

def execute(args,m,helper,state,source_map,support):
    if args.run_id!=RUN_ID or args.limit_seconds!=MAX_WALL: raise Hold('only the fixed one-case R448 execution is allowed')
    if shutil.disk_usage(ROOT).free<MIN_FREE: raise Hold('12GB free-space floor not met')
    helper.ensure_no_competing_swift()
    swift_raw=shutil.which('swift')
    if not swift_raw: raise Hold('Swift unavailable')
    swift=Path(swift_raw).resolve(strict=True)
    try: version=subprocess.run([str(swift),'--version'],capture_output=True,text=True,timeout=8,check=True).stdout.strip()
    except (OSError,subprocess.SubprocessError) as e: raise Hold(f'Swift preflight failed before lock: {type(e).__name__}: {e}')
    if not version: raise Hold('Swift version is empty')
    no_link(RUNS,missing_leaf=True); no_link(LOCK,missing_leaf=True)
    out=RUNS/RUN_ID; no_link(out,missing_leaf=True)
    if out.exists(): raise Hold('exclusive R448 run already exists; no retry')
    env=os.environ.copy(); reportdir=out/f'r448_{RUN_ID}'
    env.update({'TMPDIR':str(out/'scratch'/'tmp'),'WITCH_SOURCE_ROOT':str(out/'package'),
        'WITCH_R355_COHORT':'free_no_ad','WITCH_R355_HORIZON':'30','WITCH_R355_SEED':'100049','WITCH_R355_ATTEMPT':'1',
        'WITCH_R355_CASE_ID':'R448-free_no_ad-30-seed100049','WITCH_R355_RUN_ID':RUN_ID,
        'WITCH_R355_PRODUCT_INPUTS':str(ROOT/m['productInputs']['path']),'WITCH_R355_PRODUCT_INPUTS_SHA256':m['productInputs']['sha256'],
        'WITCH_R355_APP_IDENTITY_PATH':str(ROOT/m['appRuntimeIdentity']['path']),'WITCH_R355_APP_IDENTITY_SHA256':m['appRuntimeIdentity']['sha256'],
        'WITCH_R355_OUTPUT':str(reportdir/'report.json')})
    no_link(LOCK,missing_leaf=True)
    try: fd=os.open(LOCK,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    except FileExistsError: raise Hold('single R448 invocation already recorded')
    with os.fdopen(fd,'w',encoding='utf-8') as f:
        json.dump({'status':'STARTED','runID':RUN_ID,'manifestSHA256':args.manifest_sha256,'runnerSHA256':args.runner_sha256,'swift':str(swift),'version':version},f,sort_keys=True); f.write('\n'); f.flush(); os.fsync(f.fileno())
    runfd=os.open(HERE,os.O_RDONLY); os.fsync(runfd); os.close(runfd)
    out.mkdir(mode=0o700,parents=True,exist_ok=False)
    started=time.monotonic(); runpath=out/'RUN.json'; log=out/'swift_test.log'; package=out/'package'; scratch=out/'scratch'
    proc=None; observed={}; cleanup=[]; errors=[]; status='INCOMPLETE_RETAINED'; rec={'schema':RUNNER_SCHEMA,'status':'PREPARING_RETAINED','runID':RUN_ID,'inputManifestSHA256':args.manifest_sha256,'runnerSHA256':args.runner_sha256,'maxWallSeconds':MAX_WALL,'maxCaseSeconds':MAX_CASE,'maxBuildAllocatedBytes':MAX_BUILD_ALLOCATED,'maxEvidenceAllocatedBytes':MAX_EVIDENCE_ALLOCATED,'minimumFreeBytes':MIN_FREE,'testFilter':TEST_FILTER,'expectedTests':[TEST_FILTER],'simulator':'NONE','liveSave':'NONE','swift':str(swift),'swiftVersion':version}
    try:
        for d in (package/'Sources/WitchGameCore',package/'Tests/WitchGameCoreTests'):
            d.mkdir(mode=0o700,parents=True,exist_ok=True)
        for x in m['stagedFiles']:
            src=ROOT/x['sourcePath']; dst=package/x['destinationPath']; no_link(src); no_link(dst,missing_leaf=True)
            dst.parent.mkdir(mode=0o700,parents=True,exist_ok=True); shutil.copyfile(src,dst); os.chmod(dst,x['mode'])
        p=package/'Package.swift'; p.write_text(m['packageTemplate']); p.chmod(0o600)
        verify_stage(helper,package,m)
        scratch.mkdir(mode=0o700)
        for name in ('cache','config','security','tmp','build'): (scratch/name).mkdir(mode=0o700)
        cmd=[str(swift),'test','--package-path',str(package),'--scratch-path',str(scratch/'build'),'--cache-path',str(scratch/'cache'),'--config-path',str(scratch/'config'),'--security-path',str(scratch/'security'),'--jobs','2','--filter',TEST_FILTER]
        rec.update({'status':'RUNNING','command':cmd,'packagePath':str(package),'scratchPath':str(scratch),'caseIdentity':m['pilot']})
        runpath.write_text(json.dumps(rec,sort_keys=True,indent=2)+'\n')
        with log.open('xb') as lf:
            proc=subprocess.Popen(cmd,cwd=ROOT,env=env,stdout=lf,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,start_new_session=True,close_fds=True)
            rec.update({'runnerPID':proc.pid,'runnerPGID':proc.pid}); runpath.write_text(json.dumps(rec,sort_keys=True,indent=2)+'\n')
            deadline=started+MAX_WALL
            while proc.poll() is None:
                if time.monotonic()>deadline: raise Hold('600 second total wall cap exceeded')
                if shutil.disk_usage(ROOT).free<MIN_FREE: raise Hold('12GB free-space floor breached')
                scratch_alloc=helper.usage(scratch)[1]
                evidence_alloc=max(0,helper.usage(out)[1]-scratch_alloc)
                if scratch_alloc>MAX_BUILD_ALLOCATED: raise Hold('500MB allocated compiler/scratch cap exceeded')
                if evidence_alloc>MAX_EVIDENCE_ALLOCATED: raise Hold('50MB allocated evidence cap exceeded')
                rows=helper.process_rows(); children=helper.descendants(rows,proc.pid)
                for child in children: observed[child['pid']]=child
                bundles=list(scratch.rglob('*.xctest'))
                for child in helper.owned_test_processes(rows,bundles): observed[child['pid']]=child
                time.sleep(.2)
            code=proc.wait(timeout=2); rec['returnCode']=code
        text=log.read_text(errors='replace')
        events=re.findall(r"Test Case '-\[WitchGameCoreTests\.([^ ]+) ([^\]]+)\]' (passed|failed|skipped)",text)
        passed=[f'{a}/{b}' for a,b,s in events if s=='passed']; failed=[f'{a}/{b}' for a,b,s in events if s=='failed']; skipped=[f'{a}/{b}' for a,b,s in events if s=='skipped']
        elapsed_match=re.search(r'Executed 1 test, with 0 failures in ([0-9.]+) seconds',text)
        case_seconds=float(elapsed_match.group(1)) if elapsed_match else None
        rec['testVerdict']={'passed':passed,'failed':failed,'skipped':skipped,'caseElapsedSeconds':case_seconds,'accepted':code==0 and passed==[TEST_FILTER] and not failed and not skipped and case_seconds is not None and case_seconds<=MAX_CASE}
        if rec['testVerdict']['accepted']: status='ONE_CASE_PASSED_REVIEW_REQUIRED'
        else: errors.append('test outcome did not match the exact one-test R448 acceptance')
        report=reportdir/'report.json'
        if not report.is_file() or report.is_symlink(): errors.append('expected Core report.json missing or unsafe')
        else:
            rec['reportSHA256']=sha_file(report); rec['reportSizeBytes']=report.stat().st_size
            if report.stat().st_size>MAX_EVIDENCE_ALLOCATED: errors.append('report exceeds evidence byte limit')
    except BaseException as e:
        errors.append(f'{type(e).__name__}: {e}')
        if proc is not None:
            bundles=list(scratch.rglob('*.xctest')) if scratch.exists() else []
            cleanup=helper.stop_owned(proc,bundles,observed)
    finally:
        if proc is not None:
            bundles=list(scratch.rglob('*.xctest')) if scratch.exists() else []
            cleanup.extend(helper.stop_owned(proc,bundles,observed))
            ps=helper.process_rows(); desc=helper.descendants(ps,proc.pid); tests=helper.owned_test_processes(ps,bundles)
            survivors={x['pid']:x for x in desc+tests}; rec['ownedProcessesAfter']=list(survivors.values()); rec['ownedProcessesAbsent']=not survivors
        rec['ownedCleanup']=cleanup; rec['finishedElapsedSeconds']=round(time.monotonic()-started,3)
        try:
            rec['sourceInputsUnchanged']=all(sha_file(ROOT/x['sourcePath'])==x['sha256'] for x in m['stagedFiles'])
            rec['r445MapUnchanged']=sha_file(R445_MAP)==m['r445SourceMapSHA256']
            rec['r445BuildStateUnchanged']=sha_file(R445_STATE)==m['r445BuildStateSHA256']
            rec['r368SupportManifestUnchanged']=sha_file(R368_SUPPORT)==m['r368SupportManifestSHA256']
            if log.exists():
                text=log.read_text(errors='replace'); rows=re.findall(r"Test Case '-\[WitchGameCoreTests\.([^ ]+) ([^\]]+)\]' (passed|failed|skipped)",text)
                rec['testEventsCloseout']=[f'{a}/{b}:{s}' for a,b,s in rows]
            if out.exists():
                scratch_alloc=helper.usage(scratch)[1] if scratch.exists() else 0
                rec['outputAllocatedBytes']=helper.usage(out)[1]; rec['scratchAllocatedBytes']=scratch_alloc
                rec['evidenceAllocatedBytes']=max(0,rec['outputAllocatedBytes']-scratch_alloc)
            rec['freeBytesAfter']=shutil.disk_usage(ROOT).free
        except BaseException as e: errors.append(f'closeout readback: {type(e).__name__}: {e}')
        if rec.get('finishedElapsedSeconds',MAX_WALL+1)>MAX_WALL or rec.get('scratchAllocatedBytes',MAX_BUILD_ALLOCATED+1)>MAX_BUILD_ALLOCATED or rec.get('evidenceAllocatedBytes',MAX_EVIDENCE_ALLOCATED+1)>MAX_EVIDENCE_ALLOCATED or not rec.get('sourceInputsUnchanged',False) or not rec.get('r445MapUnchanged',False) or not rec.get('r445BuildStateUnchanged',False) or not rec.get('r368SupportManifestUnchanged',False) or (proc is not None and not rec.get('ownedProcessesAbsent',False)) or any('exceeds' in e or 'missing' in e for e in errors):
            status='INCOMPLETE_RETAINED'
        rec['status']=status; rec['errors']=errors
        runpath.write_text(json.dumps(rec,ensure_ascii=False,sort_keys=True,indent=2)+'\n')
    return status,runpath

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--manifest-sha256',required=True); ap.add_argument('--runner-sha256',required=True); ap.add_argument('--execute',action='store_true'); ap.add_argument('--run-id',default=RUN_ID); ap.add_argument('--limit-seconds',type=int,default=MAX_WALL); a=ap.parse_args()
    if not re.fullmatch('[0-9a-f]{64}',a.manifest_sha256) or not re.fullmatch('[0-9a-f]{64}',a.runner_sha256): raise Hold('lowercase SHA-256 pins required')
    m,helper,state,source_map,support=verify_inputs(a.manifest_sha256,a.runner_sha256,require_sealed=a.execute)
    if not a.execute:
        print(json.dumps({'status':'PREFLIGHT_ONLY_NOT_RUN','rootSealRequired':m.get('status')!='PREPARED_NOT_RUN','pilot':m['pilot'],'coreSwiftSources':56,'resources':2,'stagedRows':len(m['stagedFiles']),'testFilter':TEST_FILTER,'simulator':'NONE','liveSave':'NONE'},ensure_ascii=False,indent=2)); return 0
    status,path=execute(a,m,helper,state,source_map,support); print(json.dumps({'status':status,'receipt':str(path)},ensure_ascii=False,indent=2)); return 0 if status=='ONE_CASE_PASSED_REVIEW_REQUIRED' else 2
if __name__=='__main__':
    try: raise SystemExit(main())
    except Hold as e: print(f'HOLD: {e}',file=sys.stderr); raise SystemExit(2)

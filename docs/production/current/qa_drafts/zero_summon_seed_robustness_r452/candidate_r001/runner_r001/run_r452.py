#!/usr/bin/env python3
"""R452 two-seed zero-summon Core robustness batch. Root execution only; never touches app/live saves."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, os, re, shutil, stat, subprocess, sys, time
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
HERE = ROOT / 'docs/production/current/qa_drafts/zero_summon_seed_robustness_r452/candidate_r001/runner_r001'
MANIFEST = HERE / 'INPUT_MANIFEST_R001.json'
RUNS = HERE / 'runs'
LOCK = HERE / 'EXECUTION_STARTED_R001.json'
R448_SEAL = ROOT / 'docs/production/current/qa_drafts/zero_summon_first_craft_r448/candidate_r002/ROOT_EXECUTION_SEAL_R002.json'
R448_RESULT = ROOT / 'docs/production/current/qa_drafts/zero_summon_first_craft_r448/ROOT_SCOPED_RESULT_R001.json'
R448_RUN = ROOT / 'docs/production/current/qa_drafts/zero_summon_first_craft_r448/candidate_r002/runner_r001/runs/44800000-0001-4002-8000-000000000001/RUN.json'
R445_STATE = ROOT / 'docs/production/current/qa_drafts/native_completion_r445/build_tools_r001/BUILD_STATE_R001.json'
R445_MAP = ROOT / 'docs/production/current/qa_drafts/native_completion_r445/build_tools_r001/NATIVE_SOURCE_MAP_R001.json'
R445_RELEASE = ROOT / 'docs/production/current/qa_drafts/native_completion_r445/build_tools_r001/postbuild_readback_r001/release_BUILD_PASS.json'
R445_INSTALL = ROOT / 'docs/production/current/qa_drafts/native_completion_r445/install_release_r001/RESULT.json'
R447_READBACK = ROOT / 'docs/production/current/qa_drafts/native_completion_r447/build_tools_r001/postbuild_readback_r001/READBACK.json'
R447_SEAL = ROOT / 'docs/production/current/qa_drafts/native_completion_r447/build_tools_r001/ROOT_SEAL_R001.json'
R447_RUN = ROOT / 'native/build/ActiveIntegrationR447/seal-ac8853d549477ad4/run_001/RUN.json'
R368_SUPPORT = ROOT / 'docs/production/current/qa_drafts/normal_onboarding_progression_r368/candidate_r001/runner_r001/INPUT_MANIFEST_R001.json'
PRODUCT_INPUTS = ROOT / 'docs/production/current/qa_drafts/economy_cohorts_r195/candidate_r004/PRODUCT_INPUTS_R001.json'
HELPER = ROOT / 'docs/production/current/qa_drafts/migration_receipt_reconciliation_r356/runner_r002/run_core_r356.py'
HELPER_SHA = 'f5771645bfc9ee46645a9951443b7cd3de0d1fe262a9dfb86dcb3cb88b03cc5b'
MAX_WALL = 600
MAX_CASE = 90
MAX_BUILD_ALLOCATED = 500_000_000
MAX_EVIDENCE_ALLOCATED = 60_000_000
MIN_FREE = 12_000_000_000
RUNNER_SCHEMA = 'r452-zero-summon-seed-robustness-v1'
TEST_METHOD = 'testR452FreeNoAdZeroSummonFirstCraftProgression'
TEST_FILTER = 'EconomyCohortProgressionR355Tests/' + TEST_METHOD
SEEDS = [100069, 200071]
RUN_IDS = [
    '45200000-0001-4002-8000-000000000001',
    '45200000-0002-4002-8000-000000000001',
]

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
def write_json(path: Path, obj: dict, exclusive=False):
    data=(json.dumps(obj,ensure_ascii=False,sort_keys=True,indent=2)+'\n').encode()
    if exclusive:
        fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'wb') as f: f.write(data); f.flush(); os.fsync(f.fileno())
    else:
        temp=path.with_name(path.name+'.tmp')
        fd=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'wb') as f: f.write(data); f.flush(); os.fsync(f.fileno())
        os.replace(temp,path)
        dfd=os.open(path.parent,os.O_RDONLY)
        try: os.fsync(dfd)
        finally: os.close(dfd)

def verify_inputs(manifest_sha: str, runner_sha: str):
    if ROOT.resolve()!=ROOT or Path(__file__).resolve()!=HERE/'run_r452.py': raise Hold('fixed worktree/runner path mismatch')
    if sha_file(MANIFEST)!=manifest_sha or sha_file(Path(__file__))!=runner_sha: raise Hold('manifest or runner SHA mismatch')
    m=read_json(MANIFEST)
    if m.get('schema')!='r452-zero-summon-seed-robustness-input-v1' or m.get('fixedWorktree')!=str(ROOT): raise Hold('R452 schema/worktree mismatch')
    if m.get('status')!='PREPARED_NOT_RUN' or m.get('runnerPath')!='docs/production/current/qa_drafts/zero_summon_seed_robustness_r452/candidate_r001/runner_r001/run_r452.py' or m.get('runnerSHA256')!=runner_sha:
        raise Hold('R452 candidate is not sealed to this runner')
    if m.get('limits')!={'compileInvocations':1,'maxAttemptsPerCase':1,'caseCount':2,'jobs':2,'maxWallSeconds':MAX_WALL,'maxCaseSeconds':MAX_CASE,'maxBuildAllocatedBytes':MAX_BUILD_ALLOCATED,'maxEvidenceAllocatedBytes':MAX_EVIDENCE_ALLOCATED,'minimumFreeBytes':MIN_FREE}:
        raise Hold('R452 caps/schema mismatch')
    cases=m.get('cases')
    if not isinstance(cases,list) or len(cases)!=2: raise Hold('exactly two cases required')
    expected=[]
    for i,(seed,rid) in enumerate(zip(SEEDS,RUN_IDS),1):
        expected.append({'attempt':1,'caseID':f'R452-free_no_ad-30-seed{seed}','cohort':'free_no_ad','horizonDays':30,
                         'seed':seed,'runID':rid,'suite':'EconomyCohortProgressionR355Tests',
                         'testMethod':TEST_METHOD,'testFilter':TEST_FILTER})
    if cases!=expected or m.get('pilotSeeds')!=SEEDS or m.get('pilotRunIDs')!=RUN_IDS:
        raise Hold('seed/run preregistration differs; R448 seed100049 is not allowed here')
    if m.get('testFilter')!=TEST_FILTER: raise Hold('test selector mismatch')
    for p in (R448_SEAL,R448_RESULT,R448_RUN,R445_STATE,R445_MAP,R445_RELEASE,R445_INSTALL,R447_READBACK,R447_SEAL,R447_RUN,R368_SUPPORT,PRODUCT_INPUTS,HELPER): no_link(p)
    compat=m.get('compatibilityEvidence',{})
    for p,key in ((R448_SEAL,'r448ExecutionSealSHA256'),(R448_RESULT,'r448ScopedResultSHA256'),(R448_RUN,'r448RunSHA256'),(R445_STATE,'r445BuildStateSHA256'),(R445_MAP,'r445SourceMapSHA256'),
                  (R445_RELEASE,'r445ReleaseReceiptSHA256'),(R445_INSTALL,'r445InstallReceiptSHA256'),
                  (R447_READBACK,'r447ReadbackSHA256'),(R447_SEAL,'r447SealSHA256'),(R447_RUN,'r447RunSHA256'),
                  (R368_SUPPORT,'r368SupportManifestSHA256'),
                  (PRODUCT_INPUTS,'productInputsSHA256')):
        if sha_file(p)!=compat.get(key): raise Hold(f'upstream compatibility pin changed: {p.name}')
    seal=read_json(R448_SEAL); prior_result=read_json(R448_RESULT); prior_run=read_json(R448_RUN); state=read_json(R445_STATE); smap=read_json(R445_MAP)
    release=read_json(R445_RELEASE); install=read_json(R445_INSTALL)
    readback=read_json(R447_READBACK); r447seal=read_json(R447_SEAL); r447=read_json(R447_RUN); support=read_json(R368_SUPPORT)
    if seal.get('status')!='ROOT_SEALED_ONE_CORRECTED_EXECUTION' or seal.get('identity',{}).get('sha256')!=m['appRuntimeIdentity']['sha256']:
        raise Hold('R448 corrected source/policy/identity seal mismatch')
    if prior_result.get('status')!='SCOPED_XCTEST_AND_PROVENANCE_PASS_WRAPPER_FAILURE_RETAINED' or prior_result.get('observed',{}).get('freeSummonDrawCount')!=0 or prior_result.get('observed',{}).get('paidSummonDrawCount')!=0:
        raise Hold('R448 prior outcome is not the preserved one-seed zero-summon result')
    if prior_run.get('caseIdentity',{}).get('seed')!=100049 or prior_run.get('caseIdentity',{}).get('runID')!='44800000-0001-4002-8000-000000000001':
        raise Hold('R448 prior run cross-join mismatch')
    if state.get('phase')!='PASS_RELEASE_ONLY' or state.get('sourceMapSHA256')!=compat.get('r445SourceMapSHA256') or state.get('sourceMap')!=smap:
        raise Hold('R445 Release state/map mismatch')
    if release.get('phase')!='BUILD_PASS' or release.get('bundleIdentifier')!='local.witch.autonomous.r1.completion.r445':
        raise Hold('R445 Release product receipt not successful')
    if install.get('status')!='PASS_NEW_BUNDLE_INSTALLED' or install.get('bundleID')!='local.witch.autonomous.r1.completion.r445':
        raise Hold('R445 install receipt not successful')
    if not seal.get('compatibilityEvidence',{}).get('r446InstalledAppExact'):
        raise Hold('R448 seal does not prove actual R446 installed app matches R445 Release')
    if readback.get('sourceSHA256')!=compat.get('r447RunSHA256') or readback.get('copySHA256')!=compat.get('r447RunSHA256') or not readback.get('unsignedCompileOnly') or not readback.get('originalRetained'):
        raise Hold('R447 readback does not bind the actual compile-only receipt')
    if r447seal.get('status')!='ROOT_SEALED_READY_TO_BUILD' or r447.get('status')!='PASS_IOS_SDK_UNSIGNED_COMPILE_ONLY' or r447.get('sourceMapSHA256')!=compat.get('r445R447SameFrozenSourceMapSHA256'):
        raise Hold('R447 receipt is not same-frozen-map compile-only evidence')
    frozen=Path(state.get('frozen',''))
    if not frozen.is_absolute() or not frozen.is_dir() or frozen.is_symlink(): raise Hold('R445 frozen source root unavailable')
    identity=m.get('appRuntimeIdentity',{}); ip=ROOT/identity.get('path','')
    no_link(ip)
    if not ip.is_file() or ip.stat().st_size!=identity.get('sizeBytes') or sha_file(ip)!=identity.get('sha256'):
        raise Hold('R446 actual runtime identity pin mismatch')
    rows=m.get('stagedFiles',[]); snap=m.get('stagedRowsSnapshot',{})
    sp=ROOT/snap.get('path',''); no_link(sp)
    if snap.get('path')!='docs/production/current/qa_drafts/zero_summon_seed_robustness_r452/candidate_r001/staged_rows_r001.json' or not sp.is_file() or sp.stat().st_size!=snap.get('sizeBytes') or sha_file(sp)!=snap.get('sha256') or json.loads(sp.read_text())!=rows:
        raise Hold('staged-row snapshot mismatch')
    if not rows or rows!=sorted(rows,key=lambda x:x['destinationPath']) or len({x['destinationPath'] for x in rows})!=len(rows):
        raise Hold('staged rows not canonical and unique')
    by_dest={x['destinationPath']:x for x in rows}
    expected_core=[]
    for key in sorted(smap):
        if not key.startswith('WitchGameCore/Sources/WitchGameCore/'): continue
        role='resource' if '/Resources/' in key else ('core' if key.endswith('.swift') else None)
        if role:
            src=(frozen/key).relative_to(ROOT).as_posix()
            expected_core.append(file_row(src,key[len('WitchGameCore/'):],role))
    core_rows=[x for x in rows if x['role'] in ('core','resource')]
    if core_rows!=sorted(expected_core,key=lambda x:x['destinationPath']) or sum(x['role']=='core' for x in rows)!=56 or sum(x['role']=='resource' for x in rows)!=2:
        raise Hold('current frozen Core/resource stage is not exact R445 map')
    support_rows=[x for x in rows if x['role'] in ('candidate_helper','test_support')]
    old_support=[x for x in support.get('stagedFiles',[]) if x['role'] in ('candidate_helper','test_support')]
    expected_support=[file_row(x['sourcePath'],x['destinationPath'],x['role']) for x in old_support]
    if support_rows!=sorted(expected_support,key=lambda x:x['destinationPath']): raise Hold('R368 helper/support pins differ')
    trows=[x for x in rows if x['role']=='pilot_test']
    if len(trows)!=1 or trows[0]!=m.get('pilotTestOverride'): raise Hold('test override row mismatch')
    if trows[0]!=file_row(m['candidateTestPath'],'Tests/WitchGameCoreTests/EconomyCohortProgressionR355Tests.swift','pilot_test'):
        raise Hold('R452 exact test file pin mismatch')
    if len(rows)!=56+2+len(support_rows)+1: raise Hold('unexpected stage row count')
    test_text=(ROOT/m['candidateTestPath']).read_text(encoding='utf-8')
    if not re.search(r'func\s+'+re.escape(TEST_METHOD)+r'\s*\(',test_text) or '.mockSummon(' in test_text:
        raise Hold('exact test missing or contains an executable summon call')
    if 'private let seeds: [UInt64] = [100_069, 200_071]' not in test_text or '45210000-' not in test_text:
        raise Hold('candidate is not restricted to requested seeds and unique R452 operation namespace')
    match=re.search(r'let sourcePaths\s*=\s*\[(.*?)\]',test_text,re.S)
    if not match: raise Hold('Core/test input digest contract sourcePaths missing')
    for spath in re.findall(r'"([^"]+)"',match.group(1)):
        if spath.startswith(('Sources/WitchGameCore/','Tests/WitchGameCoreTests/')) and spath not in by_dest:
            raise Hold(f'test source-digest path not staged: {spath}')
    product=m['productInputs']; pp=ROOT/product['path']; no_link(pp)
    if sha_file(pp)!=product['sha256'] or pp.stat().st_size!=product['sizeBytes'] or support.get('productInputs',{}).get('sha256')!=product['sha256']:
        raise Hold('exact R195 treatment input mismatch')
    if m.get('packageTemplateSHA256')!=sha_bytes(m.get('packageTemplate','').encode()): raise Hold('Package.swift template hash mismatch')
    helper=load_helper()
    return m,helper,state,smap,support

def verify_stage(package: Path,m:dict):
    allowed={'Package.swift'}|{x['destinationPath'] for x in m['stagedFiles']}; seen=set()
    for p in package.rglob('*'):
        if p.is_symlink(): raise Hold(f'staged package symlink: {p}')
        if p.is_file():
            rel=p.relative_to(package).as_posix()
            if rel not in allowed: raise Hold(f'unexpected staged package file: {rel}')
            seen.add(rel)
    expected={'Package.swift'}|{x['destinationPath'] for x in m['stagedFiles']}
    if seen!=expected: raise Hold(f'stage mismatch missing={sorted(expected-seen)} extra={sorted(seen-expected)}')
    for x in m['stagedFiles']:
        p=package/x['destinationPath']
        if p.stat().st_size!=x['sizeBytes'] or stat.S_IMODE(p.stat().st_mode)!=x['mode'] or sha_file(p)!=x['sha256']:
            raise Hold(f'post-stage SHA/size/mode mismatch: {x["destinationPath"]}')

def validate_report(report_path:Path, case:dict, identity_sha:str):
    errors=[]
    if not report_path.is_file() or report_path.is_symlink():
        return None,['report missing/unsafe']
    try: r=json.loads(report_path.read_text())
    except (OSError,ValueError) as e: return None,[f'report JSON invalid: {type(e).__name__}']
    exact={'caseID':case['caseID'],'runID':case['runID'],'cohortID':'free_no_ad','seed':case['seed'],'days':30}
    for k,v in exact.items():
        if r.get(k)!=v: errors.append(f'{k} mismatch')
    if r.get('appRuntimeIdentitySHA256')!=identity_sha: errors.append('App identity drift')
    if (r.get('campaignVictoryCount')!=30 or r.get('campaignDefeatCount')!=0 or
        r.get('unresolvedCampaignEnemyIDs')!=[] or r.get('challengeVictoryCount')!=15 or
        r.get('challengeDefeatCount')!=0 or r.get('unresolvedChallengeIDs')!=[]):
        errors.append('campaign/challenge outcomes mismatch')
    if (len(r.get('completedResearchIDs',[]))!=5 or len(r.get('unresolvedResearchIDs',[]))!=0 or
        len(r.get('daily',[]))!=30 or len(r['daily'][-1].get('unlockedRegions',[]))!=5):
        errors.append('research/region/day outcomes mismatch')
    if r.get('freeSummonDrawCount')!=0 or r.get('paidSummonDrawCount')!=0 or r.get('syntheticGrantReceipts')!=[]:
        errors.append('summon/grant count is nonzero')
    if ('RC_EQ_F_01' not in r.get('craftedRecipeIDs',[]) or not r.get('evolvedRecipeIDs') or
        r.get('enhancementActionCount',0)<1 or r.get('refinementActionCount',0)<1):
        errors.append('craft/evolve/enhance/refine evidence missing')
    if not r.get('naturalGearAcquisitionRecords') or not r.get('gearInstancesAddedOrEvolvedDuringRun'):
        errors.append('gear provenance observations missing')
    origin_path=report_path.parent/'GEAR_ORIGIN_JOIN_R002.json'
    if not origin_path.is_file() or origin_path.is_symlink():
        errors.append('gear-origin join missing/unsafe')
    else:
        try: origins=json.loads(origin_path.read_text())
        except (OSError,ValueError): origins={}
        groups=[set(origins.get(k,[])) for k in ('starterIDs','craftedIDs','naturalIDs')]
        if origins.get('unclassifiedIDs')!=[] or len(set.union(*groups))!=sum(len(g) for g in groups):
            errors.append('gear UUID origin groups overlap or contain unclassified IDs')
        if not set(origins.get('finalGearIDs',[])).issubset(set.union(*groups)):
            errors.append('final gear UUID lacks starter/craft/natural provenance')
        acq_ids={str(x.get('gearInstanceID','')).lower() for x in r.get('naturalGearAcquisitionRecords',[])}
        if not acq_ids or not acq_ids.issubset({x.lower() for x in origins.get('naturalIDs',[])}):
            errors.append('natural acquisition ledger does not join to UUID provenance')
    return r,errors

def run_process(cmd,env,logpath,proc_index,started,deadline,helper,scratch,out,expected_case,observed,rows_seen):
    proc=None
    logpath.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
    with logpath.open('xb') as lf:
        proc=subprocess.Popen(cmd,cwd=ROOT,env=env,stdout=lf,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,start_new_session=True,close_fds=True)
        pid=proc.pid
        ownership={'phaseIndex':proc_index,'pid':pid,'pgid':pid,'command':cmd,'state':'RUNNING'}
        rows_seen.append(ownership)
        phase_start=time.monotonic()
        test_started=None
        phase_cap=180 if proc_index==0 else 110
        try:
            while proc.poll() is None:
                now=time.monotonic()
                if now>deadline: raise Hold('aggregate 600-second wall cap exceeded')
                if now-phase_start>phase_cap: raise Hold(f'case {proc_index+1} process wall cap exceeded')
                if shutil.disk_usage(ROOT).free<MIN_FREE: raise Hold('12GB free-space floor breached')
                _,scratch_alloc=helper.usage(scratch); _,out_alloc=helper.usage(out)
                if scratch_alloc>MAX_BUILD_ALLOCATED: raise Hold('500MB allocated scratch cap exceeded')
                if max(0,out_alloc-scratch_alloc)>MAX_EVIDENCE_ALLOCATED: raise Hold('60MB allocated evidence cap exceeded')
                try: logtext=logpath.read_text(errors='replace')
                except OSError: logtext=''
                start_token=f"Test Case '-[WitchGameCoreTests.EconomyCohortProgressionR355Tests {TEST_METHOD}]' started."
                if test_started is None and start_token in logtext: test_started=now
                if test_started is not None and now-test_started>MAX_CASE: raise Hold(f'case {expected_case["caseID"]} exceeded 90-second XCTest case limit')
                ps=helper.process_rows(); children=helper.descendants(ps,pid)
                for child in children: observed[child['pid']]=child
                bundles=list(scratch.rglob('*.xctest'))
                for child in helper.owned_test_processes(ps,bundles): observed[child['pid']]=child
                time.sleep(.2)
            code=proc.wait(timeout=3)
        except BaseException as e:
            cleanup=helper.stop_owned(proc,list(scratch.rglob('*.xctest')),observed)
            close=helper.process_rows(); bundles=list(scratch.rglob('*.xctest'))
            descendants=helper.descendants(close,pid); owned_tests=helper.owned_test_processes(close,bundles)
            survivors={x['pid']:x for x in descendants+owned_tests}
            ownership.update({'state':'STOPPED_AFTER_ERROR','error':f'{type(e).__name__}: {e}',
                              'cleanup':cleanup,'returnCode':proc.poll(),
                              'parentAbsent':proc.poll() is not None,'ownedChildrenAbsent':not survivors,
                              'survivors':list(survivors.values())})
            raise
    cleanup=helper.stop_owned(proc,list(scratch.rglob('*.xctest')),observed)
    close=helper.process_rows(); bundles=list(scratch.rglob('*.xctest'))
    descendants=helper.descendants(close,pid); owned_tests=helper.owned_test_processes(close,bundles)
    survivors={x['pid']:x for x in descendants+owned_tests}
    parent_absent=proc.poll() is not None
    ownership.update({'state':'CLOSED','returnCode':code,'parentAbsent':parent_absent,
                      'ownedChildrenAbsent':not survivors,'survivors':list(survivors.values()),
                      'cleanup':cleanup})
    if not parent_absent or survivors: raise Hold(f'owned test process survivors for {expected_case["caseID"]}')
    return code,logpath.read_text(errors='replace'),phase_start

def execute(args,m,helper,state,smap,support):
    if args.limit_seconds!=MAX_WALL: raise Hold('only fixed 600-second batch is allowed')
    if shutil.disk_usage(ROOT).free<MIN_FREE: raise Hold('12GB free-space floor not met')
    helper.ensure_no_competing_swift()
    swiftraw=shutil.which('swift')
    if not swiftraw: raise Hold('Swift unavailable')
    swift=Path(swiftraw).resolve(strict=True)
    version=subprocess.run([str(swift),'--version'],capture_output=True,text=True,timeout=8,check=True).stdout.strip()
    if not version: raise Hold('Swift version empty')
    no_link(RUNS,missing_leaf=True); no_link(LOCK,missing_leaf=True)
    batch='R452_BATCH_001'
    out=RUNS/batch; no_link(out,missing_leaf=True)
    if out.exists(): raise Hold('exclusive R452 output exists; no retry')
    fd=os.open(LOCK,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f:
        json.dump({'status':'STARTED','batchID':batch,'manifestSHA256':args.manifest_sha256,'runnerSHA256':args.runner_sha256,'swift':str(swift),'version':version},f,sort_keys=True); f.write('\n'); f.flush(); os.fsync(f.fileno())
    out.mkdir(mode=0o700,parents=True,exist_ok=False)
    started=time.monotonic(); deadline=started+MAX_WALL
    package=out/'package'; scratch=out/'scratch'; evidence=out/'cases'
    rec={'schema':RUNNER_SCHEMA,'status':'PREPARING_RETAINED','batchID':batch,'manifestSHA256':args.manifest_sha256,
         'runnerSHA256':args.runner_sha256,'seeds':SEEDS,'runIDs':RUN_IDS,'expectedTests':[TEST_FILTER,TEST_FILTER],
         'compileInvocations':1,'simulator':'NONE','liveSave':'NONE','maxWallSeconds':MAX_WALL,'maxCaseSeconds':MAX_CASE,
         'maxBuildAllocatedBytes':MAX_BUILD_ALLOCATED,'maxEvidenceAllocatedBytes':MAX_EVIDENCE_ALLOCATED,
         'minimumFreeBytes':MIN_FREE,'swift':str(swift),'swiftVersion':version,'caseExecutions':[],'ownedProcesses':[],'errors':[]}
    runpath=out/'RUN.json'; write_json(runpath,rec,exclusive=True)
    package.mkdir(mode=0o700); evidence.mkdir(mode=0o700)
    for d in (package/'Sources/WitchGameCore',package/'Tests/WitchGameCoreTests'): d.mkdir(mode=0o700,parents=True,exist_ok=True)
    scratch.mkdir(mode=0o700)
    for name in ('cache','config','security','tmp','build'): (scratch/name).mkdir(mode=0o700)
    procs=[]; status='INCOMPLETE_RETAINED'; infrastructure_error=False
    try:
        for row in m['stagedFiles']:
            src=ROOT/row['sourcePath']; dst=package/row['destinationPath']; no_link(src); no_link(dst,missing_leaf=True)
            dst.parent.mkdir(mode=0o700,parents=True,exist_ok=True); shutil.copyfile(src,dst); os.chmod(dst,row['mode'])
        (package/'Package.swift').write_text(m['packageTemplate'],encoding='utf-8'); os.chmod(package/'Package.swift',0o600)
        verify_stage(package,m)
        for index,case in enumerate(m['cases']):
            if time.monotonic()>deadline: raise Hold('aggregate wall cap reached before next case')
            case_root=evidence/case['runID']; case_root.mkdir(mode=0o700,exist_ok=False)
            report_dir=case_root/f'r452_{case["runID"]}'
            report_path=report_dir/'report.json'
            env=os.environ.copy()
            env.update({'TMPDIR':str(scratch/'tmp'),'WITCH_SOURCE_ROOT':str(package),
                'WITCH_R355_COHORT':case['cohort'],'WITCH_R355_HORIZON':str(case['horizonDays']),
                'WITCH_R355_SEED':str(case['seed']),'WITCH_R355_ATTEMPT':str(case['attempt']),
                'WITCH_R355_CASE_ID':case['caseID'],'WITCH_R355_RUN_ID':case['runID'],
                'WITCH_R355_PRODUCT_INPUTS':str(ROOT/m['productInputs']['path']),
                'WITCH_R355_PRODUCT_INPUTS_SHA256':m['productInputs']['sha256'],
                'WITCH_R355_APP_IDENTITY_PATH':str(ROOT/m['appRuntimeIdentity']['path']),
                'WITCH_R355_APP_IDENTITY_SHA256':m['appRuntimeIdentity']['sha256'],
                'WITCH_R355_OUTPUT':str(report_path)})
            command=[str(swift),'test']
            if index==1: command.append('--skip-build')
            command += ['--package-path',str(package),'--scratch-path',str(scratch/'build'),
                        '--cache-path',str(scratch/'cache'),'--config-path',str(scratch/'config'),
                        '--security-path',str(scratch/'security'),'--jobs','2','--filter',TEST_FILTER]
            log=case_root/'swift_test.log'
            case_start=time.monotonic()
            phase={'case':case,'command':command,'reportPath':str(report_path),'logPath':str(log),
                   'compileExpected':index==0,'status':'STARTING'}
            case_receipt=case_root/'EXECUTION_R452.json'; write_json(case_receipt,phase,exclusive=True)
            try:
                code,logtext,phase_start=run_process(command,env,log,index,started,deadline,helper,scratch,out,case,{},procs)
                events=re.findall(r"Test Case '-\[WitchGameCoreTests\.([^ ]+) ([^\]]+)\]' (passed|failed|skipped)(?: \(([0-9.]+) seconds\))?\.",logtext)
                selected=[e for e in events if e[0]=='EconomyCohortProgressionR355Tests' and e[1]==TEST_METHOD]
                exact_pass=len(events)==1 and len(selected)==1 and selected[0][2]=='passed'
                elapsed=float(selected[0][3]) if selected and selected[0][3] else None
                accepted=bool(exact_pass and elapsed is not None and elapsed<=MAX_CASE and code==0)
                report_summary=None
                report_errors=[]
                if report_path.is_file() and not report_path.is_symlink():
                    report,report_errors=validate_report(report_path,case,m['appRuntimeIdentity']['sha256'])
                    if report is not None:
                        report_summary={'sha256':sha_file(report_path),'sizeBytes':report_path.stat().st_size,
                                        'seed':report.get('seed'),'campaignWins':report.get('campaignVictoryCount'),
                                        'challengeWins':report.get('challengeVictoryCount'),'researchCompleted':len(report.get('completedResearchIDs',[])),
                                        'crafted':len(report.get('craftedRecipeIDs',[])),'evolved':len(report.get('evolvedRecipeIDs',[])),
                                        'enhanceActions':report.get('enhancementActionCount'),'refineActions':report.get('refinementActionCount'),
                                        'freeSummons':report.get('freeSummonDrawCount'),'paidSummons':report.get('paidSummonDrawCount'),
                                        'syntheticGrants':len(report.get('syntheticGrantReceipts',[])),
                                        'naturalAcquisitionRecords':len(report.get('naturalGearAcquisitionRecords',[]))}
                else:
                    report_errors.append('report missing/unsafe')
                accepted=bool(accepted and not report_errors)
                phase.update({'status':'PASS' if accepted else 'FAIL_RETAINED','returnCode':code,
                              'xctestEvents':[{'class':e[0],'method':e[1],'result':e[2],'elapsedSeconds':float(e[3]) if e[3] else None} for e in events],
                              'selectedTestElapsedSeconds':elapsed,'accepted':accepted,'report':report_summary,
                              'reportValidationErrors':report_errors,'processWallSeconds':round(time.monotonic()-case_start,3)})
                write_json(case_receipt,phase)
                rec['caseExecutions'].append(phase)
                write_json(runpath,rec)
                if index==0 and code!=0 and not events:
                    infrastructure_error=True
                    raise Hold('first invocation did not reach a test event; cannot reuse possibly-unbuilt package')
            except BaseException as e:
                phase.update({'status':'INCOMPLETE_RETAINED','error':f'{type(e).__name__}: {e}'})
                if case_receipt.exists(): write_json(case_receipt,phase)
                rec['caseExecutions'].append(phase); rec['errors'].append(phase['error']); write_json(runpath,rec)
                infrastructure_error=True
                raise
        if len(rec['caseExecutions'])==2 and all(x.get('accepted') for x in rec['caseExecutions']):
            status='TWO_CASES_PASSED_REVIEW_REQUIRED'
        else:
            status='TWO_CASES_RETAINED_WITH_FAILURE'
    except BaseException as e:
        rec['errors'].append(f'{type(e).__name__}: {e}')
        status='INCOMPLETE_RETAINED'
    finally:
        try:
            source_unchanged=all(sha_file(ROOT/x['sourcePath'])==x['sha256'] for x in m['stagedFiles'])
            protected={
             'r448SealUnchanged':sha_file(R448_SEAL)==m['compatibilityEvidence']['r448ExecutionSealSHA256'],
             'r448ResultUnchanged':sha_file(R448_RESULT)==m['compatibilityEvidence']['r448ScopedResultSHA256'],
             'r448RunUnchanged':sha_file(R448_RUN)==m['compatibilityEvidence']['r448RunSHA256'],
             'r445StateUnchanged':sha_file(R445_STATE)==m['compatibilityEvidence']['r445BuildStateSHA256'],
             'r445ReleaseUnchanged':sha_file(R445_RELEASE)==m['compatibilityEvidence']['r445ReleaseReceiptSHA256'],
             'r445InstallUnchanged':sha_file(R445_INSTALL)==m['compatibilityEvidence']['r445InstallReceiptSHA256'],
             'r447SealUnchanged':sha_file(R447_SEAL)==m['compatibilityEvidence']['r447SealSHA256'],
             'r445MapUnchanged':sha_file(R445_MAP)==m['compatibilityEvidence']['r445SourceMapSHA256'],
             'r447ReadbackUnchanged':sha_file(R447_READBACK)==m['compatibilityEvidence']['r447ReadbackSHA256'],
             'r447RunUnchanged':sha_file(R447_RUN)==m['compatibilityEvidence']['r447RunSHA256'],
             'r368SupportUnchanged':sha_file(R368_SUPPORT)==m['compatibilityEvidence']['r368SupportManifestSHA256'],
             'productInputsUnchanged':sha_file(PRODUCT_INPUTS)==m['compatibilityEvidence']['productInputsSHA256']}
            rec.update({'sourceInputsUnchanged':source_unchanged,'protectedInputsUnchanged':all(protected.values()),
                        'protectedInputChecks':protected,'appRuntimeIdentityUnchanged':sha_file(ROOT/m['appRuntimeIdentity']['path'])==m['appRuntimeIdentity']['sha256'],
                        'scratchAllocatedBytes':helper.usage(scratch)[1] if scratch.exists() else 0,
                        'outputAllocatedBytes':helper.usage(out)[1] if out.exists() else 0,
                        'freeBytesAfter':shutil.disk_usage(ROOT).free,'finishedElapsedSeconds':round(time.monotonic()-started,3)})
            rec['evidenceAllocatedBytes']=max(0,rec['outputAllocatedBytes']-rec['scratchAllocatedBytes'])
            rec['ownedProcessesAbsent']=all(x['parentAbsent'] and x['ownedChildrenAbsent'] for x in procs)
        except BaseException as e:
            rec['errors'].append(f'closeout: {type(e).__name__}: {e}')
            status='INCOMPLETE_RETAINED'
        if rec.get('finishedElapsedSeconds',MAX_WALL+1)>MAX_WALL or rec.get('scratchAllocatedBytes',MAX_BUILD_ALLOCATED+1)>MAX_BUILD_ALLOCATED or rec.get('evidenceAllocatedBytes',MAX_EVIDENCE_ALLOCATED+1)>MAX_EVIDENCE_ALLOCATED or rec.get('freeBytesAfter',0)<MIN_FREE or not rec.get('sourceInputsUnchanged') or not rec.get('protectedInputsUnchanged') or not rec.get('appRuntimeIdentityUnchanged') or not rec.get('ownedProcessesAbsent'):
            status='INCOMPLETE_RETAINED'
        rec['status']=status
        write_json(runpath,rec)
    return status,runpath

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--manifest-sha256',required=True); ap.add_argument('--runner-sha256',required=True)
    ap.add_argument('--execute',action='store_true'); ap.add_argument('--limit-seconds',type=int,default=MAX_WALL)
    a=ap.parse_args()
    if not re.fullmatch('[0-9a-f]{64}',a.manifest_sha256) or not re.fullmatch('[0-9a-f]{64}',a.runner_sha256):
        raise Hold('lowercase SHA-256 pins required')
    m,helper,state,smap,support=verify_inputs(a.manifest_sha256,a.runner_sha256)
    if not a.execute:
        print(json.dumps({'status':'PREFLIGHT_ONLY_NOT_RUN','seeds':SEEDS,'runIDs':RUN_IDS,'testFilter':TEST_FILTER,
                          'coreSwiftSources':56,'resources':2,'stagedRows':len(m['stagedFiles']),
                          'compileInvocations':1,'caseInvocations':2,'simulator':'NONE','liveSave':'NONE'},indent=2))
        return 0
    status,path=execute(a,m,helper,state,smap,support)
    print(json.dumps({'status':status,'receipt':str(path)},indent=2))
    return 0 if status=='TWO_CASES_PASSED_REVIEW_REQUIRED' else 2
if __name__=='__main__':
    try: raise SystemExit(main())
    except Hold as e: print('HOLD: '+str(e),file=sys.stderr); raise SystemExit(2)

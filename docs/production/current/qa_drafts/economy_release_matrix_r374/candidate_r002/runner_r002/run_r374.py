#!/usr/bin/env python3
"""R374 one-compile, 16-case candidate cohort batch. Default mode only verifies pins."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, os, shutil, signal, stat, subprocess, sys, time
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
HERE = ROOT / 'docs/production/current/qa_drafts/economy_release_matrix_r374/candidate_r002/runner_r002'
MANIFEST = HERE / 'INPUT_MANIFEST_R002.json'
RUNS = HERE / 'runs'
LOCK = HERE / 'EXECUTION_STARTED_R002.json'
R368_RUN = ROOT / 'docs/production/current/qa_drafts/normal_onboarding_progression_r368/candidate_r002/runner_r002/runs/36800000-0001-4001-8000-000000000001/RUN.json'
R356_HELPER = ROOT / 'docs/production/current/qa_drafts/migration_receipt_reconciliation_r356/runner_r002/run_core_r356.py'
R356_HELPER_SHA = 'f5771645bfc9ee46645a9951443b7cd3de0d1fe262a9dfb86dcb3cb88b03cc5b'
MAX_SECONDS = 6000
MAX_ALLOCATED = 2_000_000_000
MIN_FREE = 12_000_000_000
PER_CASE_30 = 180
PER_CASE_90 = 600

class Hold(RuntimeError): pass

def sha_bytes(data: bytes) -> str: return hashlib.sha256(data).hexdigest()
def sha_file(path: Path) -> str:
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''): h.update(block)
    return h.hexdigest()
def no_link(path: Path, allow_missing_leaf=False) -> None:
    path=Path(os.path.abspath(path)); cur=Path(path.anchor)
    parts=path.parts[1:]
    for i,name in enumerate(parts):
        cur=cur/name
        if allow_missing_leaf and i==len(parts)-1 and not cur.exists() and not cur.is_symlink(): continue
        if cur.is_symlink(): raise Hold(f'symlink rejected: {cur}')
def read_json(path: Path):
    no_link(path)
    if not path.is_file(): raise Hold(f'missing input {path}')
    return json.loads(path.read_text(encoding='utf-8'))
def row_now(item: dict) -> dict:
    p=ROOT/item['sourcePath']; no_link(p)
    if not p.is_file(): raise Hold(f'nonregular source {p}')
    st=p.stat()
    return {'sourcePath':item['sourcePath'],'destinationPath':item['destinationPath'],'role':item['role'],
            'sizeBytes':st.st_size,'mode':stat.S_IMODE(st.st_mode),'sha256':sha_file(p)}
def case_ids(m: dict): return [x['runID'] for x in m['cases']]
def verify_inputs(manifest_pin: str, runner_pin: str):
    if ROOT.resolve()!=ROOT or Path(__file__).resolve()!=HERE/'run_r374.py': raise Hold('fixed worktree/runner path mismatch')
    if sha_file(MANIFEST)!=manifest_pin or sha_file(Path(__file__))!=runner_pin: raise Hold('manifest or runner pin mismatch')
    m=read_json(MANIFEST)
    if m.get('schema')!='r374-release-onboarding-matrix-input-v1' or m.get('status')!='PREPARED_NOT_RUN' or m.get('fixedWorktree')!=str(ROOT): raise Hold('manifest status/schema/worktree mismatch')
    failed=m['previousIncompleteR369']; failed_path=ROOT/failed['runPath']; no_link(failed_path)
    if sha_file(failed_path)!=failed['sha256']: raise Hold('R369 incomplete predecessor pin changed')
    failed_input=ROOT/failed['inputManifestPath']; no_link(failed_input)
    if sha_file(failed_input)!=failed['inputManifestSHA256']: raise Hold('R369 input manifest pin changed')
    if sha_file(ROOT/failed['candidateManifestPath'])!=failed['candidateManifestSHA256']: raise Hold('R369 candidate seal pin changed')
    failed_run=read_json(failed_path)
    if failed_run.get('inputManifestSHA256')!=failed['inputManifestSHA256']: raise Hold('R369 run does not reference pinned input manifest')
    if failed_run.get('status')!='INCOMPLETE_RETAINED' or not any('case 16 wall cap exceeded' in str(x) for x in failed_run.get('errors',[])):
        raise Hold('R369 predecessor is not the retained wall-cap failure')
    failed_cases=failed_run.get('cases',[])
    if len(failed_cases)!=1 or failed_cases[0].get('runID')!='36900000-0010-4001-8000-000000000001' or failed_cases[0].get('status')!='RUNNING':
        raise Hold('R369 predecessor case identity/status changed')
    up=m['upstreamR368']; upm=ROOT/up['manifestPath']; upr=ROOT/up['runPath']
    if sha_file(upm)!=up['manifestSHA256'] or sha_file(upr)!=up['runSHA256']: raise Hold('R368 upstream pin mismatch')
    prior=read_json(upr); priorv=prior.get('testVerdict') or {}
    if prior.get('sourceInputsUnchanged') is not True or prior.get('upstreamManifestsUnchanged') is not True or prior.get('ownedProcessesAbsent') is not True:
        raise Hold('R368 prerequisite did not close source/upstream/process preservation')
    log_path=ROOT/up.get('logPath','')
    if not up.get('logPath'): raise Hold('R368 XCTest log path missing')
    no_link(log_path)
    if sha_file(log_path)!=up.get('logSHA256'): raise Hold('R368 XCTest log pin mismatch')
    prior_report_row=up.get('reportPath'); prior_report_path=ROOT/prior_report_row if prior_report_row else ROOT
    no_link(prior_report_path)
    if not prior_report_row or sha_file(prior_report_path)!=up.get('reportSHA256') or prior_report_path.stat().st_size!=up.get('reportSizeBytes'):
        raise Hold('R368 evidence report hash/size mismatch')
    prior_report=read_json(prior_report_path)
    if any(prior_report.get(k)!=v for k,v in up.get('expectedReport',{}).items()): raise Hold('R368 pilot report identity mismatch')
    if sha_file(R356_HELPER)!=R356_HELPER_SHA: raise Hold('pinned owned-process helper changed')
    if m.get('processHelper')!={'path':'docs/production/current/qa_drafts/migration_receipt_reconciliation_r356/runner_r002/run_core_r356.py','sha256':R356_HELPER_SHA}: raise Hold('R356 process helper input row mismatch')
    if prior.get('status')!=up['requiredStatus'] or prior.get('returnCode')!=0 or prior.get('testFilter')!=up['requiredTestFilter'] or not priorv.get('accepted') or priorv.get('failed') or priorv.get('skipped') or len(priorv.get('passed',[]))!=1:
        raise Hold('R368 pilot is not the exact one-test PASS prerequisite')
    if m.get('limits')!={'compileInvocations':1,'caseInvocations':16,'maxAttempts':1,'aggregateWallSeconds':6000,'maxAllocatedBytes':2000000000,'minimumFreeBytes':12000000000,'perCaseWallSeconds':{'30':180,'90':600},'configuration':'release','seed':100049,'horizonsDays':[30,90]}:
        raise Hold('fixed batch scope/cap changed')
    if len(m['cases'])!=16 or len(set(case_ids(m)))!=16: raise Hold('expected 16 unique preregistered cases')
    if m.get('previousIncompleteR369',{}).get('sha256') != '2ff8dff96c734e621808518d6994c5386f2ec5e5fd0d0244135a2f7a91f7fb62': raise Hold('R369 predecessor SHA pin placeholder')
    cohort_order=['rewarded_ad_simulated','free_no_ad','starter_ticket_candidate','ad_skip_simulated','cosmetics_only_candidate','ticket10_candidate','value30_ticket_candidate','ticket200_candidate']
    expected=[('ticket200_candidate',90)]+[(cohort,h) for cohort in cohort_order for h in (30,90) if not (cohort=='ticket200_candidate' and h==90)]
    got=[(x['cohort'],x['horizonDays']) for x in m['cases']]
    if got!=expected or any(x['seed']!=100049 or x['attempt']!=1 or x.get('executionOrder')!=i for i,x in enumerate(m['cases'],1)):
        raise Hold('case matrix/seed/attempt/execution-order mismatch')
    for c in m['cases']:
        canonical_index=cohort_order.index(c['cohort'])*2 + ([30,90].index(c['horizonDays'])) + 1
        if c['index']!=canonical_index or c['runID']!=f"37400000-{canonical_index:04x}-4001-8000-{1:012x}" or c['caseID']!=f"R374-{c['cohort']}-{c['horizonDays']}-seed100049": raise Hold('case identity does not match canonical preregistration')
    if len({x['destinationPath'] for x in m['stagedFiles']})!=len(m['stagedFiles']): raise Hold('duplicate staged package destinations')
    if len([x for x in m['stagedFiles'] if x['role'] in ('core','override')])!=54 or len([x for x in m['stagedFiles'] if x['role']=='resource'])!=2: raise Hold('Core/resource staged count differs from R356 source map')
    if not any(x['destinationPath']=='Tests/WitchGameCoreTests/EconomyCohortProgressionR374Tests.swift' and x['role']=='pilot_test' for x in m['stagedFiles']): raise Hold('R374 XCTest file not staged as selected test')
    if not any(x['destinationPath']=='Tests/WitchGameCoreTests/EconomyCohortTreatmentR374.swift' for x in m['stagedFiles']): raise Hold('R374 scenario adapter missing')
    if m['testFilter']!='EconomyCohortProgressionR374Tests/testR374CurrentCoreEconomyCohortWithR230AndChallengeOutcomes': raise Hold('test filter mismatch')
    test_manifest_row=next(x for x in m['stagedFiles'] if x['role']=='pilot_test')
    test_text=(ROOT/test_manifest_row['sourcePath']).read_text(encoding='utf-8')
    if 'func '+m['testMethod']+'() async throws' not in test_text: raise Hold('selected XCTest method is absent from pinned file')
    input_row=m['productInputs']; identity=m['appRuntimeIdentity']
    for key in ('productInputs','appRuntimeIdentity'):
        x=m[key]; p=ROOT/x['path']; no_link(p)
        if not p.is_file() or p.stat().st_size!=x['sizeBytes'] or sha_file(p)!=x['sha256']: raise Hold(f'{key} pin mismatch')
    if input_row!=json.loads((ROOT/upm).read_text())['productInputs'] or identity!=json.loads((ROOT/upm).read_text())['appRuntimeIdentity']:
        raise Hold('R374 external inputs are not exact R368 inputs')
    products=json.loads((ROOT/input_row['path']).read_text())['products']; pm={x['id']:x for x in products}
    checks={'STARTER':{'tickets':10,'purchase_limit':'once'},'AD_SKIP':{'tickets':0,'purchase_limit':'once'},
      'VALUE30':{'tickets':20,'purchase_limit':'cooldown','cadence_days':30},
      'TICKET10':{'tickets':10,'purchase_limit':'unlimited'},'TICKET200':{'tickets':200,'purchase_limit':'unlimited'},
      'OUT_C_WITCH_MOON_01':{'tickets':0,'stat_modifier_bp':0,'purchase_limit':'once'}}
    for pid,fields in checks.items():
        item=pm.get(pid)
        if item is None or item.get('price_status')!='HYPOTHETICAL_NOT_APP_STORE_REGISTERED' or any(item.get(k)!=v for k,v in fields.items()): raise Hold(f'unapproved product input fact mismatch {pid}')
    prior_manifest=read_json(upm)
    expected_rows=[x for x in prior_manifest['stagedFiles'] if x['role']!='pilot_test']
    expected_rows += [x for x in m['stagedFiles'] if x['destinationPath'] in ('Tests/WitchGameCoreTests/EconomyCohortProgressionR374Tests.swift','Tests/WitchGameCoreTests/EconomyCohortTreatmentR374.swift')]
    expected_rows.sort(key=lambda x:x['destinationPath'])
    if expected_rows!=m['stagedFiles']: raise Hold('R374 staging does not exactly inherit R368 package inputs plus its two candidate test files')
    if len(m['stagedFiles'])!=69: raise Hold(f'unexpected staged-file count {len(m["stagedFiles"])}')
    testrow=next(x for x in m['stagedFiles'] if x['role']=='pilot_test')
    testtext=(ROOT/testrow['sourcePath']).read_text(encoding='utf-8')
    import re
    match=re.search(r'let sourcePaths\s*=\s*\[(.*?)\]',testtext,re.S)
    if not match: raise Hold('selected XCTest sourcePaths pin list is absent')
    staged={x['destinationPath'] for x in m['stagedFiles']}
    for source in re.findall(r'"([^"]+)"',match.group(1)):
        if source.startswith(('Sources/WitchGameCore/','Tests/WitchGameCoreTests/')) and source not in staged:
            raise Hold(f'selected test source path is not in the exact staged package: {source}')
    for item in m['stagedFiles']:
        if row_now(item)!=item: raise Hold(f'staged source changed: {item["sourcePath"]}')
    template=m['packageTemplate'].encode()
    if sha_bytes(template)!=m['packageTemplateSHA256']: raise Hold('Swift package template hash mismatch')
    return m

def allocated_bytes(root: Path) -> int:
    if not root.exists(): return 0
    total=0; seen=set(); stack=[root]
    while stack:
        d=stack.pop()
        try: entries=list(os.scandir(d))
        except FileNotFoundError: continue
        for e in entries:
            p=Path(e.path)
            try: st=e.stat(follow_symlinks=False)
            except FileNotFoundError:
                try: p.relative_to(root/'scratch')
                except ValueError: raise Hold(f'output path disappeared outside owned scratch: {p}')
                continue  # Swift may atomically remove a transient compiler lock in owned scratch.
            if stat.S_ISLNK(st.st_mode):
                if not str(p).startswith(str(root/'scratch')+'/'): raise Hold(f'output symlink outside scratch rejected: {p}')
                try: resolved=p.resolve(strict=True); resolved.relative_to(root/'scratch')
                except (FileNotFoundError,ValueError): raise Hold(f'unsafe/disappearing scratch symlink: {p}')
                continue
            if stat.S_ISDIR(st.st_mode): stack.append(p)
            elif stat.S_ISREG(st.st_mode):
                key=(st.st_dev,st.st_ino)
                if key not in seen: seen.add(key); total += st.st_blocks*512
    return total

def stop_group(proc):
    if proc.poll() is None:
        try: os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError: pass
        try: proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try: os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            proc.wait(timeout=3)
    try: os.killpg(proc.pid, 0)
    except ProcessLookupError: return True
    return False

def exact_executable(package: Path, scratch: Path) -> Path:
    tests=list((scratch/'build').rglob('*.xctest'))
    binaries=[]
    for bundle in tests:
        p=bundle/'Contents/MacOS'/bundle.stem
        if p.is_file() and os.access(p,os.X_OK): binaries.append(p)
    if len(binaries)!=1: raise Hold(f'expected one test executable, found {len(binaries)}')
    return binaries[0]

def execute(args,m):
    if args.run_id!='R374_MATRIX_001': raise Hold('only fixed R374 matrix execution ID is permitted')
    if shutil.disk_usage(ROOT).free < MIN_FREE: raise Hold('12GB free-space floor not met')
    swift_raw=shutil.which('swift')
    if not swift_raw: raise Hold('swift unavailable')
    swift=Path(swift_raw).resolve(strict=True)
    version=subprocess.run([str(swift),'--version'],capture_output=True,text=True,timeout=8,check=True).stdout.strip()
    if not version: raise Hold('empty Swift toolchain version')
    no_link(RUNS,allow_missing_leaf=True); no_link(LOCK,allow_missing_leaf=True)
    if LOCK.exists(): raise Hold('single-use R374 lock already exists')
    out=RUNS/'R374_MATRIX_001'; no_link(out,allow_missing_leaf=True)
    if out.exists(): raise Hold('exclusive R374 output already exists')
    # Verify competing compiler state before taking the irreversible one-shot lock.
    spec=importlib.util.spec_from_file_location('r356_owned_process_helper', R356_HELPER)
    helper=importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
    helper.ensure_no_competing_swift()
    fd=os.open(LOCK,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f: json.dump({'status':'STARTED','runID':args.run_id,'manifestSHA256':args.manifest_sha256,'runnerSHA256':args.runner_sha256,'swift':str(swift),'swiftVersion':version},f); f.write('\n'); f.flush(); os.fsync(f.fileno())
    out.mkdir(mode=0o700,parents=True,exist_ok=False)
    runpath=out/'RUN.json'
    status='PREPARING_RETAINED'; error=None; cases=[]; binary=None; binary_sha=None; proc=None
    runpath.write_text(json.dumps({'schema':'r374-batch-run-v1','status':status,'runID':args.run_id,
        'inputManifestSHA256':args.manifest_sha256,'runnerSHA256':args.runner_sha256,'swift':str(swift),
        'swiftVersion':version,'configuration':'release','compileInvocations':1,'caseCountPlanned':16,'aggregateWallSecondsCap':MAX_SECONDS,
        'allocatedBytesCap':MAX_ALLOCATED,'minimumFreeBytes':MIN_FREE,'testFilter':m['testFilter'],'cases':cases,'errors':[]},sort_keys=True,indent=2)+'\n')
    try:
        package=out/'package'; scratch=out/'scratch'; (package/'Sources/WitchGameCore').mkdir(mode=0o700,parents=True); (package/'Tests/WitchGameCoreTests').mkdir(mode=0o700,parents=True)
        for name in ('build','cache','config','security','tmp'): (scratch/name).mkdir(mode=0o700,parents=True)
        for item in m['stagedFiles']:
            src=ROOT/item['sourcePath']; dest=package/item['destinationPath']; dest.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
            shutil.copyfile(src,dest); os.chmod(dest,item['mode'])
            if dest.stat().st_size!=item['sizeBytes'] or sha_file(dest)!=item['sha256']: raise Hold(f'stage mismatch {item["destinationPath"]}')
        (package/'Package.swift').write_bytes(m['packageTemplate'].encode())
        if sha_file(package/'Package.swift')!=m['packageTemplateSHA256']: raise Hold('staged Package.swift mismatch')
        expected={'Package.swift'}|{x['destinationPath'] for x in m['stagedFiles']}; actual=set()
        for p in package.rglob('*'):
            if p.is_symlink(): raise Hold(f'package symlink {p}')
            if p.is_file(): actual.add(p.relative_to(package).as_posix())
        if actual!=expected: raise Hold('staged package file-set mismatch')
        initial_sources={x['sourcePath']:sha_file(ROOT/x['sourcePath']) for x in m['stagedFiles']}
    except BaseException as exc:
        status='STAGE_FAILED_RETAINED'; error=f'{type(exc).__name__}: {exc}'
        runpath.write_text(json.dumps({'schema':'r374-batch-run-v1','status':status,'runID':args.run_id,
            'inputManifestSHA256':args.manifest_sha256,'runnerSHA256':args.runner_sha256,'swift':str(swift),
            'swiftVersion':version,'compileInvocations':0,'caseCountPlanned':16,'cases':cases,'errors':[error]},sort_keys=True,indent=2)+'\n')
        raise
    start=time.monotonic(); status='INCOMPLETE_RETAINED'; owned_observed={}; owned_cleanup=[]; owned_survivors=[]; test_bundles=[]; final_group_absent=None; binary_pin_captured_before_verdict=False; binary_pin_capture_timing=None
    def write_run():
        data={'schema':'r374-batch-run-v1','status':status,'runID':args.run_id,'inputManifestSHA256':args.manifest_sha256,'runnerSHA256':args.runner_sha256,'swift':str(swift),'swiftVersion':version,'configuration':'release','compileInvocations':1,'caseCountPlanned':16,'aggregateWallSecondsCap':MAX_SECONDS,'allocatedBytesCap':MAX_ALLOCATED,'minimumFreeBytes':MIN_FREE,'testFilter':m['testFilter'],'binaryPath':str(binary) if binary else None,'binarySHA256':binary_sha,'binaryPinCapturedBeforeVerdict':binary_pin_captured_before_verdict,'binaryPinCaptureTiming':binary_pin_capture_timing,'cases':cases,'ownedProcessRowsObserved':list(owned_observed.values()),'ownedCleanup':owned_cleanup,'ownedXCTestSurvivors':owned_survivors,'finalProcessGroupAbsent':final_group_absent,'errors':[error] if error else []}
        runpath.write_text(json.dumps(data,sort_keys=True,indent=2)+'\n')
    write_run()
    try:
        for index,c in enumerate(m['cases']):
            elapsed=time.monotonic()-start
            if elapsed>=MAX_SECONDS: raise Hold('aggregate 6000s cap reached before next case')
            if allocated_bytes(out)>MAX_ALLOCATED: raise Hold('2GB allocated output cap reached')
            if shutil.disk_usage(ROOT).free<MIN_FREE: raise Hold('12GB free-space floor breached')
            for item in m['stagedFiles']:
                if sha_file(ROOT/item['sourcePath'])!=initial_sources[item['sourcePath']]: raise Hold('source changed during batch')
            case_dir=out/'cases'/c['runID']; case_dir.mkdir(mode=0o700,parents=True,exist_ok=False)
            report=case_dir/f'r374_{c["runID"]}'/'report.json'
            env=os.environ.copy(); env.update({'TMPDIR':str(scratch/'tmp'),'WITCH_SOURCE_ROOT':str(package),
                'WITCH_R374_COHORT':c['cohort'],'WITCH_R374_HORIZON':str(c['horizonDays']),'WITCH_R374_SEED':str(c['seed']),
                'WITCH_R374_ATTEMPT':'1','WITCH_R374_CASE_ID':c['caseID'],'WITCH_R374_RUN_ID':c['runID'],
                'WITCH_R374_PRODUCT_INPUTS':str(ROOT/m['productInputs']['path']),'WITCH_R374_PRODUCT_INPUTS_SHA256':m['productInputs']['sha256'],
                'WITCH_R374_APP_IDENTITY_PATH':str(ROOT/m['appRuntimeIdentity']['path']),'WITCH_R374_APP_IDENTITY_SHA256':m['appRuntimeIdentity']['sha256'],
                'WITCH_R374_OUTPUT':str(report)})
            command=[str(swift),'test','-c','release','--package-path',str(package),'--scratch-path',str(scratch/'build'),'--cache-path',str(scratch/'cache'),'--config-path',str(scratch/'config'),'--security-path',str(scratch/'security'),'--jobs','2','--filter',m['testFilter']]
            if '-c' not in command or command[command.index('-c')+1] != 'release': raise Hold('SwiftPM command is not Release configuration')
            if index>0:
                if binary is None or not binary.exists() or sha_file(binary)!=binary_sha: raise Hold('test executable changed before --skip-build reuse')
                command.insert(2,'--skip-build')
            rec={'index':c['index'],'executionOrder':c['executionOrder'],'caseID':c['caseID'],'runID':c['runID'],'cohort':c['cohort'],'horizonDays':c['horizonDays'],'seed':c['seed'],'command':command,'status':'RUNNING','configuration':'release','caseCapSeconds':PER_CASE_90 if c['horizonDays']==90 else PER_CASE_30,'startedElapsedSeconds':elapsed}
            cases.append(rec); write_run()
            log=case_dir/'swift_test.log'; proc=None
            with log.open('xb') as lf:
                proc=subprocess.Popen(command,cwd=ROOT,env=env,stdout=lf,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,start_new_session=True,close_fds=True)
                rec.update({'runnerPID':proc.pid,'runnerPGID':proc.pid}); write_run()
                case_deadline=min(start+MAX_SECONDS,time.monotonic()+(PER_CASE_90 if c['horizonDays']==90 else PER_CASE_30))
                while proc.poll() is None:
                    test_bundles=[x for x in (scratch/'build').rglob('*.xctest') if x.is_dir()]
                    if binary is None and b'Build complete!' in log.read_bytes():
                        binary=exact_executable(package,scratch); binary_sha=sha_file(binary)
                        binary_pin_captured_before_verdict=True; binary_pin_capture_timing='DURING_RUNNING_PROCESS_AFTER_BUILD_COMPLETE_LOG'; write_run()
                    rows=helper.process_rows()
                    owned=set(r['pid'] for r in helper.descendants(rows,proc.pid))
                    owned.update(r['pid'] for r in helper.owned_test_processes(rows,test_bundles))
                    for process_row in rows:
                        if process_row['pid'] in owned: owned_observed[process_row['pid']]=process_row
                    if time.monotonic()>case_deadline: raise Hold(f'case {c["index"]} wall cap exceeded')
                    if allocated_bytes(out)>MAX_ALLOCATED: raise Hold('2GB allocated output cap reached during XCTest')
                    if shutil.disk_usage(ROOT).free<MIN_FREE: raise Hold('12GB free-space floor breached during XCTest')
                    time.sleep(2)
                test_bundles=[x for x in (scratch/'build').rglob('*.xctest') if x.is_dir()]
                owned_cleanup.extend(helper.stop_owned(proc,test_bundles,owned_observed))
                group_absent=stop_group(proc)
                survivors=helper.owned_test_processes(helper.process_rows(),test_bundles)
                owned_survivors=survivors
                rec['ownedXCTestSurvivorsAfterCleanup']=survivors; rec['processGroupAbsentAfterCleanup']=group_absent
                if survivors: raise Hold(f'owned XCTest process remains after case {c["index"]}: {survivors}')
                if not group_absent: raise Hold(f'owned process group remains after case {c["index"]}')
            rec['returnCode']=proc.returncode; rec['finishedElapsedSeconds']=time.monotonic()-start
            if binary is None:
                try:
                    binary=exact_executable(package,scratch); binary_sha=sha_file(binary)
                    binary_pin_captured_before_verdict=True; binary_pin_capture_timing='AFTER_PROCESS_EXIT_BEFORE_VERDICT_READ'
                    write_run()
                except Hold as capture_error:
                    if proc.returncode==0: raise
                    rec['binaryPinCaptureUnavailable']=str(capture_error); write_run()
            elif sha_file(binary)!=binary_sha: raise Hold('XCTest executable changed during skip-build batch')
            if proc.returncode!=0: rec['status']='FAILED_RETAINED'; write_run(); raise Hold(f'case {c["index"]} SwiftPM exit {proc.returncode}')
            logtext=log.read_text(errors='replace')
            if 'Executed 1 test, with 0 failures' not in logtext or 'Executed 0 tests' in logtext or ' skipped' in logtext:
                rec['status']='INCOMPLETE_TEST_VERDICT'; write_run(); raise Hold(f'case {c["index"]} lacks exactly one passing XCTest verdict')
            if not report.is_file(): raise Hold(f'case {c["index"]} missing report')
            result=json.loads(report.read_text())
            if result.get('caseID')!=c['caseID'] or result.get('runID')!=c['runID'] or result.get('cohortID')!=c['cohort'] or result.get('days')!=c['horizonDays'] or result.get('seed')!=c['seed'] or result.get('status')!='RUNNER_FINISHED_XCTEST_RESULT_SEPARATE':
                raise Hold(f'case {c["index"]} report identity/status mismatch')
            daily_rows=result.get('daily',[])
            if len(daily_rows)!=c['horizonDays']: raise Hold('daily checkpoint manifest count mismatch')
            for dayrow in daily_rows:
                sidecar=report.parent/dayrow.get('gearRowsFile','')
                if sidecar.parent!=report.parent or not sidecar.is_file(): raise Hold('missing/unsafe daily gear sidecar')
                if sidecar.stat().st_size<=0 or sha_file(sidecar)!=dayrow.get('gearRowsSHA256'): raise Hold('daily gear sidecar hash mismatch')
                gear_data=json.loads(sidecar.read_text())
                if gear_data.get('schema')!='r374-daily-gear-v1' or gear_data.get('day')!=dayrow.get('day') or gear_data.get('saveSHA256')!=dayrow.get('saveSHA256') or gear_data.get('reopenedSnapshotSHA256')!=dayrow.get('reopenedSnapshotSHA256') or len(gear_data.get('rows',[]))!=dayrow.get('gearRowCount'): raise Hold('daily gear sidecar content mismatch')
            if c['cohort']=='cosmetics_only_candidate':
                receipts=result.get('syntheticCosmeticScenarioReceipts',[])
                if len(receipts)!=1 or receipts[0].get('productID')!='OUT_C_WITCH_MOON_01' or receipts[0].get('gameSnapshotEntitlementApplied') is not False: raise Hold('cosmetic scenario receipt did not remain metadata-only')
            elif result.get('syntheticCosmeticScenarioReceipts'):
                raise Hold('cosmetic metadata leaked into a non-cosmetic cohort')
            rec['reportSHA256']=sha_file(report); rec['reportPath']=str(report); rec['status']='PASS'; write_run()
        status='COMPLETE_REVIEW_REQUIRED'
    except BaseException as exc:
        error=f'{type(exc).__name__}: {exc}'
        if proc is not None:
            test_bundles=[x for x in (scratch/'build').rglob('*.xctest') if x.is_dir()]
            try: owned_cleanup.extend(helper.stop_owned(proc,test_bundles,owned_observed))
            except Exception: pass
            if proc.poll() is None: stop_group(proc)
        status='INCOMPLETE_RETAINED'
    finally:
        try:
            if proc is not None:
                test_bundles=[x for x in (scratch/'build').rglob('*.xctest') if x.is_dir()]
                try: owned_cleanup.extend(helper.stop_owned(proc,test_bundles,owned_observed))
                except Exception: pass
                final_group_absent=stop_group(proc)
                owned_survivors=helper.owned_test_processes(helper.process_rows(),test_bundles)
                if owned_survivors or not final_group_absent:
                    status='OWNED_PROCESS_REMAINS_RETAINED'
                    error=f'owned XCTest survivors={owned_survivors}; processGroupAbsent={final_group_absent}'
        except Exception as cleanup_exc:
            status='OWNED_CLEANUP_UNVERIFIED_RETAINED'; error=f'{type(cleanup_exc).__name__}: {cleanup_exc}'
        # Verify all exact inputs after all test runs; do not delete any partial output.
        changed=[]
        for src,digest in initial_sources.items():
            try:
                if sha_file(ROOT/src)!=digest: changed.append(src)
            except Exception: changed.append(src)
        if changed:
            status='INPUT_DRIFT_RETAINED'; error=f'changed source inputs: {changed}'
        if out.exists() and allocated_bytes(out)>MAX_ALLOCATED: status='OUTPUT_CAP_EXCEEDED_RETAINED'
        write_run()
    print(json.dumps({'status':status,'runPath':str(runpath),'caseCount':len(cases),'error':error,'binarySHA256':binary_sha},sort_keys=True))
    return 0 if status=='COMPLETE_REVIEW_REQUIRED' else 2

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--manifest-sha256',required=True)
    ap.add_argument('--runner-sha256',required=True)
    ap.add_argument('--execute',action='store_true')
    ap.add_argument('--run-id',default='R374_MATRIX_001')
    args=ap.parse_args()
    m=verify_inputs(args.manifest_sha256,args.runner_sha256)
    if not args.execute:
        print(json.dumps({'status':'VERIFY_ONLY_READY_NOT_RUN','cases':len(m['cases']),'manifestSHA256':args.manifest_sha256,'runnerSHA256':args.runner_sha256},sort_keys=True)); return 0
    return execute(args,m)
if __name__=='__main__': raise SystemExit(main())

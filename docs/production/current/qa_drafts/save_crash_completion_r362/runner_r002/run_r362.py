#!/usr/bin/env python3
"""Prepared, fail-closed Root runner for the isolated R362 Core interruption test.

Default invocation only verifies pins. --execute is an explicit opt-in for Root.
This script never starts Simulator/app processes, never uses a real save, and never
removes output. Each run root is exclusive and retained, including failures.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
import uuid

ROOT = Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
BASE = ROOT / 'docs/production/current/qa_drafts/save_crash_completion_r362'
CANDIDATE = BASE / 'candidate_r001'
RUNNER_DIR = BASE / 'runner_r002'
INPUTS = RUNNER_DIR / 'INPUT_MANIFEST_R001.json'
EXPECTED_INPUTS_SHA256 = '388616de0070128dea2190713f804bd21645b989615cd46adda7d1fec94aa7f8'
EXECUTION = RUNNER_DIR / 'execution_r002'
TEST_REL = Path('Tests/WitchGameCoreTests/LoadoutCrashIntegrityR362Tests.swift')
PACKAGE_ROOT = ROOT / 'native/WitchGameCore'
TOTAL_SECONDS = 180
PHASE_SECONDS = 55
LOGICAL_CAP = 300_000_000
ALLOCATED_CAP = 300_000_000
RESERVE = 2_000_000_000
FREE_FLOOR = 12_000_000_000
FILTER = 'LoadoutCrashIntegrityR362Tests/testR342LoadoutPayloadCrashBoundary'

class Hold(RuntimeError):
    pass

class RunInterrupted(RuntimeError):
    pass

def handle_stop_signal(signum, _frame):
    # Raising in the main thread reaches the active phase's BaseException
    # handler, which stops only the direct subprocess PID; no process-group signal is used.
    raise RunInterrupted(f'runner received signal {signum}')

def sha_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()

def sha_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def no_symlink_path(p: Path, allow_missing_leaf=False) -> None:
    p = Path(os.path.abspath(p))
    cur = Path(p.anchor)
    for i, part in enumerate(p.parts[1:]):
        cur = cur / part
        if allow_missing_leaf and i == len(p.parts[1:]) - 1 and not cur.exists() and not cur.is_symlink():
            continue
        if cur.is_symlink():
            raise Hold(f'symlink component: {cur}')

def write_new(path: Path, obj) -> None:
    data = (json.dumps(obj, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode()
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        view = memoryview(data)
        while view:
            n = os.write(fd, view)
            if n <= 0:
                raise OSError('short write')
            view = view[n:]
        os.fsync(fd)
    finally:
        os.close(fd)
    parentfd=os.open(path.parent,os.O_RDONLY)
    try: os.fsync(parentfd)
    finally: os.close(parentfd)

def replace_receipt(path: Path, obj) -> None:
    """The only mutable file is this run receipt; evidence/logs are create-new."""
    tmp = path.with_name(path.name + f'.tmp-{os.getpid()}')
    write_new(tmp, obj)
    os.replace(tmp, path)
    fd = os.open(path.parent, os.O_RDONLY)
    try: os.fsync(fd)
    finally: os.close(fd)

def current_package_rows() -> list[dict]:
    rows=[]
    for base in (PACKAGE_ROOT / 'Sources/WitchGameCore',):
        no_symlink_path(base)
        if not base.is_dir() or base.is_symlink():
            raise Hold(f'missing/unsafe source tree: {base}')
        for p in sorted(base.rglob('*')):
            if p.is_symlink():
                raise Hold(f'symlink input rejected: {p}')
            if not p.is_file():
                continue
            st=p.stat()
            rows.append({'path':p.relative_to(PACKAGE_ROOT).as_posix(), 'sizeBytes':st.st_size,
                         'mode':st.st_mode & 0o777, 'sha256':sha_file(p)})
    for p in (PACKAGE_ROOT / 'Package.swift', CANDIDATE / 'LoadoutCrashIntegrityR362Tests.swift'):
        no_symlink_path(p)
        if not p.is_file() or p.is_symlink(): raise Hold(f'missing/unsafe pinned input: {p}')
        st=p.stat(); root=PACKAGE_ROOT if p.parent == PACKAGE_ROOT else CANDIDATE
        rows.append({'path':('Package.swift' if root == PACKAGE_ROOT else 'TEST/LoadoutCrashIntegrityR362Tests.swift'),
                     'sizeBytes':st.st_size, 'mode':st.st_mode & 0o777, 'sha256':sha_file(p)})
    return sorted(rows, key=lambda x:x['path'])

def toolchain_info() -> dict:
    swift=shutil.which('swift')
    if not swift: raise Hold('swift unavailable')
    swift=str(Path(swift).resolve(strict=True))
    def out(args):
        return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, timeout=15, check=True).stdout.strip()
    developer=out(['xcode-select','-p'])
    sdk=out(['xcrun','--sdk','macosx','--show-sdk-path'])
    help_text=out([swift,'test','--help'])
    required=['--scratch-path','--cache-path','--config-path','--security-path']
    if any(x not in help_text for x in required): raise Hold('swift test lacks isolated path options')
    return {'swiftPath':swift,'swiftVersion':out([swift,'--version']),'xctestPath':str(Path(out(['xcrun','--find','xctest'])).resolve(strict=True)),
            'developerDir':str(Path(developer).resolve(strict=True)),
            'xcodeVersion':out(['xcodebuild','-version']),
            'sdkPath':str(Path(sdk).resolve(strict=True)),
            'sdkVersion':out(['xcrun','--sdk','macosx','--show-sdk-version']),
            'swiftTestHelpSHA256':sha_bytes(help_text.encode()), 'requiredPathOptions':required}

def verify_inputs() -> dict:
    if Path(os.path.realpath(ROOT)) != ROOT: raise Hold('unexpected fixed worktree resolution')
    if INPUTS.is_symlink() or not INPUTS.is_file(): raise Hold('input manifest missing/unsafe')
    if sha_file(INPUTS)!=EXPECTED_INPUTS_SHA256: raise Hold('pinned input manifest SHA mismatch')
    manifest=json.loads(INPUTS.read_text())
    if manifest.get('schema') != 'r362-inputs-v1': raise Hold('wrong input manifest schema')
    actual=current_package_rows()
    if actual != manifest.get('rows'): raise Hold('source/package/test bytes differ from exact manifest')
    tc=toolchain_info()
    if tc != manifest.get('toolchain'): raise Hold('Swift/Xcode/SDK changed since candidate pin')
    if manifest.get('testFilter') != FILTER: raise Hold('test filter pin mismatch')
    return {'manifestSHA256':sha_file(INPUTS),'inputCount':len(actual),'toolchain':tc,
            'sourceTreeCount':sum(1 for x in actual if x['path'].startswith('Sources/') and '/Resources/' not in x['path']),
            'resourceFileCount':sum(1 for x in actual if '/Resources/' in x['path']),
            'testSHA256':next(x['sha256'] for x in actual if x['path'].startswith('TEST/'))}

def usage(root: Path) -> tuple[int,int]:
    logical=allocated=0; seen=set(); stack=[root]
    scratch_root=(EXECUTION/'scratch').resolve(strict=False)
    def inside_scratch(path: Path) -> bool:
        try: Path(os.path.abspath(path)).relative_to(scratch_root); return True
        except ValueError: return False
    def vanished(path: Path):
        if inside_scratch(path): return
        raise Hold(f'non-scratch output disappeared during audit: {path}')
    while stack:
        p=stack.pop()
        try: st=p.lstat()
        except FileNotFoundError:
            vanished(p); continue
        ident=(st.st_dev,st.st_ino)
        if ident in seen: continue
        seen.add(ident)
        if p.is_symlink():
            link=Path(os.path.abspath(p)); target=p.resolve(strict=False)
            if not inside_scratch(link) or not inside_scratch(target):
                raise Hold(f'output symlink outside fixed scratch rejected: {p} -> {target}')
            logical+=st.st_size; allocated+=st.st_blocks*512
        elif p.is_dir():
            try: stack.extend(list(p.iterdir()))
            except FileNotFoundError:
                vanished(p); continue
        elif p.is_file(): logical+=st.st_size; allocated+=st.st_blocks*512
    return logical,allocated

def inventory(root: Path) -> list[dict]:
    rows=[]
    for p in sorted(root.rglob('*')):
        if p.is_symlink(): raise Hold(f'protected tree symlink: {p}')
        if p.is_file():
            st=p.stat(); rows.append({'path':p.relative_to(root).as_posix(),'sizeBytes':st.st_size,
               'mode':st.st_mode & 0o777,'mtimeNs':st.st_mtime_ns,'sha256':sha_file(p)})
    return rows

def check_forbidden_app(executable: Path | None) -> None:
    if executable is None: return
    target=str(executable.resolve(strict=True))
    ps=subprocess.run(['/bin/ps','-axo','pid=,command='],capture_output=True,text=True,timeout=10,check=True).stdout
    for line in ps.splitlines():
        parts=line.strip().split(None,1)
        if len(parts)!=2 or int(parts[0])==os.getpid(): continue
        executable=parts[1].split(None,1)[0]
        if executable==target:
            raise Hold(f'protected app appears running: {line.strip()}')

def process_rows() -> list[dict]:
    result=subprocess.run(['/bin/ps','-axo','pid=,ppid=,pgid=,lstart=,command='],capture_output=True,text=True,timeout=8,check=True)
    rows=[]
    for line in result.stdout.splitlines():
        bits=line.strip().split(None,8)
        if len(bits)==9:
            try: rows.append({'pid':int(bits[0]),'ppid':int(bits[1]),'pgid':int(bits[2]),'startIdentity':' '.join(bits[3:8]),'command':bits[8]})
            except ValueError: pass
    return rows

def process_row(pid: int) -> dict | None:
    return next((r for r in process_rows() if r['pid']==pid),None)

def descendants(rows: list[dict], parent_pid: int) -> list[dict]:
    by_parent={}
    for row in rows: by_parent.setdefault(row['ppid'],[]).append(row)
    result=[]; todo=[parent_pid]; seen={parent_pid}
    while todo:
        parent=todo.pop()
        for row in by_parent.get(parent,[]):
            if row['pid'] not in seen:
                seen.add(row['pid']); result.append(row); todo.append(row['pid'])
    return result

def same_owned_identity(live: dict | None, pinned: dict) -> bool:
    return bool(live and live['pid']==pinned['pid'] and live['command']==pinned['command'] and live['startIdentity']==pinned['startIdentity'])

def record_descendants(proc: subprocess.Popen, observed: dict[int,dict]) -> None:
    for row in descendants(process_rows(),proc.pid): observed[row['pid']]=row

def process_command(pid: int) -> str | None:
    row=process_row(pid)
    return row['command'] if row else None

def process_state(pid: int) -> str | None:
    result=subprocess.run(['/bin/ps','-p',str(pid),'-o','state='],capture_output=True,text=True,timeout=5)
    return result.stdout.strip() if result.returncode==0 and result.stdout.strip() else None

def bundle_processes(expected_bundle: Path, driver: str) -> list[dict]:
    bundle=str(expected_bundle.resolve())
    return [r for r in process_rows() if r['command'].startswith(driver+' ') and bundle in r['command'] and '-XCTest' in r['command']]

def stop_owned(proc: subprocess.Popen, expected_bundle: Path | None, driver: str, observed: dict[int,dict]) -> dict:
    # Signal only exact PID identities descended from this Popen or the unique XCTest bundle.
    initial=process_rows(); owned={r['pid']:r for r in descendants(initial,proc.pid)}
    if expected_bundle is not None:
        owned.update({r['pid']:r for r in bundle_processes(expected_bundle,driver)})
    for pid,pinned in observed.items():
        live=next((r for r in initial if same_owned_identity(r,pinned)),None)
        if live and (pid==proc.pid or any(x['pid']==pid for x in descendants(initial,proc.pid)) or (expected_bundle is not None and live in bundle_processes(expected_bundle,driver))): owned[pid]=live
    actions=[]
    def owned_live(row: dict) -> dict | None:
        live=process_row(row['pid'])
        if not same_owned_identity(live,row): return None
        rows=process_rows()
        is_descendant=row['pid']==proc.pid or any(x['pid']==row['pid'] and same_owned_identity(x,row) for x in descendants(rows,proc.pid))
        is_bundle=expected_bundle is not None and any(same_owned_identity(x,row) for x in bundle_processes(expected_bundle,driver))
        # A reparented child remains owned only if it was previously observed as an exact child identity.
        was_observed=row['pid'] in observed and same_owned_identity(observed[row['pid']],row)
        return live if is_descendant or is_bundle or was_observed else None
    for row in list(owned.values()):
        live=owned_live(row)
        if live:
            try: os.kill(live['pid'],signal.SIGTERM); actions.append({'pid':live['pid'],'startIdentity':live['startIdentity'],'command':live['command'],'signal':'SIGTERM'})
            except ProcessLookupError: pass
    time.sleep(1.0)
    survivors=[row for row in owned.values() if owned_live(row)]
    for row in survivors:
        live=owned_live(row)
        if live:
            try: os.kill(live['pid'],signal.SIGKILL); actions.append({'pid':live['pid'],'startIdentity':live['startIdentity'],'command':live['command'],'signal':'SIGKILL'})
            except ProcessLookupError: pass
    deadline=time.monotonic()+3.0
    while time.monotonic()<deadline and any(owned_live(row) for row in owned.values()): time.sleep(.1)
    remaining=[{'pid':row['pid'],'startIdentity':row['startIdentity'],'command':row['command']} for row in owned.values() if owned_live(row)]
    try: wrapper_code=proc.wait(timeout=1)
    except subprocess.TimeoutExpired: wrapper_code=None
    return {'ownedSupervisorPID':proc.pid,'actions':actions,'remainingOwnedProcesses':remaining,
            'allOwnedProcessesAbsent':not remaining,'wrapperReturnCode':wrapper_code,'processGroupSignalUsed':False}

def ensure_no_competing_swift() -> None:
    own=str(RUNNER_DIR.resolve())
    for row in process_rows():
        if row['pid']==os.getpid(): continue
        cmd=row['command']
        if ('swift test' in cmd or 'swift-test' in cmd or 'WitchGameCorePackageTests.xctest' in cmd or 'LoadoutCrashIntegrityR362Tests' in cmd):
            if own not in cmd:
                raise Hold(f'competing Swift/XCTest process present: pid={row["pid"]}')

def stage_ok(stage: Path, proc: subprocess.Popen, save_command_fingerprint: str, operation: str,
             phase_token: str, expected_bundle: Path, verified: dict, phase_started: float) -> dict:
    if stage.is_symlink() or not stage.is_file(): raise Hold('after-primary-replace marker absent')
    x=json.loads(stage.read_text())
    if (x.get('schema')!='r362-after-primary-replace-v1' or x.get('phase')!='afterPrimaryReplace'
        or x.get('operationID')!=operation or x.get('requestFingerprint')!=save_command_fingerprint
        or not isinstance(x.get('pid'),int) or x['pid']<=1 or x['pid']==proc.pid
        or x.get('phaseToken')!=phase_token or not isinstance(x.get('parentPID'),int)
        or not isinstance(x.get('markerUnixTime'),(int,float))
        or x['markerUnixTime'] < phase_started-2 or x['markerUnixTime'] > time.time()+2):
        raise Hold('stage marker phase/process identity mismatch')
    child=process_row(x['pid'])
    command=child['command'] if child else None
    driver=verified['toolchain']['xctestPath']
    if (not command or not command.startswith(driver+' ') or str(expected_bundle) not in command
        or 'WitchGameCoreTests.LoadoutCrashIntegrityR362Tests/testR342LoadoutPayloadCrashBoundary' not in command):
        raise Hold('marker PID is not the exact XCTest driver/test bundle launched for this phase')
    # The XCTest process is its own session leader on this host; this is recorded as evidence only.
    try: pgid=int(subprocess.run(['/bin/ps','-p',str(x['pid']),'-o','pgid='],capture_output=True,text=True,timeout=5,check=True).stdout.strip())
    except Exception as exc: raise Hold(f'cannot read exact child session identity: {exc}')
    if x.get('processGroupID') != pgid:
        raise Hold('marker process-group observation differs from live process; no signal sent')
    x['observedCommand']=command; x['processStartIdentity']=child['startIdentity']; x['observedProcessGroupID']=pgid; x['validatedDriverPath']=driver
    return x

def same_bundle_processes(expected_bundle: Path, driver: str) -> list[dict]:
    ps=subprocess.run(['/bin/ps','-axo','pid=,state=,command='],capture_output=True,text=True,timeout=5,check=True).stdout
    matches=[]
    for line in ps.splitlines():
        parts=line.strip().split(None,2)
        if len(parts)==3 and driver in parts[2] and str(expected_bundle) in parts[2]:
            matches.append({'pid':int(parts[0]),'state':parts[1],'command':parts[2]})
    return matches

def kill_validated_test_pid(marker: dict, proc: subprocess.Popen, expected_bundle: Path, verified: dict) -> dict:
    pid=marker['pid']; driver=verified['toolchain']['xctestPath']; live=process_row(pid)
    if (proc.poll() is not None or not live or live['command']!=marker.get('observedCommand')
        or live['startIdentity']!=marker.get('processStartIdentity') or not live['command'].startswith(driver+' ')
        or str(expected_bundle) not in live['command']):
        raise Hold('validated XCTest PID/start/command/supervisor identity changed before signal')
    result={'signal':'SIGKILL','targetPID':pid,'targetCommand':live['command'],'targetStartIdentity':live['startIdentity'],'groupSignalUsed':False}
    os.kill(pid,signal.SIGKILL)  # One marker-bound PID only; never signal a process group.
    deadline=time.monotonic()+8
    while time.monotonic()<deadline:
        current=process_row(pid)
        if not current or not same_owned_identity(current,live): break
        time.sleep(.1)
    else: raise Hold('exact XCTest PID remained after SIGKILL')
    try: result['returnCode']=proc.wait(timeout=20)
    except subprocess.TimeoutExpired: raise Hold('Swift test supervisor did not recover after child interruption')
    if process_row(pid) is not None: raise Hold('killed XCTest PID still present after wrapper recovery')
    leftovers=bundle_processes(expected_bundle,driver)
    if leftovers: raise Hold('XCTest remains on unique bundle path after crash-child kill')
    result.update({'targetPIDAbsent':True,'wrapperRecovered':True,'remainingBundleProcesses':leftovers,'allOwnedProcessesAbsent':True})
    return result

def parse_one_pass(log: Path, passed: bool) -> bool:
    text=log.read_text(errors='replace')
    import re
    status='passed' if passed else 'started'
    labels=re.findall(r"Test Case '([^']+)' "+status,text,re.I)
    if passed:
        return len(labels)==1 and 'LoadoutCrashIntegrityR362Tests' in labels[0] and FILTER.split('/')[-1] in labels[0] and bool(re.search(r'Executed 1 test, with 0 failures',text)) and not re.search(r'Test Case .* skipped',text,re.I)
    return len(labels)==1 and 'LoadoutCrashIntegrityR362Tests' in labels[0] and FILTER.split('/')[-1] in labels[0]

def execute(args, verified):
    out=EXECUTION
    no_symlink_path(out,allow_missing_leaf=True)
    if out.exists() or out.is_symlink(): raise Hold('execution_r001 already exists; no overwrite/retry')
    if not args.protected_root or not args.protected_manifest or not args.protected_manifest_sha256 or not args.app_executable or not args.pbx:
        raise Hold('execute requires protected-root manifest+SHA, stopped-app executable and PBX pins')
    for raw_path in (args.protected_root,args.protected_manifest,args.save,args.pbx,args.app_executable):
        if raw_path is None or not Path(raw_path).is_absolute(): raise Hold('all protected paths must be absolute')
        no_symlink_path(Path(raw_path))
    protected=Path(args.protected_root).resolve(strict=True)
    if sha_file(args.protected_manifest)!=args.protected_manifest_sha256: raise Hold('protected namespace manifest SHA mismatch')
    baseline=json.loads(Path(args.protected_manifest).read_text())
    if baseline.get('rows')!=inventory(protected): raise Hold('protected namespace does not match supplied baseline')
    if sha_file(args.pbx)!=args.pbx_sha256: raise Hold('PBX pin mismatch')
    save=Path(args.save).resolve(strict=True)
    if save.is_symlink() or sha_file(save)!=args.save_sha256: raise Hold('seed save152 pin mismatch')
    check_forbidden_app(args.app_executable)
    free=shutil.disk_usage(ROOT).free
    if free < LOGICAL_CAP+RESERVE+FREE_FLOOR: raise Hold('capacity reserve/floor not met')
    started=time.monotonic()
    deadline=started+TOTAL_SECONDS
    out.mkdir(mode=0o700,exist_ok=False)
    (out/'prepared').mkdir(mode=0o700,exist_ok=False)
    (out/'tmp').mkdir(mode=0o700,exist_ok=False)
    trial=out/'trial_001'; trial.mkdir(mode=0o700,exist_ok=False)
    work=trial/'state'; work.mkdir(mode=0o700,exist_ok=False)
    pkg=out/'prepared/package'; pkg.mkdir(mode=0o700,exist_ok=False)
    rows=verified['manifestRows']
    source_root=PACKAGE_ROOT
    for row in rows:
        if time.monotonic()-started > TOTAL_SECONDS: raise Hold('aggregate 180s budget exceeded while preparing package')
        if row['path']=='Package.swift':
            # Pin the repository manifest as an input, but use the separate minimal
            # manifest pinned below for this isolated test package.
            continue
        if row['path'].startswith('TEST/'): src=CANDIDATE/'LoadoutCrashIntegrityR362Tests.swift'; rel=TEST_REL
        else: src=source_root/row['path']; rel=Path(row['path'])
        dest=pkg/rel
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(src,dest,follow_symlinks=False)
        os.chmod(dest,row['mode'])
        if sha_file(dest)!=row['sha256'] or dest.stat().st_size!=row['sizeBytes']: raise Hold('staged input mismatch')
    package_text='''// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: "WitchGameCore", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "WitchGameCore", targets: ["WitchGameCore"])], targets: [.target(name: "WitchGameCore", resources: [.process("Resources")]), .testTarget(name: "WitchGameCoreTests", dependencies: ["WitchGameCore"])])\n'''
    package_file=pkg/'Package.swift'
    if package_file.exists(): raise Hold('manifest copy conflict')
    package_file.write_text(package_text)
    if sha_file(package_file)!=verified['minimalPackageSHA256']: raise Hold('generated minimal Package.swift differs from pinned template')
    expected_staged={Path(r['path']).as_posix() for r in rows if r['path'] not in ('Package.swift',) and not r['path'].startswith('TEST/')}
    expected_staged.add(TEST_REL.as_posix()); expected_staged.add('Package.swift')
    staged=set()
    for item in pkg.rglob('*'):
        if item.is_symlink(): raise Hold(f'staged package symlink: {item}')
        if item.is_file(): staged.add(item.relative_to(pkg).as_posix())
    if staged!=expected_staged: raise Hold('staged package contains missing/unexpected inputs')
    l,a=usage(out)
    if l>LOGICAL_CAP or a>ALLOCATED_CAP or shutil.disk_usage(ROOT).free<LOGICAL_CAP+RESERVE+FREE_FLOOR:
        raise Hold('output cap or free-space floor failed after staging, before XCTest')
    scratch=out/'scratch'; scratch.mkdir(mode=0o700,exist_ok=False)
    for n in ('swift-cache','swift-config','swift-security','clang-module-cache'):(scratch/n).mkdir(mode=0o700,exist_ok=False)
    ids={'seed':str(uuid.uuid4()),'save':str(uuid.uuid4())}
    while ids['seed']==ids['save']: ids['save']=str(uuid.uuid4())
    rec={'schema':'r362-run-v1','status':'RUNNING','startedAt':dt.datetime.now().astimezone().isoformat(),
         'limitSeconds':TOTAL_SECONDS,'attempt':1,'attemptLimit':1,'automaticRetry':False,
         'outputCapLogicalBytes':LOGICAL_CAP,'outputCapAllocatedBytes':ALLOCATED_CAP,'reserveBytes':RESERVE,
         'freeFloorBytes':FREE_FLOOR,'pins':verified,'protectedRowsBefore':baseline['rows'],
         'protectedRowsBeforeSHA256':sha_bytes(json.dumps(baseline['rows'],sort_keys=True,separators=(',',':')).encode()),
         'seedSaveSHA256':args.save_sha256,'pbxSHA256':args.pbx_sha256,'operationIDs':ids,'phases':[]}
    run_path=trial/'RUN.json'; replace_receipt(run_path,rec)
    env={k:v for k,v in os.environ.items() if k in ('USER','LOGNAME','SHELL','LANG','LC_ALL','HOME','PATH')}
    env['PATH']=os.pathsep.join([str(Path(verified['toolchain']['swiftPath']).parent),'/usr/bin','/bin','/usr/sbin','/sbin'])
    env['DEVELOPER_DIR']=verified['toolchain']['developerDir']; env['SDKROOT']=verified['toolchain']['sdkPath']
    env['TMPDIR']=str(out/'tmp'); env['CLANG_MODULE_CACHE_PATH']=str(scratch/'clang-module-cache')
    env.update({'WITCH_R362_ROOT':str(work),'WITCH_R362_SEED_OPERATION_ID':ids['seed'],'WITCH_R362_SAVE_OPERATION_ID':ids['save']})
    staged_hashes={q.relative_to(pkg).as_posix():sha_file(q) for q in pkg.rglob('*') if q.is_file()}
    test_executable=None; test_executable_sha=None; test_bundle=None
    phases=[]; observed_processes={}
    try:
        for mode in ('seed','crash-child','verify'):
            remain=min(PHASE_SECONDS,deadline-time.monotonic())
            if remain<=5: raise Hold('aggregate 180s budget exhausted')
            log=trial/(mode+'.log')
            cmd=[verified['toolchain']['swiftPath'],'test','--package-path',str(pkg),'--scratch-path',str(scratch),
                 '--cache-path',str(scratch/'swift-cache'),'--config-path',str(scratch/'swift-config'),
                 '--security-path',str(scratch/'swift-security'),'--jobs','2','--filter',FILTER]
            if mode!='seed': cmd.append('--skip-build')
            if {q.relative_to(pkg).as_posix():sha_file(q) for q in pkg.rglob('*') if q.is_file()} != staged_hashes:
                raise Hold('frozen staged inputs changed between phases')
            if mode!='seed' and (test_executable is None or sha_file(test_executable)!=test_executable_sha):
                raise Hold('single test executable changed before reuse')
            env['WITCH_R362_MODE']=mode
            phaseToken=str(uuid.uuid4())
            env['WITCH_R362_PHASE_TOKEN']=phaseToken
            t0_wall=time.time()
            pgrp=None
            with log.open('xb') as f:
                proc=subprocess.Popen(cmd,cwd=ROOT,env=env,stdout=f,stderr=subprocess.STDOUT,
                    stdin=subprocess.DEVNULL,start_new_session=True,close_fds=True)
                root_identity=process_row(proc.pid)
                if root_identity is None: raise Hold('cannot capture exact Swift supervisor identity')
                observed_processes[proc.pid]=root_identity
                record_descendants(proc,observed_processes)
                phase={'mode':mode,'command':cmd,'pid':proc.pid,'pgid':proc.pid,'startIdentity':root_identity['startIdentity'],'log':str(log),
                       'startedAt':dt.datetime.now().astimezone().isoformat()}
                t0=time.monotonic(); interrupted=False
                try:
                    write_new(trial/(mode+'-start.json'),{'schema':'r362-phase-start-v1',**phase})
                    if mode=='crash-child':
                        if test_bundle is None: raise Hold('compiled XCTest bundle path unavailable')
                        stage=work/'after-primary-replace.json'
                        while not stage.exists():
                            record_descendants(proc,observed_processes)
                            if proc.poll() is not None: raise Hold('crash child exited before barrier marker')
                            if time.monotonic()-t0>remain: raise Hold('crash-child phase timeout before barrier')
                            if shutil.disk_usage(ROOT).free<LOGICAL_CAP+RESERVE+FREE_FLOOR: raise Hold('capacity floor breached')
                            l,a=usage(out)
                            if l>LOGICAL_CAP or a>ALLOCATED_CAP: raise Hold('output cap breached')
                            time.sleep(0.2)
                        marker=stage_ok(stage,proc, 'saveGearLoadoutR342|1:1', ids['save'], phaseToken, test_bundle, verified, t0_wall)
                        if proc.poll() is not None or sha_file(work/'save.json') != marker.get('primarySHA256'):
                            raise Hold('barrier child exited or primary bytes differ from marker before kill')
                        phase['stageMarker']=marker
                        child_identity=process_row(marker['pid'])
                        if child_identity is None or child_identity['startIdentity']!=marker['processStartIdentity']:
                            raise Hold('marker-bound XCTest identity changed before ownership record')
                        observed_processes[marker['pid']]=child_identity
                        phase['termination']=kill_validated_test_pid(marker,proc,test_bundle,verified); interrupted=True
                        phase['signalSentByRunner']='SIGKILL_EXACT_XCTEST_PID_ONLY'
                        if phase['termination'].get('targetPID') != marker['pid'] or phase['termination'].get('groupSignalUsed') is not False or phase['termination'].get('wrapperRecovered') is not True or phase['termination'].get('targetPIDAbsent') is not True:
                            raise Hold('exact XCTest PID kill or supervisor recovery was not confirmed')
                        phase['terminationClass']='VALIDATED_XCTEST_CHILD_PID_KILLED_WRAPPER_RECOVERED'
                    else:
                        while proc.poll() is None:
                            record_descendants(proc,observed_processes)
                            if time.monotonic()-t0>remain: raise Hold(f'{mode} timed out')
                            if shutil.disk_usage(ROOT).free<LOGICAL_CAP+RESERVE+FREE_FLOOR: raise Hold('capacity floor breached')
                            l,a=usage(out)
                            if l>LOGICAL_CAP or a>ALLOCATED_CAP: raise Hold('output cap breached')
                            time.sleep(0.5)
                        phase['returnCode']=proc.wait(timeout=5)
                        phase['accepted']=phase['returnCode']==0 and parse_one_pass(log,True)
                    f.flush(); os.fsync(f.fileno())
                except BaseException as exc:
                    phase['error']=f'{type(exc).__name__}: {exc}'
                    phase['termination']=stop_owned(proc,test_bundle,verified['toolchain']['xctestPath'],observed_processes)
                    phase['elapsedSeconds']=round(time.monotonic()-t0,3)
                    f.flush(); os.fsync(f.fileno())
                    phase['logSHA256']=sha_file(log); phase['logBytes']=log.stat().st_size
                    if not any(row.get('mode')==mode for row in phases): phases.append(phase)
                    rec['phases']=phases; replace_receipt(run_path,rec)
                    raise
            phase['elapsedSeconds']=round(time.monotonic()-t0,3)
            phase['logSHA256']=sha_file(log); phase['logBytes']=log.stat().st_size
            if mode=='crash-child':
                text=log.read_text(errors='replace')
                import re
                phase['accepted']=(phase.get('terminationClass')=='VALIDATED_XCTEST_CHILD_PID_KILLED_WRAPPER_RECOVERED'
                    and phase.get('stageMarker') is not None
                    and phase.get('termination',{}).get('targetPID') == phase.get('stageMarker',{}).get('pid')
                    and phase.get('termination',{}).get('returnCode') not in (None,0)
                    and phase.get('termination',{}).get('groupSignalUsed') is False and phase.get('termination',{}).get('wrapperRecovered') is True and phase.get('termination',{}).get('targetPIDAbsent') is True
                    and parse_one_pass(log,False) and not re.search(r'Test Case .* passed',text,re.I)
                    and not re.search(r'Test Case .* skipped',text,re.I))
            record_descendants(proc,observed_processes)
            if mode=='seed' and phase.get('accepted',False):
                found=[q for q in scratch.rglob('*') if q.is_dir() and q.name.endswith('.xctest') and not q.is_symlink()]
                if len(found)!=1: raise Hold('expected exactly one compiled XCTest bundle')
                test_bundle=found[0].resolve(strict=True)
                execs=[q for q in test_bundle.rglob('*') if q.is_file() and os.access(q,os.X_OK) and q.parent.name=='MacOS']
                if len(execs)!=1: raise Hold('expected exactly one executable in compiled XCTest bundle')
                test_executable=execs[0]; test_executable_sha=sha_file(test_executable)
                rec['testExecutable']={'path':str(test_executable),'sha256':test_executable_sha}
            if test_executable is not None and sha_file(test_executable)!=test_executable_sha:
                raise Hold('single test executable changed after phase')
            if {q.relative_to(pkg).as_posix():sha_file(q) for q in pkg.rglob('*') if q.is_file()} != staged_hashes:
                raise Hold('frozen staged inputs changed after phase')
            if not phase.get('accepted',False):
                phases.append(phase); raise Hold(f'phase not accepted: {mode}')
            phases.append(phase); rec['phases']=phases; replace_receipt(run_path,rec)
        rec['status']='SEMANTIC_REVIEW_REQUIRED'
    except BaseException as exc:
        rec['status']='INCOMPLETE_RETAINED'; rec['error']=f'{type(exc).__name__}: {exc}'
        rec['phases']=phases
    finally:
        rec['elapsedSeconds']=round(time.monotonic()-started,3)
        rec['finishedAt']=dt.datetime.now().astimezone().isoformat()
        audit_errors=[]
        try:
            current_rows=process_rows()
            owned_remaining=[]
            for pid,pinned in observed_processes.items():
                current=next((r for r in current_rows if r['pid']==pid),None)
                if same_owned_identity(current,pinned):
                    owned_remaining.append({'pid':pid,'startIdentity':pinned['startIdentity'],'command':pinned['command']})
            rec['ownedProcessesAfter']=owned_remaining
            if owned_remaining: raise Hold('owned Swift/XCTest process remains after final phase')
            if test_bundle is not None:
                remaining=bundle_processes(test_bundle,verified['toolchain']['xctestPath'])
                rec['xctestProcessesAfter']=remaining
                if remaining: raise Hold('XCTest process remains on unique bundle path after final phase')
            else: rec['xctestProcessesAfter']=[]
            rec['sourceRowsAfter']=current_package_rows()
            rec['sourceUnchanged']=rec['sourceRowsAfter']==verified['manifestRows']
        except Exception as exc:
            rec['sourceUnchanged']=False; audit_errors.append(f'source audit: {type(exc).__name__}: {exc}')
        try:
            rec['protectedRowsAfter']=inventory(protected)
            rec['protectedUnchanged']=rec['protectedRowsAfter']==baseline['rows']
        except Exception as exc:
            rec['protectedUnchanged']=False; audit_errors.append(f'protected audit: {type(exc).__name__}: {exc}')
        try: rec['pbxUnchanged']=sha_file(args.pbx)==args.pbx_sha256
        except Exception as exc: rec['pbxUnchanged']=False; audit_errors.append(f'PBX audit: {type(exc).__name__}: {exc}')
        try: rec['saveUnchanged']=sha_file(save)==args.save_sha256
        except Exception as exc: rec['saveUnchanged']=False; audit_errors.append(f'save audit: {type(exc).__name__}: {exc}')
        try: check_forbidden_app(args.app_executable)
        except Exception as exc: rec['appStoppedAfter']=False; audit_errors.append(f'app stop audit: {type(exc).__name__}: {exc}')
        else: rec['appStoppedAfter']=True
        try:
            l,a=usage(out); rec['outputUsage']={'logicalBytes':l,'allocatedBytes':a}
        except Exception as exc:
            l=a=LOGICAL_CAP+1; audit_errors.append(f'output audit: {type(exc).__name__}: {exc}')
        if audit_errors: rec['auditErrors']=audit_errors
        if rec['elapsedSeconds']>TOTAL_SECONDS or l>LOGICAL_CAP or a>ALLOCATED_CAP or not rec.get('protectedUnchanged') or not rec.get('pbxUnchanged') or not rec.get('saveUnchanged') or not rec.get('sourceUnchanged') or not rec.get('appStoppedAfter'):
            rec['status']='INCOMPLETE_RETAINED'
        replace_receipt(run_path,rec)
    return rec

def main():
    signal.signal(signal.SIGTERM,handle_stop_signal)
    signal.signal(signal.SIGINT,handle_stop_signal)
    ap=argparse.ArgumentParser()
    ap.add_argument('--execute',action='store_true',help='Root-only explicit execution; default is read-only pin verification')
    ap.add_argument('--protected-root',type=Path)
    ap.add_argument('--protected-manifest',type=Path)
    ap.add_argument('--protected-manifest-sha256')
    ap.add_argument('--save',type=Path)
    ap.add_argument('--save-sha256')
    ap.add_argument('--pbx',type=Path)
    ap.add_argument('--pbx-sha256')
    ap.add_argument('--app-executable',type=Path)
    args=ap.parse_args()
    if args.execute:
        def interrupted(signum, frame):
            raise KeyboardInterrupt(f"R362 owned runner interrupted by signal {signum}")
        signal.signal(signal.SIGTERM, interrupted)
        signal.signal(signal.SIGINT, interrupted)
    verified=verify_inputs()
    ensure_no_competing_swift()
    manifest=json.loads(INPUTS.read_text()); verified['manifestRows']=manifest['rows']; verified['minimalPackageSHA256']=manifest['minimalPackageSHA256']
    if not args.execute:
        print(json.dumps({'status':'VERIFIED_ONLY_NOT_RUN',**{k:v for k,v in verified.items() if k!='manifestRows'}},indent=2))
        return 0
    rec=execute(args,verified)
    print(json.dumps({'status':rec['status'],'runReceipt':str(EXECUTION/'trial_001/RUN.json'),'elapsedSeconds':rec['elapsedSeconds']},indent=2))
    return 0 if rec['status']=='SEMANTIC_REVIEW_REQUIRED' else 2
if __name__=='__main__':
    try: raise SystemExit(main())
    except Hold as exc:
        print(f'HOLD: {exc}',file=sys.stderr); raise SystemExit(2)

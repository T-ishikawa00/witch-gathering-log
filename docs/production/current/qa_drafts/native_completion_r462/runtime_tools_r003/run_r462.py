#!/usr/bin/env python3
"""R462 install + bounded manual checkpoint recorder. Draft only; Root operates it."""
from __future__ import annotations
import argparse, fcntl, hashlib, json, os, plistlib, shlex, shutil, subprocess, time, uuid
from pathlib import Path
from typing import Optional

ROOT = Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
BASE = Path(__file__).resolve().parent
SEAL_PATH = BASE / 'RUNTIME_SEAL_R001.json'
DEVICE = '9A067715-7CF3-40D3-9064-38423223959B'
BUNDLE = 'local.witch.autonomous.r1.completion.r462'
R445_BUNDLE = 'local.witch.autonomous.r1.completion.r445'
R456_BUNDLE = 'local.witch.autonomous.r1.completion.r456'
R456_RUN = ROOT / 'docs/production/current/qa_drafts/native_completion_r456/runtime_tools_r002/runs/1605ec80-407f-4736-a077-1be866dac17a/RUN.json'
R456_BUILD = ROOT / 'docs/production/current/qa_drafts/native_completion_r456/build_tools_r003/BUILD_RESULT_R003.json'
R454_ORIGIN = ROOT / 'docs/production/current/qa_drafts/storekit_event_export_r454/runtime_r001/INSTALLED_ORIGIN_R004.json'
MAX_SECONDS, MAX_BYTES, START_FREE, FREE_FLOOR = 600, 1_040_000_000, 15_000_000_000, 10_000_000_000
SCREENSHOT_CAP, SCREENSHOTS_MAX = 20_000_000, 4
CAPTURE_LABELS = ('home','empty_search','filters_cleared','before_cold','cold')
EVIDENCE_CAP = 40_000_000
APP_SUPPORT = 'Library/Application Support/Witch03to05DevelopmentR169'
SEED_NAMES = ('save.json', 'save.json.previous', 'last_standard_play_identity_r169.json')
FLAGS = ['STANDARD_PLAY_R169', 'FIRST_CRAFT_AID_R179', 'EQUIPMENT_LOADOUTS_R342',
         'NATURAL_GEAR_R350', 'NATURAL_GEAR_REFINEMENT_R352', 'GEAR_DISMANTLE_REFUND_R353']


def sha_bytes(b: bytes) -> str: return hashlib.sha256(b).hexdigest()
def sha_file(p: Path) -> str: return sha_bytes(p.read_bytes())
def strict_json_bytes(b: bytes):
    def unique(pairs):
        d = {}
        for k,v in pairs:
            if k in d: raise RuntimeError('duplicate JSON key: '+k)
            d[k] = v
        return d
    return json.loads(b.decode('utf-8'), object_pairs_hook=unique)
def read_json(p: Path): return strict_json_bytes(p.read_bytes())
def atomic_json(p: Path, value):
    tmp = p.with_name(p.name+'.writing')
    with tmp.open('x', encoding='utf-8') as f:
        json.dump(value, f, ensure_ascii=False, sort_keys=True, indent=2); f.write('\n'); f.flush(); os.fsync(f.fileno())
    os.replace(tmp, p)
def rooted(value: str) -> Path:
    p = Path(value)
    if not p.is_absolute(): raise RuntimeError('sealed paths must be absolute')
    q = Path(os.path.abspath(p))
    if not q.is_relative_to(ROOT): raise RuntimeError('sealed path outside fixed worktree')
    cur = ROOT
    for part in q.relative_to(ROOT).parts:
        cur /= part
        if cur.is_symlink(): raise RuntimeError('symlink in sealed path')
    return q
def seed_source_path(value: str, seal: dict) -> Path:
    # Read-only seed sources are outside the worktree, inside the separately pinned
    # closed R456 Simulator data container. Never reuse the output-root validator.
    p = Path(value)
    support = Path(seal['r456DataContainerPath']) / APP_SUPPORT
    if not p.is_absolute() or p.parent != support or p.name not in SEED_NAMES:
        raise RuntimeError('seed source is outside the pinned R456 support directory')
    if p.resolve(strict=True) != p or not p.is_file():
        raise RuntimeError('seed source path is not canonical/regular')
    for part in [p, *p.parents]:
        if part.is_symlink(): raise RuntimeError('symlink in seed source path')
    return p

def run_directory(run_id: str) -> Path:
    try:
        if str(uuid.UUID(run_id))!=run_id: raise ValueError('noncanonical UUID')
    except (ValueError, AttributeError):
        raise RuntimeError('run ID must be a canonical UUID')
    parent=BASE/'runs'
    if parent.is_symlink(): raise RuntimeError('runs output parent is symlinked')
    p=parent/run_id
    if p.is_symlink() or not p.resolve().is_relative_to(parent.resolve()): raise RuntimeError('run path escapes R462 runtime output')
    return p
def tree_map(root: Path) -> dict[str,str]:
    if root.is_symlink() or not root.is_dir(): raise RuntimeError('unsafe protected tree: '+str(root))
    out={}
    for parent, dirs, files in os.walk(root, followlinks=False):
        parent=Path(parent)
        for d in dirs:
            if (parent/d).is_symlink(): raise RuntimeError('symlink in protected tree')
        for name in files:
            p=parent/name
            if p.is_symlink() or not p.is_file(): raise RuntimeError('nonregular protected file')
            out[p.relative_to(root).as_posix()]=sha_file(p)
    return out
def run(argv, timeout=30):
    p=subprocess.run(argv,capture_output=True,text=True,timeout=timeout)
    if p.returncode: raise RuntimeError(f'{Path(argv[0]).name} failed ({p.returncode}): {p.stderr[-1000:]}')
    return p.stdout.strip()
def app_container(bundle: str, kind: str):
    p=subprocess.run(['xcrun','simctl','get_app_container',DEVICE,bundle,kind],capture_output=True,text=True,timeout=15)
    if p.returncode:
        if 'No such file or directory' in p.stderr or 'No app for bundle identifier' in p.stderr: return None
        raise RuntimeError('simctl could not resolve app container: '+p.stderr[-500:])
    raw=Path(p.stdout.strip())
    if not raw.is_absolute() or raw.is_symlink(): raise RuntimeError('simctl returned unsafe container path')
    return raw.resolve(strict=True)
def running_exe(exe: Path):
    rows=run(['ps','-axo','pid=,lstart=,command=']).splitlines()
    found=[]
    for row in rows:
        bits=row.strip().split(None,6)
        if len(bits)==7:
            try: command=shlex.split(bits[6])
            except ValueError: continue
            if command and command[0]==str(exe):
                try: found.append({'pid':int(bits[0]),'startIdentity':' '.join(bits[1:6])})
                except ValueError: pass
    return found
def app_map(app: Path, executable: str):
    files=tree_map(app)
    return {k:v for k,v in files.items() if k not in {'Info.plist','PkgInfo',executable}}, files

def validate_seal(expected_sha: str):
    if str(ROOT) != '/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg': raise RuntimeError('wrong fixed worktree')
    if SEAL_PATH.is_symlink() or not SEAL_PATH.is_file() or sha_file(SEAL_PATH)!=expected_sha: raise RuntimeError('Root runtime seal is absent/unbound')
    seal=read_json(SEAL_PATH)
    if seal.get('schema')!='native-completion-r462-runtime-seal-v2' or seal.get('status')!='ROOT_SEALED_READY_TO_INSTALL': raise RuntimeError('runtime seal not ready')
    if seal.get('driverSHA256')!=sha_file(Path(__file__)) or seal.get('device')!=DEVICE or seal.get('bundleID')!=BUNDLE: raise RuntimeError('runtime driver/device/bundle pin mismatch')
    if seal.get('limits')!={'maxSeconds':MAX_SECONDS,'maxAdditionalBytes':MAX_BYTES,'requiredStartFreeBytes':START_FREE,'minimumFreeBytes':FREE_FLOOR,'maxScreenshots':SCREENSHOTS_MAX,'maxScreenshotBytes':SCREENSHOT_CAP,'maxEvidenceBytes':EVIDENCE_CAP,'automaticLaunch':False,'delete':False}: raise RuntimeError('runtime limits mismatch')
    build_path=rooted(seal['buildReceiptPath'])
    if str(build_path)!=str(ROOT/'docs/production/current/qa_drafts/native_completion_r462/build_tools_r002/BUILD_RESULT_R001.json') or sha_file(build_path)!=seal['buildReceiptSHA256']: raise RuntimeError('R462 build receipt path/hash mismatch')
    build=read_json(build_path)
    if build.get('status')!='BUILD_COMMANDS_PASS' or build.get('bundleIdentifier')!=BUNDLE or build.get('configuration')!='Release' or build.get('flags')!=FLAGS or build.get('install') is not False or build.get('launch') is not False: raise RuntimeError('R462 build receipt contract mismatch')
    packaged=build.get('packagedResourceMaps',{})
    if packaged.get('simulator')!=packaged.get('iphoneos') or len(packaged.get('simulator',{}))!=1922: raise RuntimeError('both R462 SDK products must carry the same exact 1,922 packaged resources')
    if seal.get('captureLabels')!=list(CAPTURE_LABELS): raise RuntimeError('R462 capture-label contract mismatch')
    if seal.get('r456RuntimeRunPath')!=str(R456_RUN) or sha_file(R456_RUN)!=seal.get('r456RuntimeRunSHA256'): raise RuntimeError('R456 runtime source receipt mismatch')
    r456run=read_json(R456_RUN)
    if r456run.get('status')!='CAPTURE_CLOSED_COLD_BYTES_EXACT' or r456run.get('bundleID')!=R456_BUNDLE: raise RuntimeError('R456 source run is not closed')
    if seal.get('r456BuildReceiptPath')!=r456run.get('buildReceiptPath') or seal.get('r456BuildReceiptSHA256')!=r456run.get('buildReceiptSHA256') or str(rooted(seal['r456BuildReceiptPath']))!=str(R456_BUILD) or sha_file(R456_BUILD)!=seal.get('r456BuildReceiptSHA256'): raise RuntimeError('R456 build receipt binding mismatch')
    oldbuild=read_json(R456_BUILD)
    if oldbuild.get('status')!='BUILD_COMMANDS_PASS' or oldbuild.get('bundleIdentifier')!=R456_BUNDLE or oldbuild.get('configuration')!='Release': raise RuntimeError('R456 Release build receipt is not valid')
    if seal.get('r456AppContainerPath')!=r456run.get('installedApp') or seal.get('r456DataContainerPath')!=r456run.get('dataContainer'): raise RuntimeError('R456 app/data container differs from closed runtime receipt')
    cold=next((x for x in r456run.get('checkpoints',[]) if x.get('label')=='cold'),None)
    if not cold or cold.get('saveFiles',{}).get('save.json',{}).get('sha256')!=seal.get('r456PrimarySaveSHA256') or cold.get('revision')!=138: raise RuntimeError('R456 final cold primary save pin/revision mismatch')
    if seal.get('r456PrimarySaveSHA256')!='3725e9c13d0e514804d5941d23b7847e12d7c13eb04aac0b3e676b190ae3a3c1': raise RuntimeError('R456 seed is not the Root-selected revision-138 save')
    seeds=seal.get('seedFiles')
    if not isinstance(seeds,list) or {x.get('name') for x in seeds}!=set(SEED_NAMES) or len(seeds)!=3: raise RuntimeError('exact three-file R456 seed set required')
    for row in seeds:
        if set(row)!={'name','path','sha256','sizeBytes'} or type(row['sizeBytes']) is not int or row['sizeBytes']<=0 or len(row['sha256'])!=64: raise RuntimeError('R456 seed row schema invalid')
    if next(x['sha256'] for x in seeds if x['name']=='save.json')!=seal['r456PrimarySaveSHA256']: raise RuntimeError('R456 primary seed file hash mismatch')
    containers=seal.get('protectedContainers')
    if not isinstance(containers,list) or len(containers)!=6 or {x.get('name') for x in containers}!={'r445App','r445Data','r454App','r454Data','r456App','r456Data'}: raise RuntimeError('must pin exactly all three older app/data containers')
    expected={'r445App':(R445_BUNDLE,'app'),'r445Data':(R445_BUNDLE,'data'),'r454App':(None,'app'),'r454Data':(None,'data'),'r456App':(R456_BUNDLE,'app'),'r456Data':(R456_BUNDLE,'data')}
    for row in containers:
        bundle,kind=expected[row['name']]
        if row.get('kind')!=kind or (bundle and row.get('bundleID')!=bundle) or not Path(row.get('path','')).is_absolute(): raise RuntimeError('protected container row mismatch')
    protected_by_name={row['name']:row for row in containers}
    if protected_by_name['r456App']['path']!=seal['r456AppContainerPath'] or protected_by_name['r456Data']['path']!=seal['r456DataContainerPath']: raise RuntimeError('R456 protected-container rows differ from source run')
    origin_path=rooted(seal['r454OriginPath'])
    if str(origin_path)!=str(R454_ORIGIN) or sha_file(origin_path)!=seal['r454OriginSHA256']: raise RuntimeError('R454 origin pin mismatch')
    origin=read_json(origin_path)
    if origin.get('allAppFilesMatch') is not True or origin.get('coldRelaunch') is not True: raise RuntimeError('R454 origin is not a closed verified install record')
    if protected_by_name['r454App']['path']!=origin.get('appContainer') or protected_by_name['r454Data']['path']!=origin.get('dataContainer'): raise RuntimeError('R454 protected-container rows do not match origin')
    if protected_by_name['r454App']['bundleID']!=plistlib.loads((Path(origin['appContainer'])/'Info.plist').read_bytes()).get('CFBundleIdentifier'): raise RuntimeError('R454 protected bundle ID mismatch')
    if seal.get('r445PreviousBaselinePath')!=str(R456_RUN) or seal.get('r445PreviousBaselineSHA256')!=seal.get('r456RuntimeRunSHA256'): raise RuntimeError('prior R445/R454 baseline must be the exact R456 run receipt')
    baseline=r456run.get('protectedBaseline',{})
    expected_old_paths={x['path'] for x in containers if x['name'] in ('r445App','r445Data','r454App','r454Data')}
    if set(baseline)!=expected_old_paths: raise RuntimeError('R456 closed baseline does not enumerate exact R445/R454 trees')
    for row in seeds:
        path=seed_source_path(row['path'],seal)
        expected_support=Path(seal['r456DataContainerPath'])/APP_SUPPORT
        if path.parent!=expected_support or path.name!=row['name'] or path.is_symlink() or not path.is_file(): raise RuntimeError('R456 seed source path invalid')
        if sha_file(path)!=row['sha256'] or path.stat().st_size!=row['sizeBytes']: raise RuntimeError('R456 seed source hash/size mismatch')
    if read_json(Path(next(x['path'] for x in seeds if x['name']=='save.json'))).get('snapshot',{}).get('revision')!=138: raise RuntimeError('R456 source save revision is not 138')
    return seal,build,r456run,seeds

def validate_build_product(build,seal):
    app=rooted(build['products']['simulator']['app'])
    exe=rooted(build['products']['simulator']['executable'])
    plist=plistlib.loads((app/'Info.plist').read_bytes())
    if plist.get('CFBundleIdentifier')!=BUNDLE: raise RuntimeError('Simulator product plist mismatch')
    exe_name=plist.get('CFBundleExecutable')
    if exe.name!=exe_name or sha_file(exe)!=build['products']['simulator']['executableSHA256']: raise RuntimeError('Simulator executable pin mismatch')
    resources,files=app_map(app,exe_name)
    expected=build.get('packagedResourceMaps',{}).get('simulator')
    if resources!=expected or len(resources)!=1922 or len(files)!=1925: raise RuntimeError('R462 app resource set does not match sealed 1,922-file build output')
    return app,exe,resources,files

def protected_snapshot(seal, r456run):
    rows={}
    prior=r456run.get('protectedBaseline',{})
    for item in seal['protectedContainers']:
        name=item['name']; kind=item['kind']; bundle=item['bundleID']; p=Path(item['path']).resolve(strict=True)
        actual=app_container(bundle,kind)
        if actual is None or actual!=p: raise RuntimeError(f'{name} path no longer matches simctl')
        current=tree_map(p)
        if name in ('r445App','r445Data','r454App','r454Data'):
            if current!=prior.get(str(p)): raise RuntimeError(f'{name} differs from its R456-closed baseline')
        elif name=='r456App':
            info=plistlib.loads((p/'Info.plist').read_bytes()); exe=info.get('CFBundleExecutable')
            oldbuild=read_json(R456_BUILD); expected=oldbuild.get('packagedResourceMaps',{}).get('simulator')
            resources,allfiles=app_map(p,exe)
            if resources!=expected or len(resources)!=1922 or sha_file(p/exe)!=oldbuild['products']['simulator']['executableSHA256']:
                raise RuntimeError('R456 installed app differs from its exact closed Release product')
        rows[str(p)]=current
    return rows

def file_snapshot(support: Path, out: Path):
    out.mkdir(parents=True,exist_ok=False)
    row={}
    for name in SEED_NAMES:
        src=support/name
        if src.is_symlink() or not src.is_file(): raise RuntimeError('required save file missing/unsafe: '+name)
        b1=src.read_bytes(); time.sleep(.05); b2=src.read_bytes()
        if sha_bytes(b1)!=sha_bytes(b2): raise RuntimeError('save changed during read: '+name)
        dest=out/name
        with dest.open('xb') as f: f.write(b1); f.flush(); os.fsync(f.fileno())
        row[name]={'sha256':sha_bytes(b1),'sizeBytes':len(b1)}
    save=read_json(out/'save.json')
    row['revision']=save.get('snapshot',{}).get('revision')
    return row

def elapsed_seconds(started_epoch_ns: int, now_epoch_ns: Optional[int] = None) -> float:
    if type(started_epoch_ns) is not int or started_epoch_ns < 0:
        raise RuntimeError('invalid persisted epoch start time')
    now = time.time_ns() if now_epoch_ns is None else now_epoch_ns
    if type(now) is not int or now < started_epoch_ns:
        raise RuntimeError('wall clock moved backward; runtime bound cannot be verified')
    return (now-started_epoch_ns)/1e9

def resource_budget(run_dir: Path, started_free: int, started_epoch_ns: int):
    elapsed=elapsed_seconds(started_epoch_ns)
    total=0
    for p in run_dir.rglob('*'):
        if p.is_symlink(): raise RuntimeError('capture output contains symlink')
        if p.is_file(): total += p.stat().st_blocks*512
    free=shutil.disk_usage(ROOT).free
    evidence=0
    for p in (run_dir/'checkpoints').rglob('screen.png') if (run_dir/'checkpoints').exists() else []:
        if p.is_symlink(): raise RuntimeError('screenshot evidence contains symlink')
        evidence += p.stat().st_blocks*512
    if elapsed>MAX_SECONDS or total>MAX_BYTES or started_free-free>MAX_BYTES or free<FREE_FLOOR or evidence>EVIDENCE_CAP: raise RuntimeError('R462 runtime time/storage bound exceeded')
    return {'elapsedSeconds':elapsed,'runAllocatedBytes':total,'screenshotAllocatedBytes':evidence,'freeBytes':free}

def verify_protected_trees(baseline, seal, r456run):
    for row in seal['protectedContainers']:
        if row['kind']!='app': continue
        app=Path(row['path']); info=plistlib.loads((app/'Info.plist').read_bytes())
        if running_exe(app/info['CFBundleExecutable']): raise RuntimeError(row['name']+' app started during R462 runtime capture')
    if protected_snapshot(seal,r456run)!=baseline: raise RuntimeError('an older R445/R454/R456 app/data tree changed')
    return True

def install(args):
    started=time.time_ns()
    start_free=shutil.disk_usage(ROOT).free
    if start_free<START_FREE: raise RuntimeError('required 15 GB starting free space not available')
    seal,build,r456run,seeds=validate_seal(args.seal_sha256)
    app,exe,resources,files=validate_build_product(build,seal)
    device_list=json.loads(run(['xcrun','simctl','list','devices','--json']))
    booted={d.get('udid') for group in device_list.get('devices',{}).values() for d in group if d.get('state')=='Booted'}
    if DEVICE not in booted: raise RuntimeError('R462 target Simulator is not booted')
    if running_exe(exe): raise RuntimeError('R462 executable already running')
    
    r445_app=app_container(R445_BUNDLE,'app'); r445_data=app_container(R445_BUNDLE,'data')
    if r445_app is None or r445_data is None: raise RuntimeError('R445 source install/data missing')
    protected={row['name']:row for row in seal['protectedContainers']}
    for name,row in protected.items():
        current=app_container(row['bundleID'],row['kind'])
        if current is None or str(current)!=row['path']: raise RuntimeError(name+' container differs from Root seal')
        protected_app=Path(row['path'])
        if row['kind']=='app':
            info=plistlib.loads((protected_app/'Info.plist').read_bytes())
            if running_exe(protected_app/info['CFBundleExecutable']): raise RuntimeError(name+' source app must be stopped before seeding')
    if app_container(BUNDLE,'app') is not None or app_container(BUNDLE,'data') is not None: raise RuntimeError('R462 bundle is already installed; refusing overwrite')
    r456_support=Path(seal['r456DataContainerPath'])/APP_SUPPORT
    source_files={}
    for row in seeds:
        src=seed_source_path(row['path'],seal)
        if src.parent!=r456_support or src.name!=row['name'] or src.is_symlink() or not src.is_file(): raise RuntimeError('R456 seed source path invalid')
        if sha_file(src)!=row['sha256'] or src.stat().st_size!=row['sizeBytes']: raise RuntimeError('R456 seed file hash/size mismatch')
        source_files[row['name']]=src
    if read_json(source_files['save.json']).get('snapshot',{}).get('revision')!=138: raise RuntimeError('R456 primary save revision mismatch')
    baseline=protected_snapshot(seal,r456run)
    if set(baseline)!={row['path'] for row in seal['protectedContainers']}: raise RuntimeError('all six R445/R454/R456 trees must be protected')
    run_dir=run_directory(args.run_id)
    if run_dir.exists(): raise RuntimeError('run ID already used')
    runs_parent=BASE/'runs'
    if runs_parent.is_symlink(): raise RuntimeError('runs parent is symlinked')
    runs_parent.mkdir(exist_ok=True)
    run_dir.mkdir(parents=True,exist_ok=False)
    receipt={'schema':'r462-runtime-capture-v1','status':'INSTALLING_NO_LAUNCH','runID':args.run_id,'bundleID':BUNDLE,'device':DEVICE,'buildReceiptPath':seal['buildReceiptPath'],'buildReceiptSHA256':seal['buildReceiptSHA256'],'r454OriginSHA256':seal['r454OriginSHA256'],'r456RuntimeRunSHA256':seal['r456RuntimeRunSHA256'],'r456SeedSource':{n:{'path':str(p),'sha256':sha_file(p)} for n,p in source_files.items()},'r456SeedRevision':138,'protectedBaseline':baseline,'startedFreeBytes':start_free,'startedEpochNS':started,'checkpoints':[]}
    atomic_json(run_dir/'RUN.json',receipt)
    lock=(run_dir/'RUN.lock').open('x+'); fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    try:
        run(['xcrun','simctl','install',DEVICE,str(app)],timeout=120)
        installed=app_container(BUNDLE,'app'); data=app_container(BUNDLE,'data')
        if installed is None or data is None or str(installed) in baseline or str(data) in baseline: raise RuntimeError('fresh R462 app/data containers not created uniquely')
        if tree_map(installed)!=files: raise RuntimeError('installed app differs from exact built Simulator product')
        if running_exe(installed/plistlib.loads((installed/'Info.plist').read_bytes())['CFBundleExecutable']): raise RuntimeError('simctl install unexpectedly launched R462')
        support=data/APP_SUPPORT
        if support.exists() or support.is_symlink(): raise RuntimeError('R462 app support namespace already exists; refuse overwrite')
        support.mkdir(parents=True,exist_ok=False)
        seeded={}
        for name,src in source_files.items():
            dest=support/name
            run(['/bin/cp','-c','-p',str(src),str(dest)],timeout=30)
            if dest.is_symlink() or not dest.is_file() or sha_file(dest)!=sha_file(src): raise RuntimeError('APFS clone verification failed: '+name)
            seeded[name]={'sha256':sha_file(dest),'sizeBytes':dest.stat().st_size}
        if not verify_protected_trees(baseline,seal,r456run): raise RuntimeError('protected tree failure')
        bounds=resource_budget(run_dir,start_free,started)
        receipt.update({'status':'INSTALLED_SEEDED_APP_NOT_LAUNCHED','installedApp':str(installed),'dataContainer':str(data),'supportDirectory':str(support),'seededFiles':seeded,'protectedUnchanged':True,'bounds':bounds,'coldBaseline':None})
        atomic_json(run_dir/'RUN.json',receipt)
        receipt['boundsAfterReceipt']=resource_budget(run_dir,start_free,started)
        atomic_json(run_dir/'RUN.json',receipt)
    except BaseException as e:
        try: unchanged=verify_protected_trees(baseline,seal,r456run)
        except BaseException: unchanged=False
        receipt.update({'status':'INSTALL_HOLD_RETAINED','errorType':type(e).__name__,'error':str(e),'protectedUnchanged':unchanged})
        atomic_json(run_dir/'RUN.json',receipt)
        raise
    finally: lock.close()

def checkpoint(args):
    seal,build,r456run,seeds=validate_seal(args.seal_sha256)
    run_dir=run_directory(args.run_id)
    if not run_dir.is_dir() or run_dir.is_symlink(): raise RuntimeError('R462 run directory missing')
    lock=(run_dir/'RUN.lock').open('a+')
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    try:
        r=read_json(run_dir/'RUN.json')
        if r['status'] not in ('INSTALLED_SEEDED_APP_NOT_LAUNCHED','CAPTURING'): raise RuntimeError('runtime run is not open for checkpoints')
        if r['buildReceiptSHA256']!=seal['buildReceiptSHA256']: raise RuntimeError('run/build pin mismatch')
        if args.label not in CAPTURE_LABELS: raise RuntimeError('unknown checkpoint label')
        ordered=[x['label'] for x in r['checkpoints']]
        expected_index=len(ordered)
        if expected_index>=len(CAPTURE_LABELS) or args.label!=CAPTURE_LABELS[expected_index]:
            raise RuntimeError('checkpoint labels must follow the sealed home → no-match → cleared → cold sequence')
        if any(x['label']==args.label for x in r['checkpoints']): raise RuntimeError('checkpoint label already captured')
        if len([x for x in r['checkpoints'] if x.get('screenshot')])>=SCREENSHOTS_MAX and args.screenshot: raise RuntimeError('four screenshot cap reached')
        started_epoch_ns=r['startedEpochNS']; start_free=r['startedFreeBytes']; bounds=resource_budget(run_dir,start_free,started_epoch_ns)
        baseline=r['protectedBaseline']; verify_protected_trees(baseline,seal,r456run)
        data=Path(r['dataContainer']); support=data/APP_SUPPORT
        app=app_container(BUNDLE,'app'); actual_data=app_container(BUNDLE,'data')
        if app is None or actual_data!=data: raise RuntimeError('R462 app/data container identity changed')
        info=plistlib.loads((app/'Info.plist').read_bytes()); exe=app/info['CFBundleExecutable']
        pids=running_exe(exe)
        if len(pids)!=1: raise RuntimeError('expected one currently running R462 app process')
        cp=run_dir/'checkpoints'/args.label; cp.mkdir(parents=True,exist_ok=False)
        image=None
        if args.screenshot:
            image=cp/'screen.png'
            run(['xcrun','simctl','io',DEVICE,'screenshot',str(image)],timeout=30)
            if image.stat().st_size>SCREENSHOT_CAP: raise RuntimeError('single screenshot exceeds 20 MB cap')
        files=file_snapshot(support,cp/'files')
        if files['revision'] != 138: raise RuntimeError('read-only inventory filter flow changed the seeded revision-138 save')
        for name in ('save.json','save.json.previous'):
            if files[name]['sha256'] != r['seededFiles'][name]['sha256']: raise RuntimeError('read-only search/filter scope changed '+name)
        row={'label':args.label,'capturedAt':time.time(),'revision':files['revision'],'saveFiles':files,'processIdentity':pids[0],'appExecutable':str(exe),'screenshot':str(image) if image else None,'screenshotSHA256':sha_file(image) if image else None,'bounds':resource_budget(run_dir,start_free,started_epoch_ns),'protectedUnchanged':True}
        if args.label=='before_cold': r['coldBaseline']={n:v['sha256'] for n,v in files.items() if isinstance(v,dict)}
        if args.label=='cold':
            prior=next((x for x in r['checkpoints'] if x['label']=='before_cold'),None)
            if prior is None: raise RuntimeError('before_cold checkpoint required before cold comparison')
            if prior['processIdentity']==pids[0]: raise RuntimeError('cold app process was not restarted between checkpoints')
            for name in ('save.json','save.json.previous'):
                if prior['saveFiles'][name]['sha256']!=files[name]['sha256']: raise RuntimeError('save bytes changed across cold relaunch: '+name)
            row['coldSaveBytesExact']=True
        r['checkpoints'].append(row); r['status']='CAPTURING'
        if sum(Path(x['screenshot']).stat().st_size for x in r['checkpoints'] if x.get('screenshot'))>EVIDENCE_CAP: raise RuntimeError('aggregate screenshot bytes exceed 40 MB')
        verify_protected_trees(baseline,seal,r456run)
        atomic_json(run_dir/'RUN.json',r)
        resource_budget(run_dir,start_free,started_epoch_ns)
    finally: lock.close()

def finish(args):
    seal,_,r456run,_=validate_seal(args.seal_sha256)
    run_dir=run_directory(args.run_id)
    lock=(run_dir/'RUN.lock').open('a+')
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    try:
        r=read_json(run_dir/'RUN.json')
        labels={x['label'] for x in r['checkpoints']}
        if labels!=set(CAPTURE_LABELS): raise RuntimeError('home, no-match, cleared-filter, and cold byte checkpoints incomplete')
        verify_protected_trees(r['protectedBaseline'],seal,r456run)
        bounds=resource_budget(run_dir,r['startedFreeBytes'],r['startedEpochNS'])
        r.update({'status':'CAPTURE_CLOSED_FILTER_GUIDANCE_COLD_SAVES_EXACT','finishedAt':time.time(),'finalBounds':bounds,'protectedUnchanged':True,'automaticLaunch':False,'deleted':False})
        atomic_json(run_dir/'RUN.json',r)
        r['finalBoundsAfterReceipt']=resource_budget(run_dir,r['startedFreeBytes'],r['startedEpochNS'])
        verify_protected_trees(r['protectedBaseline'],seal,r456run)
        atomic_json(run_dir/'RUN.json',r)
    finally: lock.close()

def main():
    p=argparse.ArgumentParser(); p.add_argument('action',choices=('install','checkpoint','finish')); p.add_argument('--seal-sha256',required=True); p.add_argument('--run-id',required=True); p.add_argument('--label'); p.add_argument('--screenshot',action='store_true')
    a=p.parse_args()
    try:
        if a.action=='install': install(a)
        elif a.action=='checkpoint':
            if not a.label: raise RuntimeError('--label required for checkpoint')
            if a.label=='before_cold' and a.screenshot: raise RuntimeError('before_cold is a save-only checkpoint')
            if a.label!='before_cold' and not a.screenshot: raise RuntimeError('visible checkpoints require screenshot evidence')
            checkpoint(a)
        else: finish(a)
    except BaseException as exc:
        try: run_dir=run_directory(a.run_id)
        except Exception: run_dir=None
        if run_dir is not None and run_dir.is_dir() and not run_dir.is_symlink() and (run_dir/'RUN.json').is_file():
            try:
                partial=read_json(run_dir/'RUN.json')
                partial['status']='HOLD_RETAINED'
                partial['lastError']={'type':type(exc).__name__,'message':str(exc)}
                atomic_json(run_dir/'RUN.json',partial)
            except BaseException: pass
        raise
if __name__=='__main__': main()

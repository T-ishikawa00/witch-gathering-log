#!/usr/bin/env python3
"""R456 install + bounded manual checkpoint recorder. Draft only; Root operates it."""
from __future__ import annotations
import argparse, fcntl, hashlib, json, os, plistlib, shlex, shutil, subprocess, time, uuid
from pathlib import Path

ROOT = Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
BASE = Path(__file__).resolve().parent
SEAL_PATH = BASE / 'RUNTIME_SEAL_R001.json'
DEVICE = '9A067715-7CF3-40D3-9064-38423223959B'
BUNDLE = 'local.witch.autonomous.r1.completion.r456'
R445_BUNDLE = 'local.witch.autonomous.r1.completion.r445'
R454_ORIGIN = ROOT / 'docs/production/current/qa_drafts/storekit_event_export_r454/runtime_r001/INSTALLED_ORIGIN_R004.json'
MAX_SECONDS, MAX_BYTES, START_FREE, FREE_FLOOR = 600, 500_000_000, 22_000_000_000, 20_000_000_000
SCREENSHOT_CAP, SCREENSHOTS_MAX = 15_000_000, 4
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
def run_directory(run_id: str) -> Path:
    try:
        if str(uuid.UUID(run_id))!=run_id: raise ValueError('noncanonical UUID')
    except (ValueError, AttributeError):
        raise RuntimeError('run ID must be a canonical UUID')
    parent=BASE/'runs'
    if parent.is_symlink(): raise RuntimeError('runs output parent is symlinked')
    p=parent/run_id
    if p.is_symlink() or not p.resolve().is_relative_to(parent.resolve()): raise RuntimeError('run path escapes R456 runtime output')
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
    p=subprocess.run(['xcrun','simctl','get_app_container',DEVICE,bundle,kind],capture_output=True,text=True)
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
    if seal.get('schema')!='native-completion-r456-runtime-seal-v1' or seal.get('status')!='ROOT_SEALED_READY_TO_INSTALL': raise RuntimeError('runtime seal not ready')
    if seal.get('driverSHA256')!=sha_file(Path(__file__)) or seal.get('device')!=DEVICE or seal.get('bundleID')!=BUNDLE: raise RuntimeError('runtime driver/device/bundle pin mismatch')
    if seal.get('limits')!={'maxSeconds':MAX_SECONDS,'maxAdditionalBytes':MAX_BYTES,'requiredStartFreeBytes':START_FREE,'minimumFreeBytes':FREE_FLOOR,'maxScreenshots':SCREENSHOTS_MAX,'maxScreenshotBytes':SCREENSHOT_CAP,'automaticLaunch':False,'delete':False}: raise RuntimeError('runtime limits mismatch')
    build_path=rooted(seal['buildReceiptPath'])
    if sha_file(build_path)!=seal['buildReceiptSHA256']: raise RuntimeError('R456 build receipt hash mismatch')
    build=read_json(build_path)
    if build.get('status')!='BUILD_COMMANDS_PASS' or build.get('bundleIdentifier')!=BUNDLE or build.get('configuration')!='Release' or build.get('flags')!=FLAGS or build.get('install') is not False or build.get('launch') is not False: raise RuntimeError('R456 build receipt contract mismatch')
    packaged=build.get('packagedResourceMaps',{})
    if packaged.get('simulator')!=packaged.get('iphoneos') or len(packaged.get('simulator',{}))!=1922: raise RuntimeError('both SDK products must carry the same exact 1,922 packaged resources')
    origin_path=rooted(seal['r454OriginPath'])
    if str(origin_path)!=str(R454_ORIGIN) or sha_file(origin_path)!=seal['r454OriginSHA256']: raise RuntimeError('R454 origin pin mismatch')
    origin=read_json(origin_path)
    if origin.get('allAppFilesMatch') is not True or origin.get('coldRelaunch') is not True: raise RuntimeError('R454 origin is not a closed verified install record')
    if seal.get('r454OriginBuildReceiptSHA256')!=origin.get('buildReceiptSHA256'): raise RuntimeError('R454 origin build receipt differs from Root seal')
    r454_save=Path(origin['dataContainer'])/APP_SUPPORT/'save.json'
    if not r454_save.is_file() or sha_file(r454_save)!=origin.get('preservedSaveSHA256'): raise RuntimeError('R454 preserved save no longer matches installed origin receipt')
    if seal.get('r445BundleID')!=R445_BUNDLE or seal.get('r445SeedRevision')!=137: raise RuntimeError('R445 source seed identity/revision mismatch')
    seed=seal.get('seedFiles')
    if not isinstance(seed,list) or {x.get('name') for x in seed}!=set(SEED_NAMES) or len(seed)!=3: raise RuntimeError('exact three-file R445 seed set required')
    for row in seed:
        if set(row)!={'name','path','sha256','sizeBytes'} or type(row['sizeBytes']) is not int or row['sizeBytes']<=0: raise RuntimeError('R445 seed row schema invalid')
    if seal.get('r445PrimarySaveSHA256')!=next(x['sha256'] for x in seed if x['name']=='save.json'): raise RuntimeError('R445 primary save hash differs from explicit Root pin')
    return seal,build,origin,seed

def validate_build_product(build,seal):
    app=rooted(build['products']['simulator']['app'])
    exe=rooted(build['products']['simulator']['executable'])
    plist=plistlib.loads((app/'Info.plist').read_bytes())
    if plist.get('CFBundleIdentifier')!=BUNDLE or 'SKIncludeConsumableInAppPurchaseHistory' in plist: raise RuntimeError('Simulator product plist mismatch')
    exe_name=plist.get('CFBundleExecutable')
    if exe.name!=exe_name or sha_file(exe)!=build['products']['simulator']['executableSHA256']: raise RuntimeError('Simulator executable pin mismatch')
    resources,files=app_map(app,exe_name)
    expected=build.get('packagedResourceMaps',{}).get('simulator')
    if resources!=expected or len(resources)!=1922 or len(files)!=1925: raise RuntimeError('R456 app resource set does not match sealed 1,922-file build output')
    return app,exe,resources,files

def protected_snapshot():
    rows={}
    for bundle in (R445_BUNDLE,):
        for kind in ('app','data'):
            p=app_container(bundle,kind)
            if p is None: raise RuntimeError(f'prior R445 {kind} container missing')
            rows[str(p)]=tree_map(p)
    origin=read_json(R454_ORIGIN)
    r454_bundle=seal_bundle_from_origin(origin)
    for label in ('appContainer','dataContainer'):
        p=Path(origin[label]).resolve(strict=True)
        actual=app_container(r454_bundle, 'app' if label=='appContainer' else 'data')
        if actual is None or actual!=p: raise RuntimeError('R454 origin container no longer matches simctl')
        rows[str(p)]=tree_map(p)
    return rows

def seal_bundle_from_origin(origin):
    app=Path(origin['appContainer'])
    info=plistlib.loads((app/'Info.plist').read_bytes())
    return info['CFBundleIdentifier']

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

def resource_budget(run_dir: Path, started_free: int, started_ns: int):
    elapsed=(time.monotonic_ns()-started_ns)/1e9
    total=0
    for p in run_dir.rglob('*'):
        if p.is_symlink(): raise RuntimeError('capture output contains symlink')
        if p.is_file(): total += p.stat().st_blocks*512
    free=shutil.disk_usage(ROOT).free
    if elapsed>MAX_SECONDS or total>MAX_BYTES or started_free-free>MAX_BYTES or free<FREE_FLOOR: raise RuntimeError('R456 runtime time/storage bound exceeded')
    return {'elapsedSeconds':elapsed,'runAllocatedBytes':total,'freeBytes':free}

def verify_old_trees(baseline):
    origin=read_json(R454_ORIGIN)
    r445_app=app_container(R445_BUNDLE,'app')
    if r445_app is None: raise RuntimeError('R445 app container disappeared')
    r445_info=plistlib.loads((r445_app/'Info.plist').read_bytes())
    if running_exe(r445_app/r445_info['CFBundleExecutable']): raise RuntimeError('R445 app started during R456 runtime capture')
    r454_app=Path(origin['appContainer'])
    r454_info=plistlib.loads((r454_app/'Info.plist').read_bytes())
    if running_exe(r454_app/r454_info['CFBundleExecutable']): raise RuntimeError('R454 app started during R456 runtime capture')
    now=protected_snapshot()
    if now!=baseline: raise RuntimeError('R445/R454 protected app/data tree changed')
    return True

def install(args):
    started=time.monotonic_ns()
    start_free=shutil.disk_usage(ROOT).free
    if start_free<START_FREE: raise RuntimeError('required 22 GB starting free space not available')
    seal,build,origin,seeds=validate_seal(args.seal_sha256)
    app,exe,resources,files=validate_build_product(build,seal)
    device_list=json.loads(run(['xcrun','simctl','list','devices','--json']))
    booted={d.get('udid') for group in device_list.get('devices',{}).values() for d in group if d.get('state')=='Booted'}
    if DEVICE not in booted: raise RuntimeError('R456 target Simulator is not booted')
    if running_exe(exe): raise RuntimeError('R456 executable already running')
    if running_exe(Path(origin['appContainer'])/plistlib.loads((Path(origin['appContainer'])/'Info.plist').read_bytes())['CFBundleExecutable']): raise RuntimeError('R454 app is running')
    r445_app=app_container(R445_BUNDLE,'app'); r445_data=app_container(R445_BUNDLE,'data')
    if r445_app is None or r445_data is None: raise RuntimeError('R445 source install/data missing')
    if str(r445_app)!=seal.get('r445AppContainerPath') or str(r445_data)!=seal.get('r445DataContainerPath'): raise RuntimeError('R445 container differs from Root seal')
    r445_info=plistlib.loads((r445_app/'Info.plist').read_bytes())
    if running_exe(r445_app/r445_info['CFBundleExecutable']): raise RuntimeError('R445 source app must be stopped before seeding')
    if app_container(BUNDLE,'app') is not None or app_container(BUNDLE,'data') is not None: raise RuntimeError('R456 bundle is already installed; refusing overwrite')
    r445_support=r445_data/APP_SUPPORT
    source_files={}
    for row in seeds:
        raw_src=Path(row['path'])
        if not raw_src.is_absolute() or raw_src.is_symlink(): raise RuntimeError('R445 seed path must be absolute and nonsymlinked')
        src=raw_src.resolve(strict=True)
        if (not src.is_relative_to(r445_support.resolve(strict=True)) or sha_file(src)!=row['sha256']
                or src.stat().st_size!=row['sizeBytes']): raise RuntimeError('R445 seed file path/hash/size mismatch')
        source_files[row['name']]=src
    if source_files['save.json'].name!='save.json' or read_json(source_files['save.json']).get('snapshot',{}).get('revision')!=137: raise RuntimeError('R445 primary save revision mismatch')
    baseline=protected_snapshot()
    if str(r445_app) not in baseline or str(r445_data) not in baseline: raise RuntimeError('R445 tree baseline missing')
    r454_app=Path(origin['appContainer']).resolve(strict=True); r454_data=Path(origin['dataContainer']).resolve(strict=True)
    if str(r454_app) not in baseline or str(r454_data) not in baseline: raise RuntimeError('R454 tree baseline missing')
    run_dir=run_directory(args.run_id)
    if run_dir.exists(): raise RuntimeError('run ID already used')
    runs_parent=BASE/'runs'
    if runs_parent.is_symlink(): raise RuntimeError('runs parent is symlinked')
    runs_parent.mkdir(exist_ok=True)
    run_dir.mkdir(parents=True,exist_ok=False)
    receipt={'schema':'r456-runtime-capture-v1','status':'INSTALLING_NO_LAUNCH','runID':args.run_id,'bundleID':BUNDLE,'device':DEVICE,'buildReceiptPath':seal['buildReceiptPath'],'buildReceiptSHA256':seal['buildReceiptSHA256'],'r454OriginSHA256':seal['r454OriginSHA256'],'r445SeedSource':{n:{'path':str(p),'sha256':sha_file(p)} for n,p in source_files.items()},'r445SeedRevision':137,'protectedBaseline':baseline,'startedFreeBytes':start_free,'startedMonotonicNS':started,'checkpoints':[]}
    atomic_json(run_dir/'RUN.json',receipt)
    lock=(run_dir/'RUN.lock').open('x+'); fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    try:
        run(['xcrun','simctl','install',DEVICE,str(app)],timeout=120)
        installed=app_container(BUNDLE,'app'); data=app_container(BUNDLE,'data')
        if installed is None or data is None or str(installed) in baseline or str(data) in baseline: raise RuntimeError('fresh R456 app/data containers not created uniquely')
        if tree_map(installed)!=files: raise RuntimeError('installed app differs from exact built Simulator product')
        if running_exe(installed/plistlib.loads((installed/'Info.plist').read_bytes())['CFBundleExecutable']): raise RuntimeError('simctl install unexpectedly launched R456')
        support=data/APP_SUPPORT
        if support.exists() or support.is_symlink(): raise RuntimeError('R456 app support namespace already exists; refuse overwrite')
        support.mkdir(parents=True,exist_ok=False)
        seeded={}
        for name,src in source_files.items():
            dest=support/name
            run(['/bin/cp','-c','-p',str(src),str(dest)],timeout=30)
            if dest.is_symlink() or not dest.is_file() or sha_file(dest)!=sha_file(src): raise RuntimeError('APFS clone verification failed: '+name)
            seeded[name]={'sha256':sha_file(dest),'sizeBytes':dest.stat().st_size}
        if not verify_old_trees(baseline): raise RuntimeError('protected tree failure')
        bounds=resource_budget(run_dir,start_free,started)
        receipt.update({'status':'INSTALLED_SEEDED_APP_NOT_LAUNCHED','installedApp':str(installed),'dataContainer':str(data),'supportDirectory':str(support),'seededFiles':seeded,'protectedUnchanged':True,'bounds':bounds,'coldBaseline':None})
        atomic_json(run_dir/'RUN.json',receipt)
        receipt['boundsAfterReceipt']=resource_budget(run_dir,start_free,started)
        atomic_json(run_dir/'RUN.json',receipt)
    except BaseException as e:
        try: unchanged=verify_old_trees(baseline)
        except BaseException: unchanged=False
        receipt.update({'status':'INSTALL_HOLD_RETAINED','errorType':type(e).__name__,'error':str(e),'protectedUnchanged':unchanged})
        atomic_json(run_dir/'RUN.json',receipt)
        raise
    finally: lock.close()

def checkpoint(args):
    seal,build,origin,seeds=validate_seal(args.seal_sha256)
    run_dir=run_directory(args.run_id)
    if not run_dir.is_dir() or run_dir.is_symlink(): raise RuntimeError('R456 run directory missing')
    lock=(run_dir/'RUN.lock').open('a+')
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    try:
        r=read_json(run_dir/'RUN.json')
        if r['status'] not in ('INSTALLED_SEEDED_APP_NOT_LAUNCHED','CAPTURING'): raise RuntimeError('runtime run is not open for checkpoints')
        if r['buildReceiptSHA256']!=seal['buildReceiptSHA256']: raise RuntimeError('run/build pin mismatch')
        if args.label not in ('launch','gear','battle','before_cold','cold'): raise RuntimeError('unknown checkpoint label')
        if any(x['label']==args.label for x in r['checkpoints']): raise RuntimeError('checkpoint label already captured')
        if len([x for x in r['checkpoints'] if x.get('screenshot')])>=SCREENSHOTS_MAX and args.screenshot: raise RuntimeError('four screenshot cap reached')
        started_ns=r['startedMonotonicNS']; start_free=r['startedFreeBytes']; bounds=resource_budget(run_dir,start_free,started_ns)
        baseline=r['protectedBaseline']; verify_old_trees(baseline)
        data=Path(r['dataContainer']); support=data/APP_SUPPORT
        app=app_container(BUNDLE,'app'); actual_data=app_container(BUNDLE,'data')
        if app is None or actual_data!=data: raise RuntimeError('R456 app/data container identity changed')
        info=plistlib.loads((app/'Info.plist').read_bytes()); exe=app/info['CFBundleExecutable']
        pids=running_exe(exe)
        if len(pids)!=1: raise RuntimeError('expected one currently running R456 app process')
        cp=run_dir/'checkpoints'/args.label; cp.mkdir(parents=True,exist_ok=False)
        image=None
        if args.screenshot:
            image=cp/'screen.png'
            run(['xcrun','simctl','io',DEVICE,'screenshot',str(image)],timeout=30)
            if image.stat().st_size>SCREENSHOT_CAP: raise RuntimeError('single screenshot exceeds 15 MB cap')
        files=file_snapshot(support,cp/'files')
        row={'label':args.label,'capturedAt':time.time(),'revision':files['revision'],'saveFiles':files,'processIdentity':pids[0],'appExecutable':str(exe),'screenshot':str(image) if image else None,'screenshotSHA256':sha_file(image) if image else None,'bounds':resource_budget(run_dir,start_free,started_ns),'protectedUnchanged':True}
        if args.label=='before_cold': r['coldBaseline']={n:v['sha256'] for n,v in files.items() if isinstance(v,dict)}
        if args.label=='cold':
            prior=next((x for x in r['checkpoints'] if x['label']=='before_cold'),None)
            if prior is None: raise RuntimeError('before_cold checkpoint required before cold comparison')
            if prior['processIdentity']==pids[0]: raise RuntimeError('cold app process was not restarted between checkpoints')
            for name in ('save.json','save.json.previous'):
                if prior['saveFiles'][name]['sha256']!=files[name]['sha256']: raise RuntimeError('save bytes changed across cold relaunch: '+name)
            row['coldSaveBytesExact']=True
        r['checkpoints'].append(row); r['status']='CAPTURING'
        if sum(Path(x['screenshot']).stat().st_size for x in r['checkpoints'] if x.get('screenshot'))>SCREENSHOT_CAP: raise RuntimeError('aggregate screenshot bytes exceed 15 MB')
        verify_old_trees(baseline)
        atomic_json(run_dir/'RUN.json',r)
        resource_budget(run_dir,start_free,started_ns)
    finally: lock.close()

def finish(args):
    seal,_,_,_=validate_seal(args.seal_sha256)
    run_dir=run_directory(args.run_id)
    lock=(run_dir/'RUN.lock').open('a+')
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    try:
        r=read_json(run_dir/'RUN.json')
        labels={x['label'] for x in r['checkpoints']}
        if not {'launch','before_cold','cold'}.issubset(labels): raise RuntimeError('launch and cold byte checkpoints incomplete')
        verify_old_trees(r['protectedBaseline'])
        bounds=resource_budget(run_dir,r['startedFreeBytes'],r['startedMonotonicNS'])
        r.update({'status':'CAPTURE_CLOSED_COLD_BYTES_EXACT','finishedAt':time.time(),'finalBounds':bounds,'protectedUnchanged':True,'automaticLaunch':False,'deleted':False})
        atomic_json(run_dir/'RUN.json',r)
        r['finalBoundsAfterReceipt']=resource_budget(run_dir,r['startedFreeBytes'],r['startedMonotonicNS'])
        verify_old_trees(r['protectedBaseline'])
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

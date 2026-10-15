#!/usr/bin/env python3
"""Prepared only: direct-XCTest R362 completion using the existing sealed bundle; no build."""
from __future__ import annotations
import datetime as dt, hashlib, json, os, re, shutil, signal, subprocess, sys, time, uuid
from pathlib import Path

ROOT=Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
BASE=ROOT/'docs/production/current/qa_drafts/save_crash_completion_r362'
INPUTS=BASE/'runner_r001/INPUT_MANIFEST_R001.json'
INPUT_SHA='388616de0070128dea2190713f804bd21645b989615cd46adda7d1fec94aa7f8'
OLD_RUN=BASE/'runner_root_r003/execution_r002/trial_001/RUN.json'
PACKAGE=BASE/'runner_root_r003/execution_r002/prepared/package'
SCRATCH=BASE/'runner_root_r003/execution_r002/scratch'
BUNDLE=SCRATCH/'arm64-apple-macosx/debug/WitchGameCorePackageTests.xctest'
TEST_EXE=BUNDLE/'Contents/MacOS/WitchGameCorePackageTests'
XCTEST_ALIAS=Path('/Applications/Xcode.app/Contents/Developer/usr/bin/xctest')
XCTEST_REAL=Path('/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Xcode/Agents/xctest')
OUT=BASE/'direct_completion_r001/execution_r001'
FILTER='WitchGameCoreTests.LoadoutCrashIntegrityR362Tests/testR342LoadoutPayloadCrashBoundary'
TOTAL=90; PHASE_LIMIT={'seed':20,'crash-child':45,'verify':20}; CAP=2_000_000; FLOOR=12_000_000_000; RESERVE=2_000_000_000

class Hold(RuntimeError): pass

def sha_bytes(b): return hashlib.sha256(b).hexdigest()
def sha_file(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()
def write_new(p,obj):
    data=(json.dumps(obj,sort_keys=True,ensure_ascii=False,indent=2)+'\n').encode(); fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    try: os.write(fd,data); os.fsync(fd)
    finally: os.close(fd)
def inventory(root):
    rows=[]
    for p in sorted(root.rglob('*')):
        if p.is_symlink(): raise Hold(f'protected symlink: {p}')
        if p.is_file():
            st=p.stat(); rows.append({'path':p.relative_to(root).as_posix(),'sizeBytes':st.st_size,'mode':st.st_mode&0o777,'mtimeNs':st.st_mtime_ns,'sha256':sha_file(p)})
    return rows
def ps_rows():
    out=subprocess.run(['/bin/ps','-axo','pid=,ppid=,pgid=,lstart=,command='],capture_output=True,text=True,timeout=5,check=True).stdout; rows=[]
    for line in out.splitlines():
        x=line.strip().split(None,8)
        if len(x)==9:
            try: rows.append({'pid':int(x[0]),'ppid':int(x[1]),'pgid':int(x[2]),'start':' '.join(x[3:8]),'command':x[8]})
            except ValueError: pass
    return rows
def descendants(rows,pid):
    by={}
    for r in rows: by.setdefault(r['ppid'],[]).append(r)
    got=[]; todo=[pid]; seen={pid}
    while todo:
        parent=todo.pop()
        for r in by.get(parent,[]):
            if r['pid'] not in seen: seen.add(r['pid']); got.append(r); todo.append(r['pid'])
    return got
def same(a,b): return bool(a and b and a['pid']==b['pid'] and a['start']==b['start'] and a['command']==b['command'])
def record_descendants(proc,observed):
    for row in descendants(ps_rows(),proc.pid): observed[row['pid']]=row

def output_size(root):
    total=0
    for p in root.rglob('*'):
        if p.is_symlink(): raise Hold(f'output symlink rejected: {p}')
        if p.is_file(): total+=p.stat().st_size
    return total

def owned_cleanup(proc,observed):
    rows=ps_rows(); owned={r['pid']:r for r in descendants(rows,proc.pid)}
    own=next((r for r in rows if r['pid']==proc.pid),None)
    if own: owned[own['pid']]=own
    for pid,r in observed.items():
        live=next((q for q in rows if same(q,r)),None)
        if live: owned[pid]=live
    actions=[]
    def current(row):
        q=next((x for x in ps_rows() if x['pid']==row['pid']),None)
        if not same(q,row): return None
        now=ps_rows()
        return q if row['pid']==proc.pid or any(same(x,row) for x in descendants(now,proc.pid)) or row['pid'] in observed else None
    for row in owned.values():
        q=current(row)
        if q:
            try: os.kill(q['pid'],signal.SIGTERM); actions.append({'pid':q['pid'],'start':q['start'],'signal':'TERM'})
            except ProcessLookupError: pass
    time.sleep(.5)
    for row in owned.values():
        q=current(row)
        if q:
            try: os.kill(q['pid'],signal.SIGKILL); actions.append({'pid':q['pid'],'start':q['start'],'signal':'KILL'})
            except ProcessLookupError: pass
    deadline=time.monotonic()+2
    while time.monotonic()<deadline and any(current(r) for r in owned.values()): time.sleep(.1)
    remaining=[{'pid':r['pid'],'start':r['start'],'command':r['command']} for r in owned.values() if current(r)]
    try: code=proc.wait(timeout=.5)
    except subprocess.TimeoutExpired: code=None
    return {'actions':actions,'remaining':remaining,'allOwnedAbsent':not remaining,'wrapperReturnCode':code}
def verify_static():
    if Path(os.path.realpath(ROOT))!=ROOT: raise Hold('worktree path mismatch')
    if sha_file(INPUTS)!=INPUT_SHA: raise Hold('R362 input manifest changed')
    m=json.loads(INPUTS.read_text()); old=json.loads(OLD_RUN.read_text())
    if old.get('status')!='INCOMPLETE_RETAINED' or old.get('saveUnchanged') is not True: raise Hold('original R362 run is not preserved as expected')
    expected={r['path']:r for r in m['rows'] if r['path']!='Package.swift'}
    actual={}
    for p in PACKAGE.rglob('*'):
        if p.is_symlink(): raise Hold(f'compiled package source symlink: {p}')
        if p.is_file():
            rel=p.relative_to(PACKAGE).as_posix()
            if rel.startswith('Tests/'): rel='TEST/'+rel[len('Tests/'):]
            st=p.stat(); actual[rel]={'path':rel,'sizeBytes':st.st_size,'mode':st.st_mode&0o777,'sha256':sha_file(p)}
    if set(actual)-{'Package.swift'}!=set(expected) or any(any(actual[k].get(f)!=expected[k].get(f) for f in ('sizeBytes','mode','sha256')) for k in expected) or actual.get('Package.swift',{}).get('sha256')!=m.get('minimalPackageSHA256') or m.get('sourceFileCount')!=54 or m.get('resourceFileCount')!=2: raise Hold('existing staged package differs from pinned 54-source/2-resource/test inputs/minimal Package')
    if sha_file(TEST_EXE)!=old['testExecutable']['sha256'] or str(TEST_EXE)!=old['testExecutable']['path']: raise Hold('compiled XCTest binary path/hash differs from successful seed phase')
    a=XCTEST_ALIAS.stat(); b=XCTEST_REAL.stat()
    if XCTEST_ALIAS.resolve()!=XCTEST_REAL or (a.st_dev,a.st_ino)!=(b.st_dev,b.st_ino) or sha_file(XCTEST_ALIAS)!=sha_file(XCTEST_REAL): raise Hold('xctest alias/canonical binary identity differs')
    return {'inputManifestSHA256':INPUT_SHA,'packageRowCount':len(actual),'packageRowsSHA256':sha_bytes(json.dumps(list(actual.values()),sort_keys=True,separators=(',',':')).encode()),'testExecutableSHA256':sha_file(TEST_EXE),'xctestAlias':str(XCTEST_ALIAS),'xctestCanonical':str(XCTEST_REAL),'xctestDevice':a.st_dev,'xctestInode':a.st_ino,'xctestSHA256':sha_file(XCTEST_ALIAS)}
def parse(log,passed):
    text=log.read_text(errors='replace'); matches=re.findall(r"Test Case '([^']+)' (passed|started)",text,re.I)
    expected='WitchGameCoreTests.LoadoutCrashIntegrityR362Tests testR342LoadoutPayloadCrashBoundary'
    relevant=[(x,s) for x,s in matches if expected in x]
    if passed: return len(relevant)==1 and 'Executed 1 test, with 0 failures' in text and not re.search(r'Test Case .* (failed|skipped)',text,re.I)
    return len(relevant)==1 and relevant[0][1].lower()=='started' and not re.search(r'Test Case .* (passed|skipped)',text,re.I)
def remaining_owned(observed):
    rows=ps_rows(); return [r for r in observed.values() if any(same(q,r) for q in rows)]
def write_receipt(path,rec):
    tmp=path.with_name(path.name+'.tmp'); data=(json.dumps(rec,sort_keys=True,ensure_ascii=False,indent=2)+'\n').encode(); tmp.write_bytes(data); fd=os.open(tmp,os.O_RDONLY); os.fsync(fd); os.close(fd); os.replace(tmp,path)
def main():
    def stop_signal(signum, _frame): raise KeyboardInterrupt(f'R362 direct runner interrupted by signal {signum}')
    signal.signal(signal.SIGTERM,stop_signal); signal.signal(signal.SIGINT,stop_signal)
    if not sys.argv[1:] or sys.argv[1:]!=['--execute']: raise Hold('Root must explicitly invoke --execute after review')
    pins=verify_static()
    args=json.loads((BASE/'runner_root_r003/EXECUTE_ARGS_R001.json').read_text()); args=dict(zip(args[1::2],args[2::2]))
    protected=Path(args['--protected-root']); baseline_path=Path(args['--protected-manifest']); save=Path(args['--save']); app=Path(args['--app-executable'])
    if sha_file(baseline_path)!=args['--protected-manifest-sha256']: raise Hold('protected inventory manifest changed')
    baseline=json.loads(baseline_path.read_text())['rows']
    if inventory(protected)!=baseline: raise Hold('protected namespace changed before launch')
    if sha_file(save)!=args['--save-sha256']: raise Hold('protected ordinary save changed')
    if sha_file(Path(args['--pbx']))!=args['--pbx-sha256']: raise Hold('live PBX changed')
    for r in ps_rows():
        if str(app.resolve()) in r['command']: raise Hold('protected app is running')
        if ('swift test' in r['command'] or 'WitchGameCorePackageTests.xctest' in r['command']) and str(OUT.parent.resolve()) not in r['command']:
            raise Hold('competing Swift/XCTest process present')
    if shutil.disk_usage(ROOT).free < CAP+RESERVE+FLOOR: raise Hold('capacity floor/reserve not met')
    if OUT.exists() or OUT.is_symlink(): raise Hold('direct-completion output already exists; no retry')
    OUT.mkdir(mode=0o700,parents=False); trial=OUT/'trial_001'; trial.mkdir(mode=0o700)
    state=trial/'state'; state.mkdir(mode=0o700); tmp=OUT/'tmp'; tmp.mkdir(mode=0o700)
    start=time.monotonic(); deadline=start+TOTAL
    ids={'seed':str(uuid.uuid4()),'save':str(uuid.uuid4())}; 
    rec={'schema':'r362-direct-xctest-v1','status':'RUNNING','startedAt':dt.datetime.now().astimezone().isoformat(),'pins':pins,'inputManifestSHA256':INPUT_SHA,'executionContract':{'totalSeconds':TOTAL,'outputCapBytes':CAP,'noBuild':True,'directOwnedPIDKillOnly':True},'operationIDs':ids,'phaseTokens':{},'phases':[]}
    rp=trial/'RUN.json'; write_receipt(rp,rec)
    protected_before=inventory(protected); save_sha=sha_file(save); pbx_sha=sha_file(Path(args['--pbx']))
    observed={}; result=[]
    for mode in ('seed','crash-child','verify'):
        if time.monotonic()>deadline: raise Hold('aggregate wall cap exhausted')
        root=state; log=trial/(mode+'.log'); stage=root/'after-primary-replace.json'
        phase_token=str(uuid.uuid4()); rec['phaseTokens'][mode]=phase_token
        env={k:v for k,v in os.environ.items() if k in ('USER','LOGNAME','SHELL','LANG','LC_ALL','PATH')}
        isolated_home=tmp/'home'; isolated_home.mkdir(mode=0o700,exist_ok=True)
        env['HOME']=str(isolated_home)
        env.update({'DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer','SDKROOT':'/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk','TMPDIR':str(tmp),'CLANG_MODULE_CACHE_PATH':str(tmp/'clang-module-cache'),'WITCH_R362_ROOT':str(root),'WITCH_R362_MODE':mode,'WITCH_R362_PHASE_TOKEN':phase_token,'WITCH_R362_SEED_OPERATION_ID':ids['seed'],'WITCH_R362_SAVE_OPERATION_ID':ids['save']})
        Path(env['CLANG_MODULE_CACHE_PATH']).mkdir(mode=0o700,exist_ok=True)
        cmd=[str(XCTEST_ALIAS),'-XCTest',FILTER,str(BUNDLE)]
        phase={'mode':mode,'command':cmd,'startedAt':dt.datetime.now().astimezone().isoformat(),'phaseToken':phase_token}; t=time.monotonic(); proc=None
        try:
            with log.open('xb') as f:
                proc=subprocess.Popen(cmd,cwd=ROOT,env=env,stdin=subprocess.DEVNULL,stdout=f,stderr=subprocess.STDOUT,close_fds=True,start_new_session=True)
                rows=ps_rows(); ident=next((r for r in rows if r['pid']==proc.pid),None)
                if not ident or not ident['command'].startswith(str(XCTEST_ALIAS)+' '): raise Hold('direct XCTest launch identity unavailable')
                observed[proc.pid]=ident; phase.update({'pid':proc.pid,'startIdentity':ident['start'],'commandIdentity':ident['command']})
                limit=min(PHASE_LIMIT[mode],deadline-time.monotonic())
                if mode=='crash-child':
                    while not stage.exists():
                        record_descendants(proc,observed)
                        if time.monotonic()-t>limit: raise Hold('crash barrier timeout')
                        live=next((r for r in ps_rows() if r['pid']==proc.pid),None)
                        if not same(live,ident): raise Hold('direct XCTest PID identity changed before marker')
                        if proc.poll() is not None: raise Hold('XCTest exited before crash barrier')
                        time.sleep(.1)
                    marker=json.loads(stage.read_text())
                    live=next((r for r in ps_rows() if r['pid']==proc.pid),None)
                    if (marker.get('pid')!=proc.pid or marker.get('parentPID')!=os.getpid() or marker.get('phaseToken')!=phase_token
                        or not same(live,ident) or marker.get('operationID')!=ids['save']
                        or marker.get('phase')!='afterPrimaryReplace' or marker.get('requestFingerprint')!='saveGearLoadoutR342|1:1'
                        or marker.get('processGroupID')!=proc.pid or sha_file(state/'save.json')!=marker.get('primarySHA256')): raise Hold('barrier PID/parent/token/operation mismatch; no signal sent')
                    phase['stageMarker']=marker
                    os.kill(proc.pid,signal.SIGKILL)
                    code=proc.wait(timeout=5); phase['returnCode']=code
                    phase['accepted']=code==-signal.SIGKILL and parse(log,False)
                    phase['targetPIDAbsent']=not any(r['pid']==proc.pid and r['start']==ident['start'] for r in ps_rows())
                    phase['ownedProcessesRemaining']=remaining_owned(observed)
                    phase['allOwnedProcessesAbsent']=phase['targetPIDAbsent'] and not phase['ownedProcessesRemaining']
                    phase['signal']='SIGKILL_EXACT_POPEN_PID'
                else:
                    while proc.poll() is None:
                        record_descendants(proc,observed)
                        if time.monotonic()-t>limit: raise Hold(f'{mode} phase timeout')
                        if shutil.disk_usage(ROOT).free<CAP+RESERVE+FLOOR: raise Hold('capacity floor breached')
                        time.sleep(.1)
                    code=proc.wait(timeout=1); phase['returnCode']=code; phase['accepted']=code==0 and parse(log,True)
                    phase['targetPIDAbsent']=not any(r['pid']==proc.pid and r['start']==ident['start'] for r in ps_rows())
                    phase['ownedProcessesRemaining']=remaining_owned(observed)
                    phase['allOwnedProcessesAbsent']=phase['targetPIDAbsent'] and not phase['ownedProcessesRemaining']
                phase['elapsedSeconds']=round(time.monotonic()-t,3); phase['logSHA256']=sha_file(log); phase['logBytes']=log.stat().st_size
                result.append(phase); rec['phases']=result; rec['status']='RUNNING'; write_receipt(rp,rec)
                if not phase['accepted'] or not phase['allOwnedProcessesAbsent']: raise Hold(f'{mode} phase acceptance failed')
                if output_size(OUT)>CAP: raise Hold('output logical cap exceeded')
                manifest_rows=json.loads(INPUTS.read_text()); expected_after={r['path'].replace('TEST/','Tests/',1):r['sha256'] for r in manifest_rows['rows'] if r['path']!='Package.swift'}; expected_after['Package.swift']=manifest_rows['minimalPackageSHA256']
                actual_after={p.relative_to(PACKAGE).as_posix():sha_file(p) for p in PACKAGE.rglob('*') if p.is_file()}
                if actual_after!=expected_after: raise Hold('staged build package changed')
        except BaseException as exc:
            if proc is not None:
                phase['cleanup']=owned_cleanup(proc,observed)
            phase['error']=f'{type(exc).__name__}: {exc}'; phase['elapsedSeconds']=round(time.monotonic()-t,3)
            if log.exists(): phase['logSHA256']=sha_file(log); phase['logBytes']=log.stat().st_size
            if not any(x.get('mode')==mode for x in result): result.append(phase)
            rec.update({'status':'INCOMPLETE_RETAINED','error':phase['error'],'phases':result}); write_receipt(rp,rec); return 2
    rec.update({'status':'SEMANTIC_REVIEW_REQUIRED','phases':result})
    try:
        rec['protectedUnchanged']=inventory(protected)==protected_before
        rec['saveUnchanged']=sha_file(save)==save_sha
        rec['pbxUnchanged']=sha_file(Path(args['--pbx']))==pbx_sha
        rec['ownedProcessesAfter']=[r for r in ps_rows() if r['pid'] in observed and same(r,observed[r['pid']])]
        rec['outputBytes']=output_size(OUT)
        if not rec['protectedUnchanged'] or not rec['saveUnchanged'] or not rec['pbxUnchanged'] or rec['ownedProcessesAfter'] or rec['outputBytes']>CAP or time.monotonic()-start>TOTAL: rec['status']='INCOMPLETE_RETAINED'
    except Exception as exc: rec['status']='INCOMPLETE_RETAINED'; rec['finalAuditError']=str(exc)
    rec['elapsedSeconds']=round(time.monotonic()-start,3); rec['finishedAt']=dt.datetime.now().astimezone().isoformat(); write_receipt(rp,rec)
    return 0 if rec['status']=='SEMANTIC_REVIEW_REQUIRED' else 2
if __name__=='__main__':
    try: raise SystemExit(main())
    except Hold as e: print('HOLD:',e,file=sys.stderr); raise SystemExit(2)

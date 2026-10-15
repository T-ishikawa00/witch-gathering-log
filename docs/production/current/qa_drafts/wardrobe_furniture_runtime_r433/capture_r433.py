"""Bounded evidence and owned lifecycle for ordinary R420 wardrobe UI.

Gameplay is operated through visible UI. No save injection, resource copy,
purchase, build, deletion, or restoration is performed by this helper.
"""
from pathlib import Path
import argparse, datetime, hashlib, importlib.util, json, os, re, shutil, signal, subprocess, time

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[4]
OUT = BASE / 'execution_r001'
PRIOR = ROOT / 'docs/production/current/qa_drafts/normal_progression_r421'
DEVICE = '9A067715-7CF3-40D3-9064-38423223959B'
BUNDLE = 'local.witch.autonomous.r1.completion.r420'
MAX_SECONDS = 2700
MAX_BYTES = 180_000_000
MAX_SHOTS = 32

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p, d):
    with p.open('x') as f:
        json.dump(d, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write('\n'); f.flush(); os.fsync(f.fileno())
def load_helper():
    p = PRIOR / 'snapshot_r421_r002.py'
    assert sha(p) == '6fe314a33ce19de71af8b21cec035070ee0a3a54c54434a7d460dfd315d9b9bd'
    spec = importlib.util.spec_from_file_location('r421_readonly', p)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m
H = load_helper()
def tree(p):
    result = {}
    for q in p.rglob('*'):
        if q.is_symlink(): raise RuntimeError('symlink: '+str(q))
        if q.is_file(): result[str(q.relative_to(p))] = sha(q)
    return result
def usage(): return sum(p.stat().st_size for p in OUT.rglob('*') if p.is_file())
def gate(closing=False):
    assert shutil.disk_usage(ROOT).free > 10_000_000_000 + MAX_BYTES
    if (OUT/'START.json').exists():
        start=json.loads((OUT/'START.json').read_text())
        if not closing:
            assert time.time()-start['startedEpoch'] < MAX_SECONDS
            assert usage()+6_000_000 < MAX_BYTES
def snapshot(label, shot=False, closing=False):
    gate(closing); assert re.fullmatch('[A-Za-z0-9_-]{1,48}', label)
    assert not (closing and shot)
    inputs=H.fixed_inputs(); dst=OUT/'checkpoints'/label; dst.mkdir(parents=True,exist_ok=False)
    files={}
    for name,p in H.support_files(inputs['data']).items():
        raw,meta=H.stable_read(p)
        assert len(raw)<2_000_000
        target=dst/name
        with target.open('xb') as f: f.write(raw); f.flush(); os.fsync(f.fileno())
        assert sha(target)==meta['sha256'] and H.stable_read(p)[0]==raw
        files[name]=meta
    snap=json.loads((dst/'save.json').read_text())['snapshot']
    screenshot=None
    if shot:
        assert len(list(OUT.glob('checkpoints/*/screen.png')))<MAX_SHOTS
        p=dst/'screen.png'
        H.run_read(['xcrun','simctl','io',DEVICE,'screenshot',str(p)],timeout=20)
        screenshot={'path':str(p.relative_to(OUT)),'sha256':sha(p),'bytes':p.stat().st_size}
    row={'label':label,'at':datetime.datetime.now().astimezone().isoformat(),
         'files':files,'saveSHA256':sha(dst/'save.json'),'revision':snap['revision'],
         'selectedCosmeticIDs':snap['selectedCosmeticIDs'],
         'selectedWeaponAppearanceIDs':snap['selectedWeaponAppearanceIDs'],
         'ownedCosmeticIDs':snap['ownedCosmeticIDs'],
         'ownedFurnitureIDs':snap['ownedFurnitureIDs'],'placedFurnitureIDs':snap['placedFurnitureIDs'],
         'screenshot':screenshot,'syntheticSaveWrites':False}
    write(dst/'CHECKPOINT.json',row)
    if usage() > MAX_BYTES:
        raise RuntimeError('Evidence cap exceeded; retain raw files and close without more screenshots')
    print(json.dumps({k:row[k] for k in ['label','revision','selectedCosmeticIDs','selectedWeaponAppearanceIDs','placedFurnitureIDs']},ensure_ascii=False))
    return row
def launch(label):
    inputs=H.fixed_inputs(); assert not H.process_rows(inputs['executable'])
    identity=inputs['data']/H.SUPPORT_REL/'last_standard_play_identity_r169.json'
    before_identity=sha(identity)
    expected_revision=json.loads((inputs['data']/H.SUPPORT_REL/'save.json').read_text())['snapshot']['revision']
    p=subprocess.run(['xcrun','simctl','launch',DEVICE,BUNDLE],capture_output=True,text=True,timeout=30)
    m=re.fullmatch(re.escape(BUNDLE)+r': (\d+)\s*',p.stdout)
    write(OUT/(label+'_LAUNCH.json'),{'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'flags':[],'at':time.time()})
    assert p.returncode==0 and m
    deadline=time.monotonic()+20
    while time.monotonic()<deadline:
        if identity.is_file() and sha(identity)!=before_identity:
            d=json.loads(identity.read_text())
            if d.get('revision')==expected_revision and d.get('wardrobeCandidateDevelopmentEnabled') is True:
                write(OUT/(label+'_READY.json'),{'identitySHA256':sha(identity),'revision':expected_revision,
                    'newIdentityObserved':True,'visualUIReadiness':'Requires separate CUA observation'})
                return int(m.group(1))
        time.sleep(0.1)
    raise RuntimeError('Fresh runtime identity not observed within 20s; keep evidence and stop owned process')
def stop_owned():
    inputs=H.fixed_inputs(); owned=set()
    for p in OUT.glob('*_LAUNCH.json'):
        d=json.loads(p.read_text()); m=re.fullmatch(re.escape(BUNDLE)+r': (\d+)\s*',d['stdout'])
        if m: owned.add(int(m.group(1)))
    rows=H.process_rows(inputs['executable'])
    for row in rows:
        assert row['pid'] in owned and row['command'].split()[0]==str(inputs['executable'])
        os.kill(row['pid'],signal.SIGTERM)
    deadline=time.monotonic()+10
    while H.process_rows(inputs['executable']) and time.monotonic()<deadline: time.sleep(0.1)
    assert not H.process_rows(inputs['executable'])
def main():
    ap=argparse.ArgumentParser();ap.add_argument('phase',choices=['start','snapshot','cold','close']);ap.add_argument('--label');ap.add_argument('--shot',action='store_true');a=ap.parse_args()
    gate(closing=a.phase=='close'); inputs=H.fixed_inputs()
    if a.phase=='start':
        assert not OUT.exists() and not H.process_rows(inputs['executable'])
        save=inputs['data']/H.SUPPORT_REL/'save.json'
        assert sha(save)=='07252129426c3d68b9617c2569f1a6c79c16f86968ed6a6841a1aa472150cab6'
        OUT.mkdir()
        protected={str(p):tree(p) for p in map(Path,inputs['install']['protectedTrees'])}
        write(OUT/'START.json',{'startedEpoch':time.time(),'app':str(inputs['app']),'data':str(inputs['data']),
            'appInventory':tree(inputs['app']),'protectedTrees':protected,
            'sourceMapSHA256':'cee0238900cbd8bade40a52d0aac98e880770064e02b5130366b32c2b6acc355',
            'freeBytes':shutil.disk_usage(ROOT).free,'maxBytes':MAX_BYTES,'maxSeconds':MAX_SECONDS,
            'maxScreenshots':MAX_SHOTS,'flags':[],'syntheticSaveWrites':False,'clockChanges':False,
            'allowedUI':'Preview/apply/reset existing free development wardrobe; claim/place/store free desk; ordinary battle. No purchase.',
            'acceptance':'Persist each selected appearance; render preview/home/companion/battle; cold bytes exact; protected trees exact.',
            'video':False,'deletion':False,'push':False})
        snapshot('before');launch('INITIAL')
    elif a.phase=='snapshot': snapshot(a.label,a.shot)
    elif a.phase=='cold':
        assert re.fullmatch('[A-Za-z0-9_-]{1,32}',a.label)
        row=snapshot(a.label+'_before'); stop_owned(); launch(a.label)
        after=snapshot(a.label+'_after',a.shot)
        write(OUT/(a.label+'_COLD.json'),{'before':row['saveSHA256'],'after':after['saveSHA256'],'exact':row['saveSHA256']==after['saveSHA256']})
        assert row['saveSHA256']==after['saveSHA256']
    else:
        stop_owned();snapshot('final',closing=True);start=json.loads((OUT/'START.json').read_text())
        checks=[{'path':p,'files':len(before),'exact':tree(Path(p))==before} for p,before in start['protectedTrees'].items()]
        app_exact=tree(inputs['app'])==start['appInventory']
        write(OUT/'CLOSURE.json',{'status':'CAPTURE_CLOSED_REQUIRES_RESULT_REVIEW','protectedTrees':checks,
            'appExact':app_exact,'ownedProcessesAbsent':not H.process_rows(inputs['executable']),
            'elapsedSeconds':time.time()-start['startedEpoch'],'evidenceBytes':usage(),
            'gameSaveChanges':'Only ordinary visible UI actions; initial and every checkpoint archived.',
            'formalQualityAccepted':False,'realCharge':False,'deletion':False})
        assert app_exact and all(c['exact'] for c in checks)
if __name__=='__main__':main()

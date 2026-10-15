#!/usr/bin/env python3
"""R449 Root-operated ordinary challenge capture. This helper never launches,
terminates, installs, edits, copies, restores, or deletes game data. It reads
state, archives evidence, and optionally asks simctl for a screenshot only.
"""
from __future__ import annotations
import argparse, datetime as dt, hashlib, json, os, plistlib, re, shlex, shutil, subprocess, time
from pathlib import Path

ROOT = Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
HERE = ROOT / 'docs/production/current/qa_drafts/native_challenge_completion_r449/candidate_r001'
OUT = HERE / 'execution_r001'
DEVICE = '9A067715-7CF3-40D3-9064-38423223959B'
BUNDLE = 'local.witch.autonomous.r1.completion.r445'
EXPECTED_APP = Path('/Users/PUBLIC_USER/Library/Developer/CoreSimulator/Devices/9A067715-7CF3-40D3-9064-38423223959B/data/Containers/Bundle/Application/1BEDDB67-CEDB-4BA6-A436-F143749796A5/WitchGathering.app')
EXPECTED_DATA = Path('/Users/PUBLIC_USER/Library/Developer/CoreSimulator/Devices/9A067715-7CF3-40D3-9064-38423223959B/data/Containers/Data/Application/61DD54AD-8723-4481-9FF0-46624F4C8096')
SUPPORT = Path('Library/Application Support/Witch03to05DevelopmentR169')
R445_INSTALL = ROOT / 'docs/production/current/qa_drafts/native_completion_r445/install_release_r001/RESULT.json'
R445_INSTALL_SHA = '8990781fbbff10c073ee8e6085e0edc9e71f8eeff6f2d3ec55c6d6fd4f3113ee'
R445_BUILD = ROOT / 'docs/production/current/qa_drafts/native_completion_r445/build_tools_r001/postbuild_readback_r001/release_BUILD_PASS.json'
R445_BUILD_SHA = 'f6482cdd910d30e633af9a78068e751a85074bcdfa744a9ccffa0bde2f2d123c'
R446_CLOSE = ROOT / 'docs/production/current/qa_drafts/native_reading_mantle_r446/execution_r001/CLOSURE.json'
R446_CLOSE_SHA = '01b33e7a5d35a52b25769e3df67a72657dfeab8fc6b41656c67ec50782be1518'
R446_SAVE = ROOT / 'docs/production/current/qa_drafts/native_reading_mantle_r446/execution_r001/checkpoints/cold_after/support/save.json'
R446_SAVE_SHA = 'af864f432b2e16255e9fa050f0b1cf5189492c297260e64d1eae6ec465d03cc4'
R443_CLOSE = ROOT / 'docs/production/current/qa_drafts/normal_progression_continuation_r443/candidate_r002/execution_r001/CLOSURE.json'
R443_CLOSE_SHA = 'bee6afc91e27fbcee4dac0632ebdbddf1738f5ea63706fb31dec76f2665fdf51'
R443_MOCK_SEED = ROOT / 'docs/production/current/qa_drafts/normal_progression_continuation_r443/candidate_r002/execution_r001/checkpoints/before/files/save.json'
R443_MOCK_SEED_SHA = '51c07a8d8c262f930bda41728b2775ac1338187644ed3a60fda05fbf24786475'
BASELINE_SHA = R446_SAVE_SHA
BASELINE_REVISION = 117
ALL_CHALLENGES = tuple(f'CH_R{r:02d}_{n:02d}' for r in range(1, 6) for n in range(1, 4))
START_CLEARED = tuple(f'CHALLENGE_CLEAR|{x}' for x in ('CH_R01_01','CH_R01_02','CH_R01_03','CH_R02_01','CH_R02_02','CH_R02_03','CH_R03_01'))
STATIC_LABELS = ('before','region_R01','region_R02','region_R03','region_R04','region_R05','cold_before','cold_after')
STATIC_SHOTS = {'before','region_R03','region_R04','region_R05','cold_after'}
MAX_WALL = 1800
MAX_BYTES = 35_000_000
MAX_SHOTS = 6
MIN_FREE = 10_000_000_000
REQUIRED_SUPPORT = {'save.json','save.json.previous','last_standard_play_identity_r169.json'}
MUTABLE_SUPPORT = REQUIRED_SUPPORT | {'save.json.lock','last_battle.json','last_battle_art.json','last_challenge.json','last_challenge_art.json','last_shared_party_work_r146.json'}
MOCK_GEAR = {
    '8C49CD7A-29A5-407E-AEE3-F60C35B31C30':'EQ_HAND_02',
    'E56F7BB6-D8A6-4611-8B5D-94DB13508979':'EQ_RING_03',
    '45135D4D-CECB-4896-80B6-2D1894782322':'EQ_W_P2',
    'EA238209-61A6-442D-9BB2-A37C6D8A3AB3':'EQ_S_03',
    'C71D598A-C628-4B98-967D-0F3FF551E1E6':'EQ_S_02',
}
OWN_CACHE = Path('Library/Caches') / BUNDLE
OWN_METAL = OWN_CACHE / 'com.apple.metal'
OWN_SAVED_STATE = Path('Library/Saved Application State') / f'{BUNDLE}.savedState'


def sha(raw: bytes) -> str: return hashlib.sha256(raw).hexdigest()
def sha_file(path: Path) -> str: return sha(path.read_bytes())
def stamp() -> str: return dt.datetime.now().astimezone().isoformat()
def write_once(path: Path, value: object) -> None:
    raw=(json.dumps(value,ensure_ascii=False,sort_keys=True,indent=2)+'\n').encode()
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    try:
        with os.fdopen(fd,'wb',closefd=False) as f: f.write(raw); f.flush(); os.fsync(f.fileno())
    finally: os.close(fd)
def command(argv: list[str], timeout: int=30) -> str:
    r=subprocess.run(argv,capture_output=True,text=True,timeout=timeout,check=False)
    if r.returncode: raise RuntimeError(f'{argv[0]} failed {r.returncode}: {r.stderr[-1200:]}')
    return r.stdout
def tree(root: Path) -> dict[str,str]:
    if root.is_symlink() or not root.is_dir(): raise RuntimeError(f'protected tree missing/unsafe: {root}')
    out={}
    for p in root.rglob('*'):
        if p.is_symlink(): raise RuntimeError(f'symlink in protected tree: {p}')
        if p.is_file(): out[str(p.relative_to(root))]=sha_file(p)
    return out
def inventory(root: Path) -> dict[str,dict]:
    if root.is_symlink() or not root.is_dir(): raise RuntimeError('unsafe data container')
    out={}
    for p in root.rglob('*'):
        if p.is_symlink(): raise RuntimeError(f'symlink in data container: {p}')
        if p.is_file():
            st=p.stat(); out[str(p.relative_to(root))]={'sha256':sha_file(p),'sizeBytes':st.st_size,'mode':st.st_mode&0o777}
    return out
def app_pids(exe: Path) -> list[int]:
    expected=os.path.realpath(exe)
    found=[]
    for row in command(['ps','-axo','pid=,command=']).splitlines():
        bits=row.strip().split(maxsplit=1)
        if len(bits)!=2: continue
        try: pid=int(bits[0]); argv=shlex.split(bits[1])
        except (ValueError, OSError): continue
        if argv and os.path.realpath(argv[0])==expected: found.append(pid)
    return sorted(set(found))
def output_bytes() -> int:
    if not OUT.exists(): return 0
    total=0
    for p in OUT.rglob('*'):
        if p.is_symlink(): raise RuntimeError(f'symlink in evidence output: {p}')
        if p.is_file(): total+=p.stat().st_size
    return total
def snapshot_of(path: Path) -> dict:
    d=json.loads(path.read_bytes())
    if not isinstance(d.get('snapshot'),dict) or not isinstance(d.get('receipts'),list): raise RuntimeError('save envelope shape invalid')
    return d
def receipt_objects(envelope: dict) -> list[dict]:
    return [x for x in envelope['receipts'] if isinstance(x,dict) and isinstance(x.get('operationID'),str)]
def challenge_clears(snapshot: dict) -> set[str]:
    return {str(x) for x in snapshot.get('completedEncounterIDs',[]) if str(x).startswith('CHALLENGE_CLEAR|')}
def equipped_ids(snapshot: dict) -> set[str]:
    eq=snapshot.get('equippedGearIDs')
    if not isinstance(eq,dict): raise RuntimeError('equippedGearIDs missing/invalid')
    return {str(x) for x in eq.values()}
def summon_receipts(envelope: dict) -> list[dict]:
    return sorted(({'operationID':x.get('operationID'),'requestFingerprint':x.get('requestFingerprint'),'result':x.get('result'),'revision':x.get('revision')}
        for x in receipt_objects(envelope) if str(x.get('requestFingerprint','')).startswith('summon|') or str(x.get('result','')).startswith('MOCK_ONLY')),
        key=lambda x:(str(x.get('revision')),str(x.get('operationID'))))
def load_baseline_history() -> dict:
    if sha_file(R443_CLOSE)!=R443_CLOSE_SHA or sha_file(R443_MOCK_SEED)!=R443_MOCK_SEED_SHA: raise RuntimeError('Pinned R443 history changed')
    r443=json.loads(R443_CLOSE.read_bytes())
    if r443.get('status')!='CLOSED_PRESERVATION_EXACT' or r443.get('finalRevision')!=113: raise RuntimeError('R443 historical closure is not exact')
    hist=snapshot_of(R443_MOCK_SEED); hs=hist['snapshot']
    mock_receipts=[x for x in receipt_objects(hist) if str(x.get('result','')).startswith('MOCK_ONLY R3 test draw x5:')]
    if len(mock_receipts)!=1 or mock_receipts[0].get('operationID')!='C385C74B-86AC-4EE7-8DF7-84EBDF76F208': raise RuntimeError('Expected historical mock-five receipt not found')
    gear={str(x.get('id')):str(x.get('definitionID')) for x in hs.get('gear',[]) if isinstance(x,dict)}
    if any(gear.get(k)!=v for k,v in MOCK_GEAR.items()): raise RuntimeError('Historical mock gear UUID/template map mismatch')
    return {'r443ClosureSHA256':R443_CLOSE_SHA,'mockSeedSHA256':R443_MOCK_SEED_SHA,'mockFiveOperationID':mock_receipts[0]['operationID'],'mockFiveReceiptRevision':mock_receipts[0].get('revision'),'knownMockGearUUIDs':MOCK_GEAR}
def validate_r446_closure() -> dict:
    if sha_file(R446_CLOSE)!=R446_CLOSE_SHA or sha_file(R446_SAVE)!=BASELINE_SHA: raise RuntimeError('Pinned R446 closure/save changed')
    c=json.loads(R446_CLOSE.read_bytes())
    # R446 remained INCOMPLETE_RETAINED only for three newly-created OS Saved Application State files.
    expected_os={
      f'Library/Saved Application State/{BUNDLE}.savedState/5F21554A-B60B-4443-AAE5-44EA0F7EE051/data.data',
      f'Library/Saved Application State/{BUNDLE}.savedState/5F21554A-B60B-4443-AAE5-44EA0F7EE051/userInfo.data',
      f'Library/Saved Application State/{BUNDLE}.savedState/KnownSceneSessions/data.data',
    }
    if not (c.get('status')=='INCOMPLETE_RETAINED' and c.get('protectedTreesExact') is True and c.get('installedAppExact') is True
        and c.get('coldBeforeAfterSaveByteEqual') is True and c.get('liveSaveMatchesColdAfter') is True
        and c.get('coldRestartDistinctPIDsObserved') is True and c.get('withinBudgets') is True
        and c.get('missingLabels')==[] and c.get('archiveMismatches')==[] and c.get('screenshotMismatches')==[]
        and c.get('dataUnexpectedMissing')==[] and c.get('dataUnexpectedChanged')==[]
        and c.get('dataUnexpectedNew') is not None and set(c['dataUnexpectedNew'])==expected_os):
        raise RuntimeError('R446 is not the expected preservation/cold state')
    cp=c.get('checkpoints',{}).get('cold_after',{})
    if cp.get('revision')!=BASELINE_REVISION or cp.get('saveSHA256')!=BASELINE_SHA: raise RuntimeError('R446 revision117 baseline mismatch')
    return {'closureSHA256':R446_CLOSE_SHA,'saveSHA256':BASELINE_SHA,'revision':BASELINE_REVISION,'knownSavedStateNewFiles':sorted(expected_os)}
def validate_install() -> tuple[dict,dict,Path,Path]:
    if sha_file(R445_INSTALL)!=R445_INSTALL_SHA or sha_file(R445_BUILD)!=R445_BUILD_SHA: raise RuntimeError('Pinned R445 install/build receipt changed')
    ir=json.loads(R445_INSTALL.read_bytes()); br=json.loads(R445_BUILD.read_bytes())
    if ir.get('status')!='PASS_NEW_BUNDLE_INSTALLED' or ir.get('launch') is not False or ir.get('bundleID')!=BUNDLE or ir.get('device')!=DEVICE: raise RuntimeError('R445 installation receipt invalid')
    app=Path(ir['installedApp']).resolve(strict=True); data=Path(ir['data']).resolve(strict=True); exe=app/'WitchGathering'
    if app!=EXPECTED_APP.resolve(strict=True) or data!=EXPECTED_DATA.resolve(strict=True): raise RuntimeError('R445 app/data container UUID changed since R446')
    if plistlib.loads((app/'Info.plist').read_bytes()).get('CFBundleIdentifier')!=BUNDLE: raise RuntimeError('installed R445 bundle ID mismatch')
    if sha_file(exe)!=ir.get('installedExecutableSHA256') or tree(app)!=br.get('appFiles'): raise RuntimeError('R445 installed app differs from build receipt')
    if br.get('phase')!='BUILD_PASS' or br.get('bundleIdentifier')!=BUNDLE or sha_file(exe)!=br.get('executableSHA256'): raise RuntimeError('R445 build receipt does not match installed app')
    protected=ir.get('protectedTrees')
    if not isinstance(protected,dict) or len(protected)<18: raise RuntimeError('R445 receipt lacks historical protected trees')
    actual={p:tree(Path(p)) for p in protected}
    if actual!=protected: raise RuntimeError('R420/R437 and other historical protected trees changed')
    return ir,br,app,data

def validate_equipment(snapshot: dict, baseline_equipped: set[str]) -> dict:
    gear=snapshot.get('gear')
    if not isinstance(gear,list): return {'valid':False,'reason':'gear list missing'}
    gear_ids={str(x.get('id')) for x in gear if isinstance(x,dict)}
    equipped=equipped_ids(snapshot)
    absent=sorted(equipped-gear_ids)
    mock=sorted(equipped & set(MOCK_GEAR))
    return {'valid':not absent and not mock and equipped==baseline_equipped,'equippedCount':len(equipped),
            'equippedUUIDs':sorted(equipped),'missingOwnedUUIDs':absent,'historicalMockUUIDsEquipped':mock,
            'currentGearCount':len(gear)}
def challenge_event(snapshot: dict, support: Path, challenge_id: str) -> dict:
    save_rev=snapshot.get('revision'); last_id=snapshot.get('lastEncounterID')
    p=support/'last_challenge.json'; art=support/'last_challenge_art.json'
    outcome=None; match=False; art_match=False; value=None; sidecar_rev=None; art_rev=None
    try:
        d=json.loads(p.read_bytes()); value=d.get('value'); sidecar_rev=d.get('revision')
        match=(d.get('kind')=='challenge' and sidecar_rev==save_rev and isinstance(value,str) and value.startswith(challenge_id+':CHALLENGE '))
        if isinstance(value,str):
            outcome='WIN' if ('VICTORY' in value and f'{challenge_id}:' in value) else ('DEFEAT' if 'DEFEAT' in value else 'UNKNOWN')
    except Exception as e: value=f'{type(e).__name__}: {e}'
    try:
        a=json.loads(art.read_bytes()); art_rev=a.get('revision'); payload=json.loads(a.get('value','{}'))
        art_match=(a.get('kind')=='challenge_art' and art_rev==save_rev and isinstance(payload,dict) and isinstance(payload.get('actorIDs'),list))
    except Exception: pass
    marker='CHALLENGE_CLEAR|'+challenge_id in set(map(str,snapshot.get('completedEncounterIDs',[])))
    combat=snapshot.get('lastCombatResult')
    won=combat.get('won') if isinstance(combat,dict) and isinstance(combat.get('won'),bool) else None
    outcome_matches_combat=(won is not None and ((outcome=='WIN')==won if outcome in ('WIN','DEFEAT') else False))
    return {'challengeID':challenge_id,'lastEncounterID':last_id,'saveRevision':save_rev,'sidecarRevision':sidecar_rev,
            'sidecarMatches':match,'outcomeText':value,'outcome':outcome,'clearMarkerPresent':marker,
            'lastCombatResultWon':won,'outcomeMatchesLastCombatResult':outcome_matches_combat,
            'resultConsistent':match and last_id==challenge_id and outcome_matches_combat and art_match,
            'challengeArtRevision':art_rev,'challengeArtMatches':art_match}

def session() -> dict:
    p=OUT/'SESSION.json'
    if not p.is_file(): raise RuntimeError('R449 session not prepared')
    s=json.loads(p.read_bytes())
    if time.time()-float(s['startedEpoch'])>MAX_WALL: raise RuntimeError('30-minute cap reached; retain and close')
    if output_bytes()+1_000_000>MAX_BYTES: raise RuntimeError('35MB evidence reserve reached')
    if shutil.disk_usage(ROOT).free<MIN_FREE: raise RuntimeError('free-space floor below 10GB')
    return s

def prepare() -> None:
    if OUT.exists(): raise RuntimeError('R449 fixed output already exists; no overwrite/retry')
    if shutil.disk_usage(ROOT).free<MIN_FREE+MAX_BYTES: raise RuntimeError('10GB free floor plus 35MB evidence reserve unavailable')
    if sha_file(R443_CLOSE)!=R443_CLOSE_SHA: raise RuntimeError('R443 closure pin mismatch')
    history=load_baseline_history(); r446=validate_r446_closure(); ir,br,app,data=validate_install()
    exe=app/'WitchGathering'
    if app_pids(exe): raise RuntimeError('R445 app must be stopped before preparation')
    support=data/SUPPORT; save=support/'save.json'
    if support.is_symlink() or not support.is_dir() or save.is_symlink() or not save.is_file() or sha_file(save)!=BASELINE_SHA: raise RuntimeError('live save is not exact R446 revision117')
    env=snapshot_of(save); snap=env['snapshot']
    if snap.get('revision')!=BASELINE_REVISION: raise RuntimeError('live save revision differs from R446')
    initial_clears=challenge_clears(snap)
    if initial_clears!=set(START_CLEARED): raise RuntimeError('R446 seven-cleared challenge baseline differs')
    if set(map(str,snap.get('unlockedRegionIDs',[])))!={'R01','R02','R03','R04','R05'}: raise RuntimeError('R446 all-five-region unlock baseline differs')
    eq=validate_equipment(snap,equipped_ids(snap))
    if not eq['valid']: raise RuntimeError('R446 equipped UUIDs do not form a current non-mock owned loadout')
    current_gear={str(g.get('id')):str(g.get('definitionID')) for g in snap.get('gear',[]) if isinstance(g,dict)}
    historical_mock_present={k:current_gear.get(k) for k in MOCK_GEAR if k in current_gear}
    mock_receipts=[x for x in receipt_objects(env) if x.get('operationID')==history['mockFiveOperationID']]
    if len(mock_receipts)!=1 or mock_receipts[0].get('result','').find('MOCK_ONLY R3 test draw x5:')!=0: raise RuntimeError('R446 save does not retain the identified historical mock-draw receipt')
    data_before=inventory(data); support_before={}
    for name in sorted(REQUIRED_SUPPORT):
        p=support/name
        if p.is_symlink() or not p.is_file(): raise RuntimeError(f'required R446 support file missing: {name}')
        raw=p.read_bytes(); support_before[name]={'sha256':sha(raw),'sizeBytes':len(raw),'mode':p.stat().st_mode&0o777}
    OUT.mkdir(parents=True,exist_ok=False)
    write_once(OUT/'SESSION.json',{'schema':'native-challenge-completion-r449-v1','status':'PREPARED_NOT_RUN_ROOT_OPERATED',
      'startedAt':stamp(),'startedEpoch':time.time(),'device':DEVICE,'bundleID':BUNDLE,'installedApp':str(app),'installedData':str(data),
      'installReceiptPath':str(R445_INSTALL),'installReceiptSHA256':R445_INSTALL_SHA,'buildReceiptPath':str(R445_BUILD),'buildReceiptSHA256':R445_BUILD_SHA,
      'executableSHA256':sha_file(exe),'appFiles':br['appFiles'],'protectedTreesBefore':ir['protectedTrees'],
      'r443HistoricalClosureSHA256':R443_CLOSE_SHA,'r443MockSeedSHA256':R443_MOCK_SEED_SHA,'r446ClosureSHA256':r446['closureSHA256'],
      'r446BaselineSaveSHA256':BASELINE_SHA,'baselineRevision':BASELINE_REVISION,'baselineSupportFiles':support_before,
      'dataInventoryBefore':data_before,'supportRelativePath':str(SUPPORT),'mutableSupportPaths':sorted(MUTABLE_SUPPORT),
      'knownHistoricalMockDraw':history,'historicalMockGearStillOwned':historical_mock_present,
      'historicalMockGearUUIDs':MOCK_GEAR,'currentEquippedUUIDs':sorted(eq['equippedUUIDs']),
      'currentEquippedLoadoutHasNoKnownMockUUIDs':True,'currentCompletedChallengeClearIDs':sorted(initial_clears),
      'allChallengeIDs':list(ALL_CHALLENGES),'initialGachaPity':snap.get('gachaPity'),
      'initialMockPurchaseRecords':snap.get('mockPurchaseRecords'),'initialSummonReceipts':summon_receipts(env),'initialNaturalGearRecordCount':len(snap.get('naturalGearDiscoveryR350',{}).get('acquisitionRecords',[])),
      'ownCacheRoots':{'allBundleCache':str(OWN_CACHE),'metal':str(OWN_METAL),'savedApplicationState':str(OWN_SAVED_STATE)},
      'limits':{'wallSeconds':MAX_WALL,'evidenceBytes':MAX_BYTES,'screenshots':MAX_SHOTS,'minFreeBytes':MIN_FREE},
      'screenshotsRequired':sorted(STATIC_SHOTS),'screenshotsOptional':'At most one screenshot from any of the 15 challenge attempts in addition to the five required; no video.',
      'operatorActions':'Root only: ordinary UI challenge selection and battle resolution, region navigation, cold restart. Helper performs no launch, termination, game action, install, save edit, copy, restore, or deletion.'})
    write_once(OUT/'PREPARED.json',{'status':'READY_ROOT_OPERATED_UNRUN','baselineRevision':BASELINE_REVISION,'baselineSaveSHA256':BASELINE_SHA,
      'historicalPriorChallengeWins':len(initial_clears),'historicalMockDraws':5,'equippedMockUUIDCount':0,'helperLaunchedApp':False,'helperChangedSave':False})

def capture(label: str, screenshot: bool=False, challenge_id: str|None=None) -> dict:
    s=session(); static=label in STATIC_LABELS
    if static:
        if challenge_id is not None: raise RuntimeError('challenge ID not allowed for static checkpoint')
    else:
        if challenge_id not in ALL_CHALLENGES: raise RuntimeError('non-static checkpoint must name one of the 15 known challenge IDs')
        if not re.fullmatch(rf'battle_{re.escape(challenge_id)}_attempt_[0-9]{{2}}',label): raise RuntimeError('battle checkpoint label mismatch')
    if label=='cold_before' and screenshot: raise RuntimeError('cold_before is a snapshot only')
    if screenshot and not static and challenge_id is None: raise RuntimeError('optional screenshot only allowed for a named challenge attempt')
    if screenshot and len(list(OUT.glob('checkpoints/*/screen.png')))>=MAX_SHOTS: raise RuntimeError('six screenshot maximum reached')
    if static and (OUT/'checkpoints'/label).exists(): raise RuntimeError('checkpoint label already used')
    if challenge_id:
        prior=[p for p in (OUT/'checkpoints').glob(f'battle_{challenge_id}_attempt_[0-9][0-9]') if p.is_dir()]
        expected_attempt=f'battle_{challenge_id}_attempt_{len(prior)+1:02d}'
        if label!=expected_attempt: raise RuntimeError(f'challenge attempt label must be next unused {expected_attempt}')
    app=Path(s['installedApp']); data=Path(s['installedData']); exe=app/'WitchGathering'
    if sha_file(exe)!=s['executableSHA256']: raise RuntimeError('installed R445 executable changed')
    pids=app_pids(exe)
    if len(pids)!=1: raise RuntimeError(f'expected exactly one Root-owned visible app process; observed {pids}')
    support=data/SUPPORT
    if support.is_symlink() or not support.is_dir(): raise RuntimeError('game support folder missing/unsafe')
    dest=OUT/'checkpoints'/label; dest.parent.mkdir(exist_ok=True); dest.mkdir(exist_ok=False)
    archive=dest/'support'; archive.mkdir()
    files={}; copied=0
    for p in sorted(support.iterdir()):
        if p.is_symlink() or p.is_dir(): raise RuntimeError(f'unexpected support entry: {p.name}')
        if not p.is_file() or p.name=='save.json.lock': continue
        st0=p.stat(); raw=p.read_bytes(); st1=p.stat()
        if (st0.st_ino,st0.st_size,st0.st_mtime_ns)!=(st1.st_ino,st1.st_size,st1.st_mtime_ns): raise RuntimeError('support changed while capturing; retain partial folder')
        copied+=len(raw)
        if copied>2_000_000: raise RuntimeError('support archive exceeds 2MB/checkpoint')
        q=archive/p.name; fd=os.open(q,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'wb') as f: f.write(raw); f.flush(); os.fsync(f.fileno())
        files[p.name]={'sha256':sha(raw),'sizeBytes':len(raw),'sourceMode':st1.st_mode&0o777,'archiveMode':q.stat().st_mode&0o777}
    for name in REQUIRED_SUPPORT:
        if name not in files: raise RuntimeError(f'checkpoint missing required support snapshot {name}')
    env=snapshot_of(archive/'save.json'); snap=env['snapshot']; equip=validate_equipment(snap,set(s['currentEquippedUUIDs']))
    event=challenge_event(snap,support,challenge_id) if challenge_id else None
    shot=None
    if screenshot:
        if output_bytes()+4_000_000>MAX_BYTES: raise RuntimeError('4MB screenshot reserve unavailable')
        path=dest/'screen.png'; command(['xcrun','simctl','io',DEVICE,'screenshot',str(path)],timeout=30)
        if not path.is_file() or path.stat().st_size<=0 or path.is_symlink(): raise RuntimeError('screenshot missing/invalid')
        shot={'path':str(path.relative_to(OUT)),'sha256':sha_file(path),'bytes':path.stat().st_size}
    row={'label':label,'capturedAt':stamp(),'revision':snap.get('revision'),'saveSHA256':sha_file(archive/'save.json'),
      'completedChallengeClearIDs':sorted(challenge_clears(snap)),'unlockedRegionIDs':sorted(map(str,snap.get('unlockedRegionIDs',[]))),
      'activeRegionID':snap.get('activeRegionID'),'regionLabelMatches':(label.startswith('region_') and snap.get('activeRegionID')==label[-3:]) if label.startswith('region_') else True,
      'equippedLoadout':equip,'gearCount':len(snap.get('gear',[])),'receiptObjectCount':len(receipt_objects(env)),
      'gachaPity':snap.get('gachaPity'),'mockPurchaseRecords':snap.get('mockPurchaseRecords'),
      'naturalGearRecordCount':len(snap.get('naturalGearDiscoveryR350',{}).get('acquisitionRecords',[])),'summonReceipts':summon_receipts(env),
      'challengeAttempt':event,'files':files,'appPIDsObserved':pids,'screenshot':shot,'snapshotOnly':True,'operatorActions':'Root ordinary UI'}
    write_once(dest/'CHECKPOINT.json',row)
    if output_bytes()>MAX_BYTES: raise RuntimeError('35MB evidence cap exceeded; retain and close incomplete')
    return row

def next_challenge_attempt(challenge_id: str) -> str:
    if challenge_id not in ALL_CHALLENGES: raise RuntimeError('challenge is not one of the 15 known challenge IDs')
    existing=[p for p in (OUT/'checkpoints').glob(f'battle_{challenge_id}_attempt_[0-9][0-9]') if p.is_dir()]
    return f'battle_{challenge_id}_attempt_{len(existing)+1:02d}'

def close() -> dict:
    if not (OUT/'SESSION.json').is_file(): raise RuntimeError('R449 session missing')
    s=json.loads((OUT/'SESSION.json').read_bytes())
    rows={}; bad=[]
    for d in sorted((OUT/'checkpoints').glob('*')):
        if not d.is_dir() or d.is_symlink(): continue
        p=d/'CHECKPOINT.json'
        if not p.is_file(): bad.append({'label':d.name,'error':'checkpoint metadata missing'}); continue
        try: rows[d.name]=json.loads(p.read_bytes())
        except Exception as e: bad.append({'label':d.name,'error':f'{type(e).__name__}: {e}'})
    missing_static=sorted(set(STATIC_LABELS)-set(rows))
    screenshot_errors=[]
    for label,row in rows.items():
        d=OUT/'checkpoints'/label; arch=d/'support'; exp=row.get('files',{})
        if not isinstance(exp,dict) or not arch.is_dir(): bad.append({'label':label,'error':'support archive/map missing'}); continue
        names={p.name for p in arch.iterdir() if p.is_file() and not p.is_symlink()}
        if names!=set(exp): bad.append({'label':label,'error':'support archive filenames differ'})
        for n,m in exp.items():
            p=arch/n
            if p.is_symlink() or not p.is_file() or sha_file(p)!=m.get('sha256') or p.stat().st_size!=m.get('sizeBytes') or (p.stat().st_mode&0o777)!=m.get('archiveMode'):
                bad.append({'label':label,'file':n,'error':'support archive hash/size/mode mismatch'})
    actual_shots={str(p.relative_to(OUT)) for p in OUT.glob('checkpoints/*/screen.png') if p.is_file() and not p.is_symlink()}
    required_shots={f'checkpoints/{x}/screen.png' for x in STATIC_SHOTS}
    optional_challenge_shots={p for p in actual_shots if re.fullmatch(r'checkpoints/battle_CH_R0[1-5]_0[1-3]_attempt_[0-9]{2}/screen.png',p)}
    if not required_shots.issubset(actual_shots) or len(actual_shots)>MAX_SHOTS or actual_shots-required_shots!=optional_challenge_shots or len(optional_challenge_shots)>1:
        screenshot_errors.append({'required':sorted(required_shots),'actual':sorted(actual_shots),'max':MAX_SHOTS})
    for label,row in rows.items():
        sp=OUT/'checkpoints'/label/'screen.png'; declared=row.get('screenshot')
        if sp.exists() and (declared is None or sp.is_symlink() or not sp.is_file() or sha_file(sp)!=declared.get('sha256') or sp.stat().st_size!=declared.get('bytes')):
            screenshot_errors.append({'label':label,'error':'screenshot hash/size mismatch'})
    # Every challenge is attempted in this run; old clear markers are not evidence of its new outcome.
    winning_attempts={}
    attempt_errors=[]
    for label,row in rows.items():
        event=row.get('challengeAttempt')
        if event is None: continue
        cid=event.get('challengeID')
        if cid not in ALL_CHALLENGES or not label.startswith(f'battle_{cid}_attempt_'):
            attempt_errors.append({'label':label,'error':'unexpected challenge attempt identity'}); continue
        if not event.get('resultConsistent'):
            attempt_errors.append({'label':label,'challengeID':cid,'result':'sidecar/save/result disagreement'})
        if event.get('outcome')=='WIN' and event.get('clearMarkerPresent'):
            winning_attempts[cid]=label
    missing_wins=sorted(set(ALL_CHALLENGES)-set(winning_attempts))
    loadout_bad=sorted(label for label,row in rows.items() if isinstance(row.get('equippedLoadout'),dict) and row['equippedLoadout'].get('valid') is not True)
    region_bad=sorted(label for label,row in rows.items() if label.startswith('region_') and row.get('regionLabelMatches') is not True)
    cold_before=rows.get('cold_before',{}); cold_after=rows.get('cold_after',{})
    p_before=OUT/'checkpoints/cold_before/support/save.json'; p_after=OUT/'checkpoints/cold_after/support/save.json'
    rb=p_before.read_bytes() if p_before.is_file() and not p_before.is_symlink() else None
    ra=p_after.read_bytes() if p_after.is_file() and not p_after.is_symlink() else None
    hb=sha(rb) if rb is not None else None; ha=sha(ra) if ra is not None else None
    cold_equal=bool(rb is not None and ra is not None and rb==ra and hb==cold_before.get('saveSHA256') and ha==cold_after.get('saveSHA256'))
    pb=set(cold_before.get('appPIDsObserved',[])); pa=set(cold_after.get('appPIDsObserved',[])); cold_distinct=bool(pb and pa and pb.isdisjoint(pa))
    data=Path(s['installedData']); live_save=data/SUPPORT/'save.json'; live_sha=sha_file(live_save) if live_save.is_file() and not live_save.is_symlink() else None
    cold_live=bool(ha and live_sha==ha)
    try: after=inventory(data); inventory_error=None
    except Exception as e: after={}; inventory_error=f'{type(e).__name__}: {e}'
    before=s['dataInventoryBefore']; missing=sorted(set(before)-set(after)); new=sorted(set(after)-set(before)); changed=sorted(k for k in set(before)&set(after) if before[k]!=after[k])
    support_prefix=str(SUPPORT)+'/'; mutable={support_prefix+n for n in MUTABLE_SUPPORT}
    allowed_changed=sorted(x for x in changed if x in mutable); allowed_new=sorted(x for x in new if x in mutable)
    allowed_missing=sorted(x for x in missing if x in mutable)
    cache_prefix=str(OWN_CACHE)+'/'; metal_prefix=str(OWN_METAL)+'/'; state_prefix=str(OWN_SAVED_STATE)+'/'; saved_state_parent='Library/Saved Application State/'
    own_cache_before={k:v for k,v in before.items() if k.startswith(cache_prefix)}; own_cache_after={k:v for k,v in after.items() if k.startswith(cache_prefix)}
    cache_missing=sorted(set(own_cache_before)-set(own_cache_after)); cache_new=sorted(set(own_cache_after)-set(own_cache_before)); cache_changed=sorted(k for k in set(own_cache_before)&set(own_cache_after) if own_cache_before[k]!=own_cache_after[k])
    state_before={k:v for k,v in before.items() if k.startswith(state_prefix)}; state_after={k:v for k,v in after.items() if k.startswith(state_prefix)}
    state_missing=sorted(set(state_before)-set(state_after)); state_new=sorted(set(state_after)-set(state_before)); state_changed=sorted(k for k in set(state_before)&set(state_after) if state_before[k]!=state_after[k])
    # System/app cache files are separately measured, not counted as user-save changes.
    def special(k:str)->bool: return k.startswith(cache_prefix) or k.startswith(state_prefix)
    unexpected_missing=sorted(x for x in missing if x not in mutable and not special(x))
    unexpected_new=sorted(x for x in new if x not in mutable and not special(x))
    unexpected_changed=sorted(x for x in changed if x not in mutable and not special(x))
    required_missing=sorted(support_prefix+n for n in REQUIRED_SUPPORT if support_prefix+n not in after)
    try:
        ir,br,app,data2=validate_install(); app_exact=True; protected_exact=True; install_error=None
        app_exact=tree(app)==s['appFiles']; protected_exact=ir.get('protectedTrees')==s['protectedTreesBefore']
    except Exception as e: app_exact=False; protected_exact=False; install_error=f'{type(e).__name__}: {e}'
    remaining_pids=app_pids(Path(s['installedApp'])/'WitchGathering') if s.get('installedApp') else []
    elapsed=time.time()-float(s['startedEpoch']); size=output_bytes()
    final_snap=snapshot_of(p_after)['snapshot'] if p_after.is_file() and not p_after.is_symlink() else {}
    final_clears=challenge_clears(final_snap)
    all15=final_clears=={f'CHALLENGE_CLEAR|{x}' for x in ALL_CHALLENGES}
    final_equipment=validate_equipment(final_snap,set(s['currentEquippedUUIDs'])) if final_snap else {'valid':False,'reason':'final snapshot missing'}
    final_env=snapshot_of(p_after) if p_after.is_file() and not p_after.is_symlink() else {}
    gacha_unchanged=(final_snap.get('gachaPity')==s['initialGachaPity'] and final_snap.get('mockPurchaseRecords')==s['initialMockPurchaseRecords']
        and summon_receipts(final_env)==s['initialSummonReceipts']) if final_snap else False
    support_ok=not required_missing and not allowed_missing
    preservation_ok=(inventory_error is None and not unexpected_missing and not unexpected_new and not unexpected_changed and support_ok and not cache_missing and not state_missing)
    checks={'staticCheckpointsComplete':not missing_static,'screenshotSetValid':not screenshot_errors,'challengeAttemptsConsistent':not attempt_errors,
      'allFifteenChallengesWonDuringRun':not missing_wins,'allFifteenChallengeClearsPresent':all15,
      'zeroMockEquippedLoadoutPreserved':final_equipment.get('valid') is True and not loadout_bad,'historicalMockGachaStateUnchanged':gacha_unchanged,
      'regionCheckpointsMatchActiveRegion':not region_bad,
      'coldSaveByteExact':cold_equal,'coldRestartDistinctProcess':cold_distinct,'liveSaveEqualsColdAfter':cold_live,
      'installedR445AppExact':app_exact,'historicalR420R437TreesExact':protected_exact,'noUnownedAppProcess':not remaining_pids,
      'nonMutableDataPreserved':preservation_ok,'wallAndEvidenceCaps':elapsed<=MAX_WALL and size<=MAX_BYTES}
    status='CLOSED_CAPTURE_RECORDED' if all(checks.values()) and inventory_error is None and install_error is None and not bad else 'INCOMPLETE_RETAINED'
    report={'schema':'native-challenge-completion-r449-close-v1','status':status,'closedAt':stamp(),'elapsedSeconds':elapsed,'evidenceBytes':size,
      'limits':{'wallSeconds':MAX_WALL,'evidenceBytes':MAX_BYTES,'screenshotsMax':MAX_SHOTS,'screenshotsActual':len(actual_shots)},
      'checks':checks,'missingStaticCheckpoints':missing_static,'missingChallengeWins':missing_wins,'winningAttemptCheckpointByChallenge':winning_attempts,
      'challengeAttemptErrors':attempt_errors,'checkpointsWithLoadoutMismatch':loadout_bad,'regionCheckpointMismatches':region_bad,
      'archiveErrors':bad,'screenshotErrors':screenshot_errors,'inventoryError':inventory_error,'installError':install_error,
      'initialRevision':BASELINE_REVISION,'initialSaveSHA256':BASELINE_SHA,'finalRevision':final_snap.get('revision'),'finalSaveSHA256':ha,'liveSaveSHA256':live_sha,
      'initialChallengeClears':sorted(START_CLEARED),'finalChallengeClears':sorted(final_clears),'finalHasAll15Challenges':all15,
      'initialEquippedUUIDs':s['currentEquippedUUIDs'],'finalEquippedLoadout':final_equipment,'initialGachaPity':s['initialGachaPity'],
      'finalGachaPity':final_snap.get('gachaPity'),'initialMockPurchaseRecords':s['initialMockPurchaseRecords'],'finalMockPurchaseRecords':final_snap.get('mockPurchaseRecords'),
      'initialSummonReceipts':s['initialSummonReceipts'],'finalSummonReceipts':summon_receipts(final_env) if final_env else [],
      'historicalQualification':{'priorChallengeClearCount':7,'challengeTargetsAttemptedDuringRun':list(ALL_CHALLENGES),'historicalMockDrawCount':5,
         'mockDrawOperationID':s['knownHistoricalMockDraw']['mockFiveOperationID'],'mockGearUUIDs':MOCK_GEAR,
         'currentEquippedMockUUIDs':sorted(final_equipment.get('historicalMockUUIDsEquipped',[])),
         'qualification':'Prior mock draw and seven prior challenge wins are retained as history; the five known mock UUIDs were not equipped at baseline and the run requires the same equipped UUID set throughout.'},
      'dataAllowedSupportChanged':allowed_changed,'dataAllowedSupportNew':allowed_new,'dataAllowedSupportMissing':allowed_missing,
      'dataUnexpectedMissing':unexpected_missing,'dataUnexpectedNew':unexpected_new,'dataUnexpectedChanged':unexpected_changed,'requiredSupportMissing':required_missing,
      'appOwnedCaches':{'root':str(OWN_CACHE),'beforeCount':len(own_cache_before),'afterCount':len(own_cache_after),'new':cache_new,'changed':cache_changed,'missing':cache_missing},
      'savedApplicationState':{'root':str(OWN_SAVED_STATE),'beforeCount':len(state_before),'afterCount':len(state_after),'new':state_new,'changed':state_changed,'missing':state_missing},
      'coldBeforeAfterSaveSHAEqual':cold_equal,'coldRestartDistinctPIDs':cold_distinct,'appPIDsStillRunning':remaining_pids,
      'helperLaunchedOrChangedGameData':False,'normalUIActionsBy':'Root','releaseAcceptance':False,
      'scopeLimit':'Local ordinary UI evidence for attempts at all 15 challenges on this R445 save. Seven earlier clear markers and five historic mock draws remain prior history; prior markers do not prove a new battle outcome and replays do not imply first-clear rewards. This is not a pristine-profile or formal design/art acceptance.'}
    write_once(OUT/'CLOSURE.json',report)
    return report

def main() -> None:
    p=argparse.ArgumentParser(); sp=p.add_subparsers(dest='phase',required=True)
    sp.add_parser('prepare')
    c=sp.add_parser('checkpoint'); c.add_argument('label',choices=STATIC_LABELS); c.add_argument('--screenshot',action='store_true')
    b=sp.add_parser('challenge'); b.add_argument('challenge_id',choices=ALL_CHALLENGES); b.add_argument('--screenshot',action='store_true')
    sp.add_parser('close'); a=p.parse_args()
    if a.phase=='prepare': prepare()
    elif a.phase=='checkpoint': capture(a.label,a.screenshot)
    elif a.phase=='challenge':
        label=next_challenge_attempt(a.challenge_id); row=capture(label,a.screenshot,a.challenge_id)
        print(json.dumps({'checkpoint':label,'challengeAttempt':row.get('challengeAttempt')},ensure_ascii=False,sort_keys=True))
    else:
        report=close(); print(json.dumps({'status':report['status'],'checks':report['checks'],'missingChallengeWins':report['missingChallengeWins']},ensure_ascii=False,sort_keys=True))
if __name__=='__main__': main()

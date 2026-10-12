#!/usr/bin/env python3
"""Bounded normal-pace candidate enemy integration capture; isolated fixture only."""
import argparse
import datetime as dt
import fcntl
import hashlib
import json
from pathlib import Path
import shutil
import signal
import subprocess
import time
import uuid
from state_transition_capture import validate_normal_build, restore_fixed_receipts

DEVICE = '1D034CC3-9259-4AEE-A21D-E6E88D242ACF'
BUNDLE = 'local.witch.autonomous.r1'
ENEMIES = ('E_R05_04', 'E_R03_02', 'E_R02_04', 'E_R04_02', 'E_R02_03')

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p, v): p.write_text(json.dumps(v, ensure_ascii=False, indent=2)+'\n')
def cmd(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=35).strip()
def fresh(p, after, predicate):
    if p.is_file() and p.stat().st_mtime >= after:
        try:
            v=json.loads(p.read_text())
            if predicate(v): return v
        except (ValueError, KeyError, TypeError): pass
    return None

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--app',type=Path,required=True); ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--enemy',action='append',choices=ENEMIES,help='Repeat for a bounded batch; default preserves the original plant/bat pair.')
    a=ap.parse_args(); app=a.app.resolve(); out=a.output.resolve()
    selected=a.enemy or list(ENEMIES[:2])
    if len(selected)!=len(set(selected)): ap.error('Duplicate enemy selection is not allowed')
    build=validate_normal_build(app,app.parent/'BUILD_RECEIPT.json')
    if build['status']!='SIMULATOR_BUILD_PASS' or not all(build['checks'].values()): raise ValueError('invalid frozen build')
    lock=(Path('/tmp')/f'witch-loop-qa-{DEVICE}.lock').open('a')
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    out.mkdir(parents=True,exist_ok=False);shutil.copy2(app.parent/'BUILD_RECEIPT.json',out/'BUILD_RECEIPT.json')
    cmd('xcrun','simctl','install',DEVICE,str(app))
    support=Path(cmd('xcrun','simctl','get_app_container',DEVICE,BUNDLE,'data'))/'Library/Application Support/Witch03to05R1'
    before={}; backup=out/'prior_fixed_receipts';backup.mkdir()
    for p in sorted(support.glob('*.json')):
        if p.name.startswith('last_') or p.name in ('battle_before.json','runtime_metrics.json'):
            st=p.stat();data=p.read_bytes();before[p.name]={'bytes':data,'atime_ns':st.st_atime_ns,'mtime_ns':st.st_mtime_ns,'mode':st.st_mode&0o777}
            (backup/p.name).write_bytes(data)
    report={'status':'RUNNING','scope':'ISOLATED_CHALLENGE_FIXTURE_NORMAL_PACE_NOT_EARNED_BALANCE_OR_HUMAN_ACCEPTANCE','startedAt':dt.datetime.now().astimezone().isoformat(),'app':str(app),'executableSHA256':sha(app/'WitchGathering'),'selectedEnemyIDs':selected,'cases':[]}
    write(out/'RUN.json',report)
    try:
        for enemy in selected:
            case=out/enemy;case.mkdir();key='candidate-battle-'+uuid.uuid4().hex
            save=support/('qa-'+key+'-save.json');assert not save.exists()
            row={'enemyID':enemy,'saveKey':key,'status':'RUNNING'};report['cases'].append(row)
            log=(case/'record.log').open('w'); video=case/'battle.mp4'
            proc=subprocess.Popen(['xcrun','simctl','io',DEVICE,'recordVideo','--codec=h264',str(video)],stdout=log,stderr=subprocess.STDOUT)
            row['recorderStartedUnix']=time.time()
            try:
                time.sleep(.4);start=time.time();row['launchStartedUnix']=start
                args=['--qa-isolated','--qa-save-key='+key,'--qa-fixture=challenge','--qa-persist-fixture','--qa-encounter='+enemy]
                row['launchArguments']=args;row['launchResult']=cmd('xcrun','simctl','launch','--terminate-running-process',DEVICE,BUNDLE,*args)
                deadline=time.monotonic()+120;shot=False; result=None
                while time.monotonic()<deadline:
                    if not shot and time.time()-start>=4:
                        cmd('xcrun','simctl','io',DEVICE,'screenshot',str(case/'battle.png'));shot=True
                    result=fresh(support/'last_battle.json',start,lambda v: enemy in v.get('value',''))
                    resolution=fresh(support/'last_battle_resolution.json',start,lambda v: json.loads(v['value']).get('saveFile')==save.name)
                    if result and resolution: break
                    time.sleep(.1)
                if not result or not resolution: raise TimeoutError('matching battle completion missing')
                for name in ('last_battle.json','last_battle_art.json','last_battle_resolution.json','last_presentation_hp.json','battle_before.json',save.name):
                    p=support/name
                    if not p.is_file() or p.stat().st_mtime<start: raise ValueError('missing or stale '+name)
                    shutil.copy2(p,case/name)
                saved=json.loads(save.read_text())['snapshot'];initial=json.loads((case/'battle_before.json').read_text())
                value=json.loads(resolution['value']); hp=json.loads(json.loads((case/'last_presentation_hp.json').read_text())['value'])
                row['checks']={'expectedEnemy':saved['lastEncounterID']==enemy and value['enemyID']==enemy,'won':saved['lastCombatResult']['won'] is True and value['won'] is True,'revisionOnce':saved['revision']==initial['revision']+1,'receiptRevisionMatches':result['revision']==saved['revision'],'hpMatches':hp=={},'resolutionNotCancelled':not value['cancelled'],'resolutionSamples':bool(value['samples'])}
                row['revisionBefore']=initial['revision'];row['revisionAfter']=saved['revision']
                cmd('xcrun','simctl','io',DEVICE,'screenshot',str(case/'result.png'))
            finally:
                if proc.poll() is None: proc.send_signal(signal.SIGINT)
                row['recorderExitCode']=proc.wait(timeout=25);log.close()
                subprocess.run(['xcrun','simctl','terminate',DEVICE,BUNDLE],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=20)
                raw=case/'fresh_fixed_receipts';raw.mkdir()
                for p in support.glob('*.json'):
                    if p.stat().st_mtime>=row.get('launchStartedUnix',float('inf')) and (p.name.startswith('last_') or p.name in ('battle_before.json','runtime_metrics.json')): shutil.copy2(p,raw/p.name)
                if video.exists():
                    probe=subprocess.run(['ffprobe','-v','error','-show_format','-of','json',str(video)],capture_output=True,text=True,timeout=30)
                    (case/'video_probe.json').write_text(probe.stdout)
                    decoded=subprocess.run(['ffmpeg','-v','error','-i',str(video),'-fps_mode','passthrough','-f','null','-'],capture_output=True,text=True,timeout=60)
                    row['mediaChecks']={'recorderExit0':row['recorderExitCode']==0,'probeExit0':probe.returncode==0,'decodeExit0':decoded.returncode==0,'positiveDuration':float(json.loads(probe.stdout).get('format',{}).get('duration',0))>0 if probe.returncode==0 else False}
                    (case/'decode.log').write_text(decoded.stderr);row['videoSHA256']=sha(video)
            media=row.get('mediaChecks',{})
            row['status']='PASS_TECHNICAL_REQUIRES_VISUAL_REVIEW' if row.get('checks') and all(row['checks'].values()) and set(media)=={'recorderExit0','probeExit0','decodeExit0','positiveDuration'} and all(media.values()) else 'FAIL'
            row['filesSHA256']={str(p.relative_to(case)):sha(p) for p in case.rglob('*') if p.is_file()}
            write(case/'RESULT.json',row);write(out/'RUN.json',report)
            if row['status']=='FAIL': raise ValueError('case checks failed')
        report['exactSelectedCoverage']=[row['enemyID'] for row in report['cases']]==selected
        if not report['exactSelectedCoverage']: raise ValueError('selected case coverage mismatch')
        report['status']='PASS_TECHNICAL_REQUIRES_VISUAL_REVIEW'
    except Exception as error:
        report['status']='FAIL';report['error']=repr(error)
    finally:
        restored=restore_fixed_receipts(support,before);report['priorFixedReceiptRestoration']=restored
        if not all(restored.values()): report['status']='FAIL'
        report['finishedAt']=dt.datetime.now().astimezone().isoformat();write(out/'RUN.json',report)
    print(json.dumps({k:report.get(k) for k in ('status','error','finishedAt')}))
    return 0 if report['status']=='PASS_TECHNICAL_REQUIRES_VISUAL_REVIEW' else 1

if __name__=='__main__': raise SystemExit(main())

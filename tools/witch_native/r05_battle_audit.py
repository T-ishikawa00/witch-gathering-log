#!/usr/bin/env python3
"""Run the six R05 encounters through the normal game command path on 9A QA sim.
Uses one fresh isolated save per encounter; never touches the normal save.
"""
from pathlib import Path
import argparse, collections, hashlib, json, os, signal, subprocess, time

DEVICE='9A067715-7CF3-40D3-9064-38423223959B'
BUNDLE='local.witch.autonomous.r1'
R05_IDS=['E_R05_01','E_R05_02','E_R05_03','E_R05_04','B_R05_A','B_R05_B']

def run(*cmd): return subprocess.check_output(cmd,text=True,stderr=subprocess.STDOUT).strip()
def sha(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()
def read_json(path):
    try:return json.loads(Path(path).read_text())
    except Exception:return None
def record_video(path):
    return subprocess.Popen(['xcrun','simctl','io',DEVICE,'recordVideo',str(path)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,start_new_session=True,text=True)
def stop_video(proc):
    if proc.poll() is None:
        os.killpg(proc.pid,signal.SIGINT)
    try: out=proc.communicate(timeout=12)[0]
    except subprocess.TimeoutExpired:
        proc.kill();out=proc.communicate()[0]
    return out

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--app',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--timeout',type=int,default=180);a=ap.parse_args()
    app=a.app.resolve();out=a.output.resolve()
    if out.exists():raise SystemExit(f'Output already exists; refusing to overwrite: {out}')
    receipt_path=app.parent/'BUILD_RECEIPT.json';receipt=read_json(receipt_path)
    if not receipt or receipt.get('bundle')!=str(app) or receipt.get('status')!='SIMULATOR_BUILD_PASS':raise SystemExit('App receipt missing/mismatched/not a simulator build pass')
    if receipt.get('png_decode_validation')!='PASS' or receipt.get('source_stability')!='PASS':raise SystemExit('Build receipt lacks PNG decode/source stability PASS')
    exe=app/'WitchGathering'
    exe_sha=sha(exe)
    if exe_sha!=receipt.get('executable_sha256'):raise SystemExit('Executable SHA does not match build receipt')
    # Fail early if the frame that was corrupt in R029 is not a decodable image.
    from PIL import Image
    frame=app/'Art/GeneratedCandidates/ACT_B_R05_A/rest_hit_resolve_r001/frames/pose_002.png'
    with Image.open(frame) as img:img.verify()
    catalog=read_json(app/'catalog_overlay.json')
    if not catalog:raise SystemExit('Bundled candidate catalog unreadable')
    enemies={e['id']:e for e in catalog.get('enemies',[])}
    if any(eid not in enemies for eid in R05_IDS):raise SystemExit('R05 catalog IDs incomplete')
    out.mkdir(parents=True)
    run('xcrun','simctl','install',DEVICE,str(app))
    folder=Path(run('xcrun','simctl','get_app_container',DEVICE,BUNDLE,'data'))/'Library/Application Support/Witch03to05R1'
    report={'schema':'r05_normal_battle_audit_r001','app':str(app),'buildReceipt':str(receipt_path),'executableSHA256':exe_sha,'device':DEVICE,'fixture':'challenge (endgame-only isolated QA fixture; not earned progression)','commandPath':'GameModel.fight -> GameEngine.resolveEncounter -> R6TimelineSimulator -> normal BattlePlayback','status':'RUNNING','cases':[]}
    (out/'RUN.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    for eid in R05_IDS:
        case=out/eid;case.mkdir();key=f'r05-battle-r030-{eid.replace("_","-")}'
        save=folder/f'qa-{key}-save.json';battle=folder/'last_battle.json';before=folder/'battle_before.json';art=folder/'last_battle_art.json';hp=folder/'last_presentation_hp.json'
        # Preserve previous receipt metadata for freshness checks; do not delete another run's QA files.
        old_mtime=battle.stat().st_mtime_ns if battle.exists() else 0
        video=case/'normal_battle.mp4';rec=record_video(video);time.sleep(.75)
        launch_started=time.time()
        launch_output=run('xcrun','simctl','launch','--terminate-running-process',DEVICE,BUNDLE,'--qa-isolated','--qa-save-key='+key,'--qa-fixture=challenge','--qa-encounter='+eid,'--qa-slow-battle')
        time.sleep(2.5)
        run('xcrun','simctl','io',DEVICE,'screenshot',str(case/'battle_2_5s.png'))
        deadline=time.monotonic()+a.timeout;resolved_at=None;battle_obj=None
        while time.monotonic()<deadline:
            obj=read_json(battle)
            if obj and battle.stat().st_mtime_ns>old_mtime and battle.stat().st_mtime>=launch_started and obj.get('kind')=='battle' and eid in str(obj.get('value','')):
                resolved_at=time.monotonic();battle_obj=obj;break
            time.sleep(.5)
        if resolved_at is not None:
            time.sleep(3.5)
            run('xcrun','simctl','io',DEVICE,'screenshot',str(case/'after_resolve_3_5s.png'))
        stoplog=stop_video(rec)
        row={'enemyID':eid,'regionID':enemies[eid]['regionID'],'saveKey':key,'launchOutput':launch_output,'receiptFresh':resolved_at is not None,'postReceiptVideoSeconds':round(time.monotonic()-resolved_at,2) if resolved_at else None,'videoExists':video.exists(),'videoSHA256':sha(video) if video.exists() else None,'videoProbe':None}
        if video.exists():
            probe=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(video)],text=True,capture_output=True)
            row['videoProbe']={'returncode':probe.returncode,'durationSeconds':float(probe.stdout.strip()) if probe.returncode==0 and probe.stdout.strip() else None,'stderr':probe.stderr.strip()}
        if not resolved_at:
            row['timeoutReceipt']=read_json(battle)
        if save.exists():
            final_bytes=save.read_bytes();(case/'save.json').write_bytes(final_bytes);snap=read_json(save).get('snapshot',{})
            row['saveSHA256']=hashlib.sha256(final_bytes).hexdigest();row['revisionAfter']=snap.get('revision');row['lastEncounterID']=snap.get('lastEncounterID')
            combat=snap.get('lastCombatResult') or {};row.update({'won':combat.get('won'),'eventCount':len(combat.get('events',[])),'lastEventMs':max((e.get('timestampMs',e.get('tick',0)*1000) for e in combat.get('events',[])),default=0),'eventKinds':dict(collections.Counter(e.get('kind','?') for e in combat.get('events',[])))})
        if before.exists():
            bbytes=before.read_bytes();(case/'battle_before.json').write_bytes(bbytes);bsnap=read_json(before) or {};row['beforeSHA256']=hashlib.sha256(bbytes).hexdigest();row['revisionBefore']=bsnap.get('revision')
            after=read_json(save) if save.exists() else {};after=after.get('snapshot',{})
            row['revisionDelta']=after.get('revision',0)-bsnap.get('revision',0)
            bmat=bsnap.get('materials',{});amat=after.get('materials',{});row['materialDelta']={k:amat.get(k,0)-bmat.get(k,0) for k in set(bmat)|set(amat) if amat.get(k,0)!=bmat.get(k,0)}
            bcoin=bsnap.get('currency',{}).get('coin',0);acoin=after.get('currency',{}).get('coin',0);row['coinDelta']=acoin-bcoin
        for src,name in [(battle,'last_battle.json'),(art,'last_battle_art.json'),(hp,'last_presentation_hp.json')]:
            if src.exists() and src.stat().st_mtime>=launch_started:(case/name).write_bytes(src.read_bytes());row[name+'SHA256']=sha(case/name)
        if art.exists() and art.stat().st_mtime>=launch_started:
            artjson=read_json(art);row['battleArtReceipt']=artjson
        row['captureProcessTail']=stoplog[-1000:]
        report['cases'].append(row);report['status']='RUNNING';(out/'RUN.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        print(json.dumps({'enemyID':eid,'receiptFresh':row['receiptFresh'],'won':row.get('won'),'lastEventMs':row.get('lastEventMs'),'postReceiptVideoSeconds':row['postReceiptVideoSeconds'],'durationSeconds':(row.get('videoProbe') or {}).get('durationSeconds')},ensure_ascii=False),flush=True)
        if not row['receiptFresh'] or row.get('lastEncounterID')!=eid or row.get('postReceiptVideoSeconds',0)<3.0:
            report['status']='STOPPED_INCOMPLETE_CASE';break
    else: report['status']='ALL_SIX_CAPTURED_REQUIRES_INDEPENDENT_VISUAL_REVIEW'
    (out/'RUN.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()

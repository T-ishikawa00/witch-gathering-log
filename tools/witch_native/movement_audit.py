#!/usr/bin/env python3
"""Record authored movement and short hit/recovery states on an isolated simulator."""
from pathlib import Path
import argparse,hashlib,json,shutil,signal,subprocess,time
DEVICE='1D034CC3-9259-4AEE-A21D-E6E88D242ACF'
BUNDLE='local.witch.autonomous.r1'
def run(*cmd):return subprocess.check_output(cmd,text=True,stderr=subprocess.STDOUT).strip()
STATES=['idle','walk','anticipate','execute','recover','hit','resolve']
def read_fresh(path, launched, actor, completed=False):
    try:
        if path.stat().st_mtime < launched:return None
        receipt=json.loads(path.read_text());value=receipt.get('value')
        if not completed:return receipt if value==actor+':idle' else None
        payload=json.loads(value)
        if payload.get('actorIDs') != [actor]:return None
        if not all(payload.get('states',{}).get(actor+':'+s) is True for s in STATES):return None
        return receipt
    except (OSError,ValueError,TypeError):return None
def wait_receipt(path, launched, actor, completed=False, timeout=30):
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        receipt=read_fresh(path,launched,actor,completed)
        if receipt:return receipt
        time.sleep(.1)
    raise RuntimeError('Fresh matching receipt not received: '+actor+' '+str(path))
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--app',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--include-flight',action='store_true');ap.add_argument('--dragon-mesh-r004',action='store_true');ap.add_argument('actors',nargs='+');a=ap.parse_args()
    app=a.app.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    run('xcrun','simctl','install',DEVICE,str(app))
    folder=Path(run('xcrun','simctl','get_app_container',DEVICE,BUNDLE,'data'))/'Library/Application Support/Witch03to05R1'
    report={'app':str(app),'sha256':hashlib.sha256((app/'WitchGathering').read_bytes()).hexdigest(),'device':DEVICE,'dragonMeshR004Requested':a.dragon_mesh_r004,'status':'RECORDING','cases':[]}
    for actor in a.actors:
        log=(out/(actor+'_video.log')).open('w')
        recorder=subprocess.Popen(['xcrun','simctl','io',DEVICE,'recordVideo','--codec=h264',str(out/(actor+'.mp4'))],stdout=log,stderr=subprocess.STDOUT)
        start=time.monotonic();launched=time.time();failure=None;ready=None
        try:
            extra=['--qa-art-flight'] if a.include_flight else []
            if a.dragon_mesh_r004: extra.append('--qa-dragon-mesh-r004')
            run('xcrun','simctl','launch','--terminate-running-process',DEVICE,BUNDLE,'--qa-isolated','--qa-save-key='+out.name.replace('_','-')+'-'+actor.replace('_','-'),'--art-audit='+actor,*extra)
            ready_receipt=wait_receipt(folder/'last_art_state.json',launched,actor,timeout=20);ready=time.monotonic()
            (out/(actor+'_ready.json')).write_text(json.dumps(ready_receipt,indent=2))
            times=[2.1,2.5,2.9,3.3,3.7,4.1,6.1,8.1,10.1,12.1]
            if a.include_flight: times += [14.1,14.5,16.1,18.1,18.5,20.1]
            for t in times:
                time.sleep(max(0,t-(time.monotonic()-ready)))
                run('xcrun','simctl','io',DEVICE,'screenshot',str(out/(actor+'_'+str(t)+'s.png')))
            receipt=wait_receipt(folder/'last_art_audit.json',launched,actor,completed=True,timeout=20)
            (out/(actor+'_receipt.json')).write_text(json.dumps(receipt,indent=2))
            samples={}
            for state in STATES+(['flight'] if a.include_flight else []):
                for phase in ['early','late']:
                    source=folder/('last_art_sample_'+state+'_'+phase+'.json')
                    if source.exists() and source.stat().st_mtime>=launched:
                        raw=json.loads(source.read_text());payload=json.loads(raw['value'])
                        if payload.get('actorIDs')==[actor]:
                            samples[state+'_'+phase]=payload.get('enemyPresentation',{}).get(actor,{})
                            shutil.copy2(source,out/(actor+'_'+source.name))
            (out/(actor+'_presentation_samples.json')).write_text(json.dumps(samples,indent=2))
            if a.include_flight:
                payload=json.loads(receipt['value'])
                assert payload.get('states',{}).get(actor+':flight') is True, 'Explicit flight request failed'
                assert samples.get('flight_late',{}).get('state')=='flight', 'Flight receipt missing or stale'
                assert samples.get('idle_late',{}).get('state')=='idle', 'Flight/walk did not return to idle'
                assert not samples['flight_late']['partRig']['walkLegOverlayActive'], 'Ground legs active in flight'
                assert not samples['idle_late']['partRig']['walkLegOverlayActive'], 'Ground legs remain after idle'
                walk=samples.get('walk_late',{}).get('partRig',{})
                if a.dragon_mesh_r004 and actor=='ACT_B_R04_B':
                    pair=[samples['walk_'+phase]['partRig'] for phase in ['early','late']]
                    assert all(s.get('walkMeshActive') and s.get('walkMeshGeometryPresent') and s.get('walkMeshActionRunning') for s in pair), 'Walk mesh not active'
                    assert all(not s['walkLegOverlayActive'] for s in pair), 'Old crop overlay remains visible'
                    assert all(s.get('bodySubdivisionLevels')==0 for s in pair), 'Mesh subdivision mismatch'
                    assert pair[0].get('walkMeshReadback') != pair[1].get('walkMeshReadback'), 'Mesh getter did not change'
                    for state in ['idle','flight','anticipate','execute','recover','hit','resolve']:
                        for phase in ['early','late']:
                            rig=samples[state+'_'+phase]['partRig']
                            assert not rig.get('walkMeshActive') and not rig.get('walkMeshGeometryPresent') and not rig.get('walkMeshActionRunning'), 'Mesh leaked into '+state+' '+phase
                elif walk.get('walkLegOverlayStatus')=='candidate_ready_unapproved':
                    pair=[samples['walk_'+phase]['partRig'] for phase in ['early','late']]
                    assert all(s['walkLegOverlayActive'] for s in pair), 'Ground overlay was not enabled for walk'
                    assert {s['walkLegOverlayFrameIndex'] for s in pair}=={0,1}, 'Two ground leg frames were not observed'
                    assert all(s.get('walkMeshStatus')=='not_enabled' and not s.get('walkMeshActive') for s in pair), 'Mesh unexpectedly enabled without opt-in'
            time.sleep(max(0,16-(time.monotonic()-ready)))
        except Exception as exc:
            failure=str(exc)
            for name in ['last_art_audit.json','last_art_state.json','runtime_metrics.json']:
                evidence=folder/name
                if evidence.exists():shutil.copy2(evidence,out/(actor+'_failure_'+name))
        finally:
            recorder.send_signal(signal.SIGINT);recorder.wait(timeout=15);log.close()
        video=out/(actor+'.mp4');report['cases'].append({'actor':actor,'video':video.name,'sha256':hashlib.sha256(video.read_bytes()).hexdigest(),'elapsedSeconds':time.monotonic()-start,'readyOffsetSeconds':None if ready is None else ready-start,'receiptVerified':failure is None,'error':failure,'screenshotTimingOrigin':'fresh matching idle receipt; independent of launch latency'})
        (out/'RUN.json').write_text(json.dumps(report,indent=2));print(actor,flush=True)
    report['status']='CAPTURED_REQUIRES_VISUAL_REVIEW' if all(c['receiptVerified'] for c in report['cases']) else 'FAILED_RECEIPT_VALIDATION';(out/'RUN.json').write_text(json.dumps(report,indent=2))
    if report['status']=='FAILED_RECEIPT_VALIDATION':raise SystemExit(1)
if __name__=='__main__':main()

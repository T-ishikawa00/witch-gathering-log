#!/usr/bin/env python3
"""Capture equipped candidates with fresh state receipts and per-layer load checks."""
from pathlib import Path
import argparse,hashlib,json,signal,subprocess,time
from party_motion_audit import DEVICE,BUNDLE,run,wait,validated_geometry,field_heights
STATES=['idle','walk','anticipate','execute','recover','hit','resolve']
def main():
 p=argparse.ArgumentParser();p.add_argument('--app',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--device',default=DEVICE);p.add_argument('--scene-width',type=float,default=440);p.add_argument('--compact-field',action='store_true');p.add_argument('fixtures',nargs='+');a=p.parse_args()
 device=a.device;heights=field_heights(a.scene_width,a.compact_field)
 app=a.app.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);run('xcrun','simctl','install',device,str(app))
 folder=Path(run('xcrun','simctl','get_app_container',device,BUNDLE,'data'))/'Library/Application Support/Witch03to05R1'
 report={'app':str(app),'executableSHA256':hashlib.sha256((app/'WitchGathering').read_bytes()).hexdigest(),'scope':'ISOLATED_EQUIPPED_CANDIDATES_NOT_EARNED_PROGRESSION','device':device,'independentExpectedHeights':heights,'cases':[]}
 for fixture in a.fixtures:
  case=out/fixture;case.mkdir();log=(case/'video.log').open('w');rec=subprocess.Popen(['xcrun','simctl','io',device,'recordVideo','--codec=h264',str(case/'motion.mp4')],stdout=log,stderr=subprocess.STDOUT);launched=time.time();error=None
  try:
   run('xcrun','simctl','launch','--terminate-running-process',device,BUNDLE,'--qa-isolated','--qa-save-key='+out.name.replace('_','-')+'-'+fixture,'--qa-fixture='+fixture,'--qa-party-motion')
   ready=wait(folder/'last_party_state.json',launched,lambda d:d.get('value')=='idle');origin=time.monotonic();(case/'ready.json').write_text(json.dumps(ready,indent=2))
   for at in [.1,.6,1.6,2.15,2.5,2.85,4.15,6.15,8.15,10.15,12.15,14.15]:
    time.sleep(max(0,at-(time.monotonic()-origin)));run('xcrun','simctl','io',device,'screenshot',str(case/(str(at)+'s.png')))
    raw=validated_geometry(folder,launched,expected_heights=heights);(case/(str(at)+'s_geometry.json')).write_bytes(raw)
   final=wait(folder/'last_party_art.json',launched,lambda d:all(json.loads(d['value']).get('states',{}).get(actor+':'+s) is True for actor in ['ERNA','LUNA','AIRA','NOIR'] for s in STATES))
   data=json.loads(final['value']);appearance=data['appearance'];states=data['states']
   if fixture.startswith('book-'):
    if appearance.get('APPRENTICE_BOOK_GEAR') != fixture[5:]:raise RuntimeError('Wrong equipped book projection')
    if not all(states.get('LUNA:book_'+s) is True for s in STATES):raise RuntimeError('Missing book/body motion state')
   if fixture.startswith('details-'):
    selected={v for k,v in appearance.items() if k.startswith('DETAIL|')}
    if not selected:raise RuntimeError('No equipped detail projection')
    failed=[gear+':'+s for gear in selected for s in STATES if states.get('detail_'+gear+':'+s) is not True]
    if failed:raise RuntimeError('Missing detail textures or states: '+repr(failed))
   (case/'receipt.json').write_text(json.dumps(final,indent=2));time.sleep(max(0,16-(time.monotonic()-origin)))
  except Exception as exc:error=str(exc)
  finally:rec.send_signal(signal.SIGINT);rec.wait(timeout=15);log.close()
  report['cases'].append({'fixture':fixture,'error':error,'stateAndGeometryVerified':error is None,'videoSHA256':hashlib.sha256((case/'motion.mp4').read_bytes()).hexdigest(),'humanApproved':False,'naturalMotionComplete':False})
  (out/'RUN.json').write_text(json.dumps(report,indent=2));print(fixture,error or 'CAPTURED',flush=True)
 report['status']='CAPTURED_REQUIRES_VISUAL_REVIEW' if all(c['error'] is None for c in report['cases']) else 'FAILED';(out/'RUN.json').write_text(json.dumps(report,indent=2))
 if report['status']=='FAILED':raise SystemExit(1)
if __name__=='__main__':main()

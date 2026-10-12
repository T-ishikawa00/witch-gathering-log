#!/usr/bin/env python3
"""Capture candidate body/staff motion with fresh QA state/actor verification."""
from pathlib import Path
import argparse,hashlib,json,signal,subprocess,time
DEVICE='1D034CC3-9259-4AEE-A21D-E6E88D242ACF';BUNDLE='local.witch.autonomous.r1'
ACTOR_HEIGHTS={'ERNA':145.57214,'LUNA':145.57214,'AIRA':145.57214,'NOIR':78.80597}
def field_heights(scene_width,compact=False):
    """Independent field-layout expectation; caller supplies observed scene size.

    Do not derive the baseline from the renderer's own expected-height receipt:
    a renderer regression can make both its expected and actual values wrong.
    """
    if scene_width<=0:raise ValueError('Scene width must be positive')
    return {actor:(72 if actor=='NOIR' else 102 if compact else 133)*scene_width/402 for actor in ACTOR_HEIGHTS}
def run(*args):return subprocess.check_output(args,text=True,stderr=subprocess.STDOUT).strip()
def wait(path,start,predicate,timeout=25):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  try:
   if path.stat().st_mtime>=start:
    d=json.loads(path.read_text())
    if predicate(d):return d
  except (OSError,ValueError,TypeError):pass
  time.sleep(.08)
 raise RuntimeError('Fresh receipt timeout '+str(path))
def validated_geometry(folder,launch_time,timeout=3,expected_heights=None):
    """Return only a geometry receipt newer than its state receipt and containing that state."""
    state_path=folder/'last_party_state.json';geometry_path=folder/'last_party_geometry.json';end=time.monotonic()+timeout;last_error=None
    while time.monotonic()<end:
        try:
            state=json.loads(state_path.read_text());state_mtime=state_path.stat().st_mtime
            if state_mtime < launch_time:raise ValueError('stale party state receipt')
            raw=geometry_path.read_bytes();geom=json.loads(raw);geom_mtime=geometry_path.stat().st_mtime
            if geom_mtime < launch_time or geom_mtime < state_mtime:raise ValueError('stale geometry receipt')
            payload=json.loads(geom['value']);pose=state['value'];states=payload.get('states',{})
            if not all(states.get(actor+':'+pose) is True for actor in ACTOR_HEIGHTS):raise ValueError('geometry does not attest current pose '+pose)
            expected=payload.get('expectedPartyHeights',{});actual=payload.get('geometry',{})
            for actor,baseline in (expected_heights or ACTOR_HEIGHTS).items():
                target=float(expected.get(actor,baseline));height=float(actual[actor]['height'])
                if abs(target-baseline)>0.75 or abs(height-baseline)>0.75:
                    raise ValueError(f'party actor height regression {actor}: expected {baseline}, receipt {target}, actual {height}')
            return raw
        except (OSError,ValueError,TypeError,KeyError) as error:last_error=error;time.sleep(.05)
    raise RuntimeError('Fresh state-matched geometry timeout '+str(geometry_path)+'; last validation error: '+repr(last_error))
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--app',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--default-only',action='store_true');ap.add_argument('--device',default=DEVICE);ap.add_argument('--scene-width',type=float,default=440);ap.add_argument('--compact-field',action='store_true');a=ap.parse_args();device=a.device;heights=field_heights(a.scene_width,a.compact_field);app=a.app.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);run('xcrun','simctl','install',device,str(app));folder=Path(run('xcrun','simctl','get_app_container',device,BUNDLE,'data'))/'Library/Application Support/Witch03to05R1';report={'app':str(app),'sha256':hashlib.sha256((app/'WitchGathering').read_bytes()).hexdigest(),'independentExpectedHeights':heights,'device':device,'cases':[]}
 for costume in ['standard','travel']:
  for weapon in ['branch','moon']:
   if a.default_only and (costume!='standard' or weapon!='branch'):continue
   if a.default_only:weapon='original'
   case=out/(costume+'-'+weapon);case.mkdir();log=(case/'video.log').open('w');rec=subprocess.Popen(['xcrun','simctl','io',device,'recordVideo','--codec=h264',str(case/'motion.mp4')],stdout=log,stderr=subprocess.STDOUT);started=time.time();start=time.monotonic()
   try:
    run('xcrun','simctl','launch','--terminate-running-process',device,BUNDLE,'--qa-isolated','--qa-save-key='+out.name.replace('_','-')+'-'+case.name,'--qa-fixture='+('normal' if a.default_only else 'appearance-'+case.name),'--qa-party-motion')
    ready=wait(folder/'last_party_state.json',started,lambda d:d.get('value')=='idle');at=time.monotonic();(case/'ready.json').write_text(json.dumps(ready,indent=2))
    for t in [.10,.60,1.60,1.85,2.15,2.5,2.85,3.2,3.55,4.15,6.15,8.15,10.15,12.15,14.15]:
     time.sleep(max(0,t-(time.monotonic()-at)));run('xcrun','simctl','io',device,'screenshot',str(case/(str(t)+'s.png')))
     geometry=validated_geometry(folder,started,expected_heights=heights)
     (case/(str(t)+'s_geometry.json')).write_bytes(geometry)
    receipt=wait(folder/'last_party_art.json',started,lambda d:all(json.loads(d['value']).get('states',{}).get(actor+':'+state) is True for actor in ['ERNA','LUNA','AIRA','NOIR'] for state in ['idle','walk','anticipate','execute','recover','hit','resolve']))
    (case/'receipt.json').write_text(json.dumps(receipt,indent=2));time.sleep(max(0,16-(time.monotonic()-at)))
   finally:rec.send_signal(signal.SIGINT);rec.wait(timeout=15);log.close()
   report['cases'].append({'combination':case.name,'videoSHA256':hashlib.sha256((case/'motion.mp4').read_bytes()).hexdigest(),'readyOffsetSeconds':at-start,'allFourActorsSevenStatesAccepted':True,'naturalMotionComplete':False});(out/'RUN.json').write_text(json.dumps(report,indent=2));print(case.name,flush=True)
 report['status']='CAPTURED_REQUIRES_FRAME_GRIP_AND_NATURAL_MOTION_REVIEW';(out/'RUN.json').write_text(json.dumps(report,indent=2))
if __name__=='__main__':main()

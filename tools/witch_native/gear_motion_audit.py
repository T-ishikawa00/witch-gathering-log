#!/usr/bin/env python3
"""Exercise gear-driven body/staff scenes in isolated Simulator fixtures."""
from pathlib import Path
import argparse,hashlib,json,signal,subprocess,time
from party_motion_audit import DEVICE,BUNDLE,run,wait,validated_geometry

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--app',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('gear',nargs='+');args=parser.parse_args()
    app=args.app.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    run('xcrun','simctl','install',DEVICE,str(app))
    folder=Path(run('xcrun','simctl','get_app_container',DEVICE,BUNDLE,'data'))/'Library/Application Support/Witch03to05R1'
    report={'app':str(app),'executableSHA256':hashlib.sha256((app/'WitchGathering').read_bytes()).hexdigest(),'scope':'ISOLATED_GEAR_FIXTURE_NOT_EARNED_PROGRESSION','cases':[]}
    cases=[(gear,costume,False) for gear in args.gear for costume in ['standard','travel']]
    cases += [(args.gear[0],costume,True) for costume in ['standard','travel']]
    for gear,costume,override in cases:
        scenario='gear-'+gear+'-'+costume+('-moon' if override else '')
        case=out/scenario;case.mkdir();log=(case/'video.log').open('w')
        recorder=subprocess.Popen(['xcrun','simctl','io',DEVICE,'recordVideo','--codec=h264',str(case/'motion.mp4')],stdout=log,stderr=subprocess.STDOUT)
        launched=time.time();expected='STAFF_MOON' if override else 'STAFF_'+gear
        try:
            run('xcrun','simctl','launch','--terminate-running-process',DEVICE,BUNDLE,'--qa-isolated','--qa-save-key='+out.name.replace('_','-')+'-'+scenario,'--qa-fixture='+scenario,'--qa-party-motion')
            ready=wait(folder/'last_party_state.json',launched,lambda d:d.get('value')=='idle');origin=time.monotonic();(case/'ready.json').write_text(json.dumps(ready,indent=2))
            for at in [.1,.6,1.6,2.15,2.85,4.15,6.15,8.15,10.15,12.15,14.15]:
                time.sleep(max(0,at-(time.monotonic()-origin)))
                run('xcrun','simctl','io',DEVICE,'screenshot',str(case/(str(at)+'s.png')))
                raw=validated_geometry(folder,launched);payload=json.loads(json.loads(raw)['value'])
                if payload['appearance'].get('WITCH_WEAPON')!=expected:raise RuntimeError('Wrong gear/cosmetic sprite: '+str(payload['appearance']))
                (case/(str(at)+'s_geometry.json')).write_bytes(raw)
            receipt=wait(folder/'last_party_art.json',launched,lambda d:all(json.loads(d['value']).get('states',{}).get(actor+':'+state) is True for actor in ['ERNA','LUNA','AIRA','NOIR'] for state in ['idle','walk','anticipate','execute','recover','hit','resolve']))
            (case/'receipt.json').write_text(json.dumps(receipt,indent=2));time.sleep(max(0,16-(time.monotonic()-origin)))
        finally:recorder.send_signal(signal.SIGINT);recorder.wait(timeout=15);log.close()
        report['cases'].append({'fixture':scenario,'gearID':gear,'costume':costume,'cosmeticOverride':override,'expectedSprite':expected,'videoSHA256':hashlib.sha256((case/'motion.mp4').read_bytes()).hexdigest(),'fourActorSevenStates':True,'geometryAndSpriteReceipt':'PASS','naturalMotionComplete':False,'humanApproval':False})
        (out/'RUN.json').write_text(json.dumps(report,indent=2));print(scenario,flush=True)
    report['status']='CAPTURED_REQUIRES_VISUAL_REVIEW';(out/'RUN.json').write_text(json.dumps(report,indent=2))

if __name__=='__main__':main()

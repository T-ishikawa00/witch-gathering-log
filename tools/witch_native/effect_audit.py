#!/usr/bin/env python3
"""Native emitter load/finite-lifetime evidence; no save or rewards dispatched."""
from pathlib import Path
import argparse,hashlib,json,subprocess,time
from party_motion_audit import DEVICE,BUNDLE,run,wait

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--app',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    app=args.app.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    ids=sorted(json.loads((app/'Art/runtime_index.json').read_text())['effects'])
    run('xcrun','simctl','install',DEVICE,str(app))
    folder=Path(run('xcrun','simctl','get_app_container',DEVICE,BUNDLE,'data'))/'Library/Application Support/Witch03to05R1'
    report={'app':str(app),'executableSHA256':hashlib.sha256((app/'WitchGathering').read_bytes()).hexdigest(),'scope':'ISOLATED_EMITTER_RENDERER_NOT_GAMEPLAY_EVENT_MAPPING','cases':[]}
    for id in ids:
        case=out/id;case.mkdir();launched=time.time()
        run('xcrun','simctl','launch','--terminate-running-process',DEVICE,BUNDLE,'--qa-isolated','--qa-save-key='+out.name.replace('_','-')+'-'+id,'--qa-effect='+id)
        receipt=wait(folder/'last_effect_art.json',launched,lambda d:json.loads(d.get('value','{}')).get('effects',{}).get('last',{}).get('id')==id)
        state=json.loads(receipt['value']);effects=state['effects']
        if effects['activeCombat']<1 or effects['peakCombat']>2 or effects['peakEnvironment']>2:raise RuntimeError('Emitter count contract '+id)
        (case/'receipt.json').write_text(json.dumps(receipt,indent=2))
        run('xcrun','simctl','io',DEVICE,'screenshot',str(case/'impact.png'))
        clean=wait(folder/'last_effect_cleanup.json',launched,lambda d:json.loads(d.get('value','{}')).get('effects',{}).get('activeCombat')==0)
        (case/'cleanup.json').write_text(json.dumps(clean,indent=2))
        run('xcrun','simctl','io',DEVICE,'screenshot',str(case/'cleanup.png'))
        report['cases'].append({'id':id,'load':True,'combatLifetimeEnds':True,'combatEmitterPeak':effects['peakCombat'],'environmentEmitterPeak':effects['peakEnvironment'],'impactScreenshotSHA256':hashlib.sha256((case/'impact.png').read_bytes()).hexdigest(),'normalGameplayMappingVerified':False,'humanApproval':False})
        (out/'RUN.json').write_text(json.dumps(report,indent=2));print(id,flush=True)
    report['status']='PASS_LOAD_AND_LIFETIME_REQUIRES_VISUAL_REVIEW';(out/'RUN.json').write_text(json.dumps(report,indent=2))
if __name__=='__main__':main()

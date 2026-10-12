#!/usr/bin/env python3
"""Capture four actual body/staff combinations, six poses, home and wardrobe."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,time
DEVICE='1D034CC3-9259-4AEE-A21D-E6E88D242ACF'
BUNDLE='local.witch.autonomous.r1'
def run(*cmd):return subprocess.check_output(cmd,text=True,stderr=subprocess.STDOUT).strip()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--app',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
    app=args.app.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    run('xcrun','simctl','install',DEVICE,str(app))
    folder=Path(run('xcrun','simctl','get_app_container',DEVICE,BUNDLE,'data'))/'Library/Application Support/Witch03to05R1'
    report={'app':str(app),'executableSHA256':hashlib.sha256((app/'WitchGathering').read_bytes()).hexdigest(),'device':DEVICE,'status':'CAPTURING_REQUIRES_VISUAL_REVIEW','cases':[]}
    for costume in ['standard','travel']:
        for weapon in ['branch','moon']:
            fixture='appearance-'+costume+'-'+weapon
            for screen,pose in [('仲間',p) for p in ['idle','anticipate','execute','recover','hit','resolve']]+[('家','idle'),('試着','idle')]:
                name=costume+'_'+weapon+'_'+screen+'_'+pose;key=out.name.replace('_','-')+'-'+name.replace('_','-')
                run('xcrun','simctl','launch','--terminate-running-process',DEVICE,BUNDLE,'--qa-isolated','--qa-save-key='+key,'--qa-fixture='+fixture,'--screen='+screen,'--qa-pose='+pose)
                time.sleep(2)
                run('xcrun','simctl','io',DEVICE,'screenshot',str(out/(name+'.png')))
                receipt=folder/'last_appearance_art.json'
                if receipt.exists():shutil.copy2(receipt,out/(name+'_receipt.json'))
                report['cases'].append({'costume':costume,'weapon':weapon,'screen':screen,'pose':pose,'screenshot':name+'.png'})
                (out/'RUN.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
                print(name,flush=True)
    report['status']='32_CAPTURES_COMPLETE_REQUIRES_VISUAL_REVIEW';(out/'RUN.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Capture actual field backgrounds and the authored challenge lamp on dedicated QA."""
import argparse, hashlib, json, shutil, subprocess, time
from pathlib import Path

DEVICE = '1D034CC3-9259-4AEE-A21D-E6E88D242ACF'
BUNDLE = 'local.witch.autonomous.r1'
def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--app',required=True,type=Path);ap.add_argument('--output',required=True,type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    app=args.app.resolve();run('xcrun','simctl','install',DEVICE,str(app))
    record={'app':str(app),'executableSHA256':hashlib.sha256((app/'WitchGathering').read_bytes()).hexdigest(),'device':DEVICE,'cases':[],'status':'RUNNING'}
    def capture(name):run('xcrun','simctl','io',DEVICE,'screenshot',str(out/(name+'.png')))
    def data():return Path(run('xcrun','simctl','get_app_container',DEVICE,BUNDLE,'data'))/'Library/Application Support/Witch03to05R1'
    for actor in [f'ACT_E_R0{n}_01' for n in range(1,6)]+['ACT_B_R04_A']:
        run('xcrun','simctl','launch','--terminate-running-process',DEVICE,BUNDLE,'--qa-isolated','--qa-save-key=scene-'+actor,'--art-audit='+actor)
        time.sleep(2);capture(actor+'_idle');time.sleep(2);capture(actor+'_walk');time.sleep(12)
        receipt=data()/'last_art_audit.json';value=json.loads(receipt.read_text());shutil.copy2(receipt,out/(actor+'_receipt.json'))
        record['cases'].append({'actor':actor,'receipt':value});(out/'RUN.json').write_text(json.dumps(record,indent=2)+'\n');print(actor,flush=True)
    run('xcrun','simctl','launch','--terminate-running-process',DEVICE,BUNDLE,'--qa-isolated','--qa-save-key=lamp-scene-r001','--qa-fixture=challenge','--qa-challenge=CH_R05_02')
    time.sleep(2);capture('lamp_002s');time.sleep(6);capture('lamp_008s');time.sleep(10);capture('lamp_018s')
    time.sleep(60);capture('lamp_result')
    for name in ['last_challenge.json','last_challenge_art.json']:
        if (data()/name).exists():shutil.copy2(data()/name,out/name)
    record['status']='CAPTURE_COMPLETE_REQUIRES_VISUAL_REVIEW';(out/'RUN.json').write_text(json.dumps(record,indent=2)+'\n')
    print(out,flush=True)
if __name__=='__main__':main()

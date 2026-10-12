#!/usr/bin/env python3
"""Verify four cosmetic combinations in actual combat and same-container relaunch."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,time
DEVICE='1D034CC3-9259-4AEE-A21D-E6E88D242ACF'
BUNDLE='local.witch.autonomous.r1'
def run(*cmd):return subprocess.check_output(cmd,text=True,stderr=subprocess.STDOUT).strip()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--app',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
    app=a.app.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);run('xcrun','simctl','install',DEVICE,str(app))
    folder=Path(run('xcrun','simctl','get_app_container',DEVICE,BUNDLE,'data'))/'Library/Application Support/Witch03to05R1'
    report={'app':str(app),'sha256':hashlib.sha256((app/'WitchGathering').read_bytes()).hexdigest(),'device':DEVICE,'status':'RUNNING','cases':[]}
    for costume in ['standard','travel']:
        for weapon in ['branch','moon']:
            name=costume+'-'+weapon;case=out/name;case.mkdir();key=out.name.replace('_','-')+'-'+name;started=time.time()
            run('xcrun','simctl','launch','--terminate-running-process',DEVICE,BUNDLE,'--qa-isolated','--qa-save-key='+key,'--qa-fixture=appearance-'+name,'--qa-encounter=E_R01_01')
            time.sleep(3);run('xcrun','simctl','io',DEVICE,'screenshot',str(case/'battle_003s.png'))
            receipt=folder/'last_battle.json'
            while time.time()-started<150 and not(receipt.exists() and receipt.stat().st_mtime>=started):time.sleep(1)
            if not(receipt.exists() and receipt.stat().st_mtime>=started):raise RuntimeError('battle timeout '+name)
            for f in ['last_battle.json','last_battle_art.json','last_presentation_hp.json','battle_before.json']:
                shutil.copy2(folder/f,case/f)
            path=folder/('qa-'+key+'-save.json');before=path.read_bytes();shutil.copy2(path,case/'save_before_restart.json')
            state=json.loads(before)['snapshot'];run('xcrun','simctl','io',DEVICE,'screenshot',str(case/'result.png'))
            run('xcrun','simctl','launch','--terminate-running-process',DEVICE,BUNDLE,'--qa-isolated','--qa-save-key='+key,'--screen=仲間')
            time.sleep(2);run('xcrun','simctl','io',DEVICE,'screenshot',str(case/'restarted_appearance.png'))
            after=path.read_bytes();shutil.copy2(path,case/'save_after_restart.json')
            row={'combination':name,'won':state['lastCombatResult']['won'],'presentationHPMismatches':json.loads((case/'last_presentation_hp.json').read_text())['value'],'selectedCosmeticIDs':state['selectedCosmeticIDs'],'selectedWeaponAppearanceIDs':state['selectedWeaponAppearanceIDs'],'initialPartyHP':state['lastCombatResult']['initialPartyHP'],'restartBytesUnchanged':before==after,'saveSHA256':hashlib.sha256(after).hexdigest()}
            report['cases'].append(row);(out/'RUN.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(row),flush=True)
    report['status']='COMPLETED_REQUIRES_VISUAL_REVIEW';(out/'RUN.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()

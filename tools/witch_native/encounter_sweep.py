#!/usr/bin/env python3
"""Exercise all actual encounter commands/playback on an isolated Simulator save.

The endgame gear/unlocks are a test fixture, not proof of earning progression.
"""
from pathlib import Path
import argparse,collections,hashlib,json,shutil,subprocess,time

DEVICE='1D034CC3-9259-4AEE-A21D-E6E88D242ACF'
BUNDLE='local.witch.autonomous.r1'
def run(*cmd):return subprocess.check_output(cmd,text=True,stderr=subprocess.STDOUT).strip()
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--app',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    app=args.app.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    catalog=json.loads((app/'catalog_overlay.json').read_text());started=time.monotonic()
    report={'app':str(app),'sha256':hashlib.sha256((app/'WitchGathering').read_bytes()).hexdigest(),'device':DEVICE,'scope':'ENDGAME_FIXTURE_ACTUAL_COMMANDS_AND_REALTIME_PRESENTATION_NOT_PROGRESSION_EVIDENCE','status':'RUNNING','cases':[]}
    run('xcrun','simctl','install',DEVICE,str(app))
    folder=Path(run('xcrun','simctl','get_app_container',DEVICE,BUNDLE,'data'))/'Library/Application Support/Witch03to05R1'
    for enemy in catalog['enemies']:
        eid=enemy['id'];case=out/eid;case.mkdir();key='encounter-'+out.name.replace('_','-')+'-'+eid.replace('_','-');start=time.monotonic()
        run('xcrun','simctl','launch','--terminate-running-process',DEVICE,BUNDLE,'--qa-isolated','--qa-save-key='+key,'--qa-fixture=challenge','--qa-encounter='+eid)
        def capture(name):run('xcrun','simctl','io',DEVICE,'screenshot',str(case/(name+'.png')))
        time.sleep(3);capture('battle_003s')
        path=folder/('qa-'+key+'-save.json');receipt=folder/'last_battle.json'
        completed=False
        while time.monotonic()-start<150:
            if receipt.exists():
                value=json.loads(receipt.read_text())
                if eid in value.get('value','') and receipt.stat().st_mtime>time.time()-(time.monotonic()-start):completed=True;break
            time.sleep(1)
        capture('result' if completed else 'timeout')
        row={'enemyID':eid,'regionID':enemy['regionID'],'completedPlayback':completed,'elapsedSeconds':round(time.monotonic()-start,3)}
        if path.exists():
            shutil.copy2(path,case/'save.json');state=json.loads(path.read_text())['snapshot'];combat=state.get('lastCombatResult',{});before={}
            if (folder/'battle_before.json').exists():shutil.copy2(folder/'battle_before.json',case/'before.json');before=json.loads((case/'before.json').read_text())
            row.update({'won':combat.get('won'),'eventCount':len(combat.get('events',[])),'lastEventMs':max((x.get('timestampMs',x['tick']*1000) for x in combat.get('events',[])),default=0),'kinds':dict(collections.Counter(x['kind'] for x in combat.get('events',[]))),'partyCount':len(combat.get('initialPartyHP',{})),'enemyCount':len(combat.get('initialEnemyHP',{})),'materialDelta':{k:v-before.get('materials',{}).get(k,0) for k,v in state.get('materials',{}).items() if v!=before.get('materials',{}).get(k,0)},'revisionDelta':state['revision']-before.get('revision',0)})
        for name in ['last_battle.json','last_battle_art.json','runtime_metrics.json']:
            if (folder/name).exists():shutil.copy2(folder/name,case/name)
        report['cases'].append(row);report['elapsedSeconds']=round(time.monotonic()-started,3);(out/'RUN.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(row,ensure_ascii=False),flush=True)
        if not completed:report['status']='STOPPED_AT_PLAYBACK_TIMEOUT';break
    else:report['status']='ALL_30_CAPTURED_REQUIRES_VISUAL_REVIEW'
    report['elapsedSeconds']=round(time.monotonic()-started,3);(out/'RUN.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()

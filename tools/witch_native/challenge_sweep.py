#!/usr/bin/env python3
"""Exercise actual challenge playback on the task-created large Simulator.
Fixture gear/progression is explicit QA input, never evidence of earning it.
"""
import argparse,datetime,hashlib,json,subprocess,time,uuid,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
DEVICE='1D034CC3-9259-4AEE-A21D-E6E88D242ACF'
BUNDLE='local.witch.autonomous.r1'
def run(*args):return subprocess.check_output(args,text=True,stderr=subprocess.STDOUT).strip()
def main():
 p=argparse.ArgumentParser();p.add_argument('--app',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--device',default=DEVICE);a=p.parse_args()
 device=a.device
 if device not in [DEVICE,'9A067715-7CF3-40D3-9064-38423223959B','F843518C-7377-434C-A960-B26FB7F34C4B']:raise ValueError('Use an allocated game QA Simulator; StoreKit evidence device is excluded')
 catalog=json.loads((a.app/'catalog_overlay.json').read_text());records=[]
 for challenge in catalog['challenges']:
  if not isinstance(challenge.get('id'),str) or not isinstance(challenge.get('first_clear_powder'),int):raise ValueError('Challenge catalog contract is missing required fields')
 if a.output.exists():raise ValueError('Use a new evidence directory')
 a.output.mkdir(parents=True)
 run('xcrun','simctl','install',device,str(a.app))
 folder=Path(run('xcrun','simctl','get_app_container',device,BUNDLE,'data'))/'Library/Application Support/Witch03to05R1'
 for challenge in catalog['challenges']:
  cid=challenge['id'];key='challenge-'+cid.replace('_','-')+'-'+uuid.uuid4().hex[:8];dest=a.output/cid;dest.mkdir()
  save=folder/f'qa-{key}-save.json'
  setup=time.time();run('xcrun','simctl','launch','--terminate-running-process',device,BUNDLE,'--qa-isolated','--qa-fixture=challenge','--qa-persist-fixture','--qa-save-key='+key)
  while not save.exists() and time.time()-setup<30:time.sleep(.25)
  if not save.exists():raise RuntimeError('Fixture did not persist: '+cid)
  before=json.loads(save.read_text())['snapshot'];shutil.copy2(save,dest/'BEFORE_SAVE.json')
  start=time.time();run('xcrun','simctl','launch','--terminate-running-process',device,BUNDLE,'--qa-isolated','--qa-challenge='+cid,'--qa-save-key='+key)
  frames=[];next_shot=2;receipt=None
  while time.time()-start<150:
   elapsed=time.time()-start
   if elapsed>=next_shot:
    name=f'{int(elapsed):03d}s.png';run('xcrun','simctl','io',device,'screenshot',str(dest/name));frames.append(name);next_shot+=8
   f=folder/'last_challenge.json'
   if f.exists() and f.stat().st_mtime>=start:
    value=json.loads(f.read_text())
    if value['value'].startswith(cid+':'):receipt=value;break
   time.sleep(.4)
  snapshot=json.loads(save.read_text())['snapshot'] if save.exists() else {}
  battle=snapshot.get('lastCombatResult',{})
  art=folder/'last_challenge_art.json';art_state=json.loads(art.read_text()) if art.exists() and art.stat().st_mtime>=start else None
  final='result.png';run('xcrun','simctl','io',device,'screenshot',str(dest/final));frames.append(final)
  saved_bytes=save.read_bytes();shutil.copy2(save,dest/'AFTER_SAVE.json')
  # Reopen this exact isolated namespace without fixture or challenge arguments.
  restarted=time.time();run('xcrun','simctl','launch','--terminate-running-process',device,BUNDLE,'--qa-isolated','--qa-save-key='+key,'--screen=探索')
  load_receipt=folder/'last_candidate_character_growth.json'
  while time.time()-restarted<20:
   if load_receipt.exists() and load_receipt.stat().st_mtime>=restarted:break
   time.sleep(.25)
  reloaded=load_receipt.exists() and load_receipt.stat().st_mtime>=restarted
  run('xcrun','simctl','io',device,'screenshot',str(dest/'restart.png'));frames.append('restart.png')
  checks={'playbackCompleted':receipt is not None,'fourPartyMembers':len(battle.get('initialPartyHP',{}))==4,
          'won':battle.get('won') is True,'clearRecorded':('CHALLENGE_CLEAR|'+cid) in snapshot.get('completedEncounterIDs',[]),
          'firstClearReward':snapshot.get('materials',{}).get('refine_dust',0)-before.get('materials',{}).get('refine_dust',0)==challenge['first_clear_powder'],
          'oneRevision':snapshot.get('revision',0)==before['revision']+1,'savedRegionPreserved':snapshot.get('activeRegionID')==before.get('activeRegionID'),
          'restartLoaded':reloaded,'restartBytesUnchanged':save.read_bytes()==saved_bytes}
  item={'challengeID':cid,'playbackCompleted':receipt is not None,'receipt':receipt,'elapsedSeconds':time.time()-start,'battle':battle,'artReceipt':art_state,'screenshots':frames,'qaSaveSHA256':hashlib.sha256(save.read_bytes()).hexdigest() if save.exists() else None}
  item['checks']=checks;item['technicalStatus']='PASS' if all(checks.values()) else 'FAIL'
  (dest/'RESULT.json').write_text(json.dumps(item,ensure_ascii=False,indent=2));records.append(item)
  report={'status':'RUNNING' if len(records)<len(catalog['challenges']) else 'FINISHED_REQUIRES_VISUAL_REVIEW','scope':'SIMULATOR_CANDIDATE_CHALLENGE_FIXTURE_ACTUAL_COMMAND_AND_PLAYBACK_NOT_UI_SELECTION_OR_EARNED_PROGRESSION','app':str(a.app),'executableSHA256':hashlib.sha256((a.app/'WitchGathering').read_bytes()).hexdigest(),'device':device,'cases':records}
  (a.output/'RUN.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(cid,'completed',receipt is not None,'won',battle.get('won'),'targets',len(battle.get('initialEnemyHP',{})),flush=True)
if __name__=='__main__':main()

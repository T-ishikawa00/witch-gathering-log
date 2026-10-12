#!/usr/bin/env python3
"""Capture exact held body frames; this validates registration, not natural motion."""
import argparse, hashlib, json, time
from pathlib import Path
from party_motion_audit import run, wait, BUNDLE
from frame_source_proof import verify_frame_source,expected_detail_visibility

ACTOR_IDS={'ERNA':'C_WITCH','LUNA':'C_APPRENTICE','AIRA':'C_SMITH','NOIR':'C_FAMILIAR'}

def expected_details(actor,fixture):
    if fixture.startswith('detail-item-'):
        parts=fixture.split('-')
        if len(parts) not in (4,5) or parts[2]!=ACTOR_IDS[actor] or not parts[3].startswith('EQ_'):
            raise ValueError('Single detail fixture must match the audited actor and equipment ID')
        if len(parts)==5 and (actor!='ERNA' or parts[4]!='travel'):
            raise ValueError('Only ERNA supports the travel single-detail fixture')
        # Fresh NOIR fixtures inherit the real new-game catalyst EQ_F_01.
        # Equipping an amulet does not replace that independent weapon slot, so
        # its registration must be present in the exact-keys receipt too.
        # F_02/F_03 fixtures replace the selected catalyst in that same slot.
        return {parts[3], 'EQ_F_01'} if actor=='NOIR' and not parts[3].startswith('EQ_F_') else {parts[3]}
    if not fixture.startswith('details-'):return None
    parts=fixture.split('-')
    if len(parts) not in (3,4) or parts[1]!=ACTOR_IDS[actor] or parts[2] not in ('01','02','03'):
        raise ValueError('Detail fixture must match the audited actor and tier01/02/03')
    if len(parts)==4 and (actor!='ERNA' or parts[3]!='travel'):
        raise ValueError('Only ERNA supports the travel detail fixture')
    tier=parts[2]
    if actor=='NOIR':return {'EQ_AMU_'+tier,'EQ_F_'+tier}
    ids={prefix+tier for prefix in ['EQ_BODY_','EQ_HAND_','EQ_FEET_','EQ_AMU_','EQ_RING_']}
    if actor=='AIRA' and tier!='01':ids.add('EQ_S_'+tier)
    return ids

def unique_save_key(output,actor,fixture,state,index):
    identity='|'.join([str(Path(output).resolve()),actor,fixture])
    return 'frame-'+hashlib.sha256(identity.encode()).hexdigest()[:24]+'-'+state+'-'+str(index)

def detail_ids_match(geometry,expected,state=None,visibility=None):
    if expected is None:return True
    registrations=geometry.get('equipmentRegistration',{})
    if set(registrations)!=expected:return False
    for gear,entry in registrations.items():
        if entry.get('status')!='registered':return False
        if state is not None:
            visible=visibility[gear] if visibility is not None else gear not in {'EQ_F_02','EQ_F_03'} or state in {'anticipate','execute','recover'}
            if entry.get('visible') is not visible:return False
    return True

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--app',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--device',required=True)
    p.add_argument('--fixture',required=True)
    p.add_argument('--actor',choices=['ERNA','LUNA','AIRA','NOIR'],required=True)
    p.add_argument('--frames',default='anticipate:1',help='Comma separated STATE:INDEX')
    a=p.parse_args();app=a.app.resolve();out=a.output.resolve()
    try:expected=expected_details(a.actor,a.fixture)
    except ValueError as error:p.error(str(error))
    out.mkdir(parents=True,exist_ok=False)
    run('xcrun','simctl','install',a.device,str(app))
    folder=Path(run('xcrun','simctl','get_app_container',a.device,BUNDLE,'data'))/'Library/Application Support/Witch03to05R1'
    report={'scope':'ISOLATED_HELD_FRAME_NO_WARP_NOT_MOTION_ACCEPTANCE','app':str(app),'executableSHA256':hashlib.sha256((app/'WitchGathering').read_bytes()).hexdigest(),'actor':a.actor,'fixture':a.fixture,'cases':[]}
    for spec in a.frames.split(','):
        state,index=spec.split(':');index=int(index);case=out/(state+'-'+str(index));case.mkdir()
        launched=time.time();error=None
        try:
            visibility=expected_detail_visibility(app,a.actor,state,index,a.fixture,expected)
            save_key=unique_save_key(out,a.actor,a.fixture,state,index)
            run('xcrun','simctl','launch','--terminate-running-process',a.device,BUNDLE,'--qa-isolated','--qa-save-key='+save_key,'--qa-fixture='+a.fixture,'--qa-party-frame='+a.actor+':'+spec)
            def valid(receipt):
                d=json.loads(receipt['value']);h=d.get('frameHold',{});g=d.get('geometry',{}).get(a.actor,{})
                return h.get('held') and h.get('actor')==a.actor and h.get('state')==state and h.get('index')==index and h.get('renderedFrames',0)>=2 and g.get('isPaused') and g.get('bodyFrameIndex')==index and detail_ids_match(g,expected,state,visibility)
            before=wait(folder/'last_party_frame.json',launched,valid,timeout=15)
            before_data=json.loads(before['value']);(case/'before.json').write_text(json.dumps(before,indent=2))
            source_proof=verify_frame_source(app,a.actor,state,index,a.fixture,before_data['geometry'][a.actor])
            (case/'SOURCE_PROOF.json').write_text(json.dumps(source_proof,indent=2))
            run('xcrun','simctl','io',a.device,'screenshot',str(case/'held.png'))
            captured=time.time()
            after=wait(folder/'last_party_frame.json',captured,lambda r:valid(r) and json.loads(r['value'])['frameHold']['renderedFrames']>before_data['frameHold']['renderedFrames'])
            (case/'after.json').write_text(json.dumps(after,indent=2));after_data=json.loads(after['value'])
            if before_data['geometry'][a.actor]!=after_data['geometry'][a.actor]:raise RuntimeError('Target geometry changed during screenshot')
            result={'state':state,'index':index,'bodyAssetID':after_data['geometry'][a.actor]['bodyAssetID'],'stableHeldGeometry':True,'sourceProof':source_proof,'saveKey':save_key,'expectedDetailIDs':sorted(expected) if expected is not None else None,'screenshotSHA256':hashlib.sha256((case/'held.png').read_bytes()).hexdigest()}
        except Exception as exc:
            error=str(exc);result={'state':state,'index':index,'stableHeldGeometry':False,'error':error}
        report['cases'].append(result);(out/'RUN.json').write_text(json.dumps(report,indent=2));print(spec,error or 'STABLE_HELD_CAPTURE',flush=True)
    report['status']='CAPTURED_REQUIRES_VISUAL_FIT_REVIEW' if all(c['stableHeldGeometry'] for c in report['cases']) else 'FAILED'
    report['humanApproved']=False;report['naturalMotionComplete']=False
    (out/'RUN.json').write_text(json.dumps(report,indent=2))
    if report['status']=='FAILED':raise SystemExit(1)
if __name__=='__main__':main()

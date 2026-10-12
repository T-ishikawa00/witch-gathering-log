"""Resolve held actor frames against the supplied frozen app, never the worktree."""
import hashlib,json,struct
from functools import lru_cache
from pathlib import Path

@lru_cache(maxsize=32)
def document(path):
    return json.loads(Path(path).read_text())

def expected_frame(app,actor,state,index,fixture):
    app=Path(app)
    if actor=='ERNA':
        # LayeredMotion has its own frozen runtime manifest. Do not infer a
        # body path from neighboring PartyRest/PartyAttack assets: ERNA's
        # selected costume may render e.g. travel__cast_5.png instead.
        if fixture.endswith('-travel') or fixture.startswith('appearance-travel-'):
            costume='travel'
        elif fixture.startswith(('details-C_WITCH-','detail-item-C_WITCH-','appearance-standard-')):
            costume='standard'
        else:
            raise ValueError('ERNA fixture does not identify a supported costume')
        entry=document(str(app/'GeneratedArt/LayeredMotion/MANIFEST.json'))[costume]
        clip=entry.get(state)
        if not isinstance(clip,dict) or not isinstance(clip.get('frames'),list):
            raise ValueError('ERNA state is absent from frozen LayeredMotion manifest')
        frames=clip['frames']
        if not isinstance(index,int) or index<0 or index>=len(frames):
            raise ValueError('ERNA state/index is outside frozen LayeredMotion manifest')
        return 'GeneratedArt/LayeredMotion/'+frames[index]['path'],entry['canvas']
    if actor=='LUNA':
        rows=document(str(app/'Art/runtime_index.json'))['entries'][actor]['semanticFrameLandmarksCandidate']['rows']
        selected=[r for r in rows if r.get('sourceRowState')==state and r['frameIndex']==index]
        if len(selected)!=1:raise ValueError('LUNA state/index must have exactly one frozen registry row')
        return selected[0]['bodyAssetID'],selected[0]['canvas_px']
    directory='PartyWalk' if state=='walk' else 'PartyRest' if state in ('idle','hit','resolve') else 'PartyAttack'
    entry=document(str(app/f'GeneratedArt/{directory}/MANIFEST.json'))[actor]
    frames=entry['frames'] if state=='walk' else entry['clips'][state]['frames']
    return f'GeneratedArt/{directory}/'+frames[index],entry['canvas']

def verify_frame_source(app,actor,state,index,fixture,geometry):
    app=Path(app).resolve()
    expected_id,canvas=expected_frame(app,actor,state,index,fixture)
    if geometry.get('bodyAssetID')!=expected_id or geometry.get('bodyFrameIndex')!=index:
        raise ValueError('Rendered body identity does not match frozen state/index manifest')
    if [geometry.get('bodyCanvasWidth'),geometry.get('bodyCanvasHeight')]!=canvas:
        raise ValueError('Rendered canvas does not match frozen manifest')
    candidates=[app/expected_id] if expected_id.endswith('.png') else [app/'Art'/(expected_id+'.png'),app/'GeneratedArt'/(expected_id+'.png')]
    path=next((p for p in candidates if p.is_file()),None)
    if path is None:raise ValueError('Rendered body source PNG absent from supplied app')
    raw=path.read_bytes()
    if raw[:8]!=b'\x89PNG\r\n\x1a\n' or list(struct.unpack('>II',raw[16:24]))!=canvas:
        raise ValueError('Actual PNG canvas differs from frozen manifest')
    digest=hashlib.sha256(raw).hexdigest()
    if actor=='ERNA':
        costume='travel' if fixture.endswith('-travel') or fixture.startswith('appearance-travel-') else 'standard'
        motion=document(str(app/'GeneratedArt/LayeredMotion/MANIFEST.json'))[costume]
        frames=motion[state]['frames']
        row=frames[index]
        if row.get('path') != Path(expected_id).name:
            raise ValueError('LayeredMotion row path differs from the rendered body identity')
        if row.get('sha256')!=digest:
            raise ValueError('LayeredMotion manifest SHA differs from actual body PNG')
        if motion.get('canvas')!=canvas:
            raise ValueError('LayeredMotion manifest canvas differs from actual body PNG')
        manifest_scope='FROZEN_LAYERED_MOTION_MANIFEST_AND_BUNDLE_RESOURCE_RECEIPT_NOT_VISUAL_FIT'
    else:
        rows=document(str(app/'Art/runtime_index.json'))['entries'][actor]['semanticFrameLandmarksCandidate']['rows']
        matching=[r for r in rows if r['bodyAssetID']==expected_id and r['frameIndex']==index]
        if len(matching)!=1 or matching[0]['canvas_px']!=canvas:
            raise ValueError('Missing, duplicate or wrong-canvas frozen semantic registration')
        if matching[0].get('sourceSHA256')!=digest:
            raise ValueError('Frozen semantic source SHA differs from actual body PNG')
        manifest_scope='FROZEN_BUNDLE_REGISTRY_AND_MOTION_MANIFESTS_NOT_VISUAL_FIT'
    receipt=document(str(app.parent/'BUILD_RECEIPT.json'))
    relative=path.relative_to(app).as_posix()
    resource=receipt.get('resource_sha256',{}).get(relative)
    if resource!=digest:raise ValueError('Body PNG SHA differs from build receipt: '+relative)
    return {'bodyAssetID':expected_id,'frameIndex':index,'canvas':canvas,'bundlePath':relative,'sha256':digest,'buildReceiptSHA256':resource,'manifestScope':manifest_scope}

def expected_detail_visibility(app,actor,state,index,fixture,gears):
    if gears is None:return None
    asset,_=expected_frame(app,actor,state,index,fixture)
    entries=document(str(Path(app)/'Art/runtime_index.json'))['entries']
    result={gear:gear not in {'EQ_F_02','EQ_F_03'} or state in {'anticipate','execute','recover'} for gear in gears}
    for gear in gears:
        name=None
        if gear.startswith('EQ_AMU_'):name='chest'
        elif gear.startswith('EQ_FEET_'):name='visibleRightAnkle'
        elif actor in ('ERNA','LUNA','AIRA') and gear.startswith('EQ_RING_'):
            name='workingPalm' if actor=='AIRA' else 'freePalm'
        elif actor in ('ERNA','LUNA','AIRA') and gear.startswith('EQ_HAND_'):
            name='workingHand' if actor=='AIRA' else 'freeHand'
        elif actor in ('ERNA','LUNA') and gear=='EQ_BODY_03':name='neck'
        if name is not None:
            semantic=entries[actor]['semanticFrameLandmarksCandidate']['rows']
            matches=[r for r in semantic if r['bodyAssetID']==asset and r['frameIndex']==index]
            if len(matches)==1 and matches[0].get('landmarkVisibility',{}).get(name)=='occluded':
                result[gear]=False
        underlay=entries.get('DETAIL_'+gear,{}).get('bodyUnderlayFrameCandidate')
        if underlay is None:continue
        rows=[r for r in underlay['rows'] if r['actorID']==actor and r['bodyAssetID']==asset and r['frameIndex']==index]
        if len(rows)!=1 or not isinstance(rows[0].get('visible'),bool):
            raise ValueError('Underlay registration is unresolved for this exact body frame: '+gear)
        result[gear]=rows[0]['visible']
    return result

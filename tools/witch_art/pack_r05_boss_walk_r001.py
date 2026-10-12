#!/usr/bin/env python3
"""Pack additive R05 boss movement candidates while retaining exact source RGBA."""
from pathlib import Path
import hashlib, json
import numpy as np
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[2]; ART=ROOT/'native/Art'
CANVAS=(512,588); ANCHOR=(256,480); DISPLAY_SCALE=588/512
ITEMS=[{
 'id':'ACT_B_R05_A','rev':'rooted_ring_guard_cycle_r002','atlas':ART/'GeneratedCandidates/ACT_B_R05_A/ring_guard_motion_r001/imagegen_atlas_retry.png',
 'source':'ActorStills/ACT_B_R05_A/ACT_B_R05_A__still__r001.png','base':'runtime_overlay_act_b_r05_a_pose_candidate_r002.json',
 'overlay':'runtime_overlay_act_b_r05_a_pose_candidate_r004_rooted_motion_cycle.json',
 'semantic':'rooted_construct_ring_tilt_blade_guard_sweep_and_return_not_translating_walk',
 'limit':'Rooted pedestal remains stationary. Ring/arms articulate as a rooted guard motion rather than ordinary locomotion; native scale and continuity require review.'
}]

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

items_out=[]
for it in ITEMS:
    aid=it['id']; atlas=Image.open(it['atlas']).convert('RGBA'); src=ART/it['source']; base=json.loads((ART/it['base']).read_text())['entries'][aid]
    xs=[round(i*atlas.width/3) for i in range(4)]; ys=[round(i*atlas.height/3) for i in range(4)]
    out=ART/'GeneratedCandidates'/aid/it['rev'];(out/'frames').mkdir(parents=True,exist_ok=True)
    (out/'imagegen_atlas_source.png').write_bytes(it['atlas'].read_bytes());(out/'identity_reference_still.png').write_bytes(src.read_bytes())
    frames=[]; records=[]; rels=[]
    for i in range(9):
        row,col=divmod(i,3); box=(xs[col],ys[row],xs[col+1],ys[row+1]);cell=atlas.crop(box);a=np.asarray(cell.getchannel('A')); y,x=np.where(a>16)
        if not len(x): raise SystemExit(f'empty cell {i}')
        edge=int((a[[0,-1],:]>16).sum()+(a[:,[0,-1]]>16).sum())
        if edge: raise SystemExit(f'alpha>16 cell edge {aid}/{i}: {edge}')
        l,t,r,b=cell.getchannel('A').getbbox();dx=round(CANVAS[0]/2-(x.min()+x.max())/2);dy=ANCHOR[1]-int(y.max())
        if l+dx<0 or r+dx>CANVAS[0] or t+dy<0 or b+dy>CANVAS[1]: raise SystemExit(f'full alpha clip {aid}/{i} bbox={(l,t,r,b)} shift={(dx,dy)}')
        frame=Image.new('RGBA',CANVAS,(0,0,0,0));frame.alpha_composite(cell,(dx,dy))
        aa=np.asarray(frame.getchannel('A'))
        if int(np.count_nonzero(aa))!=int(np.count_nonzero(a)): raise SystemExit(f'alpha changed {aid}/{i}')
        name=f'walk_{i:03}.png';dest=out/'frames'/name;frame.save(dest);frames.append(frame)
        rel=f'GeneratedCandidates/{aid}/{it["rev"]}/frames/{name}';rels.append(rel);py,px=np.where(aa>16)
        records.append({'frame':name,'source_cell_px':[box[0],box[1],box[2]-box[0],box[3]-box[1]],'source_alpha16_margins_ltrb':[int(x.min()),int(y.min()),cell.width-1-int(x.max()),cell.height-1-int(y.max())],'source_alpha16_edge_pixels':edge,'translation_px':[dx,dy],'packed_alpha16_bbox':[int(px.min()),int(py.min()),int(px.max())+1,int(py.max())+1],'source_alpha_nonzero_pixels':int(np.count_nonzero(a)),'packed_alpha_nonzero_pixels':int(np.count_nonzero(aa)),'alpha_preserved_exactly':True,'sha256':sha(dest)})
    panel=Image.new('RGB',(1536,3*(CANVAS[1]+30)),(27,34,43));draw=ImageDraw.Draw(panel)
    for i,frame in enumerate(frames):
        xx=(i%3)*512; yy=(i//3)*(CANVAS[1]+30);bg=Image.new('RGBA',CANVAS,(27,34,43,255));bg.alpha_composite(frame);panel.paste(bg.convert('RGB'),(xx,yy+30));draw.text((xx+8,yy+6),f'{aid} / {i:03}',fill='white')
    panel.save(out/'qa_contact_sheet.jpg',quality=94)
    entry=json.loads(json.dumps(base));entry.setdefault('sequenceFrames',{})['walk']=rels
    entry.setdefault('clips',{})['walk']={'frames':rels,'frame_count':9,'fps':8,'duration_seconds':1.125,'loop':True,'complete_animation':False,'status':'UNAPPROVED_NINE_FRAME_MOTION_CANDIDATE_NOT_NATURAL_MOTION_COMPLETE','canvas_px':list(CANVAS),'anchor':list(ANCHOR),'anchor_status':'VISUAL_ESTIMATE_UNAPPROVED','movement_semantics':it['semantic'],'display_scale':DISPLAY_SCALE,'quality_limit':it['limit']}
    entry['status']='UNAPPROVED_PARTIAL_MOTION_CANDIDATE';entry['complete_animation']=False
    ov={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'candidate_manifest':f'GeneratedCandidates/{aid}/{it["rev"]}/manifest.json','entries':{aid:entry}}
    (ART/it['overlay']).write_text(json.dumps(ov,ensure_ascii=False,indent=2)+'\n')
    manifest={'schema':'witch.enemy_motion_candidate.v1','asset_id':aid,'revision':it['rev'],'approval':'UNAPPROVED_CANDIDATE_PENDING_ROOT_NATIVE_SCREEN_REVIEW','natural_motion_complete':False,'source_still_path':it['source'],'source_still_sha256':sha(src),'atlas_path':f'GeneratedCandidates/{aid}/{it["rev"]}/imagegen_atlas_source.png','atlas_sha256':sha(out/'imagegen_atlas_source.png'),'atlas_px':list(atlas.size),'grid_x':xs,'grid_y':ys,'frame_canvas_px':list(CANVAS),'anchor_candidate_px':list(ANCHOR),'display_scale_candidate':DISPLAY_SCALE,'movement_semantics':it['semantic'],'registration':'Exact cell RGBA preserved; centered by alpha16 horizontal bounds and feet/ground baseline. Translation only, no resize, recolor or alpha cleanup.','frames':records,'qa_contact_sheet':f'GeneratedCandidates/{aid}/{it["rev"]}/qa_contact_sheet.jpg','runtime_overlay':it['overlay'],'visual_status':'UNAPPROVED_CANDIDATE_PENDING_ROOT_NATIVE_SCREEN_REVIEW','limitations':[it['limit'],'Canvas expansion preserves faint source pixels; renderer scale must be inspected.']}
    (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');items_out.append(manifest)
report={'schema':'r05_boss_motion_candidates_r001','approval':'UNAPPROVED_CANDIDATES','natural_motion_complete':False,'items':items_out}
(ROOT/'docs/production/current/art/R05_boss_motion_candidates_r001.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps([{'id':m['asset_id'],'canvas':m['frame_canvas_px'],'overlay':m['runtime_overlay'],'contact':m['qa_contact_sheet']} for m in items_out],ensure_ascii=False))

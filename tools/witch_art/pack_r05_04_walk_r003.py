#!/usr/bin/env python3
"""Pack the repaired R05_04 quadruped walk atlas without alpha edits."""
from pathlib import Path
import hashlib, json
import numpy as np
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'native/Art'
ACTOR='ACT_E_R05_04'
REV='moon_bloom_beast_quadruped_walk_cycle_r003'
ATLAS=ART/'GeneratedCandidates/ACT_E_R05_04'/REV/'imagegen_atlas_source.png'
BASE=ART/'runtime_overlay_act_e_r05_04_pose_candidate_r004_walk_cycle.json'
OVERLAY=ART/'runtime_overlay_act_e_r05_04_pose_candidate_r005_walk_cycle.json'
OUT=ART/'GeneratedCandidates/ACT_E_R05_04'/REV
CANVAS=(512,592); ANCHOR=(256,490)

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

atlas=Image.open(ATLAS).convert('RGBA')
if atlas.size!=(1254,1254): raise SystemExit(f'unexpected atlas {atlas.size}')
base=json.loads(BASE.read_text())['entries'][ACTOR]
still=ART/'ActorStills/ACT_E_R05_04/ACT_E_R05_04__still__r001.png'
xs=[round(i*atlas.width/3) for i in range(4)]; ys=[round(i*atlas.height/3) for i in range(4)]
frames=[]; records=[]; rels=[]
(OUT/'frames').mkdir(parents=True,exist_ok=True)
for i in range(9):
    row,col=divmod(i,3); box=(xs[col],ys[row],xs[col+1],ys[row+1]); cell=atlas.crop(box)
    a=np.asarray(cell.getchannel('A')); y,x=np.where(a>16)
    if not len(x): raise SystemExit(f'empty cell {i}')
    edge=int((a[[0,-1],:]>16).sum()+(a[:,[0,-1]]>16).sum())
    if edge: raise SystemExit(f'alpha16 at cell edge {i}: {edge}')
    full=cell.getchannel('A').getbbox(); l,t,r,b=full
    dx=round(CANVAS[0]/2-(x.min()+x.max())/2)
    dy=ANCHOR[1]-int(y.max())
    if min(l+dx,t+dy)<0 or r+dx>CANVAS[0] or b+dy>CANVAS[1]: raise SystemExit(f'full alpha clips in cell {i}: {full} {(dx,dy)}')
    frame=Image.new('RGBA',CANVAS,(0,0,0,0)); frame.alpha_composite(cell,(dx,dy))
    if np.count_nonzero(np.asarray(frame)[:,:,3])!=np.count_nonzero(a): raise SystemExit(f'alpha count changed cell {i}')
    name=f'walk_{i:03}.png'; dest=OUT/'frames'/name; frame.save(dest); frames.append(frame)
    rel=f'GeneratedCandidates/{ACTOR}/{REV}/frames/{name}'; rels.append(rel)
    aa=np.asarray(frame.getchannel('A')); py,px=np.where(aa>16)
    records.append({'frame':name,'source_cell_px':[box[0],box[1],box[2]-box[0],box[3]-box[1]],'source_alpha16_bbox':[int(x.min()),int(y.min()),int(x.max())+1,int(y.max())+1],'source_alpha16_bottom_margin':int(cell.height-1-y.max()),'source_alpha16_edge_pixels':edge,'translation_px':[dx,dy],'packed_alpha16_bbox':[int(px.min()),int(py.min()),int(px.max())+1,int(py.max())+1],'packed_alpha_nonzero_pixel_count':int(np.count_nonzero(aa)),'alpha_preserved_exactly':True,'sha256':sha(dest)})
panel=Image.new('RGB',(1536,3*(CANVAS[1]+30)),(27,34,43)); draw=ImageDraw.Draw(panel)
for i,frame in enumerate(frames):
    x=(i%3)*512; y=(i//3)*(CANVAS[1]+30); bg=Image.new('RGBA',CANVAS,(27,34,43,255)); bg.alpha_composite(frame); panel.paste(bg.convert('RGB'),(x,y+30)); draw.text((x+8,y+6),f'{ACTOR} / {i:03}',fill='white')
panel.save(OUT/'qa_contact_sheet.jpg',quality=94)
entry=json.loads(json.dumps(base))
entry.setdefault('sequenceFrames',{})['walk']=rels
entry.setdefault('clips',{})['walk']={'frames':rels,'frame_count':9,'fps':8,'duration_seconds':1.125,'loop':True,'complete_animation':False,'status':'UNAPPROVED_NINE_FRAME_MOTION_CANDIDATE_NOT_NATURAL_MOTION_COMPLETE','canvas_px':list(CANVAS),'anchor':list(ANCHOR),'anchor_status':'VISUAL_ESTIMATE_UNAPPROVED','movement_semantics':'quadruped_alternating_footfalls_with_blossom_tail_followthrough','display_scale':1.0,'quality_limit':'Pose-cycle candidate; natural contact, body scale and identity continuity require native screen review.'}
entry['status']='UNAPPROVED_PARTIAL_MOTION_CANDIDATE'; entry['complete_animation']=False
ov={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'candidate_manifest':f'GeneratedCandidates/{ACTOR}/{REV}/manifest.json','entries':{ACTOR:entry}}
OVERLAY.write_text(json.dumps(ov,ensure_ascii=False,indent=2)+'\n')
manifest={'schema':'witch.enemy_motion_candidate.v1','asset_id':ACTOR,'revision':REV,'approval':'UNAPPROVED_CANDIDATE_PENDING_ROOT_NATIVE_SCREEN_REVIEW','natural_motion_complete':False,'source_still_path':'ActorStills/ACT_E_R05_04/ACT_E_R05_04__still__r001.png','source_still_sha256':sha(still),'atlas_path':f'GeneratedCandidates/{ACTOR}/{REV}/imagegen_atlas_source.png','atlas_sha256':sha(ATLAS),'atlas_px':list(atlas.size),'grid_x':xs,'grid_y':ys,'frame_canvas_px':list(CANVAS),'source_runtime_canvas_px':[512,512],'anchor_candidate_px':list(ANCHOR),'registration':'Exact source-cell RGBA preserved; center alpha16 x and align alpha16 foot bound to anchor. Translation only. Canvas height expanded to preserve all low-alpha source pixels; no resize, recolor or alpha cleanup.','display_scale_candidate':1.0,'frames':records,'qa_contact_sheet':f'GeneratedCandidates/{ACTOR}/{REV}/qa_contact_sheet.jpg','runtime_overlay':OVERLAY.name,'visual_status':'UNAPPROVED_CANDIDATE_PENDING_ROOT_NATIVE_SCREEN_REVIEW','limitations':['Expanded 512x592 texture canvas may affect renderer sizing; review display scale in native app.','Pose differences are candidate locomotion only; not natural-motion completion.']}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
old=json.loads((ROOT/'docs/production/current/art/R05_enemy_motion_candidates_r002.json').read_text())
new=json.loads(json.dumps(old)); new['schema']='r05_enemy_motion_candidates_r003'; new['status']='UNAPPROVED_PARTIAL_MOTION_CANDIDATES_PENDING_NATIVE_SCREEN_REVIEW'
for item in new['items']:
    if item['asset_id']==ACTOR:
        item.update({'revision':REV,'atlas_path':manifest['atlas_path'],'atlas_sha256':manifest['atlas_sha256'],'runtime_overlay':OVERLAY.name,'qa_contact_sheet':manifest['qa_contact_sheet'],'visual_status':manifest['visual_status'],'quality_limit':manifest['limitations'][0],'frames':records,'frame_canvas_px':list(CANVAS),'anchor_candidate_px':list(ANCHOR)})
(ROOT/'docs/production/current/art/R05_enemy_motion_candidates_r003.json').write_text(json.dumps(new,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'actor':ACTOR,'frames':len(records),'canvas':CANVAS,'overlay':OVERLAY.name,'contact':manifest['qa_contact_sheet'],'all_alpha_preserved':all(r['alpha_preserved_exactly'] for r in records)},ensure_ascii=False))

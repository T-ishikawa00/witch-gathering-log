#!/usr/bin/env python3
"""Pack the r005 generated 3x3 gait atlas into registration-aligned review frames.

No cleanup, recolor, rescale, or source mutation is performed. Each exact cell is
translated on a common 512x512 transparent canvas so its lowest alpha>16 pixel
lands on one shared baseline; source alpha and RGB are preserved.
"""
from pathlib import Path
import hashlib, json, shutil
from PIL import Image, ImageDraw, ImageFont
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'native/Art'
OUT = ART / 'GeneratedCandidates/ACT_E_R02_01/walk_cycle_r005'
ATLAS_SOURCE = Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-b5005176-7a3f-48ba-8175-a6f00f3395a3.png')
ORIGINAL = ART / 'ActorStills/ACT_E_R02_01/ACT_E_R02_01__still__r002.png'

def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()

OUT.mkdir(parents=True,exist_ok=True)
frames_dir=OUT/'frames'; frames_dir.mkdir(exist_ok=True)
atlas=Image.open(ATLAS_SOURCE).convert('RGBA')
assert atlas.size==(1536,1024), atlas.size
shutil.copy2(ATLAS_SOURCE, OUT/'imagegen_walk_atlas_r005.png')
shutil.copy2(ORIGINAL, OUT/'identity_reference_still_r002.png')
xs=[0,512,1024,1536]; ys=[0,341,683,1024]
measure=[]; frames=[]
for n in range(9):
    j,i=divmod(n,3)
    cell=atlas.crop((xs[i],ys[j],xs[i+1],ys[j+1]))
    a=np.asarray(cell.getchannel('A'))
    yy,xx=np.where(a>16)
    if len(xx)==0: raise ValueError(f'empty pose {n}')
    # Align by generated ground/contact boundary, retaining individual pose geometry.
    tx=round(256 - (int(xx.min())+int(xx.max()))/2)
    ty=460-int(yy.max())
    canvas=Image.new('RGBA',(512,512),(0,0,0,0))
    canvas.alpha_composite(cell,(tx,ty))
    dest=frames_dir/f'walk_{n:03}.png'; canvas.save(dest)
    a2=np.asarray(canvas.getchannel('A')); y2,x2=np.where(a2>16)
    frames.append(f'GeneratedCandidates/ACT_E_R02_01/walk_cycle_r005/frames/{dest.name}')
    measure.append({'frame':dest.name,'source_cell_xywh':[xs[i],ys[j],512,ys[j+1]-ys[j]],'source_alpha16_bounds':[int(xx.min()),int(yy.min()),int(xx.max()),int(yy.max())], 'translation_px':[tx,ty], 'packed_alpha16_bounds':[int(x2.min()),int(y2.min()),int(x2.max()),int(y2.max())], 'sha256':sha(dest)})

# Review strip on dark background; all frames shown at native 512px scale.
qa=Image.new('RGB',(3*512,3*544),(25,32,42)); d=ImageDraw.Draw(qa)
for n,rel in enumerate(frames):
    j,i=divmod(n,3); im=Image.open(ART/rel).convert('RGBA')
    bg=Image.new('RGBA',(512,512),(25,32,42,255)); bg.alpha_composite(im)
    qa.paste(bg.convert('RGB'),(i*512,j*544+32))
    d.text((i*512+8,j*544+8),f'walk {n:03}',fill=(234,235,238))
qa.save(OUT/'qa_contact_sheet_walk_r005.jpg',quality=94)
manifest={
 'candidate_id':'ACT_E_R02_01_walk_cycle_r005',
 'status':'UNAPPROVED_PARTIAL_GAIT_CANDIDATE',
 'source_original_png':'ActorStills/ACT_E_R02_01/ACT_E_R02_01__still__r002.png',
 'source_original_sha256':sha(ORIGINAL),
 'generated_atlas_workspace_copy':'GeneratedCandidates/ACT_E_R02_01/walk_cycle_r005/imagegen_walk_atlas_r005.png',
 'generated_atlas_sha256':sha(OUT/'imagegen_walk_atlas_r005.png'),
 'generation_mode':'built-in image_gen edit/reference, transparent_background requested; alpha preserved unchanged',
 'atlas_px':[1536,1024], 'grid':[3,3], 'cell_bounds_x':[0,512,1024,1536], 'cell_bounds_y':[0,341,683,1024],
 'packed_canvas_px':[512,512], 'registration':'translation only, alpha>16 lowest pixel aligned to y=460 and alpha bounds horizontal center x=256; no rescale/recolor/alpha edits',
 'anchor_px':[256,460], 'anchor_status':'VISUAL_ESTIMATE_UNAPPROVED', 'fps':12,
 'motion_sequence':['plant/compress','passing','lift/push-off','contact','passing','lift/push-off','contact','raised step','return/contact'],
 'qa_contact_sheet':'GeneratedCandidates/ACT_E_R02_01/walk_cycle_r005/qa_contact_sheet_walk_r005.jpg',
 'all_frames':measure,
 'visual_limitations':['Repeated spot pattern drifts subtly between generated poses.','Pose-level gait candidate only; contact cadence and screen naturalness unverified.','Must remain PARTIAL / UNAPPROVED until integrated visual review.']
}
(OUT/'walk_cycle_manifest_r005.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')

# Full actor entry derived from existing candidate overlay, preserving original pose candidates.
prev=json.loads((ART/'runtime_overlay_act_e_r02_01_walk_cycle_candidate_r002.json').read_text())['entries']['ACT_E_R02_01']
entry=prev.copy()
entry['sequenceFrames']=dict(prev['sequenceFrames']); entry['sequenceFrames']['walk']=frames
entry['clips']={k:dict(v) for k,v in prev['clips'].items()}
entry['clips']['walk']={'frames':frames,'frame_count':9,'fps':12,'duration_seconds':0.75,'loop':True,'status':'NINE_FRAME_GAIT_CANDIDATE_PARTIAL_UNAPPROVED','canvas_px':[512,512],'anchor':[256,460],'anchor_status':'VISUAL_ESTIMATE_UNAPPROVED'}
entry['canvas_px']=[512,512]; entry['anchor']=[256,460]; entry['anchor_status']='VISUAL_ESTIMATE_UNAPPROVED'; entry['status']='SEVEN_STATE_POSE_CANDIDATE_WITH_NINE_FRAME_GAIT_CANDIDATE_PARTIAL_UNAPPROVED'; entry['complete_animation']=False
# Existing static pose states are not upgraded. This overlay only upgrades walk evidence.
overlay={'status':'UNAPPROVED_PARTIAL_GAIT_CANDIDATE_OVERLAY','complete_animation':False,'source_candidate_manifest':'GeneratedCandidates/ACT_E_R02_01/walk_cycle_r005/walk_cycle_manifest_r005.json','entries':{'ACT_E_R02_01':entry}}
(ART/'runtime_overlay_act_e_r02_01_walk_cycle_candidate_r003.json').write_text(json.dumps(overlay,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'out':str(OUT),'qa':str(OUT/'qa_contact_sheet_walk_r005.jpg'),'overlay':'native/Art/runtime_overlay_act_e_r02_01_walk_cycle_candidate_r003.json','frame_count':len(frames),'sha256s':[x['sha256'] for x in measure]},ensure_ascii=False,indent=2))

#!/usr/bin/env python3
"""Build unapproved 24fps transform candidates for the ancient tree boss."""
from __future__ import annotations
import hashlib,json,math,shutil
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
SRC=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-c0dc27ef-65f4-48cc-81d7-93b7d3d4042f.png')
REF=Path('/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/regions/region01_forest/imports/20261009_R01_delivery/R01_PACKAGE/bosses/B_R01_B/B_R01_B_ANCIENT_TREE_base_v1.png')
OUT=ROOT/'native/Art/GeneratedCandidates/ACT_B_R01_B/rig_candidate_r001'
CANVAS=(512,512);FPS=24
# Positions/pivots estimated from generated cutouts; do not treat as approved.
PARTS=[
 {'id':'root_left','cell':[1,0],'origin':[25,350],'pivot':[170,375],'pivot_local':[145,25],'z':0},
 {'id':'root_right','cell':[1,1],'origin':[342,348],'pivot':[342,374],'pivot_local':[0,26],'z':1},
 {'id':'canopy_outer','cell':[1,3],'origin':[342,236],'pivot':[351,300],'pivot_local':[9,64],'z':2},
 {'id':'branch_left','cell':[0,0],'origin':[12,132],'pivot':[160,214],'pivot_local':[148,82],'z':3},
 {'id':'branch_right','cell':[0,2],'origin':[360,132],'pivot':[360,216],'pivot_local':[0,84],'z':4},
 {'id':'top_canopy','cell':[0,3],'origin':[157,12],'pivot':[256,151],'pivot_local':[99,139],'z':5},
 {'id':'trunk_core','cell':[0,1],'origin':[177,151],'pivot':[258,363],'pivot_local':[81,212],'z':6},
 {'id':'root_base','cell':[1,2],'origin':[178,355],'pivot':[258,421],'pivot_local':[80,66],'z':7},
]
STATES={s:{'loop':s in {'idle','walk'},'frames':24} for s in ['idle','walk','anticipate','execute','recover','hit','resolve']}
def values(state,i,n):
 t=i/max(n-1,1);p=2*math.pi*i/n;s=math.sin(p)
 if state=='idle':return {'canopy':1.5*s,'left':1.2*s,'right':-1.2*s,'root':.5*s,'bodyY':.5*s}
 if state=='walk':return {'canopy':3*s,'left':3*s,'right':-3*s,'root':2*s,'bodyY':2*abs(s)}
 if state=='anticipate':
  q=min(1,t*2);q=q*q*(3-2*q);return {'canopy':-8*q,'left':-12*q,'right':12*q,'root':-3*q,'bodyY':-2*q}
 if state=='execute':
  q=math.sin(math.pi*t);return {'canopy':5*q,'left':24*q,'right':-24*q,'root':8*q,'bodyY':-3*q}
 if state=='recover':
  q=1-t;return {'canopy':-8*q,'left':-12*q,'right':12*q,'root':-3*q,'bodyY':-2*q}
 if state=='hit':
  q=math.sin(math.pi*t);return {'canopy':-12*q,'left':-16*q,'right':16*q,'root':-8*q,'bodyY':3*q}
 if state=='resolve':
  q=t*t*(3-2*t);return {'canopy':-4*q,'left':5*q,'right':-5*q,'root':8*q,'bodyY':5*q}
 raise KeyError(state)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def pp(p):return OUT/'parts'/f"{p['id']}.png"
def crop_parts():
 im=Image.open(SRC).convert('RGBA');W,H=im.size;(OUT/'parts').mkdir(parents=True,exist_ok=True)
 for p in PARTS:
  r,c=p['cell'];x0=round(c*W/4);x1=round((c+1)*W/4);y0=round(r*H/2);y1=round((r+1)*H/2)
  cell=im.crop((x0,y0,x1,y1));a=cell.getchannel('A').point(lambda v:255 if v>=8 else 0);box=a.getbbox()
  if not box:raise ValueError(p['id'])
  crop=cell.crop(box);crop=crop.resize((round(crop.width/3),round(crop.height/3)),Image.Resampling.LANCZOS);crop.save(pp(p),optimize=True)
  p['cell_bbox']=list(box);p['part_image_px']=list(crop.size);p['pivot_in_part_px']=[round(p['pivot_local'][0]/3,3),round(p['pivot_local'][1]/3,3)]
def render(state,i,n):
 v=values(state,i,n);layers=[]
 for p in PARTS:
  im=Image.new('RGBA',CANVAS,(0,0,0,0));im.alpha_composite(Image.open(pp(p)).convert('RGBA'),tuple(p['origin']))
  angle={'top_canopy':v['canopy'],'branch_left':v['left'],'branch_right':v['right'],'canopy_outer':v['right'],'root_left':v['root'],'root_right':-v['root']}.get(p['id'],0)
  if angle:im=im.rotate(angle,resample=Image.Resampling.BICUBIC,center=tuple(p['pivot']),fillcolor=(0,0,0,0))
  if p['id'] in {'trunk_core','root_base'} and v['bodyY']:
   moved=Image.new('RGBA',CANVAS,(0,0,0,0));moved.alpha_composite(im,(0,round(v['bodyY'])));im=moved
  layers.append((p['z'],im))
 out=Image.new('RGBA',CANVAS,(0,0,0,0))
 for _,im in sorted(layers):out.alpha_composite(im)
 return out
def main():
 if OUT.exists():shutil.rmtree(OUT)
 OUT.mkdir(parents=True);shutil.copy2(SRC,OUT/'generated_parts_atlas_source_r001.png');crop_parts();clips={}
 for s,meta in STATES.items():
  kfs=[]
  for i in range(meta['frames']):
   v=values(s,i,meta['frames']);poses={
    'top_canopy':{'rotation_deg':round(v['canopy'],3)},
    'branch_left':{'rotation_deg':round(v['left'],3)},
    'branch_right':{'rotation_deg':round(v['right'],3)},
    'canopy_outer':{'rotation_deg':round(v['right'],3)},
    'root_left':{'rotation_deg':round(v['root'],3)},'root_right':{'rotation_deg':round(-v['root'],3)},
    'trunk_core':{'translation_px':[0,round(v['bodyY'],3)]},'root_base':{'translation_px':[0,round(v['bodyY'],3)]}}
   kfs.append({'frame':i,'pose_by_part':poses})
  clips[s]={'fps':FPS,'loop':meta['loop'],'frame_count':meta['frames'],'keyframes':kfs}
 manifest={'actor_id':'ACT_B_R01_B','revision':'rig_candidate_r001','status':'GENERATED_TECHNICAL_CANDIDATE_UNAPPROVED','canvas_px':list(CANVAS),'anchor_px':[256,500],'fps':FPS,
  'coordinate_system':'top-left; bundle pixels','generated_atlas_path':'GeneratedCandidates/ACT_B_R01_B/rig_candidate_r001/generated_parts_atlas_source_r001.png','generated_atlas_sha256':sha(OUT/'generated_parts_atlas_source_r001.png'),
  'reference_path':str(REF),'reference_sha256':sha(REF),'construction':'generated tree-part atlas from selected fullbody; manual registration, visual-estimated pivots; original unchanged','pivot_status':'VISUAL_ESTIMATE_UNAPPROVED',
  'parts':[{'id':p['id'],'path':'GeneratedCandidates/ACT_B_R01_B/rig_candidate_r001/parts/'+pp(p).name,'cell':p['cell'],'crop_bbox_in_cell_px':p['cell_bbox'],'part_image_px':p['part_image_px'],'pivot_in_part_px':p['pivot_in_part_px'],'rest_position_px':p['pivot'],'z_position':p['z'],'sha256':sha(pp(p)),'pivot_basis':'VISUAL_ESTIMATE_UNAPPROVED'} for p in PARTS],
  'clips':clips,'motion_limits':['walk state represents rooted sway/settle only, not locomotion','branch/canopy pivots are estimates; no in-game playback QA','generated source parts need identity and join review; candidate only','Human adoption pending'],'source_art_originals_mutated':False}
 man=OUT/'rig_manifest_candidate_r001.json';man.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 sheet=Image.new('RGBA',(512,194*4),(27,30,36,255));draw=ImageDraw.Draw(sheet)
 for j,(s,m) in enumerate(STATES.items()):
  im=render(s,6 if m['loop'] else 12,24).resize((256,256),Image.Resampling.LANCZOS);x=j%2*256;y=j//2*194;sheet.alpha_composite(im,(x,y+22));draw.text((x+6,y+4),s,fill='white')
 sheet.save(OUT/'qa_state_contact_sheet_r001.png',optimize=True)
 print(json.dumps({'manifest':str(man),'parts':len(PARTS),'states':len(clips),'keyframes':sum(x['frame_count'] for x in clips.values()),'bytes':sum(p.stat().st_size for p in OUT.rglob('*.png'))},ensure_ascii=False))
if __name__=='__main__':main()

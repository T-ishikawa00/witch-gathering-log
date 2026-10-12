#!/usr/bin/env python3
"""Create an unapproved transform-rig candidate from the generated resin beetle cutout atlas."""
from __future__ import annotations
import hashlib,json,math,shutil
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
SRC=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-2e557b8f-7ee2-4412-831b-28433570cef1.png')
REF=Path('/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/regions/region01_forest/imports/20261009_R01_delivery/R01_PACKAGE/enemies/E_R01_04/E_R01_04_base_v2.png')
OUT=ROOT/'native/Art/GeneratedCandidates/ACT_E_R01_04/rig_candidate_r001'
CANVAS=(512,341);FPS=24
# Candidate registration in 512x341 frame. Pivots and layer overlaps are visual estimates.
PARTS=[
 {'id':'rear_leg_far','cell':[1,2],'origin':[270,205],'pivot':[291,209],'pivot_local':[21,4],'z':0},
 {'id':'rear_leg_near','cell':[1,3],'origin':[315,203],'pivot':[372,208],'pivot_local':[57,5],'z':1},
 {'id':'abdomen','cell':[0,3],'origin':[215,180],'pivot':[270,215],'pivot_local':[55,35],'z':2},
 {'id':'thorax','cell':[0,1],'origin':[190,150],'pivot':[215,196],'pivot_local':[25,46],'z':3},
 {'id':'front_leg_far','cell':[1,1],'origin':[200,205],'pivot':[257,212],'pivot_local':[57,7],'z':4},
 {'id':'front_leg_near','cell':[1,0],'origin':[145,206],'pivot':[166,210],'pivot_local':[21,4],'z':5},
 {'id':'shell','cell':[0,2],'origin':[157,86],'pivot':[260,188],'pivot_local':[103,102],'z':6},
 {'id':'head','cell':[0,0],'origin':[145,168],'pivot':[215,219],'pivot_local':[70,51],'z':7},
]
STATES={s:{'loop':s in {'idle','walk'},'frames':24} for s in ['idle','walk','anticipate','execute','recover','hit','resolve','roll']}
def vals(state,i,n):
 t=i/max(n-1,1);p=2*math.pi*i/n;s=math.sin(p)
 if state=='idle': return {'bodyY':.6*s,'shell':.5*s,'head':1.2*s,'legs':[1*s,-1*s,-1*s,1*s]}
 if state=='walk': return {'bodyY':1.5*abs(s),'shell':1.2*s,'head':1.0*s,'legs':[18*s,-18*s,-18*s,18*s]}
 if state=='anticipate':
  q=min(1,t*2);q=q*q*(3-2*q);return {'bodyY':2*q,'shell':-4*q,'head':-5*q,'legs':[-4*q,4*q,5*q,-5*q]}
 if state=='execute':
  q=math.sin(math.pi*t);return {'bodyY':-4*q,'shell':8*q,'head':-7*q,'legs':[12*q,-12*q,-15*q,15*q]}
 if state=='recover':
  q=1-t;return {'bodyY':2*q,'shell':-4*q,'head':-5*q,'legs':[-4*q,4*q,5*q,-5*q]}
 if state=='hit':
  q=math.sin(math.pi*t);return {'bodyY':2*q,'shell':-8*q,'head':7*q,'legs':[-8*q,8*q,11*q,-11*q]}
 if state=='resolve':
  q=t*t*(3-2*t);return {'bodyY':6*q,'shell':5*q,'head':-4*q,'legs':[8*q,-8*q,-8*q,8*q]}
 if state=='roll':
  q=math.sin(math.pi*t);return {'bodyY':-2*q,'shell':72*q,'head':-8*q,'legs':[25*q,-25*q,-25*q,25*q]}
 raise KeyError(state)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def pp(p):return OUT/'parts'/f"{p['id']}.png"
def crop_parts():
 im=Image.open(SRC).convert('RGBA');w,h=im.size;cw=w//4;ch=h//2;(OUT/'parts').mkdir(parents=True,exist_ok=True)
 for p in PARTS:
  r,c=p['cell'];cell=im.crop((c*cw,r*ch,(c+1)*cw,(r+1)*ch));a=cell.getchannel('A').point(lambda v:255 if v>=8 else 0);box=a.getbbox()
  if not box:raise ValueError(p['id'])
  crop=cell.crop(box); crop=crop.resize((round(crop.width/3),round(crop.height/3)),Image.Resampling.LANCZOS);crop.save(pp(p),optimize=True)
  p['crop_bbox_in_cell_px']=list(box);p['pivot_in_part_px']=[round(p['pivot_local'][0]/3,3),round(p['pivot_local'][1]/3,3)]
def render(state,i,n):
 v=vals(state,i,n);legids={'rear_leg_far':0,'rear_leg_near':1,'front_leg_far':2,'front_leg_near':3};layers=[]
 for p in PARTS:
  part=Image.open(pp(p)).convert('RGBA');im=Image.new('RGBA',CANVAS,(0,0,0,0));im.alpha_composite(part,tuple(p['origin']))
  angle=v['legs'][legids[p['id']]] if p['id'] in legids else v.get({'head':'head'}.get(p['id'],p['id']),0)
  if angle:im=im.rotate(angle,resample=Image.Resampling.BICUBIC,center=tuple(p['pivot']),fillcolor=(0,0,0,0))
  if p['id'] in {'abdomen','thorax','shell','head'} and v['bodyY']:
   shifted=Image.new('RGBA',CANVAS,(0,0,0,0));shifted.alpha_composite(im,(0,round(v['bodyY'])));im=shifted
  layers.append((p['z'],im))
 out=Image.new('RGBA',CANVAS,(0,0,0,0))
 for _,im in sorted(layers):out.alpha_composite(im)
 return out
def main():
 if OUT.exists():shutil.rmtree(OUT)
 OUT.mkdir(parents=True);shutil.copy2(SRC,OUT/'generated_parts_atlas_source_r001.png');crop_parts();clips={}
 for s,meta in STATES.items():
  keys=[]
  for i in range(meta['frames']):
   v=vals(s,i,meta['frames']);pose={}
   legids={'rear_leg_far':0,'rear_leg_near':1,'front_leg_far':2,'front_leg_near':3}
   for p in PARTS:
    if p['id'] in legids:pose[p['id']]={'rotation_deg':round(v['legs'][legids[p['id']]],3)}
    else:pose[p['id']]={'rotation_deg':round(v.get({'head':'head'}.get(p['id'],p['id']),0),3)}
    if p['id'] in {'abdomen','thorax','shell','head'}:pose[p['id']]['translation_px']=[0,round(v['bodyY'],3)]
   keys.append({'frame':i,'pose_by_part':pose})
  clips[s]={'fps':FPS,'loop':meta['loop'],'frame_count':meta['frames'],'keyframes':keys}
 manifest={'actor_id':'ACT_E_R01_04','revision':'rig_candidate_r001','status':'GENERATED_TECHNICAL_CANDIDATE_UNAPPROVED',
  'canvas_px':list(CANVAS),'anchor_px':[256,319],'fps':FPS,'coordinate_system':'top-left; bundle pixels',
  'generated_atlas_path':'GeneratedCandidates/ACT_E_R01_04/rig_candidate_r001/generated_parts_atlas_source_r001.png',
  'generated_atlas_sha256':sha(OUT/'generated_parts_atlas_source_r001.png'),'reference_path':str(REF),'reference_sha256':sha(REF),
  'construction':'ImageGen isolated cutouts from reference, manually registered by visual estimate; original unchanged',
  'pivot_status':'VISUAL_ESTIMATE_UNAPPROVED',
  'parts':[{'id':p['id'],'path':'GeneratedCandidates/ACT_E_R01_04/rig_candidate_r001/parts/'+pp(p).name,'generated_atlas_cell':p['cell'],
   'crop_bbox_in_cell_px':p['crop_bbox_in_cell_px'],'part_image_px':list(Image.open(pp(p)).size),'pivot_in_part_px':p['pivot_in_part_px'],
   'rest_position_px':p['pivot'],'z_position':p['z'],'sha256':sha(pp(p)),'pivot_basis':'VISUAL_ESTIMATE_UNAPPROVED'} for p in PARTS],
  'clips':clips,'motion_limits':['All leg/body joints are generated technical cutouts, not source-authored.','roll is a 2D shell rotation test, not a validated full ball-roll pose.','style and registration require SpriteKit/Human review.','No global runtime-index change; no Human adoption.'],'source_art_originals_mutated':False}
 man=OUT/'rig_manifest_candidate_r001.json';man.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 sheet=Image.new('RGBA',(512,194*4),(27,30,36,255));draw=ImageDraw.Draw(sheet)
 for j,(s,m) in enumerate(STATES.items()):
  im=render(s,6 if m['loop'] else 12,m['frames']).resize((256,170),Image.Resampling.LANCZOS);x=j%2*256;y=j//2*194;sheet.alpha_composite(im,(x,y+22));draw.text((x+6,y+4),s,fill='white')
 sheet.save(OUT/'qa_state_contact_sheet_r001.png',optimize=True)
 print(json.dumps({'manifest':str(man),'parts':len(PARTS),'states':len(clips),'keyframes':sum(x['frame_count'] for x in clips.values()),'bytes':sum(p.stat().st_size for p in OUT.rglob('*.png'))},ensure_ascii=False))
if __name__=='__main__':main()

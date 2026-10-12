#!/usr/bin/env python3
"""Derive an unapproved 24fps four-limb/four-body-part rig candidate from a generated cutout atlas."""
from __future__ import annotations
import hashlib,json,math,shutil
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
SRC=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-ff66181c-30b2-4a4a-a578-7c56e8992992.png')
OUT=ROOT/'native/Art/GeneratedCandidates/ACT_E_R01_03/rig_candidate_r001'
CANVAS=(512,341); FPS=24
# Cell coordinates of generated atlas: row 0 = head, abdomen, wings; row 1 = four leg cutouts.
PARTS=[
 {'id':'farwing','cell':[0,3],'origin':[220,39],'pivot':[220,184],'z':0,'pivot_local':[0,145]},
 {'id':'nearwing','cell':[0,2],'origin':[112,39],'pivot':[220,184],'z':1,'pivot_local':[108,145]},
 {'id':'rear_leg_far','cell':[1,2],'origin':[245,190],'pivot':[263,199],'z':2,'pivot_local':[18,9]},
 {'id':'rear_leg_near','cell':[1,3],'origin':[284,195],'pivot':[342,207],'z':3,'pivot_local':[58,12]},
 {'id':'abdomen','cell':[0,1],'origin':[212,160],'pivot':[232,210],'z':4,'pivot_local':[20,50]},
 {'id':'front_leg_far','cell':[1,1],'origin':[198,196],'pivot':[251,208],'z':5,'pivot_local':[53,12]},
 {'id':'front_leg_near','cell':[1,0],'origin':[146,195],'pivot':[201,205],'z':6,'pivot_local':[55,10]},
 {'id':'head_thorax','cell':[0,0],'origin':[152,166],'pivot':[246,242],'z':7,'pivot_local':[94,76]},
]
STATES={s:{'loop':s in {'idle','walk','flight'},'frames':24} for s in ['idle','walk','flight','anticipate','execute','recover','hit','resolve']}
def mix(a,b,t):
 t=t*t*(3-2*t); return a+(b-a)*t
def state_values(state,i,n):
 t=i/max(n-1,1); p=2*math.pi*i/n
 if state=='idle':
  s=math.sin(p); return {'bodyY':1.0*s,'abdomen':1.2*s,'head':1.2*s,'nearwing':2*math.sin(p+.5),'farwing':-2*math.sin(p+.5),'legs':[1*s,-1*s,-1*s,1*s]}
 if state=='walk':
  s=math.sin(p); return {'bodyY':1.5*abs(s),'abdomen':1.5*s,'head':1.0*s,'nearwing':1.2*s,'farwing':-1.2*s,'legs':[18*s,-18*s,-18*s,18*s]}
 if state=='flight':
  s=math.sin(p); return {'bodyY':-3+2*s,'abdomen':1.8*s,'head':1*s,'nearwing':25*s,'farwing':-25*s,'legs':[5*s,-5*s,-5*s,5*s]}
 if state=='anticipate':
  q=min(1,t*2); return {'bodyY':mix(0,2,q),'abdomen':mix(0,-4,q),'head':mix(0,5,q),'nearwing':mix(0,-12,q),'farwing':mix(0,12,q),'legs':[mix(0,-5,q),mix(0,5,q),mix(0,5,q),mix(0,-5,q)]}
 if state=='execute':
  q=math.sin(math.pi*t); return {'bodyY':-5*q,'abdomen':-7*q,'head':-9*q,'nearwing':30*q,'farwing':-30*q,'legs':[10*q,-10*q,-12*q,12*q]}
 if state=='recover':
  q=1-t; return {'bodyY':2*q,'abdomen':-4*q,'head':4*q,'nearwing':-12*q,'farwing':12*q,'legs':[-5*q,5*q,5*q,-5*q]}
 if state=='hit':
  q=math.sin(math.pi*t); return {'bodyY':2*q,'abdomen':-6*q,'head':-8*q,'nearwing':-8*q,'farwing':8*q,'legs':[-10*q,10*q,12*q,-12*q]}
 if state=='resolve':
  q=t*t*(3-2*t); return {'bodyY':9*q,'abdomen':4*q,'head':-7*q,'nearwing':-9*q,'farwing':9*q,'legs':[8*q,-8*q,-8*q,8*q]}
 raise KeyError(state)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def part_path(part):return OUT/'parts'/f"{part['id']}.png"
def crop_sources():
 im=Image.open(SRC).convert('RGBA'); (OUT/'parts').mkdir(parents=True,exist_ok=True)
 for p in PARTS:
  row,col=p['cell']; cell=im.crop((col*384,row*512,(col+1)*384,(row+1)*512))
  alpha=cell.getchannel('A').point(lambda v:255 if v>=8 else 0)
  box=alpha.getbbox()
  if not box: raise ValueError(f"empty generated part {p['id']}")
  # Preserve the original generated RGBA within the crop; threshold only selects bounds.
  crop=cell.crop(box)
  size=(round(crop.width/3),round(crop.height/3))
  crop=crop.resize(size,Image.Resampling.LANCZOS)
  crop.save(part_path(p),optimize=True)
  p['crop_bbox_in_cell_px']=list(box)
  p['bundle_origin_px']=p['origin']
  p['bundle_pivot_px']=p['pivot']
  p['pivot_in_part_px']=[round(p['pivot_local'][0]/3,3),round(p['pivot_local'][1]/3,3)]
def render(state,i,n):
 v=state_values(state,i,n); layers=[]
 angles={'farwing':v['farwing'],'nearwing':v['nearwing'],'abdomen':v['abdomen'],'head_thorax':v['head']}
 legangle={'rear_leg_far':v['legs'][0],'rear_leg_near':v['legs'][1],'front_leg_far':v['legs'][2],'front_leg_near':v['legs'][3]}
 for p in PARTS:
  im=Image.open(part_path(p)).convert('RGBA'); base=Image.new('RGBA',CANVAS,(0,0,0,0))
  org=(round(p['origin'][0]),round(p['origin'][1])); base.alpha_composite(im,org)
  angle=angles.get(p['id'],legangle.get(p['id'],0))
  if angle: base=base.rotate(angle,resample=Image.Resampling.BICUBIC,center=tuple(p['pivot']),fillcolor=(0,0,0,0))
  dy=v['bodyY'] if p['id'] in {'abdomen','head_thorax','rear_leg_far','rear_leg_near','front_leg_far','front_leg_near'} else 0
  if dy:
   moved=Image.new('RGBA',CANVAS,(0,0,0,0));moved.alpha_composite(base,(0,round(dy)));base=moved
  layers.append((p['z'],base))
 out=Image.new('RGBA',CANVAS,(0,0,0,0))
 for _,im in sorted(layers):out.alpha_composite(im)
 return out
def main():
 if OUT.exists():shutil.rmtree(OUT)
 OUT.mkdir(parents=True);shutil.copy2(SRC,OUT/'generated_parts_atlas_source_r001.png')
 crop_sources();clips={}
 for s,meta in STATES.items():
  keys=[]
  for i in range(meta['frames']):
   v=state_values(s,i,meta['frames']); pose={}
   for p in PARTS:
    rotkey={'head_thorax':'head'}.get(p['id'],p['id'])
    angle=v.get(rotkey,0)
    if p['id'] in {'farwing','nearwing','abdomen','head_thorax'}: pose[p['id']]={'rotation_deg':round(angle,3)}
    else:
     legids={'rear_leg_far':0,'rear_leg_near':1,'front_leg_far':2,'front_leg_near':3}
     pose[p['id']]={'rotation_deg':round(v['legs'][legids[p['id']]],3)}
    if p['id'] in {'abdomen','head_thorax','rear_leg_far','rear_leg_near','front_leg_far','front_leg_near'}:
     pose[p['id']]['translation_px']=[0,round(v['bodyY'],3)]
   keys.append({'frame':i,'pose_by_part':pose})
  clips[s]={'fps':FPS,'loop':meta['loop'],'frame_count':meta['frames'],'keyframes':keys}
 manifest={
  'actor_id':'ACT_E_R01_03','revision':'rig_candidate_r001','status':'GENERATED_TECHNICAL_CANDIDATE_UNAPPROVED',
  'canvas_px':list(CANVAS),'anchor_px':[256,318],'fps':FPS,'coordinate_system':'top-left; bundle pixels',
  'generated_atlas_path':'GeneratedCandidates/ACT_E_R01_03/rig_candidate_r001/generated_parts_atlas_source_r001.png',
  'generated_atlas_sha256':sha(OUT/'generated_parts_atlas_source_r001.png'),
  'source_reference_path':'/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/regions/region01_forest/imports/20261009_R01_delivery/R01_PACKAGE/enemies/E_R01_03/E_R01_03_base_v1.png',
  'source_reference_sha256':hashlib.sha256(Path('/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/regions/region01_forest/imports/20261009_R01_delivery/R01_PACKAGE/enemies/E_R01_03/E_R01_03_base_v1.png').read_bytes()).hexdigest(),
  'construction':'generated isolated cutout atlas referenced to source static; manual candidate registration and estimated pivots; no source originals changed',
  'pivot_status':'VISUAL_ESTIMATE_UNAPPROVED',
  'parts':[{'id':p['id'],'path':'GeneratedCandidates/ACT_E_R01_03/rig_candidate_r001/parts/'+part_path(p).name,
    'generated_atlas_cell':p['cell'],'crop_bbox_in_cell_px':p['crop_bbox_in_cell_px'],'part_image_px':list(Image.open(part_path(p)).size),
    'pivot_in_part_px':p['pivot_in_part_px'],'rest_position_px':p['pivot'],'z_position':p['z'],
    'source_sha256':sha(part_path(p)),'pivot_basis':'VISUAL_ESTIMATE_UNAPPROVED'} for p in PARTS],
  'clips':clips,
  'motion_limits':['all four visible legs have individual generated cutouts; hidden anatomy not inferred as source-authored',
   'wing and leg motion are transform-rig candidates and require in-game joint-gap/review QA',
   'identity/style match is candidate only; generated atlas is not Human-approved'],
  'source_art_originals_mutated':False}
 man=OUT/'rig_manifest_candidate_r001.json';man.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 labels=[]
 for s,sp in STATES.items():
  idx=6 if s in {'idle','walk','flight'} else 12
  labels.append((s,render(s,idx,sp['frames']).resize((256,170),Image.Resampling.LANCZOS)))
 sheet=Image.new('RGBA',(512,194*4),(27,30,36,255));d=ImageDraw.Draw(sheet)
 for j,(s,im) in enumerate(labels):
  x=(j%2)*256;y=(j//2)*194;sheet.alpha_composite(im,(x,y+22));d.text((x+6,y+4),s,fill='white')
 sheet.save(OUT/'qa_state_contact_sheet_r001.png',optimize=True)
 print(json.dumps({'manifest':str(man),'parts':len(PARTS),'states':len(clips),'keyframes':sum(x['frame_count'] for x in clips.values()),'bytes':sum(p.stat().st_size for p in OUT.rglob('*.png'))},ensure_ascii=False))
if __name__=='__main__':main()

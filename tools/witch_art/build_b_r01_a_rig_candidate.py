#!/usr/bin/env python3
"""Create unapproved part-rig keyframe candidates for the forest boar boss B_R01_A."""
from __future__ import annotations
import hashlib,json,math,shutil
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
SRC=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-4e19ead4-0735-4d14-8e4c-99ec395a9776.png')
REF=Path('/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/regions/region01_forest/imports/20261009_R01_delivery/R01_PACKAGE/bosses/B_R01_A/B_R01_A_base_v2.png')
OUT=ROOT/'native/Art/GeneratedCandidates/ACT_B_R01_A/rig_candidate_r001'
CANVAS=(512,341);FPS=24
PARTS=[
 {'id':'rear_leg_far','cell':[1,2],'origin':[273,190],'pivot':[298,205],'pivot_local':[25,15],'z':0},
 {'id':'rear_leg_near','cell':[1,3],'origin':[345,189],'pivot':[386,206],'pivot_local':[41,17],'z':1},
 {'id':'rump','cell':[0,2],'origin':[270,100],'pivot':[296,194],'pivot_local':[26,94],'z':2},
 {'id':'torso','cell':[0,1],'origin':[170,96],'pivot':[256,190],'pivot_local':[86,94],'z':3},
 {'id':'front_leg_far','cell':[1,1],'origin':[189,190],'pivot':[225,205],'pivot_local':[36,15],'z':4},
 {'id':'front_leg_near','cell':[1,0],'origin':[111,190],'pivot':[147,205],'pivot_local':[36,15],'z':5},
 {'id':'mane','cell':[0,3],'origin':[125,48],'pivot':[197,160],'pivot_local':[72,112],'z':6},
 {'id':'head_tusks','cell':[0,0],'origin':[94,78],'pivot':[191,204],'pivot_local':[97,126],'z':7},
]
STATES={s:{'loop':s in {'idle','walk'},'frames':24} for s in ['idle','walk','anticipate','execute','recover','hit','resolve']}
def values(state,i,n):
 t=i/max(n-1,1);p=2*math.pi*i/n;s=math.sin(p)
 if state=='idle':return {'bodyY':.8*s,'head':1.4*s,'mane':.5*s,'legs':[1*s,-1*s,-1*s,1*s]}
 if state=='walk':return {'bodyY':1.6*abs(s),'head':1*s,'mane':1*s,'legs':[17*s,-17*s,-17*s,17*s]}
 if state=='anticipate':
  q=min(1,t*2);q=q*q*(3-2*q);return {'bodyY':2*q,'head':-7*q,'mane':-3*q,'legs':[-5*q,5*q,5*q,-5*q]}
 if state=='execute':
  q=math.sin(math.pi*t);return {'bodyY':-4*q,'head':12*q,'mane':4*q,'legs':[12*q,-12*q,-14*q,14*q]}
 if state=='recover':
  q=1-t;return {'bodyY':2*q,'head':-7*q,'mane':-3*q,'legs':[-5*q,5*q,5*q,-5*q]}
 if state=='hit':
  q=math.sin(math.pi*t);return {'bodyY':2*q,'head':-12*q,'mane':-5*q,'legs':[-9*q,9*q,12*q,-12*q]}
 if state=='resolve':
  q=t*t*(3-2*t);return {'bodyY':6*q,'head':-5*q,'mane':2*q,'legs':[8*q,-8*q,-8*q,8*q]}
 raise KeyError(state)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def pp(p):return OUT/'parts'/f"{p['id']}.png"
def crop_parts():
 im=Image.open(SRC).convert('RGBA');w,h=im.size;cw=w//4;ch=h//2;(OUT/'parts').mkdir(parents=True,exist_ok=True)
 for p in PARTS:
  r,c=p['cell'];cell=im.crop((c*cw,r*ch,(c+1)*cw,(r+1)*ch));a=cell.getchannel('A').point(lambda v:255 if v>=8 else 0);box=a.getbbox()
  if not box:raise ValueError(p['id'])
  crop=cell.crop(box).resize((round((box[2]-box[0])/3),round((box[3]-box[1])/3)),Image.Resampling.LANCZOS);crop.save(pp(p),optimize=True);p['crop_bbox_in_cell_px']=list(box);p['pivot_in_part_px']=[round(p['pivot_local'][0]/3,3),round(p['pivot_local'][1]/3,3)]
def render(state,i,n):
 v=values(state,i,n);legids={'rear_leg_far':0,'rear_leg_near':1,'front_leg_far':2,'front_leg_near':3};layers=[]
 for p in PARTS:
  part=Image.open(pp(p)).convert('RGBA');im=Image.new('RGBA',CANVAS,(0,0,0,0));im.alpha_composite(part,tuple(p['origin']))
  angle=v['legs'][legids[p['id']]] if p['id'] in legids else v.get(p['id'],0)
  if angle:im=im.rotate(angle,resample=Image.Resampling.BICUBIC,center=tuple(p['pivot']),fillcolor=(0,0,0,0))
  if p['id'] in {'rump','torso','mane','head_tusks'} and v['bodyY']:
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
   v=values(s,i,meta['frames']);poses={};legids={'rear_leg_far':0,'rear_leg_near':1,'front_leg_far':2,'front_leg_near':3}
   for p in PARTS:
    poses[p['id']]={'rotation_deg':round(v['legs'][legids[p['id']]] if p['id'] in legids else v.get(p['id'],0),3)}
    if p['id'] in {'rump','torso','mane','head_tusks'}:poses[p['id']]['translation_px']=[0,round(v['bodyY'],3)]
   kfs.append({'frame':i,'pose_by_part':poses})
  clips[s]={'fps':FPS,'loop':meta['loop'],'frame_count':meta['frames'],'keyframes':kfs}
 manifest={'actor_id':'ACT_B_R01_A','revision':'rig_candidate_r001','status':'GENERATED_TECHNICAL_CANDIDATE_UNAPPROVED',
  'canvas_px':list(CANVAS),'anchor_px':[256,326],'fps':FPS,'coordinate_system':'top-left; bundle pixels',
  'generated_atlas_path':'GeneratedCandidates/ACT_B_R01_A/rig_candidate_r001/generated_parts_atlas_source_r001.png',
  'generated_atlas_sha256':sha(OUT/'generated_parts_atlas_source_r001.png'),'reference_path':str(REF),'reference_sha256':sha(REF),
  'construction':'Generated ImageGen parts atlas based on selected static; manual estimate placement and pivots; original preserved',
  'pivot_status':'VISUAL_ESTIMATE_UNAPPROVED',
  'parts':[{'id':p['id'],'path':'GeneratedCandidates/ACT_B_R01_A/rig_candidate_r001/parts/'+pp(p).name,'cell':p['cell'],'crop_bbox_in_cell_px':p['crop_bbox_in_cell_px'],
    'part_image_px':list(Image.open(pp(p)).size),'pivot_in_part_px':p['pivot_in_part_px'],'rest_position_px':p['pivot'],'z_position':p['z'],'sha256':sha(pp(p)),'pivot_basis':'VISUAL_ESTIMATE_UNAPPROVED'} for p in PARTS],
  'clips':clips,'motion_limits':['Legs/body part decomposition and pivots are generated/estimated, not source-authored.','No visual playback QA; all states remain candidates.','No independent tail or tusk movement.'],
  'source_art_originals_mutated':False}
 man=OUT/'rig_manifest_candidate_r001.json';man.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 sheet=Image.new('RGBA',(512,194*4),(27,30,36,255));draw=ImageDraw.Draw(sheet)
 for j,(s,m) in enumerate(STATES.items()):
  im=render(s,6 if m['loop'] else 12,24).resize((256,170),Image.Resampling.LANCZOS);x=j%2*256;y=j//2*194;sheet.alpha_composite(im,(x,y+22));draw.text((x+6,y+4),s,fill='white')
 sheet.save(OUT/'qa_state_contact_sheet_r001.png',optimize=True)
 print(json.dumps({'manifest':str(man),'parts':len(PARTS),'states':len(clips),'keyframes':sum(x['frame_count'] for x in clips.values()),'bytes':sum(p.stat().st_size for p in OUT.rglob('*.png'))},ensure_ascii=False))
if __name__=='__main__':main()

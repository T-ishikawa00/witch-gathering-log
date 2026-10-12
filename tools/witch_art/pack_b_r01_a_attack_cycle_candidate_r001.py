#!/usr/bin/env python3
"""Pack the B_R01_A additive three-phase charge attack atlas, retaining source clips."""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib, json, os, shutil, statistics

ROOT=Path(__file__).resolve().parents[2];ART=ROOT/'native/Art';ACTOR='ACT_B_R01_A';REV='attack_cycle_candidate_r001'
ATLAS_SOURCE=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-d8b11ad5-2502-48c1-996c-16bc6d41ad64.png')
OUT=ART/'GeneratedCandidates'/ACTOR/REV;STATES=('anticipate','execute','recover')
STATUS='UNAPPROVED_AUTHORED_ATTACK_CYCLE_CANDIDATE'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def atomic_bytes(p,data):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);tmp=p.with_name(p.name+'.tmp');tmp.write_bytes(data);os.replace(tmp,p)
def atomic_json(p,obj):atomic_bytes(p,(json.dumps(obj,ensure_ascii=False,indent=2)+'\n').encode())
def alpha16(im):return im.getchannel('A').point(lambda a:255 if a>=16 else 0)
def gutter(mask,axis,near):
 lim=mask.width if axis=='x' else mask.height;groups=[];current=[]
 for v in range(max(1,round(near-90)),min(lim-1,round(near+90))):
  sl=(v,0,v+1,mask.height) if axis=='x' else (0,v,mask.width,v+1)
  if mask.crop(sl).getbbox() is None:current.append(v)
  elif current:groups.append(current);current=[]
 if current:groups.append(current)
 if not groups:raise ValueError(('measured transparent gutter absent',axis,near))
 return round(statistics.mean(min(groups,key=lambda g:abs(statistics.mean(g)-near)-min(20,len(g))*.25)))
def main():
 if not ATLAS_SOURCE.is_file():raise FileNotFoundError(ATLAS_SOURCE)
 if OUT.exists():raise SystemExit(f'refusing to overwrite {OUT}')
 rest=ART/'GeneratedCandidates/ACT_B_R01_A/rest_hit_resolve_r001/frames/idle_000.png'
 for p in [rest,ART/'ActorStills/ACT_B_R01_A/ACT_B_R01_A__still__B_R01_A_base_v2.png']:
  if not p.is_file():raise FileNotFoundError(p)
 (OUT/'frames').mkdir(parents=True)
 atlas_path=OUT/'imagegen_atlas_r001.png';shutil.copy2(ATLAS_SOURCE,atlas_path);atlas=Image.open(atlas_path).convert('RGBA');mask=alpha16(atlas)
 if mask.getbbox() is None or atlas.getchannel('A').getextrema()[0]!=0:raise ValueError('transparent atlas required')
 ys=[0,gutter(mask,'y',atlas.height/3),gutter(mask,'y',2*atlas.height/3),atlas.height];cells=[];xs_rows=[]
 for row in range(3):
  band=mask.crop((0,ys[row],atlas.width,ys[row+1]));xs=[0,gutter(band,'x',atlas.width/3),gutter(band,'x',2*atlas.width/3),atlas.width];xs_rows.append(xs)
  for col in range(3):
   box=(xs[col],ys[row],xs[col+1],ys[row+1]);cell=atlas.crop(box);b=alpha16(cell).getbbox()
   if not b:raise ValueError(('empty',row,col))
   margin=min(b[0],b[1],cell.width-b[2],cell.height-b[3])
   if margin<2:raise ValueError(('sprite too close to cell edge',row,col,box,b,margin))
   cells.append((cell,box,b,margin))
 baseline=Image.open(rest).convert('RGBA');bb=alpha16(baseline).getbbox();baseline_h=bb[3]-bb[1]
 windup_h=statistics.median(b[3]-b[1] for _,_,b,_ in cells[:3]);reference=baseline_h/windup_h
 fit=min(reference,500/max(b[2]-b[0] for _,_,b,_ in cells),480/max(b[3]-b[1] for _,_,b,_ in cells))
 display_scale=round(reference/fit,6);anchor=[256,490]
 frames=[];contact=Image.new('RGBA',(1536,1536),(31,36,41,255));draw=ImageDraw.Draw(contact)
 for n,(cell,box,b,src_margin) in enumerate(cells):
  scaled=cell.resize((round(cell.width*fit),round(cell.height*fit)),Image.Resampling.LANCZOS);sb=alpha16(scaled).getbbox()
  dx=round(256-(sb[0]+sb[2])/2);dy=round(anchor[1]-sb[3]);frame=Image.new('RGBA',(512,512),(0,0,0,0));frame.alpha_composite(scaled,(dx,dy));fb=alpha16(frame).getbbox()
  if min(fb[0],fb[1],512-fb[2],512-fb[3])<2:raise ValueError(('packed crop',n,fb))
  state=STATES[n//3];i=n%3;rel=f'GeneratedCandidates/{ACTOR}/{REV}/frames/{state}_{i:03}.png';p=ART/rel
  tmp=p.with_name(p.name+'.tmp.png');frame.save(tmp,format='PNG',optimize=True);os.replace(tmp,p)
  contact.alpha_composite(frame,((n%3)*512,(n//3)*512));draw.text(((n%3)*512+8,(n//3)*512+8),f'{state}_{i:03}',fill='white',stroke_width=2,stroke_fill=(0,0,0,255))
  frames.append({'state':state,'index':i,'path':rel,'sha256':sha(p),'source_cell_xyxy':list(box),'source_alpha16_bbox':list(b),'source_alpha16_margin_px':src_margin,'packed_alpha16_bbox':list(fb),'translation_px':[dx,dy]})
 contact_path=OUT/'qa_contact_dark.jpg';tmp=contact_path.with_name(contact_path.name+'.tmp.jpg');contact.convert('RGB').save(tmp,format='JPEG',quality=94);os.replace(tmp,contact_path)
 fps={'anticipate':8,'execute':10,'recover':8};sem={'anticipate':'Large quadruped charge windup: shoulders compress, head lowers, forefeet brace.','execute':'Tusk-led forward body thrust with progressive head/shoulder extension and hind-leg push.','recover':'Non-gory recoil, forefoot brace, weight settles toward the stable low ready stance.'}
 entry={'clips':{},'sequenceFrames':{}}
 for i,s in enumerate(STATES):
  paths=[f['path'] for f in frames[i*3:(i+1)*3]];entry['sequenceFrames'][s]=paths
  entry['clips'][s]={'frames':paths,'frame_count':3,'fps':fps[s],'duration_seconds':round(3/fps[s],6),'loop':False,'canvas_px':[512,512],'anchor':anchor,'display_scale':display_scale,'status':STATUS,'complete_animation':False,'movement_semantics':sem[s],'anchor_status':'VISUAL_ESTIMATE_UNAPPROVED'}
 overlay_path=ART/'runtime_overlay_zzzzzzz_act_b_r01_a_attack_cycle_r001.json'
 overlay={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'human_approval':False,'source_art_untouched':True,'merge_note':'Partial state overlay; updates anticipate/execute/recover only. Existing idle/hit/resolve/walk are inherited.','entries':{ACTOR:entry}}
 atomic_json(overlay_path,overlay)
 sourceStill=ART/'ActorStills/ACT_B_R01_A/ACT_B_R01_A__still__B_R01_A_base_v2.png'
 manifest={'schema':'witch.enemy.attack_cycle_candidate.v1','actorId':ACTOR,'revision':REV,'status':STATUS,'attackFamily':'low quadruped tusk-led charge','referenceStill':str(sourceStill.relative_to(ROOT)),'referenceStillSHA256':sha(sourceStill),'imagegenAtlasSource':str(ATLAS_SOURCE),'imagegenAtlasPacked':str(atlas_path.relative_to(ROOT)),'atlasSHA256':sha(atlas_path),'atlasPx':list(atlas.size),'gridYEdgesPx':ys,'gridXEdgesByRowPx':xs_rows,'baselineRestFrame':str(rest.relative_to(ROOT)),'baselineAlpha16HeightPx':baseline_h,'windupAlpha16MedianHeightPx':windup_h,'uniformPackScale':fit,'displayScaleCommonAcrossAllAttackStates':display_scale,'canvas_px':[512,512],'anchor':[256,490],'frames':frames,'contactSheet':str(contact_path.relative_to(ROOT)),'overlay':str(overlay_path.relative_to(ROOT)),'overlaySHA256':sha(overlay_path),'packing':'Measured alpha>=16 transparent gutters; preserve source cell RGBA; common Lanczos packing scale; no per-frame alpha processing. Candidate PNGs and overlay published atomically.','qa':['Transparent atlas measured RGBA alpha 0 exterior; nine alpha>=16 major components separated by empty gutters.','Composited dark preview reviewed: no visible low-alpha red fringe.','All nine sprites retain boar body/tusks/root-crown; noticeable forward lunge appears in execute middle/late frame, though several adjacent phase poses remain similar.','Candidate needs native playback/scale review; no natural animation or art acceptance claimed.'],'rejectedAttempts':[{'path':'/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-6186763b-d056-454a-b048-bbafa9372462.png','reason':'opaque brown background; incompatible with transparent runtime frames'}, {'path':'/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-acda1d04-3114-4b00-aac2-2ac9803a31c2.png','reason':'targeted background-extraction edit retained opaque brown background; rejected'}, {'path':'/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-97ac68bd-9e05-497e-92c9-5a944b9c5ef2.png','reason':'adjacent art overlapped at column gutter, so cells could not be safely separated'}, {'path':'/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65/exec-1441c2d7-4736-46c9-9129-c164a90965be.png','reason':'phase poses too similar and cell separation margins insufficient; superseded by spacing repair'}],'runtimeReview':'PENDING_ROOT_REVIEW','humanAdoption':'PENDING','naturalMotionComplete':False}
 atomic_json(OUT/'manifest.json',manifest)
 report={'schema':'witch.enemy.attack_cycle_candidate_report.v1','actorId':ACTOR,'status':'UNAPPROVED_CANDIDATE_PENDING_NATIVE_REVIEW','previousEffectiveStateCounts':{'anticipate':2,'execute':2,'recover':3,'walk':9,'idle':3,'hit':3,'resolve':3},'newStateCounts':{'anticipate':3,'execute':3,'recover':3},'overlay':str(overlay_path.relative_to(ROOT)),'overlaySHA256':sha(overlay_path),'manifest':str((OUT/'manifest.json').relative_to(ROOT)),'contactSheet':str(contact_path.relative_to(ROOT)),'uniformDisplayScale':display_scale,'rejectedAttempts':manifest['rejectedAttempts'],'nativeScreenReceipt':'NOT_CAPTURED','naturalMotionComplete':False}
 atomic_json(ROOT/'docs/production/current/art/ACT_B_R01_A_attack_cycle_candidate_r001.json',report)
 print(json.dumps({'overlay':str(overlay_path.relative_to(ROOT)),'sha256':sha(overlay_path),'manifest':str((OUT/'manifest.json').relative_to(ROOT)),'contact':str(contact_path.relative_to(ROOT)),'fit':fit,'display_scale':display_scale,'baselineHeight':baseline_h,'gridY':ys,'gridX':xs_rows},ensure_ascii=False))
if __name__=='__main__':main()

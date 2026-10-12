#!/usr/bin/env python3
"""Slice authored idle/hit/resolve candidates at measured transparent gutters."""
from pathlib import Path
from PIL import Image
import hashlib,json,shutil,statistics
ROOT=Path(__file__).resolve().parents[2];ART=ROOT/'native/Art'
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12398-0ccb-7d03-aeac-75db9b0de178')
ITEMS={
'ACT_E_R05_01':('exec-3704778e-e4ec-499d-a30f-152ba51338e5.png',388,300),
'ACT_E_R05_02':('exec-b12e3b07-1423-480e-8680-ea2d84d8a800.png',407,490),
'ACT_E_R05_03':('exec-1060f4d4-fdb9-4c94-973b-cf2c115c1fc4.png',375,300),
'ACT_E_R05_04':('exec-12315b69-737a-478f-b326-2f65fda98fa9.png',294,490),
'ACT_B_R05_A':('exec-7320b07c-2c23-48be-a7c9-84b395963d41.png',242,490),
'ACT_B_R05_B':('exec-511391a4-83cf-4ac7-800b-9e4d5d6b7a61.png',315,490),
}
def gutter(alpha,axis,near):
 limit=alpha.width if axis=='x' else alpha.height;groups=[];current=[]
 for v in range(max(1,round(near-75)),min(limit-1,round(near+75))):
  box=(v,0,v+1,alpha.height) if axis=='x' else (0,v,alpha.width,v+1)
  if alpha.crop(box).getbbox() is None:current.append(v)
  elif current:groups.append(current);current=[]
 if current:groups.append(current)
 if not groups:raise ValueError(('No empty slicing gutter',axis,near))
 group=min(groups,key=lambda g:abs(statistics.mean(g)-near)-min(20,len(g))*.25)
 return round(statistics.mean(group))
def main():
 overlay={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'entries':{}};report=[]
 for actor,(name,targetHeight,anchorY) in ITEMS.items():
  out=ART/'GeneratedCandidates'/actor/'rest_hit_resolve_r001';(out/'frames').mkdir(parents=True,exist_ok=True)
  src=out/'SOURCE.png'
  if not src.exists():shutil.copy2(GEN/name,src)
  sheet=Image.open(src).convert('RGBA');alpha=sheet.getchannel('A')
  if alpha.getextrema()[0]!=0:raise ValueError((actor,'opaque background'))
  measuredAlpha=alpha.point(lambda a:255 if a>=16 else 0)
  rows=[0,gutter(measuredAlpha,'y',sheet.height/3),gutter(measuredAlpha,'y',sheet.height*2/3),sheet.height];cells=[]
  for row in range(3):
   band=measuredAlpha.crop((0,rows[row],sheet.width,rows[row+1]));cols=[0,gutter(band,'x',sheet.width/3),gutter(band,'x',sheet.width*2/3),sheet.width]
   for col in range(3):
    box=(cols[col],rows[row],cols[col+1],rows[row+1]);cell=sheet.crop(box);b=cell.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox();margin=min(b[0],b[1],cell.width-b[2],cell.height-b[3])
    if margin<2:raise ValueError((actor,row,col,'cut',box,b))
    cells.append((cell,box,b,margin))
  referenceScale=targetHeight/statistics.median(b[3]-b[1] for _,_,b,_ in cells[:3]);scale=min(referenceScale,470/max(b[2]-b[0] for _,_,b,_ in cells),460/max(b[3]-b[1] for _,_,b,_ in cells));frames=[];contact=Image.new('RGBA',(768,768),(36,50,43,255))
  for n,(cell,box,b,margin) in enumerate(cells):
   dx=round(256-(b[0]+b[2])/2*scale)
   if anchorY==300:
    center=300 if n<6 else 320+(n-6)*30
    dy=round(min(center-(b[1]+b[3])/2*scale,490-b[3]*scale))
   else:dy=round(490-b[3]*scale)
   frame=Image.new('RGBA',(512,512));frame.alpha_composite(cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST),(dx,dy))
   exported=frame.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
   if min(exported[0],exported[1],512-exported[2],512-exported[3])<2:raise ValueError((actor,n,'export cuts artwork',exported))
   path=out/'frames'/f'pose_{n:03}.png';temporary=path.with_suffix(".tmp.png");frame.save(temporary);temporary.replace(path);contact.alpha_composite(frame.resize((256,256),Image.Resampling.NEAREST),((n%3)*256,(n//3)*256));frames.append({'path':str(path.relative_to(ART)),'sourceBox':box,'alpha16SourceMargin':margin,'exportedAlpha16Bounds':exported,'translation':[dx,dy],'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
  contact.convert('RGB').save(out/'CONTACT.jpg');entry={'clips':{},'sequenceFrames':{}}
  for state,start,fps,loop in [('idle',0,3,True),('hit',3,12,False),('resolve',6,8,False)]:
   paths=[f['path'] for f in frames[start:start+3]];entry['sequenceFrames'][state]=paths;entry['clips'][state]={'frames':paths,'fps':fps,'duration_seconds':3/fps,'frame_count':3,'loop':loop,'canvas_px':[512,512],'anchor':[256,anchorY],'display_scale':referenceScale/scale,'status':'UNAPPROVED_AUTHORED_REST_HIT_RESOLVE_CANDIDATE','complete_animation':False}
  # New idle serves as menu still as well; per-clip canvas/anchor is explicit.
  entry['selectedPNG']=frames[0]['path'];entry['canvas_px']=[512,512];entry['anchor']=[256,anchorY]
  manifest={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE','actor':actor,'sourceSHA256':hashlib.sha256(src.read_bytes()).hexdigest(),'generator':'built-in imagegen identity-preserving edit','generationSpec':'Three idle, three recoil, three settling defeat drawings; same character scale, preserved anatomy, transparent padded atlas. Repairs: flower opaque background removed; pruner padding; deer layout/heading. Deer idle includes head-turn-away candidate; Human natural-motion adoption pending.','sourceGeneratedPath':str(GEN/name),'slicing':'Full RGBA cell crops at measured alpha>=16 gutters; subthreshold pixels retained inside each cell. Exported alpha>=16 bounds checked; no alpha/color cleanup','scale':scale,'displayScale':referenceScale/scale,'frames':frames,'runtimeVerified':False,'naturalMotionApproved':False}
  (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');overlay['entries'][actor]=entry;report.append({'actor':actor,'manifest':str((out/'manifest.json').relative_to(ROOT)),'alpha16MinimumMargin':min(f['alpha16SourceMargin'] for f in frames),'frames':9})
 (ART/'runtime_overlay_zzz_r05_rest_hit_resolve_r001.json').write_text(json.dumps(overlay,ensure_ascii=False,indent=2)+'\n');(ROOT/'docs/production/current/art/R05_REST_HIT_RESOLVE_R001.json').write_text(json.dumps({'status':'PACKED_PENDING_RUNTIME_REVIEW','candidates':report},indent=2)+'\n');print(report)
if __name__=='__main__':main()

from pathlib import Path
from PIL import Image,ImageDraw
import hashlib,json,os,tempfile
ROOT=Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
DEST=ROOT/'native/Art/GeneratedCandidates/EquipmentDetails'
EVID=ROOT/'docs/production/current/art/aira_hem_landmarks_r001'
IND=EVID/'individual';IND.mkdir(parents=True,exist_ok=True)
# Candidate points read from each individual 16px source grid; values target the bottom edge of the central leather/apron panel.
points={
'rest':[(157,199),(157,200),(157,198),(158,190),(158,191),(158,192),(163,197),(163,197),(163,197)],
'attack':[(155,190),(157,188),(158,194),(159,193),(155,193),(158,194),(154,191),(158,195),(158,195)],
'walk':[(153,195),(153,196),(151,196),(151,194),(152,195),(151,194),(152,195),(153,195),(153,196)]}
mapcfg={'rest':('party_rest_r001','PartyRest'),'attack':('party_attack_r001','PartyAttack'),'walk':('party_walk_r001','PartyWalk')}
rows=[]
for group,vals in points.items():
 folder,runtime=mapcfg[group]
 for i,pt in enumerate(vals):
  name=f'AIRA__{group}_{i:02d}.png' if group!='walk' else f'AIRA__walk_{i}.png'
  src=ROOT/'native/GeneratedArt'/folder/name
  raw=src.read_bytes(); im=Image.open(src).convert('RGBA'); w,h=im.size
  out=Image.new('RGBA',(w,h),(35,39,47,255));out.alpha_composite(im)
  out=out.resize((w*3,h*3),Image.Resampling.NEAREST)
  canvas=Image.new('RGB',(w*3,h*3+30),(30,34,42));canvas.paste(out.convert('RGB'),(0,30));d=ImageDraw.Draw(canvas)
  for x in range(0,w+1,16):
   X=x*3;d.line((X,30,X,30+h*3),fill=(105,120,138),width=1)
   if x%32==0:d.text((X+2,31),str(x),fill='#ffdf80')
  for y in range(0,h+1,16):
   Y=30+y*3;d.line((0,Y,w*3,Y),fill=(105,120,138),width=1)
   if y%32==0:d.text((2,Y+2),str(y),fill='#ffdf80')
  x,y=pt;cx=x*3;cy=30+y*3;c='#48e0ea';d.line((cx-18,cy,cx+18,cy),fill=c,width=3);d.line((cx,cy-18,cx,cy+18),fill=c,width=3);d.ellipse((cx-7,cy-7,cx+7,cy+7),outline=c,width=3);d.text((cx+8,cy-24),'hem',fill=c)
  d.text((8,8),f'{name} lower-panel hem point candidate',fill='white')
  imgpath=IND/(Path(name).stem+'_HEM.png');canvas.save(imgpath)
  if group=='walk': state='walk';frame=i
  else: state= 'idle' if group=='rest' and i<3 else 'hit' if group=='rest' and i<6 else 'resolve' if group=='rest' else 'anticipate' if i<3 else 'execute' if i<6 else 'recover';frame=i%3
  rows.append({'actorID':'AIRA','bodyAssetID':f'GeneratedArt/{runtime}/{name}','frameIndex':frame,'sourceFrameIndex':i,'sourceRowState':state,'canvas_px':[w,h],'hem_px_top_left':pt,'measurementStatus':'SOURCE_GRID_VISUAL_CANDIDATE_NOT_RUNTIME_FIT','estimatedUncertaintyPx':6,'fitVerifiedInRuntime':False,'source_path':str(src.relative_to(ROOT)),'sourceSHA256':hashlib.sha256(raw).hexdigest(),'notes':'Candidate anchor is at the bottom edge of the central leather/apron panel for a small behind-body underlay. It is not a recovered hidden lining surface. R01..R03 still require pixel-accurate and held-frame underlay visibility review; explicit hide if fully covered.'})
out={'schema':'aira_outer_hem_landmarks_r001','status':'CANDIDATE_MEASUREMENTS_PENDING_NATIVE_UNDERLAY_REVIEW','humanApproval':False,'coordinate_origin':'top_left_canvas_pixels','key':['actorID','bodyAssetID','frameIndex','canvas_px'],'method':'Per-frame visual reading of original source sprites against fresh 16px coordinate grids. Coordinates indicate the visible bottom edge of the central apron/leather panel, not a measured interior lining plane. Runtime fit is untested.','rows':rows}
p=DEST/'aira_outer_hem_landmarks_r001.json';p.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(p,len(rows),IND)

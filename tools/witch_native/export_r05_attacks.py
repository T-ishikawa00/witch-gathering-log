#!/usr/bin/env python3
"""Pack authored candidates without changing pixels/alpha beyond nearest resizing.

Cuts follow measured transparent gutters, not an assumed exact generated grid.
Only attack states are overlaid; repaired walk and preserved idle/hit remain intact.
"""
from pathlib import Path
from PIL import Image
import hashlib, json, shutil

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'native/Art'
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12398-0ccb-7d03-aeac-75db9b0de178')
ITEMS={
 'ACT_E_R05_01':('exec-78bc36dc-533d-4b57-b61a-7424bc1e4752.png',[0,418,836,1254],388,300,[212,641,1055,238,684,1070,214,640,1055]),
 'ACT_E_R05_02':('exec-9bff2ebb-f2fa-4d9c-a602-0a040f74c520.png',[0,418,818,1254],407,490,[235,653,1080,263,679,1100,252,651,1071]),
 'ACT_E_R05_03':('exec-476e36f3-e4ca-4385-ae7e-3b593a42de79.png',[0,418,836,1254],375,300,[265,686,1073,299,699,1118,270,674,1080]),
 'ACT_E_R05_04':('exec-0ad9dafc-d195-4133-92da-6dd9a6f53fbc.png',[0,418,836,1254],294,490,[232,646,1068,258,670,1084,242,649,1055]),
 'ACT_B_R05_A':('exec-72c37f04-44d3-4aad-84b0-41dcad5bbef8.png',[0,418,836,1254],242,490,[241,660,1090,242,660,1090,241,650,1090]),
 'ACT_B_R05_B':('exec-deb8a25b-1015-418b-a403-7720168f8c6c.png',[0,445,818,1254],315,490,[212,637,1057,229,648,1076,220,637,1060]),
}

def main():
 overlay={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'entries':{}}
 report=[]
 for actor,(name,rows,targetHeight,anchorY,centers) in ITEMS.items():
  dest=ART/'GeneratedCandidates'/actor/'attack_cycle_r001';(dest/'frames').mkdir(parents=True,exist_ok=True)
  src=dest/'SOURCE.png'
  if not src.exists():shutil.copy2(GEN/name,src)
  sheet=Image.open(src).convert('RGBA');cells=[]
  for n in range(9):
   row,col=divmod(n,3);box=(col*418,rows[row],(col+1)*418,rows[row+1]);cell=sheet.crop(box)
   b=cell.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
   margin=min(b[0],b[1],cell.width-b[2],cell.height-b[3])
   if margin<2:raise ValueError((actor,n,'No safe gutter',b))
   cells.append((cell,box,b,margin))
  # Uniform scale based on upright recovery; constrain every pose inside canvas.
  referenceScale=targetHeight/(cells[-1][2][3]-cells[-1][2][1])
  scale=referenceScale
  scale=min(scale,460/max(c[2][3]-c[2][1] for c in cells))
  for n,(_,box,b,_) in enumerate(cells):
   localX=centers[n]-box[0]
   scale=min(scale,238/max(1,localX-b[0]),238/max(1,b[2]-localX))
  frames=[];contact=Image.new('RGBA',(768,768),(36,50,43,255))
  for n,(cell,box,b,margin) in enumerate(cells):
   dx=round(256-(centers[n]-box[0])*scale)
   dy=round(anchorY-(b[1]+b[3])/2*scale) if anchorY==300 else round(490-b[3]*scale)
   frame=Image.new('RGBA',(512,512));frame.alpha_composite(cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST),(dx,dy))
   path=dest/'frames'/f'attack_{n:03}.png';temporary=path.with_suffix(".tmp.png");frame.save(temporary);temporary.replace(path)
   contact.alpha_composite(frame.resize((256,256),Image.Resampling.NEAREST),((n%3)*256,(n//3)*256))
   frames.append({'path':str(path.relative_to(ART)),'source_box':box,'source_margin_alpha16_px':margin,'translation':[dx,dy],'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
  contact.convert('RGB').save(dest/'CONTACT.jpg')
  manifest={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE','actor':actor,'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'generator':'built-in imagegen, identity-preserving edit','source_generated_path':str(GEN/name),'productionSpec':'Nine sequential anticipation/strike/recovery drawings, exact identity, transparent background, full appendages, no text/ground; repair passes reduced each subject to provide slicing gutters. Per-pose manual body center registration; alpha preserved.','scale':scale,'anchor':[256,anchorY],'canvas_px':[512,512],'frames':frames,'naturalMotionApproved':False,'remaining':['in-game transition and all-frame review','Human art acceptance','idle/hit/resolve continuous motion review']}
  (dest/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
  entry={'clips':{},'sequenceFrames':{}}
  for state,start in [('anticipate',0),('execute',3),('recover',6)]:
   paths=[f['path'] for f in frames[start:start+3]]
   entry['sequenceFrames'][state]=paths
   entry['clips'][state]={'frames':paths,'fps':10,'duration_seconds':.3,'frame_count':3,'loop':False,'canvas_px':[512,512],'anchor':[256,anchorY],'display_scale':referenceScale/scale,'status':'UNAPPROVED_AUTHORED_ATTACK_INBETWEEN_CANDIDATE','complete_animation':False}
  overlay['entries'][actor]=entry;report.append({'actor':actor,'frames':9,'manifest':str((dest/'manifest.json').relative_to(ROOT)),'minSourceMarginAlpha16':min(f['source_margin_alpha16_px'] for f in frames),'scale':scale,'runtimeVerified':False})
 (ART/'runtime_overlay_zz_r05_attack_cycles_r001.json').write_text(json.dumps(overlay,ensure_ascii=False,indent=2)+'\n')
 (ROOT/'docs/production/current/art/R05_ATTACK_CANDIDATES_R001.json').write_text(json.dumps({'status':'PACKED_PENDING_RUNTIME_REVIEW','candidates':report},indent=2)+'\n')
 print(json.dumps(report))
if __name__=='__main__':main()

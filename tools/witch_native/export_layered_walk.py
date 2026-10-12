#!/usr/bin/env python3
"""Pack staff-free body frames and explicit per-frame hand attachment points."""
from pathlib import Path
from PIL import Image
import hashlib,json,shutil,os
ROOT=Path(__file__).resolve().parents[2]
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12398-0ccb-7d03-aeac-75db9b0de178')
OUT=ROOT/'native/GeneratedArt/layered_motion_r001'
ITEMS={
 'standard':('exec-40a53670-a1e7-463f-99b3-bf8d02af6cbb.png',[0,420,830,1254],[(264,230),(675,230),(1101,230),(262,632),(682,635),(1105,637),(263,1044),(682,1041),(1106,1043)],231),
 'travel':('exec-23ad24a1-dc58-4916-a4c3-e024f3cbb7fe.png',[0,423,829,1254],[(165,267),(557,266),(961,267),(167,668),(557,668),(961,670),(167,1075),(558,1075),(961,1075)],236),
}
def main():
 OUT.mkdir(parents=True,exist_ok=True);manifest=json.loads((OUT/'MANIFEST.json').read_text()) if (OUT/'MANIFEST.json').exists() else {}
 for costume,(name,edges,grips,height) in ITEMS.items():
  src=GEN/name;sheet=Image.open(src).convert('RGBA');shutil.copy2(src,OUT/(costume+'_WALK_SOURCE.png'));cells=[]
  for n in range(9):
   r,c=divmod(n,3);box=(c*418,edges[r],(c+1)*418,edges[r+1]);cell=sheet.crop(box);b=cell.getchannel('A').point(lambda a:255 if a>=32 else 0).getbbox()
   if not b or min(b[0],b[1],cell.width-b[2],cell.height-b[3])<2:raise ValueError((costume,n,'cropped or empty',b))
   cells.append((n,cell,b,box))
  scale=min(height/max(b[3]-b[1] for _,_,b,_ in cells),225/max(b[2]-b[0] for _,_,b,_ in cells));frames=[];contact=Image.new('RGBA',(768,768),(24,32,40,255))
  for n,cell,b,box in cells:
   dx=round(128-(b[0]+b[2])/2*scale);dy=round(244-b[3]*scale);frame=Image.new('RGBA',(256,256));resized=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST);frame.alpha_composite(resized,(dx,dy))
   path=f'{costume}__walk_{n}.png';temp=OUT/(path+'.tmp.png');frame.save(temp);os.replace(temp,OUT/path);contact.alpha_composite(frame,((n%3)*256,(n//3)*256));grip=[round((grips[n][0]-box[0])*scale+dx,3),round((grips[n][1]-box[1])*scale+dy,3)]
   frames.append({'path':path,'hand_top_left_px':grip,'angle':.80 if costume=='travel' else .08,'source_box':box,'translation':[dx,dy],'sha256':hashlib.sha256((OUT/path).read_bytes()).hexdigest()})
  contact.convert('RGB').save(OUT/(costume+'_WALK_CONTACT.jpg'))
  manifest[costume]={**manifest.get(costume,{}),'status':'UNAPPROVED_PARTIAL_CANDIDATE','naturalMotionComplete':False,'tool':'built-in image_gen','sourceSHA256':hashlib.sha256(src.read_bytes()).hexdigest(),'canvas':[256,256],'foot_anchor':[128,244],'scale':scale,'registration':'Grid crop, uniform scale across entire clip, translation to foot baseline; no per-frame scale or pixel painting. Hand coordinates measured per frame.','prompt':'Nine distinct walk phases of exact identity/costume, no staff, closed fist held steady near torso, full margins, true alpha, no background/text.','walk':{'fps':12,'loop':True,'frames':frames},'runtimeQA':'PENDING'}
 temp=OUT/'MANIFEST.tmp.json';temp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');os.replace(temp,OUT/'MANIFEST.json');print({k:len(v['walk']['frames']) for k,v in manifest.items()})
if __name__=='__main__':main()

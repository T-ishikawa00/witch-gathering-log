#!/usr/bin/env python3
"""Pack authored body casting phases and their measured hand attachment points."""
from pathlib import Path
from PIL import Image
import hashlib,json,shutil,os
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'native/GeneratedArt/layered_motion_r001'
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12398-0ccb-7d03-aeac-75db9b0de178')
ITEMS={
 'standard':('exec-27e2e6f9-b41d-4059-a682-6a130a21e50b.png',[0,416,820,1254],[(281,230),(715,267),(1142,267),(334,549),(768,562),(1206,548),(337,958),(714,1067),(1106,1044)],231,[.08,.05,-.10,-.3,-.45,-.45,-.3,-.1,.08]),
 'travel':('exec-6bba6ea6-018a-4e28-9eaf-ee5569ccda26.png',[0,417,828,1254],[(142,254),(627,214),(1007,186),(361,630),(785,619),(1210,624),(314,1045),(610,1049),(999,1085)],236,[.80,.85,.90,-.3,-.45,-.45,-.3,-.60,.80]),
}
def main():
 manifest=json.loads((OUT/'MANIFEST.json').read_text())
 for costume,(name,edges,grips,height,angles) in ITEMS.items():
  src=GEN/name;sheet=Image.open(src).convert('RGBA');shutil.copy2(src,OUT/(costume+'_CAST_SOURCE.png'));cells=[]
  for n in range(9):
   r,c=divmod(n,3);box=(c*418,edges[r],(c+1)*418,edges[r+1]);cell=sheet.crop(box);b=cell.getchannel('A').point(lambda a:255 if a>=32 else 0).getbbox()
   if not b or min(b[0],b[1],cell.width-b[2],cell.height-b[3])<1:raise ValueError((costume,n,'cropped',b))
   cells.append((n,cell,b,box))
  scale=min(height/max(b[3]-b[1] for _,_,b,_ in cells),240/max(b[2]-b[0] for _,_,b,_ in cells));frames=[];contact=Image.new('RGBA',(768,768),(24,32,40,255))
  for n,cell,b,box in cells:
   dx=round(128-(b[0]+b[2])/2*scale);dy=round(244-b[3]*scale);frame=Image.new('RGBA',(256,256));frame.alpha_composite(cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST),(dx,dy));path=f'{costume}__cast_{n}.png';temp=OUT/(path+'.tmp.png');frame.save(temp);os.replace(temp,OUT/path);contact.alpha_composite(frame,((n%3)*256,(n//3)*256));grip=[round((grips[n][0]-box[0])*scale+dx,3),round((grips[n][1]-box[1])*scale+dy,3)]
   frames.append({'path':path,'hand_top_left_px':grip,'angle':angles[n],'source_box':box,'translation':[dx,dy],'sha256':hashlib.sha256((OUT/path).read_bytes()).hexdigest()})
  contact.convert('RGB').save(OUT/(costume+'_CAST_CONTACT.jpg'));entry=manifest[costume];entry['castSourceSHA256']=hashlib.sha256(src.read_bytes()).hexdigest();entry['castScale']=scale;entry['castPrompt']='Nine sequential wind-up, extend and recovery poses preserving exact identity/costume and closed fist. No staff; full margins and true alpha.'
  for state,start in [('anticipate',0),('execute',3),('recover',6)]:entry[state]={'fps':3/.28,'loop':False,'frames':frames[start:start+3]}
 temp=OUT/'MANIFEST.tmp.json';temp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');os.replace(temp,OUT/'MANIFEST.json');print({k:len(v['execute']['frames']) for k,v in manifest.items()})
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Pack body-only rest frames and measured grips without raster retouching."""
from pathlib import Path
from PIL import Image,ImageDraw
import hashlib,json,os,shutil
from export_party_rest import gutters
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'native/GeneratedArt/layered_motion_r001'
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12398-0ccb-7d03-aeac-75db9b0de178')
ITEMS={
 'standard':('exec-f9c0de4f-6c19-4773-8b96-90eb551762bb.png',[(290,272),(684,275),(1088,275),(250,675),(651,675),(1084,650),(267,1050),(648,1040),(1064,1042)],231,[.10,.10,.10,-.25,-.35,.10,.10,.10,.10]),
 'travel':('exec-671cb5d4-d47c-40ea-ad69-2280cfc9a9a3.png',[(165,278),(556,277),(959,277),(174,679),(565,699),(969,678),(167,1085),(556,1087),(972,1085)],236,[.80,.80,.80,.80,.80,.80,.80,.80,.80]),
}
def atomic(image,path):
 temp=path.with_name(path.stem+'.tmp'+path.suffix);image.save(temp);os.replace(temp,path)
def main():
 manifest=json.loads((OUT/'MANIFEST.json').read_text())
 for costume,(name,grips,targetHeight,angles) in ITEMS.items():
  source=GEN/name;sheet=Image.open(source).convert('RGBA');shutil.copy2(source,OUT/(costume+'_REST_SOURCE.png'));xs=gutters(sheet,0);ys=gutters(sheet,1);cells=[]
  for n in range(9):
   row,col=divmod(n,3);box=(xs[col],ys[row],xs[col+1],ys[row+1]);cell=sheet.crop(box);b=cell.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
   if not b or min(b[0],b[1],cell.width-b[2],cell.height-b[3])<3:raise ValueError((costume,n,'cell cuts',b))
   cells.append((cell,b,box))
  scale=min(targetHeight/max(b[3]-b[1] for _,b,_ in cells),240/max(b[2]-b[0] for _,b,_ in cells));frames=[];contact=Image.new('RGBA',(768,768),'#253046');gripcontact=Image.new('RGBA',(768,768),'#253046')
  for n,(cell,b,box) in enumerate(cells):
   dx=round(128-(b[0]+b[2])/2*scale);dy=round(244-b[3]*scale);frame=Image.new('RGBA',(256,256));frame.alpha_composite(cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST),(dx,dy));bounds=frame.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
   if not bounds or min(bounds[0],bounds[1],256-bounds[2],256-bounds[3])<3:raise ValueError((costume,n,'export cuts',bounds))
   path=OUT/(costume+f'__rest_{n}.png');atomic(frame,path);hand=[round((grips[n][0]-box[0])*scale+dx,3),round((grips[n][1]-box[1])*scale+dy,3)];contact.alpha_composite(frame,((n%3)*256,(n//3)*256));mark=frame.copy();d=ImageDraw.Draw(mark);x,y=hand;d.ellipse((x-3,y-3,x+3,y+3),outline='lime',width=1);gripcontact.alpha_composite(mark,((n%3)*256,(n//3)*256))
   frames.append({'path':path.name,'hand_top_left_px':hand,'angle':angles[n],'source_box':box,'export_alpha16_bounds':bounds,'translation':[dx,dy],'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
  atomic(contact.convert('RGB'),OUT/(costume+'_REST_CONTACT.jpg'));atomic(gripcontact.convert('RGB'),OUT/(costume+'_REST_GRIP_QA.jpg'))
  entry=manifest[costume];entry['restSourceSHA256']=hashlib.sha256(source.read_bytes()).hexdigest();entry['restSourcePath']=str(source);entry['restScale']=scale;entry['restStatus']='UNAPPROVED_BODY_AND_HAND_MOTION_CANDIDATE';entry['restRegistration']='Measured alpha16 transparent gutters, RGBA crop/nearest scale/translation; manual per-frame grip coordinates, no painted alpha or colors.'
  for state,start,durations in [('idle',0,[1.6,1.6,.14] if costume=='standard' else [1.6,.14,1.6]),('hit',3,[.10,.12,.10]),('resolve',6,[.16,.18,.24])]:entry[state]={'fps':10,'loop':state=='idle','durations':durations,'frames':frames[start:start+3]}
 temp=OUT/'MANIFEST.tmp.json';temp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2));os.replace(temp,OUT/'MANIFEST.json');print({k:len(v['idle']['frames'])+len(v['hit']['frames'])+len(v['resolve']['frames']) for k,v in manifest.items()})
if __name__=='__main__':main()

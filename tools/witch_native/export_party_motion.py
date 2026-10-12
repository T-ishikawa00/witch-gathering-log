#!/usr/bin/env python3
"""Atlas export only: preserve source pixels/identity; normalize canvas/foot anchors.
Image generation supplies intermediate art, while rejected/clipped cells stay out of runtime.
"""
from pathlib import Path
from PIL import Image
import hashlib,json,shutil,argparse
ROOT=Path(__file__).resolve().parents[2]
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12398-0ccb-7d03-aeac-75db9b0de178')
sources={'ERNA':'exec-067b63c4-892a-45e3-bd72-963334dd130b.png','LUNA':'exec-ca1828de-543f-4f8f-9fd3-94e35ed641cf.png','AIRA':'exec-3e341651-08c5-4698-a375-4e146c5a2eca.png','NOIR':'exec-01e2f83f-0a67-4f8c-8421-aa1376990e51.png'}
parser=argparse.ArgumentParser();parser.add_argument('--luna-source');args=parser.parse_args()
if args.luna_source:sources['LUNA']=args.luna_source
# Noir cells 5/6 contain an invented tan streak and remain rejected.
excluded={'NOIR':{5,6}}
report={};out=ROOT/'native/GeneratedArt/party_motion_r002';out.mkdir(parents=True,exist_ok=True)
for actor,name in sources.items():
 source=GEN/name;sheet=Image.open(source).convert('RGBA');shutil.copy2(source,out/(actor+'_SOURCE.png'))
 cells=[];rows=[]
 for i in range(8):
  c=i%4;r=i//4;box=(round(c*sheet.width/4),round(r*sheet.height/2),round((c+1)*sheet.width/4),round((r+1)*sheet.height/2));cell=sheet.crop(box);a=cell.getchannel('A');bbox=a.point(lambda v:255 if v>=32 else 0).getbbox()
  if not bbox:continue
  edge=min(bbox[0],bbox[1],cell.width-bbox[2],cell.height-bbox[3]);reject=edge<3 or i in excluded.get(actor,set())
  rows.append({'index':i,'cell':box,'opaque_bbox':bbox,'min_edge_px':edge,'status':'REJECTED_CROP_OR_INVENTED_OBJECT' if reject else 'CANDIDATE'})
  if not reject:
   last=bbox[3];points=[x for y in range(max(bbox[1],last-14),last) for x in range(cell.width) if a.getpixel((x,y))>=64]
   foot=sum(points)/len(points) if points else (bbox[0]+bbox[2])/2
   cells.append((i,cell,bbox,foot))
 # One scale per actor, never stretch limbs or recolor art.
 canvas=(384,256);anchor=(canvas[0]//2,244)
 scale=min([0.7]+[limit for _,_,b,foot in cells for limit in [220/(b[3]-b[1]),(anchor[0]-5)/max(1,foot-b[0]),(canvas[0]-anchor[0]-5)/max(1,b[2]-foot)]])
 paths=[]
 for i,cell,bbox,foot in cells:
  last=bbox[3]
  resized=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST)
  dest=Image.new('RGBA',canvas);offset=(round(anchor[0]-foot*scale),round(anchor[1]-last*scale));dest.alpha_composite(resized,offset)
  final_box=dest.getchannel('A').point(lambda v:255 if v>=32 else 0).getbbox()
  assert final_box and min(final_box[0],final_box[1],canvas[0]-final_box[2],canvas[1]-final_box[3])>=3,(actor,i,final_box)
  path=out/(actor+f'__cast_{i}.png');dest.save(path);paths.append(path.name)
 report[actor]={'status':'UNAPPROVED_CANDIDATE_INTERMEDIATE_POSES_NOT_FULL_ANIMATION','source':str(source),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'scale':scale,'canvas':canvas,'foot_anchor':anchor,'export_boundary_check':'PASS','cells':rows,'exported_frames':paths}
(out/'MANIFEST.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps({k:{'frames':len(v['exported_frames']),'rejected':[x['index'] for x in v['cells'] if x['status'].startswith('REJECTED')]} for k,v in report.items()}))

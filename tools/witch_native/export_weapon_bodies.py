#!/usr/bin/env python3
"""Atlas packing only; image_gen authored the staff-free bodies and alpha repairs."""
from pathlib import Path
from PIL import Image
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[2]
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12398-0ccb-7d03-aeac-75db9b0de178')
out=ROOT/'native/GeneratedArt/weapon_layers_r002';out.mkdir(parents=True,exist_ok=True)
sources=[('exec-76a502ad-409b-4695-a3b0-410719be73c5.png',['idle','anticipate','execute']),('exec-e499fe1e-b773-48d7-958f-1b883a2741f3.png',['recover','hit','resolve'])]
report={'status':'UNAPPROVED_LAYERED_BODY_AND_WEAPON_CANDIDATE','humanApproval':False,'tool':'built-in image_gen','prompt':'Preserve approved ERNA pose/face/standard costume; remove complete staff and dangling crystal only, reconstruct empty grip, transparent 3-column body atlas, no redesign/props/effects. Repair cropped hat by reducing all figures to 75% and restoring tip with transparent margins. Staff extraction: preserve design, remove all brown/black diffuse glow/background/haze/shadow, true transparent alpha.','bodyFrames':{},'weapons':{}}
contact=Image.new('RGBA',(256*3,256*2),(24,34,43,255))
for row,(name,states) in enumerate(sources):
    source=GEN/name;shutil.copy2(source,out/('BODY_SOURCE_'+str(row)+'.png'));sheet=Image.open(source).convert('RGBA')
    for col,state in enumerate(states):
        cell=sheet.crop((round(col*sheet.width/3),0,round((col+1)*sheet.width/3),sheet.height));b=cell.getchannel('A').point(lambda x:255 if x>=32 else 0).getbbox()
        assert b and min(b[0],b[1],cell.width-b[2],cell.height-b[3])>=3,(state,b)
        scale=min(200/(b[3]-b[1]),238/(b[2]-b[0]));resized=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST)
        frame=Image.new('RGBA',(256,256));frame.alpha_composite(resized,(round(128-(b[0]+b[2])/2*scale),round(244-b[3]*scale)))
        path=out/('ERNA_STANDARD_BODY__'+state+'.png');frame.save(path);contact.alpha_composite(frame,(col*256,row*256))
        report['bodyFrames'][state]={'path':path.name,'source':str(source),'sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'footAnchor':[128,244],'canvas':[256,256],'scale':scale}
contact.convert('RGB').save(out/'BODY_CONTACT.jpg')
for key,name,anchor in [('STAFF_MOON','exec-f774e1fa-c7c5-41ff-97e8-98c4349f01a3.png',[0.451,0.50]),('STAFF_BRANCH','exec-8c1b7d97-e8c6-4f55-ad78-fdccc4ec5a56.png',[0.547,0.50])]:
    source=GEN/name;im=Image.open(source).convert('RGBA');im.thumbnail((512,768),Image.Resampling.LANCZOS);path=out/(key+'_ALPHA_R002.png');im.save(path)
    report['weapons'][key]={'path':path.name,'source':str(source),'sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'gripAnchor':anchor}
shutil.copy2(GEN/'exec-893d8d0b-99b2-48b1-8b26-596a166c31da.png',out/'REJECTED_CROPPED_HAT_SOURCE.png')
report['rejected']={'REJECTED_CROPPED_HAT_SOURCE.png':'Top of recovering hat touched atlas boundary; replaced by framed r002 source.'}
(out/'MANIFEST.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('6 body frames and 2 repaired alpha weapon sprites exported')

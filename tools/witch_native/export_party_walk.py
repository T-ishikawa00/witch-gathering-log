#!/usr/bin/env python3
"""Pack generated gait cells without painting, recoloring, or replacing approved art."""
from pathlib import Path
from PIL import Image
import hashlib,json,shutil

ROOT=Path(__file__).resolve().parents[2]
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12398-0ccb-7d03-aeac-75db9b0de178')
SOURCES={
    'ERNA':'exec-d78354ac-a972-4ba2-8421-8655e633a7d6.png',
    'LUNA':'exec-0fc72024-c6b9-47d7-a95d-3f3e4950b138.png',
    'AIRA':'exec-b72250e1-4bcb-41fa-b272-b4ce8ec589d4.png',
    'NOIR':'exec-06000ba8-cc27-4c1c-b252-8961568e60e4.png',
}
PROMPT='Identity-preserve approved character reference. Transparent 3x3 equal-grid atlas of nine successive gentle walk phases, alternate contact/down/passing/up, fixed identity/costume/weapon/scale, three-quarter camera facing right, full silhouette with transparent gutters, no labels, effects, ground, shadows or colored matte. Noir: four-legged gait, retain red scarf and blue pendant. Humans: same staff/hammer and hand throughout.'
out=ROOT/'native/GeneratedArt/party_walk_r001';out.mkdir(parents=True,exist_ok=True)
manifest={}
for actor,filename in SOURCES.items():
    source=GEN/filename;sheet=Image.open(source).convert('RGBA');shutil.copy2(source,out/(actor+'_SOURCE.png'))
    reference=ROOT/f'native/Art/Characters/{actor}/{actor}__idle__256__r001.png'
    ref=Image.open(reference).convert('RGBA');rb=ref.getchannel('A').point(lambda a:255 if a>=32 else 0).getbbox()
    cells=[];rows=[]
    for i in range(9):
        x,y=i%3,i//3
        # ERNA's generated rows are uneven: alpha bands 49..420,445..814,843..1214.
        # Slice in the observed transparent gaps; an equal 418px cut would clip boots.
        row_edges=[0,433,829,sheet.height] if actor=='ERNA' else [round(j*sheet.height/3) for j in range(4)]
        box=(round(x*sheet.width/3),row_edges[y],round((x+1)*sheet.width/3),row_edges[y+1])
        cell=sheet.crop(box);alpha=cell.getchannel('A');b=alpha.point(lambda a:255 if a>=32 else 0).getbbox()
        if not b:raise ValueError((actor,i,'empty cell'))
        edge=min(b[0],b[1],cell.width-b[2],cell.height-b[3])
        rejected= edge<3 or (actor=='NOIR' and i==1)
        rows.append({'index':i,'opaqueBounds':b,'edgePixels':edge,'status':'REJECTED_SITTING_POSE_OR_CROP' if rejected else 'CANDIDATE'})
        if not rejected:cells.append((i,cell,b))
    # A single scale preserves gait silhouette changes. Match approved visible height,
    # and register each cell by silhouette centre and foot baseline on the same canvas.
    scale=min((rb[3]-rb[1])/max(b[3]-b[1] for _,_,b in cells),220/max(b[2]-b[0] for _,_,b in cells))
    names=[];hashes=[];contact=Image.new('RGBA',(256*3,256*3),(23,32,39,255))
    for i,cell,b in cells:
        frame=Image.new('RGBA',(256,256));resized=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST)
        frame.alpha_composite(resized,(round(128-(b[0]+b[2])*0.5*scale),round(244-b[3]*scale)))
        fb=frame.getchannel('A').point(lambda a:255 if a>=32 else 0).getbbox()
        assert fb and min(fb[0],fb[1],256-fb[2],256-fb[3])>=3,(actor,i,fb)
        name=f'{actor}__walk_{i}.png';p=out/name;frame.save(p);names.append(name);hashes.append(hashlib.sha256(p.read_bytes()).hexdigest());contact.alpha_composite(frame,((i%3)*256,(i//3)*256))
    contact.convert('RGB').save(out/(actor+'_CONTACT.jpg'))
    manifest[actor]={'status':'UNAPPROVED_WALK_SEQUENCE_CANDIDATE','humanApproval':False,'naturalMotionComplete':False,'source':str(source),'sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'reference':str(reference),'prompt':PROMPT,'tool':'built-in image_gen','canvas':[256,256],'footAnchor':[128,244],'fps':12,'scale':scale,'cells':rows,'frames':names,'frameSHA256':hashes,'runtimeQA':'PENDING'}
(out/'MANIFEST.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:len(v['frames']) for k,v in manifest.items()}))

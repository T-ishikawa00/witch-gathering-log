#!/usr/bin/env python3
"""Pack generated resolve-only strips without painting or modifying alpha."""
from pathlib import Path
import hashlib,json,shutil
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2];ART=ROOT/'native/Art'
SOURCES={
 'ACT_E_R02_03':('exec-4a7128ce-7cda-49f1-b761-71fc2eb6a826.png','Enemies/ACT_E_R02_03/frames/frame_00000.png'),
 'ACT_E_R04_02':('exec-43cb42f7-cfba-4baf-b832-a8157e0af92b.png','GeneratedCandidates/ACT_E_R04_02/idle_hit_resolve_r001/frames/idle_001.png')}
GENERATED=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12398-0ccb-7d03-aeac-75db9b0de178')
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
entries={}
for actor,(filename,reference) in SOURCES.items():
    out=ART/'GeneratedCandidates'/actor/'terminal_resolve_r001';out.mkdir(parents=True,exist_ok=True)
    source=GENERATED/filename;im=Image.open(source).convert('RGBA');shutil.copy2(source,out/'SOURCE.png')
    alpha=im.getchannel('A').point(lambda x:255 if x>=16 else 0)
    occupied=[alpha.crop((x,0,x+1,im.height)).getbbox() is not None for x in range(im.width)]
    runs=[];begin=None
    for x,value in enumerate(occupied+[True]):
        if not value and begin is None:begin=x
        if value and begin is not None:runs.append((begin,x));begin=None
    cuts=[0]
    for k in [1,2]:
        target=im.width*k/3
        candidates=[r for r in runs if r[1]-r[0]>=6 and abs((r[0]+r[1])/2-target)<im.width/10]
        if not candidates:raise ValueError('No genuine alpha gutter: '+actor)
        cut=min(candidates,key=lambda r:abs((r[0]+r[1])/2-target));cuts.append((cut[0]+cut[1])//2)
    cuts.append(im.width)
    cells=[im.crop((cuts[i],0,cuts[i+1],im.height)) for i in range(3)]
    boxes=[cell.getchannel('A').point(lambda x:255 if x>=16 else 0).getbbox() for cell in cells]
    margins=[min(b[0],b[1],cell.width-b[2],cell.height-b[3]) for cell,b in zip(cells,boxes)]
    if min(margins)<3:raise ValueError('Edge contact: '+actor+str(margins))
    scale=min(430/max(b[2]-b[0] for b in boxes),410/max(b[3]-b[1] for b in boxes))
    frames=[];frame_boxes=[];contact=Image.new('RGBA',(1536,512),(22,26,31,255))
    for i,(cell,box) in enumerate(zip(cells,boxes)):
        # Retain each complete source cell, and clip only its empty border via the canvas.
        resized=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST)
        x=round(256-(box[0]+box[2])/2*scale);y=round(455-box[3]*scale)
        frame=Image.new('RGBA',(512,512));frame.alpha_composite(resized,(x,y));b=frame.getchannel('A').point(lambda v:255 if v>=16 else 0).getbbox()
        assert b and min(b[0],b[1],512-b[2],512-b[3])>=4
        p=out/f'resolve_{i:03}.png';tmp=p.with_suffix('.tmp.png');frame.save(tmp);tmp.replace(p);frames.append(str(p.relative_to(ART)));frame_boxes.append(b);contact.alpha_composite(frame,(512*i,0))
    ref=Image.open(ART/reference).convert('RGBA');rb=ref.getchannel('A').point(lambda x:255 if x>=16 else 0).getbbox()
    display=(rb[2]-rb[0])/ref.height*512/(frame_boxes[0][2]-frame_boxes[0][0])
    contact.convert('RGB').save(out/'CONTACT_DARK.jpg',quality=92)
    manifest={'status':'UNAPPROVED_RESOLVE_ONLY_CANDIDATE','source':str(source),'sourceSHA256':digest(source),'reference':reference,'referenceSHA256':digest(ART/reference),'cuts':cuts,'minimumCellMarginsAlpha16':margins,'uniformScale':scale,'frames':[{ 'path':p,'sha256':digest(ART/p),'alpha16Bounds':b} for p,b in zip(frames,frame_boxes)],'displayScale':display,'terminalMeaning':'visibly collapsed/resting with no return to idle','humanApproval':False,'naturalMotionComplete':False}
    (out/'MANIFEST.json').write_text(json.dumps(manifest,indent=2))
    entries[actor]={'clips':{'resolve':{'frames':frames,'frame_count':3,'fps':7,'duration_seconds':3/7,'loop':False,'canvas_px':[512,512],'anchor':[256,455],'display_scale':display,'status':'UNAPPROVED_TERMINAL_RESOLVE_CANDIDATE','complete_animation':False}}}
overlay={'status':'UNAPPROVED_RESOLVE_ONLY_CANDIDATE','human_approval':False,'source_art_untouched':True,'entries':entries}
(ART/'runtime_overlay_zzzzzzzz_root_terminal_resolve_r001.json').write_text(json.dumps(overlay,indent=2))
print(json.dumps({k:v['clips']['resolve']['display_scale'] for k,v in entries.items()}))

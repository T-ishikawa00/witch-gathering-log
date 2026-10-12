#!/usr/bin/env python3
"""Pack generated art only; no painted pixels, alpha cleanup or recoloring."""
from pathlib import Path
from PIL import Image
import hashlib,json,os,shutil
ROOT=Path(__file__).resolve().parents[2]
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12398-0ccb-7d03-aeac-75db9b0de178')
SOURCES={'ERNA':'exec-61bae633-7297-4b1a-a739-6d6b84fcddfd.png','LUNA':'exec-cf1366d6-0639-46ee-ad87-787a89b1269e.png','AIRA':'exec-756fc37d-0e7b-4504-a4d5-a4f0326adbfb.png','NOIR':'exec-219bec11-f951-4527-a8e3-978568c81d4a.png'}
OUT=ROOT/'native/GeneratedArt/party_rest_r001'
def atomic_image(image,path):
    temporary=path.with_name(path.stem+'.tmp'+path.suffix);image.save(temporary);os.replace(temporary,path)
def gutters(sheet,axis):
    mask=sheet.getchannel('A').point(lambda a:255 if a>=16 else 0);extent=sheet.width if axis==0 else sheet.height;empty=[]
    for position in range(extent):
        box=(position,0,position+1,sheet.height) if axis==0 else (0,position,sheet.width,position+1)
        empty.append(mask.crop(box).getbbox() is None)
    runs=[];start=None
    for position,value in enumerate(empty+[False]):
        if value and start is None:start=position
        if not value and start is not None:
            if position-start>=8:runs.append((start,position))
            start=None
    result=[0]
    for i in [1,2]:
        target=extent*i/3;options=[(a+b)//2 for a,b in runs if abs((a+b)/2-target)<extent/12]
        if not options:raise ValueError(('no transparent gutter',axis,i))
        result.append(min(options,key=lambda value:abs(value-target)))
    return result+[extent]
def main():
    OUT.mkdir(parents=True,exist_ok=True);manifest={}
    for actor,name in SOURCES.items():
        source=GEN/name;sheet=Image.open(source).convert('RGBA');shutil.copy2(source,OUT/(actor+'_SOURCE.png'))
        original=Image.open(ROOT/f'native/Art/Characters/{actor}/{actor}__idle__256__r001.png').convert('RGBA')
        original_box=original.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
        cells=[];xs=gutters(sheet,0);ys=gutters(sheet,1)
        for i in range(9):
            row,col=divmod(i,3);box=(xs[col],ys[row],xs[col+1],ys[row+1]);cell=sheet.crop(box)
            alpha=cell.getchannel('A');bounds=alpha.point(lambda a:255 if a>=16 else 0).getbbox()
            if not bounds:raise ValueError((actor,i,'empty'))
            margin=min(bounds[0],bounds[1],cell.width-bounds[2],cell.height-bounds[3])
            if margin<5:raise ValueError((actor,i,'cell edge',bounds))
            # Register the low central foot band; do not let an outlying hammer
            # or tail move the body pivot. Keep one scale for the whole actor.
            points=[x for y in range(max(bounds[1],bounds[3]-12),bounds[3]) for x in range(round(cell.width*.30),round(cell.width*.68)) if alpha.getpixel((x,y))>=64]
            foot=sum(points)/len(points) if points else (bounds[0]+bounds[2])/2
            cells.append((cell,box,bounds,margin,foot))
        scale=(original_box[3]-original_box[1])/(sum(c[2][3]-c[2][1] for c in cells[:3])/3)
        canvas=(320,256);anchor=(160,244);rows=[];contact=Image.new('RGBA',(960,768),'#253046')
        for i,(cell,box,bounds,margin,foot) in enumerate(cells):
            frame=Image.new('RGBA',canvas);scaled=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST)
            frame.alpha_composite(scaled,(round(anchor[0]-foot*scale),round(anchor[1]-bounds[3]*scale)))
            final=frame.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
            if not final or min(final[0],final[1],canvas[0]-final[2],canvas[1]-final[3])<3:raise ValueError((actor,i,'export edge',final))
            path=OUT/(actor+f'__rest_{i:02}.png');atomic_image(frame,path);contact.alpha_composite(frame,((i%3)*320,(i//3)*256))
            rows.append({'path':path.name,'sourceBox':box,'sourceAlpha16Bounds':bounds,'sourceMargin':margin,'exportAlpha16Bounds':final,'sourceFootX':foot,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        atomic_image(contact.convert('RGB'),OUT/(actor+'_CONTACT.jpg'))
        manifest[actor]={'status':'UNAPPROVED_ANIMATION_CANDIDATE','humanApproval':False,'naturalMotionComplete':False,'source':str(source),'sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'originalIdleSHA256':hashlib.sha256((ROOT/f'native/Art/Characters/{actor}/{actor}__idle__256__r001.png').read_bytes()).hexdigest(),'canvas':canvas,'anchor':anchor,'uniformScale':scale,'pixelHandling':'RGBA crop, uniform nearest resize and translation; alpha unchanged inside each source cell','frames':rows,'clips':{'idle':{'frames':[r['path'] for r in rows[:3]],'durations':[1.6,.14,1.6],'loop':True},'hit':{'frames':[r['path'] for r in rows[3:6]],'durations':[.10,.12,.10],'loop':False},'resolve':{'frames':[r['path'] for r in rows[6:]],'durations':[.16,.18,.24],'loop':False}}}
    temp=OUT/'MANIFEST.tmp.json';temp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2));os.replace(temp,OUT/'MANIFEST.json')
    print(json.dumps({key:len(value['frames']) for key,value in manifest.items()}))
if __name__=='__main__':main()

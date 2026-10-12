#!/usr/bin/env python3
"""Pack authored attack atlases; preserve pixels and original reference art."""
from pathlib import Path
from PIL import Image
import hashlib,json,os,shutil
from export_party_rest import gutters,atomic_image
ROOT=Path(__file__).resolve().parents[2]
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12398-0ccb-7d03-aeac-75db9b0de178')
OUT=ROOT/'native/GeneratedArt/party_attack_r001'
SOURCES={'ERNA':'exec-56ca950b-1e69-40c0-8513-0e6ac40844a7.png','LUNA':'exec-e38340ab-f54d-43d4-b811-ed9d26f99299.png','AIRA':'exec-32c7349b-d997-41e6-a80a-309ebf523f1a.png','NOIR':'exec-e7ff76c3-e4b6-4ef3-b086-a381eae6e012.png'}
def main():
    OUT.mkdir(parents=True,exist_ok=True);manifest={}
    for actor,name in SOURCES.items():
        source=GEN/name;sheet=Image.open(source).convert('RGBA');shutil.copy2(source,OUT/(actor+'_SOURCE.png'))
        original=ROOT/f'native/Art/Characters/{actor}/{actor}__idle__256__r001.png'
        original_box=Image.open(original).convert('RGBA').getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
        xs,ys=gutters(sheet,0),gutters(sheet,1);cells=[]
        for i in range(9):
            row,col=divmod(i,3);box=(xs[col],ys[row],xs[col+1],ys[row+1]);cell=sheet.crop(box);alpha=cell.getchannel('A');bounds=alpha.point(lambda a:255 if a>=16 else 0).getbbox()
            if not bounds:raise ValueError((actor,i,'empty'))
            margin=min(bounds[0],bounds[1],cell.width-bounds[2],cell.height-bounds[3])
            if margin<5:raise ValueError((actor,i,'source edge',margin))
            points=[x for y in range(max(bounds[1],bounds[3]-12),bounds[3]) for x in range(round(cell.width*.27),round(cell.width*.73)) if alpha.getpixel((x,y))>=64]
            foot=sum(points)/len(points) if points else (bounds[0]+bounds[2])/2
            cells.append((cell,box,bounds,margin,foot))
        # Match the final standing pose to canonical idle, not the raised weapon.
        end=cells[-1][2];scale=(original_box[3]-original_box[1])/(end[3]-end[1]);canvas=(320,256);anchor=(160,244);rows=[]
        contact=Image.new('RGBA',(960,768),'#253046')
        for i,(cell,box,bounds,margin,foot) in enumerate(cells):
            frame=Image.new('RGBA',canvas);scaled=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST)
            frame.alpha_composite(scaled,(round(anchor[0]-foot*scale),round(anchor[1]-bounds[3]*scale)))
            final=frame.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
            if not final or min(final[0],final[1],canvas[0]-final[2],canvas[1]-final[3])<3:raise ValueError((actor,i,'export edge',final))
            path=OUT/(actor+f'__attack_{i:02}.png');atomic_image(frame,path);contact.alpha_composite(frame,((i%3)*320,(i//3)*256))
            rows.append({'path':path.name,'sourceBox':box,'sourceAlpha16Bounds':bounds,'sourceMargin':margin,'exportAlpha16Bounds':final,'sourceFootX':foot,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        atomic_image(contact.convert('RGB'),OUT/(actor+'_CONTACT.jpg'))
        manifest[actor]={'status':'UNAPPROVED_ANIMATION_CANDIDATE','humanApproval':False,'naturalMotionComplete':False,'source':str(source),'sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'originalIdleSHA256':hashlib.sha256(original.read_bytes()).hexdigest(),'canvas':canvas,'anchor':anchor,'uniformScale':scale,'pixelHandling':'RGBA crop, uniform nearest resize and translation; no painted or alpha-modified source pixels','frames':rows,'clips':{state:{'frames':[r['path'] for r in rows[offset:offset+3]],'durations':times,'loop':False} for state,offset,times in [('anticipate',0,[.10,.10,.12]),('execute',3,[.08,.10,.12]),('recover',6,[.10,.12,.14])]}}
    temp=OUT/'MANIFEST.tmp.json';temp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2));os.replace(temp,OUT/'MANIFEST.json')
    print(json.dumps({k:len(v['frames']) for k,v in manifest.items()}))
if __name__=='__main__':main()

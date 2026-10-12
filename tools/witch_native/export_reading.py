from pathlib import Path
from PIL import Image
import json,hashlib,shutil
ROOT=Path(__file__).resolve().parents[2]
src=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12398-0ccb-7d03-aeac-75db9b0de178/exec-6a51ea69-e07a-40bb-a9f6-abdda710ff5a.png')
out=ROOT/'native/GeneratedArt/r001';shutil.copy2(src,out/'LUNA_READING_SHEET.png')
im=Image.open(src).convert('RGBA');cw,ch=im.width//2,im.height//2;records=[]
for i in range(4):
    cell=im.crop(((i%2)*cw,(i//2)*ch,(i%2+1)*cw,(i//2+1)*ch));a=cell.getchannel('A');strong=a.point(lambda v:255 if v>=128 else 0);box=strong.getbbox();bottom=box[3]
    band=strong.crop((0,max(0,bottom-18),cw,bottom));coords=[(x,v) for y in range(band.height) for x in range(cw) if (v:=band.getpixel((x,y)))>0];x=sum(x*v for x,v in coords)/sum(v for x,v in coords)
    factor=.8;scaled=cell.resize((round(cw*factor),round(ch*factor)),Image.Resampling.NEAREST);canvas=Image.new('RGBA',(512,512));offset=(round(256-x*factor),round(488-bottom*factor));canvas.alpha_composite(scaled,offset);p=out/f'LUNA_READING__{i}.png';canvas.save(p)
    records.append({'id':p.stem,'cell':i,'source_foot':[x,bottom],'target_foot':[256,488],'uniform_scale':factor,'offset':offset,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(out/'LUNA_READING_EXPORT.json').write_text(json.dumps({'source':str(src),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'status':'UNAPPROVED_TEST_ART','original_character_preserved':True,'purpose':'separate seated actor behind independent table; four authored page-turn/blink poses','foot_method':'opaque lower18px horizontal centroid with common uniform scale; candidate registration','records':records},ensure_ascii=False,indent=2))

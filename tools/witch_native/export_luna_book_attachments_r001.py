#!/usr/bin/env python3
"""Pack generated LUNA bookless pose and three book attachment candidates. Alpha is never repainted."""
from pathlib import Path
from PIL import Image,ImageDraw
import hashlib,json,os
ROOT=Path(__file__).resolve().parents[2]
S=ROOT/'native/GeneratedArt/luna_book_attachment_candidates_r001/sources'
O=ROOT/'native/GeneratedArt/r001'
SIZE=(256,256)
STATES={
 'idle': {'raw':'LUNA_BOOKLESS_IDLE_RAW.png','centerY':148,'bookTopLeft':(104,136),'bookBox':(64,44)},
 'walk': {'raw':'LUNA_BOOKLESS_WALK_RAW.png','centerY':148,'bookTopLeft':(104,136),'bookBox':(64,44)},
 'anticipate': {'raw':'LUNA_BOOKLESS_ANTICIPATE_RAW.png','centerY':148,'bookTopLeft':(104,136),'bookBox':(64,44)},
 'execute': {'raw':'LUNA_BOOKLESS_EXECUTE_RAW.png','centerY':148,'bookTopLeft':(104,136),'bookBox':(64,44)},
 'recover': {'raw':'LUNA_BOOKLESS_RECOVER_RAW.png','centerY':148,'bookTopLeft':(104,136),'bookBox':(64,44)},
 'hit': {'raw':'LUNA_BOOKLESS_HIT_RAW.png','centerY':148,'bookTopLeft':(104,136),'bookBox':(64,44)},
 'resolve': {'raw':'LUNA_BOOKLESS_RESOLVE_RAW.png','centerY':148,'bookTopLeft':(104,136),'bookBox':(64,44)},
}

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def bbox16(im):return im.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
def atomic_save(im,path):
 path=Path(path);tmp=path.with_suffix(path.suffix+'.tmp');im.save(tmp,format='JPEG' if path.suffix.lower() in ('.jpg','.jpeg') else 'PNG');os.replace(tmp,path)
def pack_crop(src,dest,max_box,center):
 im=Image.open(src).convert('RGBA');b=bbox16(im);assert b,(src,b)
 pad=12;cropbox=(max(0,b[0]-pad),max(0,b[1]-pad),min(im.width,b[2]+pad),min(im.height,b[3]+pad));crop=im.crop(cropbox)
 factor=min(max_box[0]/crop.width,max_box[1]/crop.height);w=max(1,round(crop.width*factor));h=max(1,round(crop.height*factor))
 crop=crop.resize((w,h),Image.Resampling.NEAREST)
 out=Image.new('RGBA',SIZE,(0,0,0,0));out.alpha_composite(crop,(center[0]-w//2,center[1]-h//2));atomic_save(out,dest)
 chk=Image.open(dest).convert('RGBA');assert chk.size==SIZE and bbox16(chk)
 return {'rawPath':str(src.relative_to(ROOT)),'rawSHA256':sha(src),'rawCanvasPx':list(im.size),'rawAlpha16BBoxPx':list(b),'cropWithPaddingPx':list(cropbox),'packedPath':str(dest.relative_to(ROOT)),'packedSHA256':sha(dest),'packedCanvasPx':list(SIZE),'packedAlpha16BBoxPx':list(bbox16(chk)),'resize':'nearest-neighbor, aspect-preserving transparent-alpha crop; no pixel drawing/removal'}
poseRecords=[]
for state,cfg in STATES.items():
 aid=f'LUNA_BOOKLESS_{state.upper()}_CANDIDATE_R001'
 rec=pack_crop(S/cfg['raw'],O/f'{aid}.png',(166,192),(128,cfg['centerY']))
 rec.update({'poseState':state,'assetID':aid,'sourceAlpha16BBoxPx':rec['rawAlpha16BBoxPx'],'footBaselineCanvasY':244,'status':'UNAPPROVED_TEST_OVERLAY_CANDIDATE'})
 poseRecords.append(rec)
items=[]
for gid in ['EQ_A_01','EQ_A_02','EQ_A_03']:
 icon=ROOT/f'native/Art/GearIcons/ICO_{gid}/ICO_{gid}__256__r001.png'
 for state,cfg in STATES.items():
  aid=f'BOOK_{gid}' if state=='idle' else f'BOOK_{gid}__{state}'
  pos=cfg['bookTopLeft'];box=cfg['bookBox']
  rec=pack_crop(S/f'BOOK_{gid}_RAW.png',O/f'{aid}.png',box,(pos[0]+box[0]//2,pos[1]+box[1]//2))
  rec.update({'gearID':gid,'poseState':state,'assetID':aid,'sourceIcon':str(icon.relative_to(ROOT)),'sourceIconSHA256':sha(icon),'layerTransform':{'topLeftPx':list(pos),'rotationDeg':0,'scale':1},'status':'UNAPPROVED_TEST_OVERLAY_CANDIDATE'})
  items.append(rec)
# Contact sheet visualizes all candidate pose states with the A01 book on dark/light backgrounds.
rows=[]
for bg in [(36,33,41,255),(235,232,224,255)]:
 canvas=Image.new('RGBA',(7*220,320),bg);d=ImageDraw.Draw(canvas)
 for i,(pose,item) in enumerate(zip(poseRecords,[x for x in items if x['gearID']=='EQ_A_01'])):
  x=i*220+28;y=18
  canvas.alpha_composite(Image.open(ROOT/pose['packedPath']).convert('RGBA').resize((192,192),Image.Resampling.NEAREST),(x,y))
  canvas.alpha_composite(Image.open(ROOT/item['packedPath']).convert('RGBA').resize((192,192),Image.Resampling.NEAREST),(x,y))
  d.text((x,y+218),pose['poseState'],fill='white' if bg[0]<100 else (20,20,25,255))
 rows.append(canvas.convert('RGB'))
contactImage=Image.new('RGB',(7*220,640));contactImage.paste(rows[0],(0,0));contactImage.paste(rows[1],(0,320))
contact=ROOT/'docs/production/current/core/LUNA_BOOK_ATTACHMENT_CANDIDATES_DARK_LIGHT_R002.jpg';atomic_save(contactImage,contact)
manifest={'schema':'luna_book_attachment_candidates_r002','status':'UNAPPROVED_TEST_OVERLAY','actorID':'C_APPRENTICE','spriteActorID':'LUNA','poses':poseRecords,'books':items,'canvasPx':list(SIZE),'candidateLayerLayout':{'bookCanvasSharesBase256x256':True,'footBaselineCanvasY':244,'poseSpecificBookAssets':True,'handAnchorPxByPose':{k:list(v['bookTopLeft']) for k,v in STATES.items()},'poseNotes':'All seven states are single authored key poses; not a continuous animation sequence. Book fit is provisional and requires native scene occlusion/hand alignment QA.'},'contactSheet':str(contact.relative_to(ROOT)),'sources':{'r1CharacterReference':'docs/design/visual/witch_characters_R1.png','runtimeIndex':'native/Art/runtime_index.json','r4GearSpec':'docs/design/sources/all_regions_r4/Witch_AllRegions_ArtSpec_R4_20261009/docs/04_MATERIAL_GEAR_AND_SCOPE.md'},'notApproved':['No Human design acceptance','No continuous animation acceptance','No new gear IDs or sales SKUs','Original LUNA staff poses and gear icons unchanged','Generated base poses require Human visual review']}
mp=ROOT/'native/GeneratedArt/luna_book_attachment_candidates_r001/LUNA_BOOK_ATTACHMENT_CANDIDATES_R002.json'
tmp=mp.with_suffix(mp.suffix+'.tmp');tmp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');os.replace(tmp,mp)
print(json.dumps({'poses':poseRecords,'bookLayerCount':len(items),'contact':str(contact),'manifest':str(mp)},ensure_ascii=False,indent=2))

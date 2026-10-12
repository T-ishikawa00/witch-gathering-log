#!/usr/bin/env python3
"""Package image-generated witch-staff gear candidates; never edits source icons/stills."""
from pathlib import Path
from PIL import Image
import hashlib, json, os
ROOT=Path(__file__).resolve().parents[2]
SOURCES={
 'EQ_W_P1':('/Users/PUBLIC_USER/.codex/generated_images/01a12399-5c96-7aa2-805f-d7e75a6df478/exec-bacc7ba6-7607-4b14-b408-dbe5ea6e716e.png','霧花の毒杖','共通柄を維持し密閉菌核と半透明霧室、小さな花房'),
 'EQ_W_P2':('/Users/PUBLIC_USER/.codex/generated_images/01a12399-5c96-7aa2-805f-d7e75a6df478/exec-1cd936d5-64f8-48d5-a7b8-79ac346450fc.png','夢庭の呪杖','剪定輪で囲う霧室と内部の夜花蜜弧'),
 'EQ_W_G1':('/Users/PUBLIC_USER/.codex/generated_images/01a12399-5c96-7aa2-805f-d7e75a6df478/exec-fbcba2ee-6113-413c-96f0-6e5f57a8515e.png','根守りの結界杖','枝核を細い蔓で支え根絡みの牙を小部材として添える'),
 'EQ_W_G2':('/Users/PUBLIC_USER/.codex/generated_images/01a12399-5c96-7aa2-805f-d7e75a6df478/exec-061455d3-6196-430d-ac6d-3600dc8c5558.png','月環の結界杖','内側の竜鱗膜、月銀の輪、封灯硝子'),
}
CANVAS=(512,683); GRIP=(0.547,0.5); assets=[]

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write_atomic(im,p):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);tmp=p.with_name(p.name+'.tmp');im.save(tmp,format='PNG');os.replace(tmp,p)
for gear_id,(raw,name,concept) in SOURCES.items():
 raw=Path(raw); assert raw.is_file(),raw
 icon=ROOT/'native/Art/GearIcons'/('ICO_'+gear_id)/('ICO_'+gear_id+'__256__r001.png')
 im=Image.open(raw).convert('RGBA'); a=im.getchannel('A'); bbox=a.point(lambda q:255 if q>=16 else 0).getbbox(); assert bbox,bbox
 pad=16; cropbox=(max(0,bbox[0]-pad),max(0,bbox[1]-pad),min(im.width,bbox[2]+pad),min(im.height,bbox[3]+pad)); crop=im.crop(cropbox)
 # Preserve aspect ratio while fitting the measured opaque silhouette to the base staff envelope.
 contentW,contentH=165,640; factor=min(contentW/crop.width,contentH/crop.height); size=(max(1,round(crop.width*factor)),max(1,round(crop.height*factor)))
 crop=crop.resize(size,Image.Resampling.NEAREST)
 packed=Image.new('RGBA',CANVAS,(0,0,0,0)); packed.alpha_composite(crop,((CANVAS[0]-size[0])//2,(CANVAS[1]-size[1])//2))
 asset_id='STAFF_'+gear_id; dest=ROOT/'native/GeneratedArt/r001'/f'{asset_id}.png';write_atomic(packed,dest)
 check=Image.open(dest).convert('RGBA'); alpha=check.getchannel('A'); alpha_bbox=alpha.point(lambda q:255 if q>=16 else 0).getbbox(); assert check.size==CANVAS and alpha_bbox and alpha_bbox[0]>0 and alpha_bbox[1]>0 and alpha_bbox[2]<CANVAS[0] and alpha_bbox[3]<CANVAS[1],(gear_id,alpha_bbox)
 iconcopy=ROOT/'native/GeneratedArt/gear_attachment_candidates_r001'/f'{gear_id}_ICON_REFERENCE.png'; iconcopy.parent.mkdir(parents=True,exist_ok=True)
 # Copy unchanged icon bytes; no re-encoding.
 iconcopy.write_bytes(icon.read_bytes())
 assets.append({'gearID':gear_id,'name':name,'assetID':asset_id,'concept':concept,'status':'UNAPPROVED_TEST_OVERLAY_CANDIDATE','r4Scope':'ICON_AND_LATER_ATTACHMENT','sourceIcon':str(icon.relative_to(ROOT)),'sourceIconSHA256':sha(icon),'generatedSourcePath':str(raw),'generatedSourceSHA256':sha(raw),'sourceAlpha16BBoxPx':list(bbox),'sourceCropWithPaddingPx':list(cropbox),'packedPath':str(dest.relative_to(ROOT)),'packedSHA256':sha(dest),'packedCanvasPx':list(CANVAS),'packedAlpha16BBoxPx':list(alpha_bbox),'gripAnchor':list(GRIP),'resize':'nearest-neighbor, aspect-preserving fit in standardized transparent canvas','alphaPolicy':'Retained generator alpha; no Python background removal or alpha repaint. Dark/light contact required before acceptance.'})
 manifest={'schema':'witch_staff_gear_attachments_r001','status':'UNAPPROVED_TEST_OVERLAY_CANDIDATES','canvasPx':list(CANVAS),'gripAnchor':list(GRIP),'gearAssets':assets,'rejectedAttempts':[{'gearID':'EQ_W_G1','generatedSourcePath':'/Users/PUBLIC_USER/.codex/generated_images/01a12399-5c96-7aa2-805f-d7e75a6df478/exec-00a8b2d8-bb2b-4c36-8cc4-0554dc0d0cb2.png','reason':'dark/light contact review showed an excessively narrow staff silhouette relative to the base; replaced by wider revision','sha256':sha('/Users/PUBLIC_USER/.codex/generated_images/01a12399-5c96-7aa2-805f-d7e75a6df478/exec-00a8b2d8-bb2b-4c36-8cc4-0554dc0d0cb2.png')},{'gearID':'EQ_W_G2','generatedSourcePath':'/Users/PUBLIC_USER/.codex/generated_images/01a12399-5c96-7aa2-805f-d7e75a6df478/exec-4e285ed8-fcdc-4c54-94ec-c51949798563.png','reason':'dark/light contact review showed an excessively narrow staff silhouette relative to the base; replaced by wider revision','sha256':sha('/Users/PUBLIC_USER/.codex/generated_images/01a12399-5c96-7aa2-805f-d7e75a6df478/exec-4e285ed8-fcdc-4c54-94ec-c51949798563.png')},{'gearID':'EQ_W_G2','generatedSourcePath':'/Users/PUBLIC_USER/.codex/generated_images/01a12399-5c96-7aa2-805f-d7e75a6df478/exec-9ebfa66a-d674-48ce-a58a-f51ba58619a4.png','reason':'second contact review still found the staff silhouette too narrow; replaced with a thicker-shaft edit','sha256':sha('/Users/PUBLIC_USER/.codex/generated_images/01a12399-5c96-7aa2-805f-d7e75a6df478/exec-9ebfa66a-d674-48ce-a58a-f51ba58619a4.png')}],'notIncluded':['No additional product SKUs or gear IDs','No change to combat stats/effects/recipes','No asset for EQ_S_01 hammer, whose attachment remains source-blocked']}
out=ROOT/'native/GeneratedArt/gear_attachment_candidates_r001/WITCH_STAFFS_R001_MANIFEST.json';out.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'assets':assets,'manifest':str(out.relative_to(ROOT))},ensure_ascii=False,indent=2))

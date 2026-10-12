#!/usr/bin/env python3
"""Pack individually generated transparent attack poses as additive animation candidates.
Pixels are only cropped to measured alpha bounds, nearest-resized and placed on an RGBA canvas.
Source stables and generator outputs are preserved byte-for-byte.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib, json, shutil, os
ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'native/Art'
GENS=[Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-5c96-7aa2-805f-d7e75a6df478'),Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65'),Path('/Users/PUBLIC_USER/.codex/generated_images/01a12398-0ccb-7d03-aeac-75db9b0de178')]
ACTORS={
 'ACT_E_R03_01':('銅殻やどかり','standard',[
  'exec-fd401874-5742-4792-b95a-d95ca3268a1d.png','exec-1a9d27c3-9d21-4ebb-b547-126f98eff802.png','exec-3bdfe713-546b-4a2e-a986-3c2a4586f133.png',
  'exec-3094eed8-5a3c-4c00-a471-02bafc567959.png','exec-89cd00e8-0f92-436c-bb66-a8b2fd842e38.png','exec-371c52d4-9bf0-4b2f-a26b-9f580ad2dd12.png',
  'exec-9ebafa6a-a716-412a-8691-d202411bf268.png','exec-e1d9c3a4-c32e-492e-a105-7847fbee5e8c.png','exec-99d5a953-0a02-475d-9514-c24c1741c4c9.png']),
 'ACT_E_R03_02':('晶鳴こうもり','dot',[
  'exec-0d17da95-904e-4ee3-9aeb-3a5b173f615c.png','exec-f960765a-152c-4bcc-b67d-e0da59e421f0.png','exec-cbf741c8-0e84-42b5-9de9-c660c4cdae84.png',
  'exec-585f7172-72cf-4a24-b222-7a88a2eddd51.png','exec-bbba9ddc-37fb-4498-9b58-7096ef1eb2d8.png','exec-9c3abba5-0f4d-4f78-ba31-040c384112c3.png',
  'exec-16d76c21-0174-48cd-91ab-8b236358a1cc.png','exec-cb685032-7faa-46a4-a551-f46d55f25b7c.png','exec-b7932e41-5566-499b-a10c-2fe78b941799.png']),
 'ACT_E_R03_03':('坑道の削り偶','multiHit',[
  'exec-476ec4dc-1f6c-41a1-8cb4-4ad9b93b216c.png','exec-8485f32f-20f3-44ff-965a-d133610af387.png','exec-5a7f3d45-afd0-4feb-b137-b5e3860634cd.png',
  'exec-aa875269-7afd-426d-9f33-38161712c0c3.png','exec-c53f71f5-1961-4052-a095-986ad1bfb2ca.png','exec-dcefcea2-836d-4503-8e9f-744fd6ee2e2b.png',
  'exec-9df9f03a-dd42-4f1f-b974-a67029e0d306.png','exec-cebedc79-40e1-4289-a46e-9e45178510ec.png','exec-707c81df-05ed-423f-bdd3-45625413ec1d.png']),
 'ACT_E_R03_04':('磁紋とかげ','support',[
  'exec-6bbc974e-468b-42e6-a306-22f7c8401610.png','exec-fd9f173c-9e0f-4020-90c1-bc37ca443429.png','exec-22be099f-0fff-449d-a765-58cf97b8f929.png',
  'exec-ee908dee-6c1e-48db-9553-b2dc565c8dce.png','exec-28fed1d9-7426-4fac-b2d4-98a5be50eb96.png','exec-8dcae3b0-106b-4ea7-a9f0-e1fe6e395231.png',
  'exec-d09d652b-a82a-41b9-bc11-412f5ddfeb80.png','exec-4e13ffe5-4826-4cb8-b489-b7cdabf72bda.png','exec-72cee5f1-7656-42e9-931f-930660d7dc51.png']),
 'ACT_B_R03_B':('炉守りの鉱巨人','combined',[
  'exec-a9b86dc4-1dd6-4d52-8f3e-b3892fd03355.png','exec-a2f35ea2-9f7c-4565-bd38-f797df6ce722.png','exec-b4e74b11-bf67-437f-8cff-319b4274f6bc.png',
  'exec-5b05408b-5e45-45a2-a8b2-c806e927d4cf.png','exec-88090daf-46c1-4b8a-8bca-ec5ee95a23cb.png','exec-61ab7b4e-d4d3-422b-a8a0-c1b139f015a0.png',
  'exec-95efc27d-b7b9-44fb-ab36-42cddd72b028.png','exec-1023e858-7ffb-484c-a63f-1181b651f125.png','exec-47ef5a30-0fd4-4d43-883f-e79004d2fc8a.png']),
 'ACT_E_R04_01':('霜毛おおかみ','standard',[
  'exec-60076dbe-a4e2-4216-96ff-ef5f02541bb0.png','exec-8946e74d-e408-4cda-9109-2ed5bf785b65.png','exec-e9fd8051-e35f-4008-a060-dcc240ccfbee.png',
  'exec-32856e5b-6ef0-4f0d-aeb2-48243bbc5b90.png','exec-1240998c-4406-4453-bd84-5c8472262ba9.png','exec-5d317a05-011c-4e8e-9c7a-6eae61e4e710.png',
  'exec-95aaea47-63c5-4cfe-8620-7be8415f4a16.png','exec-9eaed545-e34e-4e78-bf15-bc1949527132.png','exec-fefe83fc-9c5e-4c1d-9486-cbfb55d5dc27.png']),
 'ACT_E_R04_02':('氷羽ふくろう','support',[
  'exec-ae569018-4105-4464-ac0d-e92fc8d31c88.png','exec-a61cbee5-04bf-45a6-83da-a594adb06d25.png','exec-8a6ceaee-b739-4503-a933-ec5289a1a358.png',
  'exec-039fc148-eb6c-4a5b-8b2d-b484efb2cb6a.png','exec-6d168675-bc6e-4377-ae27-1b742f69574c.png','exec-515e550d-c4f9-49c8-9007-ef15a57e24ad.png',
  'exec-1f8931b3-063c-4b0c-b1ca-2c5ae41054d1.png','exec-59e70dec-0639-4908-9a27-5373f58b6ed7.png','exec-59d4a444-237c-4858-a20a-65a5e9e2ac57.png']),
 'ACT_E_R04_03':('雪甲ころがし','aoe',[
  'exec-4f87166f-dec5-4783-b695-69a37ad0c6cc.png','exec-b3584be0-7d7b-4e15-9a85-ce141836341f.png','exec-a23849c1-1952-4ba2-9584-ea545e2765dc.png',
  'exec-927b4465-44f7-454f-8965-5256348e3ba5.png','exec-8ea8053e-311e-42d9-8e36-ce53b6b2d775.png','exec-cfa37975-8342-4683-b592-bcf0a94dcdfb.png',
  'exec-4bc034fa-1738-46bc-8f2f-d564aaa7e40a.png','exec-17d0ddf9-94a8-4b87-92e8-30dfee786135.png','exec-f941f8c2-e32b-4d58-a4ce-4df2b59cc6b7.png']),
 'ACT_E_R04_04':('霜晶の削り偶','multiHit',[
  'exec-68196c8d-995f-46c0-9fae-bcc9e93b473c.png','exec-9a63d7e3-2026-4755-9f80-2f79ec49a56a.png','exec-701e296b-f944-40e1-830f-eaaf1048a5ef.png',
  'exec-66f44519-9a7b-4d12-b86f-090509e430c4.png','exec-3d825187-8d98-4bb3-8484-536e0da9535f.png','exec-70208c90-cb7d-42d0-8898-fe8a7257336d.png',
  'exec-6755b669-b152-479d-ac17-8e14f4163c14.png','exec-6dc99bd0-42cd-40fb-8e74-c297f77fae61.png','exec-e32e4cf5-7af1-4c9f-b54e-168e9f3a2db1.png']),
 'ACT_B_R04_A':('稜線の白角獣','heavy',[
  'exec-5f760b70-422d-4905-b2b2-2758d3ae5fde.png','exec-33e3fed3-b9a2-4b10-9c23-78112b75681c.png','exec-abe2e2fb-a87a-4083-a51c-94e7cc3300ee.png',
  'exec-a26ba2b7-ffd2-4c1b-a3c5-a88fbdf704be.png','exec-5791634f-03f2-4cde-b938-8fec2d1b06dd.png','exec-eeeb50ad-4040-46fb-9e86-3589e1137281.png',
  'exec-074e95e2-5806-46f1-9450-2b8d340e4792.png','exec-1fd66234-3160-4945-a0b3-a046e092fbe3.png','exec-4bc64c19-6fef-4ce6-adf9-9af1525ed1a5.png'])
}
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def atomic_bytes(path, data):
 tmp=path.with_name(path.name+'.tmp'); tmp.write_bytes(data); os.replace(tmp,path)
def atomic_image(image,path,**kwargs):
 tmp=path.with_name(path.stem+'.tmp'+path.suffix); image.save(tmp,**kwargs); os.replace(tmp,path)
def main():
 overlay={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'entries':{}}; summary=[]
 for ACTOR,(catalog_name,pattern,FILES) in ACTORS.items():
  srcs=sorted((ART/'ActorStills'/ACTOR).glob(f'{ACTOR}__still__r*.png'))
  if not srcs: raise FileNotFoundError(ACTOR+' source still')
  src=srcs[-1]
  dest=ART/'GeneratedCandidates'/ACTOR/'attack_cycle_r001'; framesdir=dest/'frames'; rawdir=dest/'source_frames'
  framesdir.mkdir(parents=True,exist_ok=True);rawdir.mkdir(parents=True,exist_ok=True)
  shutil.copy2(src,dest/'REFERENCE_STILL__preserved_copy.png')
  out=[]; contact=Image.new('RGBA',(768,768),(35,48,41,255)); metrics=[]
  for i,name in enumerate(FILES):
   gen=next((d/name for d in GENS if (d/name).exists()),None)
   if gen is None: raise FileNotFoundError(name)
   raw=rawdir/f'{i+1:02d}__{name}';shutil.copy2(gen,raw)
   im=Image.open(gen).convert('RGBA'); a=im.getchannel('A')
   bbox=a.point(lambda v:255 if v>=16 else 0).getbbox()
   if bbox is None: raise ValueError(f'empty alpha: {name}')
   crop=im.crop(bbox); scale=min(480/crop.width,390/crop.height)
   size=(max(1,round(crop.width*scale)),max(1,round(crop.height*scale)))
   crop=crop.resize(size,Image.Resampling.NEAREST)
   x=256-size[0]//2; y=455-size[1]
   frame=Image.new('RGBA',(512,512),(0,0,0,0)); frame.alpha_composite(crop,(x,y))
   fp=framesdir/f'attack_{i+1:03d}.png';atomic_image(frame,fp)
   contact.alpha_composite(frame.resize((256,256),Image.Resampling.NEAREST),((i%3)*256,(i//3)*256))
   alpha=frame.getchannel('A');edges={k:sum(1 for a0 in alpha.crop(box).getdata() if a0>0) for k,box in {'left':(0,0,4,512),'right':(508,0,512,512),'top':(0,0,512,4),'bottom':(0,508,512,512)}.items()}
   metrics.append({'frame':i+1,'generated_file':name,'generated_sha256':sha(gen),'alpha_bbox_threshold16':list(bbox),'resized_subject_size':list(size),'scale':scale,'placed_xy':[x,y],'canvas_bbox_threshold16':list(alpha.point(lambda v:255 if v>=16 else 0).getbbox()),'nonzero_alpha_edge_pixels_4px':edges,'output_sha256':sha(fp)})
   out.append(str(fp.relative_to(ART)))
  atomic_image(contact.convert('RGB'),dest/'CONTACT_DARK.jpg',quality=95)
  entry={'clips':{},'sequenceFrames':{}}
  for state,start in [('anticipate',0),('execute',3),('recover',6)]:
   ps=out[start:start+3];entry['sequenceFrames'][state]=ps
   entry['clips'][state]={'frames':ps,'fps':10,'duration_seconds':0.3,'frame_count':3,'loop':False,'canvas_px':[512,512],'anchor':[256,455],'display_scale':1.0,'status':'UNAPPROVED_AUTHORED_ATTACK_INBETWEEN_CANDIDATE','complete_animation':False}
  overlay['entries'][ACTOR]=entry
  manifest={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE','actorID':ACTOR,'catalogEnemyName':catalog_name,'actionPattern':pattern,'sourceStill':str(src.relative_to(ART)),'sourceStillSHA256':sha(src),'canvas_px':[512,512],'anchor':[256,455],'frameRate':10,'states':['anticipate','execute','recover'],'frames':metrics,'darkContactSheet':str((dest/'CONTACT_DARK.jpg').relative_to(ROOT)),'limitations':['Generated pose detail can vary.','Natural motion is not art-approved.','Runtime merge/build and simulator combat playback are pending.','Existing idle/walk/hit/resolve states are preserved.','No formal art acceptance or product approval.']}
  atomic_bytes(dest/'manifest.json',json.dumps(manifest,ensure_ascii=False,indent=2).encode()+b'\n')
  summary.append({'actor':ACTOR,'name':catalog_name,'pattern':pattern,'frames':9,'darkContactSheet':str((dest/'CONTACT_DARK.jpg').relative_to(ROOT)),'maxNonzeroAlphaEdgePixels':max(max(m['nonzero_alpha_edge_pixels_4px'].values()) for m in metrics),'runtimeVerified':False})
 atomic_bytes(ART/'runtime_overlay_zz_r03r04_attack_cycles_r001.json',json.dumps(overlay,ensure_ascii=False,indent=2).encode()+b'\n')
 print(json.dumps(summary,ensure_ascii=False))
if __name__=='__main__':main()

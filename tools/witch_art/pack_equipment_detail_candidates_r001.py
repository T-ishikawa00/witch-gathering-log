#!/usr/bin/env python3
"""Uniformly pack isolated equipment small-detail candidates; source RGBA remains intact."""
from __future__ import annotations
import hashlib, io, json, os
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'native/Art'
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images')
CANVAS=(256,256)
MAX_BBOX=(176,176)
STYLE='Characters/AIRA/AIRA__idle__256__r001.png'
SPECS={
 'EQ_BODY_01':('exec-acb3e9ac-8f93-40fe-aae9-20200d8db823.png','GearIcons/ICO_EQ_BODY_01/ICO_EQ_BODY_01__256__r001.png','folded inner-lining hem tab with leaf-fiber seam and resin tacks','BODY_HEM_INSERT','BODY_HEM_INSERT', [128,140]),
 'EQ_HAND_01':('exec-d8593327-1e87-4e13-b98c-b418548f0899.png','GearIcons/ICO_EQ_HAND_01/ICO_EQ_HAND_01__256__r001.png','single leafblade-shell plate for glove back; no glove/hand','HAND_BACK_PLATE','HAND_BACK', [128,128]),
 'EQ_FEET_01':('exec-3c514d6a-a129-49cf-ad29-94f3c3557196.png','GearIcons/ICO_EQ_FEET_01/ICO_EQ_FEET_01__256__r001.png','partial root-fiber ankle/sole reinforcement strip with horn stabilizer','FEET_ANKLE_PATCH','FEET_ANKLE', [128,42]),
}
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''): h.update(b)
 return h.hexdigest()
def atomic(p,data):
 p.parent.mkdir(parents=True,exist_ok=True); t=p.with_name(p.name+'.tmp')
 with t.open('wb') as f: f.write(data); f.flush(); os.fsync(f.fileno())
 os.replace(t,p)
def main():
 outdir=ART/'GeneratedCandidates/EquipmentDetails/details_r001'
 qa=Image.new('RGB',(len(SPECS)*220,300),(32,35,40)); d=ImageDraw.Draw(qa); entries=[]
 for i,(asset,(genname,icon_rel,description,part_type,slot,anchor)) in enumerate(SPECS.items()):
  source=GEN/'01a12399-b8c7-76a0-adb6-39606fe83b65'/genname
  icon=ART/icon_rel; style=ART/STYLE
  if not source.is_file() or not icon.is_file() or not style.is_file(): raise FileNotFoundError(source)
  with Image.open(source) as im:
   im.load()
   if im.mode!='RGBA': raise ValueError(f'{asset} source is not RGBA')
   src_size=list(im.size); bbox=im.getchannel('A').point(lambda x:255 if x>16 else 0).getbbox()
   if not bbox: raise ValueError(f'{asset} has empty alpha')
   crop=im.crop(bbox); scale=min(MAX_BBOX[0]/crop.width,MAX_BBOX[1]/crop.height)
   resized=crop.resize((round(crop.width*scale),round(crop.height*scale)),Image.Resampling.LANCZOS)
  x=(CANVAS[0]-resized.width)//2; y=(CANVAS[1]-resized.height)//2
  frame=Image.new('RGBA',CANVAS,(0,0,0,0)); frame.alpha_composite(resized,(x,y))
  path=outdir/f'{asset}__detail_candidate_r001.png'; bio=io.BytesIO(); frame.save(bio,'PNG',optimize=True); atomic(path,bio.getvalue())
  comp=Image.new('RGBA',CANVAS,(24,27,31,255)); comp.alpha_composite(frame); comp.thumbnail((200,200)); qa.paste(comp.convert('RGB'),(i*220+10,38)); d.text((i*220+8,12),asset,fill='white')
  entries.append({'assetId':asset,'revision':'r001','status':'UNAPPROVED_SMALL_DETAIL_CANDIDATE','scope':'ICON_AND_SMALL_DETAIL_ONLY','part_type':part_type,'attachment_slot_candidate':slot,'part_anchor_px_candidate':anchor,'canvas_px':list(CANVAS),'source_art_path':str(source),'source_sha256':sha(source),'source_canvas_px':src_size,'source_alpha16_bbox_px':list(bbox),'source_alpha_preserved':'RGBA alpha unchanged other than Lanczos resize','uniform_scale_to_176px_max':round(scale,6),'packed_path':path.relative_to(ART).as_posix(),'packed_sha256':sha(path),'packed_alpha16_bbox_px':list(frame.getchannel('A').point(lambda x:255 if x>16 else 0).getbbox()),'reference_icon_path':icon_rel,'reference_icon_sha256':sha(icon),'style_reference_path':STYLE,'style_reference_sha256':sha(style),'design_description':description,'actor_attachment_coordinates':'UNKNOWN; owner to map slot in native integration','new_product_count':0,'human_approval':False})
 contact=ART/'GeneratedCandidates/EquipmentDetails/details_r001_contact_dark.jpg'; b=io.BytesIO(); qa.save(b,'JPEG',quality=94); atomic(contact,b.getvalue())
 manifest={'schema':'witch.equipment_small_detail_candidates.v1','revision':'r001','status':'UNAPPROVED_PROCESS_PILOT','items':entries,'scope_note':'Three representative slot parts only; pilot checks independent detail authoring/packing before the remaining twelve R4 IDs. Existing 29 equipment IDs and icons are unchanged.','source_art_untouched':True,'human_adoption':False,'runtime_integration':False,'qa_contact_dark':contact.relative_to(ART).as_posix()}
 mp=ART/'GeneratedCandidates/EquipmentDetails/details_manifest_r001.json'; atomic(mp,(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode())
 print(json.dumps({'manifest':str(mp),'contact':str(contact),'count':len(entries)},ensure_ascii=False))
if __name__=='__main__': main()

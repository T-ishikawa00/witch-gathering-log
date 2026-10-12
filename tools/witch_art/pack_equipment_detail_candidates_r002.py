#!/usr/bin/env python3
"""Pack all 15 R4 small-detail candidates and emit a partial runtime overlay."""
from __future__ import annotations
import hashlib, io, json, os
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[2]; ART=ROOT/'native/Art'; GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65')
CANVAS=(256,256); MAX_BBOX=(176,176); STYLE='Characters/AIRA/AIRA__idle__256__r001.png'
# asset => source PNG, gear icon ref, visible part and native slot candidate
ROWS={
 'EQ_BODY_01':('exec-acb3e9ac-8f93-40fe-aae9-20200d8db823.png','BODY_01','folded plant-fiber lining tab with resin seam tacks','BODY_HEM_INSERT',[128,140]),
 'EQ_BODY_02':('exec-bc3a854c-084b-41f2-b92a-26313ab20229.png','BODY_02','partial damp-mist lining insert with marsh-scale flecks','BODY_CLOAK_LINING',[128,128]),
 'EQ_BODY_03':('exec-eb1229a8-c737-4bbd-a9e5-c098e253cf0e.png','BODY_03','small frost-fur and wind-woven linen collar insert','BODY_COLLAR_INSERT',[128,128]),
 'EQ_HAND_01':('exec-d8593327-1e87-4e13-b98c-b418548f0899.png','HAND_01','single layered leafblade-shell glove-back plate','HAND_BACK_PLATE',[128,128]),
 'EQ_HAND_02':('exec-7c011481-8817-4c9a-bf20-2177dc5a35e0.png','HAND_02','mica laminate plate with two copper fasteners','HAND_BACK_PLATE',[128,128]),
 'EQ_HAND_03':('exec-154e2706-e215-4a7f-9a70-dc01aba1b460.png','HAND_03','compact moon-silver ring and frost-crystal hand-cover detail','HAND_COVER_PLATE',[128,128]),
 'EQ_FEET_01':('exec-3c514d6a-a129-49cf-ad29-94f3c3557196.png','FEET_01','curved root-fiber ankle/sole reinforcement with horn tip','FEET_ANKLE_PATCH',[128,42]),
 'EQ_FEET_02':('exec-8f38fdd2-e7c0-492f-a829-94a3c01b932a.png','FEET_02','magnetic scale plate and ash-silver heel edge','FEET_ANKLE_PATCH',[128,42]),
 'EQ_FEET_03':('exec-74f1490a-65c2-4aef-8dc7-36452948b4b9.png','FEET_03','curved white-horn ankle stabilizer with binding','FEET_ANKLE_SUPPORT',[128,42]),
 'EQ_AMU_01':('exec-f4e1a1c0-7057-409d-9b9a-617c9db79e0e.png','AMU_01','small leaf sachet with thread knot and hanging loop','AMULET_ATTACHMENT',[128,228]),
 'EQ_AMU_02':('exec-79b9088a-d091-480a-bfcc-9a5e200bafc1.png','AMU_02','polished mist-crystal talisman with thin natural setting','AMULET_ATTACHMENT',[128,228]),
 'EQ_AMU_03':('exec-8e1f7f5d-2f29-47bc-ad8b-c42f0736d1c0.png','AMU_03','open woven seed-core basket charm with tiny sprout','AMULET_ATTACHMENT',[128,228]),
 'EQ_RING_01':('exec-558bc6b2-c000-4d35-bf91-9dafa4fa8fae.png','RING_01','slim twig-and-resin organic ring','RING_ATTACHMENT',[128,128]),
 'EQ_RING_02':('exec-5849cb0a-24d9-4974-a5e2-7d66945e05e2.png','RING_02','fine ash-silver ring with small tuning-fork crystal','RING_ATTACHMENT',[128,128]),
 'EQ_RING_03':('exec-6ce74c2e-cef0-411a-925b-eef40531f069.png','RING_03','delicate winter ring with red flower core and frost rim','RING_ATTACHMENT',[128,128]),
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
 outdir=ART/'GeneratedCandidates/EquipmentDetails/details_r002'; overlay_entries={}; records=[]
 qa=Image.new('RGB',(4*240,4*260),(32,35,40)); draw=ImageDraw.Draw(qa)
 for i,(eq,(filename,short,desc,slot,anchor)) in enumerate(ROWS.items()):
  source=GEN/filename; icon_rel=f'GearIcons/ICO_EQ_{short}/ICO_EQ_{short}__256__r001.png'; icon=ART/icon_rel; style=ART/STYLE
  if not all(p.is_file() for p in (source,icon,style)): raise FileNotFoundError((source,icon,style))
  with Image.open(source) as im:
   im.load()
   if im.mode!='RGBA': raise ValueError(f'{eq} requires RGBA input, found {im.mode}')
   size=list(im.size); box=im.getchannel('A').point(lambda a:255 if a>16 else 0).getbbox()
   if not box: raise ValueError(f'{eq} source alpha empty')
   crop=im.crop(box); scale=min(MAX_BBOX[0]/crop.width,MAX_BBOX[1]/crop.height); scaled=crop.resize((round(crop.width*scale),round(crop.height*scale)),Image.Resampling.LANCZOS)
  x=(CANVAS[0]-scaled.width)//2; y=(CANVAS[1]-scaled.height)//2; out=Image.new('RGBA',CANVAS,(0,0,0,0)); out.alpha_composite(scaled,(x,y))
  rel=f'GeneratedCandidates/EquipmentDetails/details_r002/DETAIL_EQ_{eq}__candidate_r002.png'; path=ART/rel; buf=io.BytesIO(); out.save(buf,'PNG',optimize=True); atomic(path,buf.getvalue())
  detail_id=f'DETAIL_{eq}'; overlay_entries[detail_id]={'kind':'equipment_small_detail','assetID':detail_id,'equipmentID':eq,'selectedPNG':rel,'pixelSize':list(CANVAS),'canvas_px':list(CANVAS),'part_anchor_px':anchor,'attachmentSlotCandidate':slot,'status':'UNAPPROVED_SMALL_DETAIL_CANDIDATE','scope':'ICON_AND_SMALL_DETAIL_ONLY','humanAdoption':'PENDING_INDIVIDUAL','runtimeIntegrationStatus':'CANDIDATE_PREVIEW_ONLY_NOT_RELEASED','visualFitStatus':'PARTIAL_PENDING_SLOT_BY_SLOT_REVIEW','sourceIcon':icon_rel.replace('__256__','__128__'),'source_path':'native/Art/'+icon_rel,'description':desc}
  comp=Image.new('RGBA',CANVAS,(24,27,31,255));comp.alpha_composite(out);comp.thumbnail((220,220));col=i%4;row=i//4;qa.paste(comp.convert('RGB'),(col*240+10,row*260+32));draw.text((col*240+8,row*260+8),eq,fill='white')
  records.append({'assetId':detail_id,'equipmentId':eq,'revision':'r002','status':'UNAPPROVED_SMALL_DETAIL_CANDIDATE','scope':'ICON_AND_SMALL_DETAIL_ONLY','part_type':slot,'attachment_slot_candidate':slot,'part_anchor_px_candidate':anchor,'canvas_px':list(CANVAS),'source_art_path':str(source),'source_sha256':sha(source),'source_canvas_px':size,'source_alpha16_bbox_px':list(box),'source_alpha_preserved':'RGBA source unchanged except uniform resize/packing','uniform_scale_to_bbox176':round(scale,6),'packed_path':rel,'packed_sha256':sha(path),'packed_alpha16_bbox_px':list(out.getchannel('A').point(lambda a:255 if a>16 else 0).getbbox()),'reference_icon_path':icon_rel,'reference_icon_sha256':sha(icon),'style_reference_path':STYLE,'style_reference_sha256':sha(style),'design_description':desc,'actor_attachment_coordinates':'UNKNOWN; root native renderer owns slot-to-actor transform','new_product_count':0,'human_approval':False})
 overlay={'status':'UNAPPROVED_EQUIPMENT_DETAILS_CANDIDATE_OVERLAY','scope':'R4 existing 15 equipment IDs; small detail components only','new_product_count':0,'humanApproval':False,'entries':overlay_entries}
 op=ART/'runtime_overlay_equipment_details_candidate_r001.json'; atomic(op,(json.dumps(overlay,ensure_ascii=False,indent=2)+'\n').encode())
 cp=ART/'GeneratedCandidates/EquipmentDetails/details_r002_contact_dark.jpg'; buf=io.BytesIO();qa.save(buf,'JPEG',quality=94);atomic(cp,buf.getvalue())
 manifest={'schema':'witch.equipment_small_detail_candidates.v1','revision':'r002','status':'UNAPPROVED_CANDIDATES_ONLY','overlay':op.relative_to(ART).as_posix(),'qa_contact_dark':cp.relative_to(ART).as_posix(),'items':records,'source_art_untouched':True,'human_adoption':False,'runtime_integration':False,'new_equipment_types':0,'limitations':['Parts are newly authored accessory candidates; exact attachment coordinates and scale need root renderer placement QA.','R4 specifications define existing gear IDs and material cues; no new products or recipes were created.']}
 mp=ART/'GeneratedCandidates/EquipmentDetails/details_manifest_r002.json';atomic(mp,(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode())
 print(json.dumps({'overlay':str(op),'manifest':str(mp),'contact':str(cp),'count':len(records)},ensure_ascii=False))
if __name__=='__main__':main()

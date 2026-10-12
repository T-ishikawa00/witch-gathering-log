#!/usr/bin/env python3
"""Pack cat-catalyst and smith-hammer detail candidates into 256px RGBA parts."""
from __future__ import annotations
import hashlib, io, json, os
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[2]; ART=ROOT/'native/Art'; GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65')
CANVAS=(256,256); MAX_BBOX=(176,176)
ROWS={
 'EQ_F_01':('exec-3d25b2bb-b661-475d-9928-bf2315c6da55.png','F_01','small floating leaf catalyst in front of cat forepaw','CAT_FOREPAW_FLOATING_CATALYST','Characters/LUNA/LUNA__idle__256__r001.png',[128,128]),
 'EQ_F_02':('exec-ed6e4e81-c7eb-4146-ae14-3d8926b98da8.png','F_02','thin temporary magical ring effect below cat feet','CAT_GROUND_TEMPORARY_RING','Characters/LUNA/LUNA__idle__256__r001.png',[128,128]),
 'EQ_F_03':('exec-3e3c88c1-0ef4-4e2f-9e21-fa0f4869c811.png','F_03','small sealed-lamp crystal shard with crescent ice-feather shadow claw','CAT_TEMPORARY_SHADOW_CLAW','Characters/LUNA/LUNA__idle__256__r001.png',[110,145]),
 'EQ_S_02':('exec-ed44303a-2564-499e-bb5f-182b4edaeb5c.png','S_02','flush ash-silver square bezel with small warm furnace-core crystal inset','HAMMER_HEAD_FACE_CORE_INSET','Characters/AIRA/AIRA__idle__256__r001.png',[128,128]),
 'EQ_S_03':('exec-0e9c7346-5044-40ef-8237-2db454a98517.png','S_03','narrow moon-silver square-head face reinforcement with porcelain buffer and shallow ring engraving','HAMMER_HEAD_NARROW_REINFORCEMENT','Characters/AIRA/AIRA__idle__256__r001.png',[128,128]),
}
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''):h.update(b)
 return h.hexdigest()
def atomic(p,data):
 p.parent.mkdir(parents=True,exist_ok=True); t=p.with_name(p.name+'.tmp')
 with t.open('wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
 os.replace(t,p)
def main():
 outdir=ART/'GeneratedCandidates/EquipmentDetails/details_r003'; extra={}; records=[]
 qa=Image.new('RGB',(len(ROWS)*230,300),(32,35,40)); draw=ImageDraw.Draw(qa)
 for i,(eq,(genname,short,desc,slot,style_rel,anchor)) in enumerate(ROWS.items()):
  source=GEN/genname; icon_rel=f'GearIcons/ICO_EQ_{short}/ICO_EQ_{short}__256__r001.png'; icon=ART/icon_rel; style=ART/style_rel
  if not all(p.is_file() for p in (source,icon,style)): raise FileNotFoundError((source,icon,style))
  with Image.open(source) as im:
   im.load()
   if im.mode!='RGBA':raise ValueError(f'{eq} source is not RGBA')
   source_size=list(im.size); box=im.getchannel('A').point(lambda a:255 if a>16 else 0).getbbox()
   if not box:raise ValueError(f'{eq} empty source')
   crop=im.crop(box); scale=min(MAX_BBOX[0]/crop.width,MAX_BBOX[1]/crop.height); fitted=crop.resize((round(crop.width*scale),round(crop.height*scale)),Image.Resampling.LANCZOS)
  x=(256-fitted.width)//2;y=(256-fitted.height)//2;out=Image.new('RGBA',CANVAS,(0,0,0,0));out.alpha_composite(fitted,(x,y))
  detail_id=f'DETAIL_{eq}'; rel=f'GeneratedCandidates/EquipmentDetails/details_r003/{detail_id}__candidate_r001.png'; path=ART/rel; buf=io.BytesIO();out.save(buf,'PNG',optimize=True);atomic(path,buf.getvalue())
  status='UNAPPROVED_CAT_EFFECT_DETAIL_CANDIDATE' if eq.startswith('EQ_F_') else 'UNAPPROVED_HAMMER_DETAIL_CANDIDATE'
  extra[detail_id]={'kind':'equipment_small_detail','assetID':detail_id,'equipmentID':eq,'selectedPNG':rel,'pixelSize':list(CANVAS),'canvas_px':list(CANVAS),'part_anchor_px':anchor,'attachmentSlotCandidate':slot,'status':status,'scope':'EXISTING_EQUIPMENT_ATTACHMENT_DETAIL','humanAdoption':'PENDING_INDIVIDUAL','runtimeIntegrationStatus':'CANDIDATE_PREVIEW_ONLY_NOT_RELEASED','visualFitStatus':'PARTIAL_PENDING_SLOT_BY_SLOT_REVIEW','sourceIcon':icon_rel.replace('__256__','__128__'),'source_path':'native/Art/'+icon_rel,'description':desc,'preserveActorOrWeaponBase':True}
  comp=Image.new('RGBA',CANVAS,(24,27,31,255));comp.alpha_composite(out);comp.thumbnail((200,240));qa.paste(comp.convert('RGB'),(i*230+15,45));draw.text((i*230+8,12),eq,fill='white')
  records.append({'assetId':detail_id,'equipmentId':eq,'revision':'special_detail_r001','status':status,'canvas_px':list(CANVAS),'part_anchor_px_candidate':anchor,'attachment_slot_candidate':slot,'source_path':str(source),'source_sha256':sha(source),'source_canvas_px':source_size,'source_alpha16_bbox_px':list(box),'source_alpha_preserved':'RGBA source unchanged other than uniform resize/packing','uniform_scale_to_bbox176':round(scale,6),'packed_path':rel,'packed_sha256':sha(path),'packed_alpha16_bbox_px':list(out.getchannel('A').point(lambda a:255 if a>16 else 0).getbbox()),'reference_icon_path':icon_rel,'reference_icon_sha256':sha(icon),'style_reference_path':style_rel,'style_reference_sha256':sha(style),'description':desc,'actor_slot_coordinates':'UNKNOWN; pending root native screen placement','new_product_count':0,'human_approval':False})
 # Preserve the existing 15 entries and add five unique keys; never mutate existing values.
 op=ART/'runtime_overlay_equipment_details_candidate_r001.json'; overlay=json.loads(op.read_text())
 if set(extra)&set(overlay.get('entries',{})):raise ValueError('candidate keys already exist; use a new overlay revision')
 overlay['entries'].update(extra); overlay['status']='UNAPPROVED_EQUIPMENT_DETAILS_CANDIDATE_OVERLAY'; overlay['new_product_count']=0; overlay['humanApproval']=False
 atomic(op,(json.dumps(overlay,ensure_ascii=False,indent=2)+'\n').encode())
 cp=ART/'GeneratedCandidates/EquipmentDetails/details_r003_special_contact_dark.jpg';buf=io.BytesIO();qa.save(buf,'JPEG',quality=94);atomic(cp,buf.getvalue())
 base=json.loads((ART/'GeneratedCandidates/EquipmentDetails/details_manifest_r002.json').read_text())
 base['revision']='r003-special-addendum';base['overlay']=op.relative_to(ART).as_posix();base['special_detail_qa_contact']=cp.relative_to(ART).as_posix();base['items'].extend(records);base['special_details_scope']='EQ_F_01..03 and EQ_S_02..03 only; EQ_S_01 remains Human-blocked.'
 mp=ART/'GeneratedCandidates/EquipmentDetails/details_manifest_r003.json';atomic(mp,(json.dumps(base,ensure_ascii=False,indent=2)+'\n').encode())
 print(json.dumps({'overlay':str(op),'manifest':str(mp),'qa':str(cp),'added':list(extra),'total_entries':len(overlay['entries'])},ensure_ascii=False))
if __name__=='__main__':main()

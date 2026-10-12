#!/usr/bin/env python3
"""Pack four R05 enemy locomotion/hover sheets as additive unapproved candidates."""
from pathlib import Path
import hashlib, json, shutil
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "native/Art"
GEN = Path("/Users/PUBLIC_USER/.codex/generated_images/01a12399-b8c7-76a0-adb6-39606fe83b65")
ITEMS = [
    {"id":"ACT_E_R05_01","atlas":GEN/"exec-a72a52a5-6e5c-45e4-bd41-612b68410017.png","source":"ActorStills/ACT_E_R05_01/ACT_E_R05_01__still__r001.png","base":"runtime_overlay_act_e_r05_01_pose_candidate_r002.json","rev":"living_book_hover_pages_cycle_r002","overlay":"runtime_overlay_act_e_r05_01_pose_candidate_r004_hover_cycle.json","anchor":[256,300],"align":"center","fps":8,"semantic":"hover_float_with_cover_page_and_vine_tendril_followthrough","limit":"Movement is deliberately subtle; page/tendril variation and in-place hover are visible, but independent flutter cadence and natural loop remain pending native review."},
    {"id":"ACT_E_R05_02","atlas":GEN/"exec-4c888967-3e63-4b2e-bfa9-070c66f2d118.png","source":"ActorStills/ACT_E_R05_02/ACT_E_R05_02__still__r002.png","base":"runtime_overlay_act_e_r05_02_pose_candidate_r001.json","rev":"moon_sentinel_planted_walk_cycle_r002","overlay":"runtime_overlay_act_e_r05_02_pose_candidate_r003_walk_cycle.json","anchor":[256,490],"align":"floor","fps":8,"semantic":"ivory_guardian_grounded_alternating_step_and_counterbalance","limit":"Full-body gait candidate with alternating knees/feet; exact contact timing and native screen scale remain pending."},
    {"id":"ACT_E_R05_03","atlas":GEN/"exec-e838423d-30d2-4089-9609-86041c2e3c93.png","source":"ActorStills/ACT_E_R05_03/ACT_E_R05_03__still__r001.png","base":"runtime_overlay_act_e_r05_03_pose_candidate_r001.json","rev":"lantern_familiar_hover_tendril_cycle_r002","overlay":"runtime_overlay_act_e_r05_03_pose_candidate_r003_hover_cycle.json","anchor":[256,300],"align":"center","fps":8,"semantic":"hover_bob_tilt_and_tendril_followthrough_no_foot_walk","limit":"Body/tendril hover cycle; internal flame dynamics are subtle and require native screen review."},
    {"id":"ACT_E_R05_04","atlas":GEN/"exec-66c34f1f-35a5-414c-8ee9-e6148a018990.png","source":"ActorStills/ACT_E_R05_04/ACT_E_R05_04__still__r001.png","base":"runtime_overlay_act_e_r05_04_pose_candidate_r002.json","rev":"moon_bloom_beast_quadruped_walk_cycle_r002","overlay":"runtime_overlay_act_e_r05_04_pose_candidate_r004_walk_cycle.json","anchor":[256,490],"align":"floor","fps":8,"semantic":"flower_beast_quadruped_alternating_footfalls_with_blossom_tail_followthrough","limit":"Readable quadruped step changes; leg contacts, persistent identity, and subtle petal motion need native screen review."},
]

def sha(path):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda:f.read(1<<20),b""): h.update(chunk)
    return h.hexdigest()

def splits(n): return [round(i*n/3) for i in range(4)]
def alpha_bounds(image):
    a=np.asarray(image.getchannel("A")); y,x=np.where(a>16)
    return None if not len(x) else [int(x.min()),int(y.min()),int(x.max()),int(y.max())]
def wh(b): return [b[2]-b[0]+1,b[3]-b[1]+1]

report={"schema":"r05_enemy_motion_candidates_r001","approval":"UNAPPROVED_CANDIDATES","natural_motion_complete":False,"items":[]}
for it in ITEMS:
    aid=it["id"]; atlas=Image.open(it["atlas"]).convert("RGBA"); src=ART/it["source"]
    if not atlas.width>=3 or not atlas.height>=3: raise ValueError((aid,atlas.size))
    revdir=ART/"GeneratedCandidates"/aid/it["rev"]; framesdir=revdir/"frames"; framesdir.mkdir(parents=True,exist_ok=True)
    shutil.copy2(it["atlas"],revdir/"imagegen_atlas_source.png"); shutil.copy2(src,revdir/"identity_reference_still.png")
    base=json.loads((ART/it["base"]).read_text())["entries"][aid]
    base_sha=sha(src); xs=splits(atlas.width); ys=splits(atlas.height); frames=[]; recs=[]; rels=[]
    for n in range(9):
        row,col=divmod(n,3); box=(xs[col],ys[row],xs[col+1],ys[row+1]); cell=atlas.crop(box)
        a=np.asarray(cell.getchannel("A")); labels,num=ndimage.label(a>16,structure=np.ones((3,3),dtype=np.uint8)); counts=np.bincount(labels.ravel()); counts[0]=0; sizes=sorted((int(c) for c in counts[1:]),reverse=True)
        yy,xx=np.where(a>16)
        if not len(xx): raise ValueError(f"empty alpha frame {aid}:{n}")
        w,h=base.get("canvas_px",[512,512]); anchor=it["anchor"]
        dx=round(w/2-(xx.min()+xx.max())/2)
        dy=round(h/2-(yy.min()+yy.max())/2) if it["align"]=="center" else int(anchor[1])-int(yy.max())
        packed=Image.new("RGBA",(w,h),(0,0,0,0));packed.alpha_composite(cell,(dx,dy))
        bb=alpha_bounds(packed)
        if bb is None or min(bb)<0 or bb[2]>=w or bb[3]>=h: raise ValueError(f"frame overflow {aid}/{n} {bb}")
        name=f"walk_{n:03}.png"; dest=framesdir/name; packed.save(dest); frames.append(packed)
        rel=f"GeneratedCandidates/{aid}/{it['rev']}/frames/{name}"; rels.append(rel)
        recs.append({"frame":name,"source_cell_px":[box[0],box[1],box[2]-box[0],box[3]-box[1]],"translation_px":[dx,dy],"alpha16_bounds_px":bb,"alpha16_size_px":wh(bb),"alpha16_pixels":int((np.asarray(packed.getchannel("A"))>16).sum()),"source_alpha16_component_count":int(num),"largest_alpha16_component_pixels":sizes[0] if sizes else 0,"other_alpha16_component_pixels":sizes[1:],"alpha_preserved_from_source_cell":True,"sha256":sha(dest)})
    contact=Image.new("RGB",(1536,1632),(27,34,43)); draw=ImageDraw.Draw(contact)
    for n,im in enumerate(frames):
        row,col=divmod(n,3); bg=Image.new("RGBA",im.size,(27,34,43,255));bg.alpha_composite(im);contact.paste(bg.convert("RGB"),(col*512,row*544+32));draw.text((col*512+8,row*544+8),f"{aid} / {n:03}",fill=(235,235,235))
    qa=revdir/"qa_contact_sheet.jpg";contact.save(qa,quality=94)
    entry=json.loads(json.dumps(base)); entry.setdefault("sequenceFrames",{})["walk"]=rels
    idle_paths=base.get("clips",{}).get("idle",{}).get("frames",[]); idle_bounds=[alpha_bounds(Image.open(ART/p).convert("RGBA")) for p in idle_paths if (ART/p).is_file()];idle_bounds=[b for b in idle_bounds if b]
    entry.setdefault("clips",{})["walk"]={"frames":rels,"frame_count":9,"fps":it["fps"],"duration_seconds":9/it["fps"],"loop":True,"complete_animation":False,"status":"UNAPPROVED_NINE_FRAME_MOTION_CANDIDATE_NOT_NATURAL_MOTION_COMPLETE","canvas_px":base.get("canvas_px",[512,512]),"anchor":it["anchor"],"anchor_status":"VISUAL_ESTIMATE_UNAPPROVED","movement_semantics":it["semantic"],"display_scale":1.0,"quality_limit":it["limit"]}
    entry["anchor"]=it["anchor"];entry["anchor_status"]="VISUAL_ESTIMATE_UNAPPROVED";entry["states_present"]=sorted(set(entry.get("states_present",[])+["walk"]));entry["status"]="UNAPPROVED_PARTIAL_MOTION_CANDIDATE";entry["complete_animation"]=False
    overlay={"status":"UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY","complete_animation":False,"candidate_manifest":f"GeneratedCandidates/{aid}/{it['rev']}/manifest.json","entries":{aid:entry}}
    (ART/it["overlay"]).write_text(json.dumps(overlay,ensure_ascii=False,indent=2)+"\n")
    m={"asset_id":aid,"revision":it["rev"],"movement_semantics":it["semantic"],"quality_limit":it["limit"],"source_still_path":it["source"],"source_still_sha256":base_sha,"atlas_path":f"GeneratedCandidates/{aid}/{it['rev']}/imagegen_atlas_source.png","atlas_sha256":sha(revdir/"imagegen_atlas_source.png"),"atlas_px":list(atlas.size),"grid_x":xs,"grid_y":ys,"frame_canvas_px":base.get("canvas_px",[512,512]),"anchor_candidate_px":it["anchor"],"registration":"Per-cell crop; translation only to center-hover or align grounded alpha16 feet to selected anchor. No resize, recolor, or alpha cleanup. Alpha16/component statistics are measurement only.","idle_alpha16_bounds_px":idle_bounds,"idle_alpha16_size_px":[wh(b) for b in idle_bounds],"candidate_walk_alpha16_bounds_px":[r["alpha16_bounds_px"] for r in recs],"candidate_walk_alpha16_size_px":[r["alpha16_size_px"] for r in recs],"clip_display_scale":1.0,"fps_candidate":it["fps"],"frames":recs,"qa_contact_sheet":f"GeneratedCandidates/{aid}/{it['rev']}/qa_contact_sheet.jpg","runtime_overlay":it["overlay"],"visual_status":"UNAPPROVED_CANDIDATE_PENDING_ROOT_NATIVE_SCREEN_REVIEW","approval_status":"HUMAN_ADOPTION_PENDING","natural_motion_complete":False}
    (revdir/"manifest.json").write_text(json.dumps(m,ensure_ascii=False,indent=2)+"\n");report["items"].append(m)
    if sha(src)!=base_sha: raise RuntimeError("identity source changed: "+aid)
report["status"]="UNAPPROVED_PARTIAL_MOTION_CANDIDATES_PENDING_NATIVE_SCREEN_REVIEW"
(ROOT/"docs/production/current/art/R05_enemy_motion_candidates_r002.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
print(json.dumps([{"id":m["asset_id"],"qa":m["qa_contact_sheet"],"overlay":m["runtime_overlay"],"idle_px":m["idle_alpha16_size_px"],"walk_px":m["candidate_walk_alpha16_size_px"]} for m in report["items"]],ensure_ascii=False,indent=2))

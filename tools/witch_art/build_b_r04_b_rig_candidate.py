#!/usr/bin/env python3
"""Build an unapproved, transform-only SpriteKit rig candidate for ACT_B_R04_B.

Four existing cutouts are downscaled, re-registered against static r004, then
animated by explicit 24 fps keyframes. Fused legs/tail are never called a walk.
"""
from __future__ import annotations
import hashlib, json, math, shutil
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ACTOR = "ACT_B_R04_B"
PARTS_SRC = ROOT / "native/Art/GeneratedCandidates/ACT_B_R04_B/parts"
OUT = ROOT / "native/Art/GeneratedCandidates/ACT_B_R04_B/rig_candidate_r001"
CANVAS = (512, 341)
FPS = 24
# Manually registered candidate placements in the 512x341 bundle canvas.
# Parts/pivots are inferred visually from r004; none are source-authored.
LAYERS = [
    {"id":"farwing", "file":"farwing_part_r001.png", "origin":[285,116], "pivot":[287,165], "z":1},
    {"id":"body4legs_tail", "file":"body4legs_tail_part_r001.png", "origin":[34,180], "pivot":[212,236], "z":2},
    {"id":"nearwing", "file":"nearwing_part_r001.png", "origin":[153,110], "pivot":[157,174], "z":3},
    {"id":"neck_head", "file":"neck_head_part_r001.png", "origin":[17,8], "pivot":[124,197], "z":4},
]
# State channels: body dx/dy, nearwing rotation, farwing rotation, neck rotation.
def values(state: str, i: int, n: int):
    t=i/max(n-1,1); phase=2*math.pi*i/max(n,1); s=math.sin(phase)
    if state == "idle": return (0, .8*s, 2.4*s, -2.7*s, 1.5*s)
    if state == "flight": return (0, -3+2*s, 12*s, -15*s, 1.8*s)
    if state == "anticipate":
        q=min(1,t*2); q=q*q*(3-2*q)
        return (-1*q, q, 7*q, -9*q, -3*q)
    if state == "execute":
        if t < .28:
            q=t/.28; e=q*q*(3-2*q)
            return (-2*e, -e, 6+7*e, -7-8*e, -2*e)
        if t < .68:
            q=(t-.28)/.40; e=q*q*(3-2*q)
            return (2*e, -3*e, 13-25*e, -15+28*e, 2+8*e)
        q=(t-.68)/.32; e=q*q*(3-2*q)
        return (2*(1-e), -3*(1-e), -12+12*e, 13-13*e, 10*(1-e))
    if state == "recover":
        q=t*t*(3-2*t); return (1*(1-q), -2*(1-q), -7*(1-q), 8*(1-q), 4*(1-q))
    if state == "hit":
        q=math.sin(math.pi*t); return (-3*q, -2*q, -10*q, 12*q, 8*q)
    if state == "resolve":
        q=t*t*(3-2*t); return (0, 4*q, -5*q, 6*q, -5*q)
    raise KeyError(state)

CLIPS={
 "idle":{"loop":True,"frames":24}, "flight":{"loop":True,"frames":24},
 "anticipate":{"loop":False,"frames":24}, "execute":{"loop":False,"frames":24},
 "recover":{"loop":False,"frames":24}, "hit":{"loop":False,"frames":24},
 "resolve":{"loop":False,"frames":24},
}
def sha(path:Path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for chunk in iter(lambda:f.read(1024*1024),b''): h.update(chunk)
 return h.hexdigest()
def out_part(meta): return OUT/"parts"/meta["file"]
def render_parts():
 (OUT/"parts").mkdir(parents=True,exist_ok=True)
 for p in LAYERS:
  src=Image.open(PARTS_SRC/p["file"]).convert('RGBA')
  dst=src.resize((round(src.width/3),round(src.height/3)),Image.Resampling.LANCZOS)
  dst.save(out_part(p),optimize=True)
def render_preview(state,i,n):
 dx,dy,nw,fw,neck=values(state,i,n)
 layer_images=[]
 for p in LAYERS:
  part=Image.open(out_part(p)).convert('RGBA')
  layer=Image.new('RGBA',CANVAS,(0,0,0,0)); layer.alpha_composite(part,tuple(p['origin']))
  angle={'nearwing':nw,'farwing':fw,'neck_head':neck}.get(p['id'],0)
  if angle: layer=layer.rotate(angle,resample=Image.Resampling.BICUBIC,center=tuple(p['pivot']),fillcolor=(0,0,0,0))
  if p['id']=='body4legs_tail' and (dx or dy):
   moved=Image.new('RGBA',CANVAS,(0,0,0,0)); moved.alpha_composite(layer,(round(dx),round(dy))); layer=moved
  layer_images.append(layer)
 result=Image.new('RGBA',CANVAS,(0,0,0,0))
 for layer in layer_images: result.alpha_composite(layer)
 return result
def main():
 # Rebuild only this additive candidate directory; preserve other candidates.
 if OUT.exists(): shutil.rmtree(OUT)
 render_parts()
 clips={}
 for state,sp in CLIPS.items():
  keyframes=[]
  for i in range(sp['frames']):
   dx,dy,nw,fw,neck=values(state,i,sp['frames'])
   keyframes.append({"frame":i,"pose_by_part":{
    "body4legs_tail":{"translation_px":[round(dx,3),round(dy,3)]},
    "nearwing":{"rotation_deg":round(nw,3)},
    "farwing":{"rotation_deg":round(fw,3)},
    "neck_head":{"rotation_deg":round(neck,3)},
   }})
  clips[state]={"fps":FPS,"loop":sp['loop'],"frame_count":sp['frames'],"keyframes":keyframes}
 # SpriteKit-compatible rig definition. Pixel coordinates use the downscaled cutouts.
 manifest={
  "actor_id":ACTOR,"revision":"rig_candidate_r001","status":"TECHNICAL_CANDIDATE_UNAPPROVED",
  "canvas_px":list(CANVAS),"anchor_px":[256,331],"fps":FPS,
  "coordinate_system":"top-left origin; output and part images use bundle pixels",
  "source_atlas_path":"/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/codex_unified_20261008T221040Z_fa70940c/representatives/ACT_B_R04_B/parts_pilot_r005/parts_atlas.png",
  "source_atlas_sha256":"e3c0f89df6bf6f1e10855c241c4236edde103ae9bf162234e9491298e2719982",
  "registration_reference":"native/Art/GeneratedCandidates/ACT_B_R04_B/ACT_B_R04_B__static_candidate__r004.png",
  "registration_method":"manual visual registration; placements and pivots are candidate estimates, not source-authored",
  "pivot_status":"VISUAL_ESTIMATE_UNAPPROVED",
  "parts":[{
   "id":p['id'],"path":"GeneratedCandidates/ACT_B_R04_B/rig_candidate_r001/parts/"+p['file'],
   "source_path":"../parts/"+p['file'],"source_sha256":sha(PARTS_SRC/p['file']),
   "part_image_px":list(Image.open(out_part(p)).size),
   "pivot_in_part_px":[round(p['pivot'][0]-p['origin'][0],3),round(p['pivot'][1]-p['origin'][1],3)],
   "rest_position_px":p['pivot'],"z_position":p['z'],"pivot_basis":"VISUAL_ESTIMATE_UNAPPROVED"
  } for p in LAYERS],
  "clips":clips,
  "motion_limits":[
   "walk absent: all four legs and tail are one source raster part",
   "flight is wing/neck motion plus small torso float; no tucked-leg art exists",
   "execute is a transform candidate only; no breath/projectile effect integrated",
   "fused legs may shift with torso during hit/resolve; not a foot-contact qualification",
   "candidate placements and pivots need SpriteKit visual review; adoption remains pending"
  ],
  "source_art_originals_mutated":False
 }
 manifest_path=OUT/"rig_manifest_candidate_r001.json"
 manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
 # Compact visual evidence only. The runtime animation is the 24 fps keyframe contract above.
 tiles=[]
 for state,sp in CLIPS.items():
  idx=sp['frames']//2 if not sp['loop'] else sp['frames']//4
  frame=render_preview(state,idx,sp['frames']).resize((256,170),Image.Resampling.LANCZOS)
  tiles.append((state,frame))
 sheet=Image.new('RGBA',(256*2,194*4),(25,28,34,255)); draw=ImageDraw.Draw(sheet)
 for j,(state,im) in enumerate(tiles):
  x=(j%2)*256;y=(j//2)*194
  sheet.alpha_composite(im,(x,y+22)); draw.text((x+6,y+4),state,fill=(240,240,240,255))
 sheet.save(OUT/"qa_representative_states_r001.png",optimize=True)
 print(json.dumps({"manifest":str(manifest_path),"candidate_png_bytes":sum(p.stat().st_size for p in OUT.rglob('*.png')),
                   "part_bytes":sum(p.stat().st_size for p in (OUT/'parts').glob('*.png')),
                   "states":list(CLIPS),"keyframe_count":sum(s['frames'] for s in CLIPS.values())},ensure_ascii=False))
if __name__=='__main__': main()

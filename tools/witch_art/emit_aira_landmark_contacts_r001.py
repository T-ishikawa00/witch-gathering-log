#!/usr/bin/env python3
"""Create QA-only 32px coordinate-grid contacts for AIRA's 27 authored body frames."""
from pathlib import Path
import hashlib, json
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'native/GeneratedArt'
OUT=ROOT/'docs/production/current/art/aira_landmark_contacts_r001'
OUT.mkdir(parents=True,exist_ok=True)
SEQUENCES={'rest':('party_rest_r001','AIRA__rest_',range(9)),
           'attack':('party_attack_r001','AIRA__attack_',range(9)),
           'walk':('party_walk_r001','AIRA__walk_',range(9))}
SCALE=2
CANVASES={'rest':(320,256),'attack':(320,256),'walk':(256,256)}
bg=(29,39,58,255)
font=ImageFont.load_default()
manifest={'status':'SOURCE_PIXELS_UNCHANGED_QA_CONTACT_ONLY','grid':'32 source px; top-left origin','contacts':[]}
for state,(folder,prefix,indices) in SEQUENCES.items():
 W,H=CANVASES[state]; PW,PH=W*SCALE,H*SCALE+34
 sheet=Image.new('RGBA',(PW*3,PH*3),bg); d=ImageDraw.Draw(sheet)
 for idx in indices:
  row,col=divmod(idx,3); x0=col*PW; y0=row*PH
  suffix=f'{idx:02d}' if state!='walk' else str(idx)
  p=ART/folder/f'{prefix}{suffix}.png'
  im=Image.open(p).convert('RGBA')
  if im.size!=(W,H): raise SystemExit(f'Unexpected canvas {p}: {im.size}')
  d.text((x0+8,y0+8),f'{state.upper()} sourceFrame={idx:02d} asset={p.name}',font=font,fill=(255,255,255,255))
  enlarged=im.resize((W*SCALE,H*SCALE),Image.Resampling.NEAREST)
  sheet.alpha_composite(enlarged,(x0,y0+34))
  # Fine, unobtrusive grid with coordinate labels in native source pixels.
  gd=ImageDraw.Draw(sheet,'RGBA')
  for px in range(0,W+1,32):
   xx=x0+px*SCALE; gd.line((xx,y0+34,xx,y0+34+H*SCALE),fill=(205,218,237,75),width=1)
   if px<W: gd.text((xx+2,y0+35),str(px),font=font,fill=(255,230,130,255))
  for py in range(0,H+1,32):
   yy=y0+34+py*SCALE; gd.line((x0,yy,x0+W*SCALE,yy),fill=(205,218,237,75),width=1)
   if py<H: gd.text((x0+2,yy+2),str(py),font=font,fill=(255,230,130,255))
  manifest['contacts'].append({'state':state,'sourceFrameIndex':idx,'sourcePath':str(p.relative_to(ROOT)),'sourceSHA256':hashlib.sha256(p.read_bytes()).hexdigest(),'canvas':[W,H]})
 out=OUT/f'{state.upper()}_SOURCE_GRID.png'; sheet.convert('RGB').save(out,optimize=True)
manifest['contactPNG_SHA256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(OUT.glob('*.png'))}
(OUT/'MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'output':str(OUT),'contacts':manifest['contactPNG_SHA256'],'sourceFrames':len(manifest['contacts'])},indent=2))

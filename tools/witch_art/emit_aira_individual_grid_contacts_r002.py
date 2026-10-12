#!/usr/bin/env python3
"""Diagnostic enlarged per-frame contacts; source pixels remain unchanged."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
DEST=ROOT/'docs/production/current/art/aira_landmark_contacts_r002'
DEST.mkdir(parents=True,exist_ok=True)
colors={'neck':'#ff4b4b','chest':'#ffc94a','workingHand':'#51e5a8','visibleRightAnkle':'#65a6ff','hammerHead':'#ed73ff'}
# Read the current candidate points to show their locations for review.
import json
landmarks=json.loads((ROOT/'native/Art/GeneratedCandidates/EquipmentDetails/aira_equipment_landmarks_r004.json').read_text())
bybody={r['bodyAssetID'].split('/')[-1]:r['landmarks_px_top_left'] for r in landmarks['rows']}
for name,directory,prefix,count in [('REST','party_rest_r001','rest',9),('ATTACK','party_attack_r001','attack',9),('WALK','party_walk_r001','walk',9)]:
 canvas=Image.new('RGB',(3*960,3*768),(30,34,42));draw=ImageDraw.Draw(canvas)
 for i in range(count):
  filename=f'AIRA__{prefix}_{i:02d}.png' if prefix!='walk' else f'AIRA__walk_{i}.png'
  src=ROOT/'native/GeneratedArt'/directory/filename
  im=Image.open(src).convert('RGBA')
  w,h=im.size
  bg=Image.new('RGBA',im.size,(35,39,47,255));bg.alpha_composite(im)
  big=bg.resize((w*3,h*3),Image.Resampling.NEAREST)
  x0=(i%3)*960;y0=(i//3)*768
  canvas.paste(big.convert('RGB'),(x0,y0+28))
  d=ImageDraw.Draw(canvas)
  for x in range(0,w+1,16):
   xx=x0+x*3;d.line((xx,y0+28,xx,y0+28+h*3),fill=(105,120,138),width=1)
   if x%32==0:d.text((xx+2,y0+29),str(x),fill='#ffdf80')
  for y in range(0,h+1,16):
   yy=y0+28+y*3;d.line((x0,yy,x0+w*3,yy),fill=(105,120,138),width=1)
   if y%32==0:d.text((x0+2,yy+2),str(y),fill='#ffdf80')
  d.text((x0+8,y0+5),f'{name} frame {i:02d} {filename}',fill='white')
  for field,point in bybody[filename].items():
   x,y=point;cx=x0+x*3;cy=y0+28+y*3;c=colors.get(field,'#ffffff')
   d.line((cx-10,cy,cx+10,cy),fill=c,width=2);d.line((cx,cy-10,cx,cy+10),fill=c,width=2)
   d.ellipse((cx-5,cy-5,cx+5,cy+5),outline=c,width=2)
   d.text((cx+4,cy-18),field[:2],fill=c)
  d=ImageDraw.Draw(canvas)
 out=DEST/f'{name}_INDIVIDUAL_GRID_R002.jpg';canvas.save(out,quality=94)
print('\n'.join(str(p) for p in sorted(DEST.glob('*'))))

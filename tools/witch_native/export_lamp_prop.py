#!/usr/bin/env python3
"""Atlas slicing/registration only; preserve the generated RGBA artwork."""
from pathlib import Path
from PIL import Image
import hashlib, json, shutil

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path('/Users/PUBLIC_USER/.codex/generated_images/01a12398-0ccb-7d03-aeac-75db9b0de178/exec-cb269eb8-19ee-45f9-a072-ee04b5d34e73.png')
DEST = ROOT / 'native/GeneratedArt/r001'
atlas = Image.open(SOURCE).convert('RGBA')
shutil.copy2(SOURCE, DEST / 'PROP_LAMP_SHEET.png')
cells = [atlas.crop((x * atlas.width // 2, y * atlas.height // 2,
                     (x + 1) * atlas.width // 2, (y + 1) * atlas.height // 2))
         for y in range(2) for x in range(2)]
bounds = [im.getchannel('A').point(lambda a: 255 if a >= 16 else 0).getbbox() for im in cells]
assert all(b and min(b[0], b[1], im.width-b[2], im.height-b[3]) >= 8 for b, im in zip(bounds, cells))
scale = min(440 / max(b[2]-b[0], b[3]-b[1]) for b in bounds)
records = []
for i, (cell, bound) in enumerate(zip(cells, bounds)):
    crop = cell.crop(bound)
    crop = crop.resize((round(crop.width*scale), round(crop.height*scale)), Image.Resampling.LANCZOS)
    frame = Image.new('RGBA', (512, 512))
    frame.alpha_composite(crop, ((512-crop.width)//2, 480-crop.height))
    name = f'PROP_LAMP__{i}.png'; frame.save(DEST/name)
    records.append({'frame': name, 'bounds': bound, 'sha256': hashlib.sha256((DEST/name).read_bytes()).hexdigest()})
(ROOT/'docs/production/current/art/LAMP_PROP_R001.json').write_text(json.dumps({
    'status': 'UNAPPROVED_ANIMATED_PROP_CANDIDATE', 'source': str(SOURCE),
    'sourceSHA256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    'reference': 'ACT_E_R05_03 material/style only; prop has no arms and a standing base',
    'prompt': 'Transparent 2x2 full lantern props, consistent gold/ivory faceted glass and geometry; low flame, high flame, healing flare, extinguished. No ghost arms, eyes, text, ground or external effects.',
    'canvas': [512,512], 'footAnchor': [256,480], 'frames': records,
    'runtimeQA': 'PENDING', 'humanApproval': False
}, indent=2)+'\n')

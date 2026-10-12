#!/usr/bin/env python3
"""Pack the reviewed imagegen deer-walk atlas without modifying source pixels."""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib, json

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'native/Art'
BASE = ART / 'GeneratedCandidates/ACT_B_R05_B/deer_walk_candidate_r001'
ATLAS = BASE / 'imagegen_atlas_source.png'
OUT = BASE / 'frames'
OUT.mkdir(parents=True, exist_ok=True)
image = Image.open(ATLAS).convert('RGBA')
w, h = image.size
if w % 3 or h % 3:
    raise SystemExit(f'atlas must split exactly 3x3: {image.size}')
cw, ch = w // 3, h // 3
canvas_w, canvas_h = 512, 704
anchor = [256, 600]
frames = []
metrics = []
for i in range(9):
    row, col = divmod(i, 3)
    tile = image.crop((col*cw, row*ch, (col+1)*cw, (row+1)*ch))
    alpha16 = tile.getchannel('A').point(lambda v: 255 if v > 16 else 0)
    bbox = alpha16.getbbox()
    if not bbox:
        raise SystemExit(f'empty sprite cell {i}')
    margins = [bbox[0], bbox[1], cw-bbox[2], ch-bbox[3]]
    if min(margins) < 28:
        raise SystemExit(f'alpha16 margin too small in cell {i}: {margins}')
    # Pack only: retain every source pixel and align the bottom alpha16 edge to the
    # candidate ground anchor. This is registration, not pixel editing.
    x = (canvas_w-cw)//2
    y = anchor[1]-bbox[3]
    if x < 0 or y < 0 or x+cw > canvas_w or y+ch > canvas_h:
        raise SystemExit(f'cell {i} would be clipped in target canvas: offset={(x,y)}')
    packed = Image.new('RGBA', (canvas_w, canvas_h), (0,0,0,0))
    packed.paste(tile, (x,y))
    name = f'walk_{i:03d}.png'
    packed.save(OUT/name, optimize=True)
    # Verify the complete original cell, including transparent RGB values, was copied byte-identically.
    if packed.crop((x,y,x+cw,y+ch)).tobytes() != tile.tobytes():
        raise SystemExit(f'pixel preservation check failed for {i}')
    packed_bbox = packed.getchannel('A').point(lambda v: 255 if v > 16 else 0).getbbox()
    frames.append(f'GeneratedCandidates/ACT_B_R05_B/deer_walk_candidate_r001/frames/{name}')
    metrics.append({'frame':name,'sourceCell':[row,col],'sourceCellSize':[cw,ch],'sourceCellSHA256':hashlib.sha256(tile.tobytes()).hexdigest(),'packedPNG_SHA256':hashlib.sha256((OUT/name).read_bytes()).hexdigest(),'packingOffsetPx':[x,y],'alpha16BBoxInSourceCell':list(bbox),'alpha16MarginsLTRB':margins,'alpha16BBoxInCanvas':list(packed_bbox),'allSourceRGBABytesPreserved':True})

still = Image.open(ART/'ActorStills/ACT_B_R05_B/ACT_B_R05_B__still__r001.png').convert('RGBA')
still_bbox = still.getchannel('A').point(lambda v: 255 if v > 16 else 0).getbbox()
heights = [m['alpha16BBoxInCanvas'][3]-m['alpha16BBoxInCanvas'][1] for m in metrics]
display_scale = round((still_bbox[3]-still_bbox[1])/(sum(heights)/len(heights)), 6)
contact = Image.new('RGB',(3*canvas_w+64,3*canvas_h+96),(34,42,39)); draw=ImageDraw.Draw(contact)
for i,rel in enumerate(frames):
    x=16+(i%3)*(canvas_w+16);y=16+(i//3)*(canvas_h+24)
    tile=Image.open(ART/rel).convert('RGBA')
    bg=Image.new('RGBA',tile.size,(34,42,39,255));bg.alpha_composite(tile)
    contact.paste(bg.convert('RGB'),(x,y));draw.text((x+5,y+canvas_h+4),f'walk {i:03d}',fill=(230,235,230))
contact.save(BASE/'qa_contact_dark.png',quality=94)
clip={'frames':frames,'frame_count':len(frames),'fps':8,'duration_seconds':len(frames)/8,'loop':True,'complete_animation':False,'status':'UNAPPROVED_NINE_FRAME_QUADRUPED_GAIT_CANDIDATE_NOT_NATURAL_MOTION_COMPLETE','canvas_px':[canvas_w,canvas_h],'anchor':anchor,'anchor_status':'VISUAL_ESTIMATE_UNAPPROVED','anchor_type':'candidate_ground_baseline_alpha16_registration','display_scale':display_scale,'movement_semantics':'heavy quadruped walk/trot; generated phases suggest alternating fore/hind hoof contacts and swing, but native visual continuity and ground contact remain unverified'}
manifest={'actorId':'ACT_B_R05_B','status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE','sourceAtlas':'imagegen_atlas_source.png','sourceAtlasSHA256':hashlib.sha256(ATLAS.read_bytes()).hexdigest(),'sourceApprovedStill':'../../../../ActorStills/ACT_B_R05_B/ACT_B_R05_B__still__r001.png','sourceApprovedStillSHA256':hashlib.sha256((ART/'ActorStills/ACT_B_R05_B/ACT_B_R05_B__still__r001.png').read_bytes()).hexdigest(),'packingMethod':'Exact 3x3 source cell copy into transparent 512x512 frames; no resizing, recoloring or alpha edits; alpha16 bottom registered to candidate ground anchor y=490.','targetCanvasPx':[canvas_w,canvas_h],'candidateAnchor':anchor,'candidateDisplayScale':display_scale,'idleAlpha16BBox':list(still_bbox),'walkAlpha16HeightPx':heights,'frames':metrics,'clip':clip,'qaContact':'qa_contact_dark.png','humanApproval':False,'nativeRuntimeVisualQA':'PENDING'}
(BASE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'frameCount':len(frames),'canvas':clip['canvas_px'],'anchor':anchor,'idleAlpha16Height':still_bbox[3]-still_bbox[1],'walkAlpha16Heights':heights,'display_scale':display_scale,'contact':str(BASE/'qa_contact_dark.png')},ensure_ascii=False))

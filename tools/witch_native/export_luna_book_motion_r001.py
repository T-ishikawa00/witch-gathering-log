#!/usr/bin/env python3
"""Pack 27 generated LUNA key poses into shared-canvas body sprites; preserve alpha."""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib, json, os
import numpy as np
from scipy import ndimage

ROOT=Path(__file__).resolve().parents[2]
S=ROOT/'native/GeneratedArt/luna_book_motion_candidates_r001/sources'
O=ROOT/'native/GeneratedArt/r001'
OUT=ROOT/'native/GeneratedArt/luna_book_motion_candidates_r001'
SIZE=(256,256)
ATLAS={'walk':('WALK_BOOKLESS_ATLAS_RAW.png',['walk']*9),
       'attack':('ATTACK_BOOKLESS_ATLAS_RAW.png',['anticipate']*3+['execute']*3+['recover']*3),
       'rest':('REST_BOOKLESS_ATLAS_RAW.png',['idle']*3+['hit']*3+['resolve']*3)}

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def alpha_bbox(im): return im.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
def atomic_save(im,path):
 path=Path(path);tmp=path.with_suffix(path.suffix+'.tmp');im.save(tmp,format='PNG');os.replace(tmp,path)
def nine_components(path):
 im=Image.open(path).convert('RGBA')
 mask=np.asarray(im.getchannel('A'))>=16
 labels,count=ndimage.label(mask)
 comps=[]
 for idx,sl in enumerate(ndimage.find_objects(labels),1):
  if sl is None: continue
  roi=labels[sl]==idx;area=int(roi.sum())
  if area>100: comps.append((area,(sl[1].start,sl[0].start,sl[1].stop,sl[0].stop)))
 if len(comps)!=9: raise ValueError(f'{path}: expected 9 alpha components, got {len(comps)}')
 return im,[b for _,b in sorted(comps,key=lambda x:(x[1][1],x[1][0]))]
def pack(src,bbox,dest):
 # Use the detected component bounds exactly: two attack/rest rows have a 3px gap,
 # so even a 1px inset could import alpha from the adjacent frame.
 pad=0;x0,y0,x1,y1=bbox
 cropbox=(max(0,x0-pad),max(0,y0-pad),min(src.width,x1+pad),min(src.height,y1+pad))
 crop=src.crop(cropbox);factor=min(166/crop.width,192/crop.height);wh=(max(1,round(crop.width*factor)),max(1,round(crop.height*factor)))
 crop=crop.resize(wh,Image.Resampling.NEAREST)
 out=Image.new('RGBA',SIZE,(0,0,0,0));visible=alpha_bbox(crop)
 out.alpha_composite(crop,(128-(visible[0]+visible[2])//2,244-visible[3]))
 atomic_save(out,dest)
 return {'packedPath':str(dest.relative_to(ROOT)),'packedSHA256':sha(dest),'canvasPx':[256,256],'alpha16BBoxPx':list(alpha_bbox(out)),'cropBoxPx':list(cropbox),'fit':'nearest-neighbor, alpha-preserving, max 166x192, bottom baseline y=244'}

def book_layer_state(frame, gear):
 src=Image.open(ROOT/f'native/GeneratedArt/r001/BOOK_{gear}.png').convert('RGBA')
 # Place the visible alpha center on the authored per-frame canvas point.
 rotated=src.rotate(frame['book']['rotationDegrees'],resample=Image.Resampling.NEAREST,center=(128,128),expand=False)
 if frame['book']['scale'] != 1:
  nw=round(256*frame['book']['scale']); nh=round(256*frame['book']['scale'])
  rotated=rotated.resize((nw,nh),Image.Resampling.NEAREST)
  sized=Image.new('RGBA',SIZE,(0,0,0,0));sized.alpha_composite(rotated,((256-nw)//2,(256-nh)//2));rotated=sized
 b=alpha_bbox(rotated);cx=(b[0]+b[2])/2;cy=(b[1]+b[3])/2
 tx=round(frame['book']['centerNormalized'][0]*256-cx);ty=round(frame['book']['centerNormalized'][1]*256-cy)
 out=Image.new('RGBA',SIZE,(0,0,0,0));out.alpha_composite(rotated,(tx,ty))
 mask=frame['book']['handOcclusionMask'];mx=mask['centerNormalized'][0]*256;my=mask['centerNormalized'][1]*256;rx=mask['radiiNormalized'][0]*256;ry=mask['radiiNormalized'][1]*256
 # Contact-only occlusion preview: clearing this ellipse reveals the source body hand below.
 from PIL import ImageChops
 ma=Image.new('L',SIZE,255);d=ImageDraw.Draw(ma);d.ellipse((mx-rx,my-ry,mx+rx,my+ry),fill=0)
 d.ellipse((110,77,176,147),fill=0)
 if frame['state']=='execute':
  ax,ay,arx,ary=[(154,145,37,11),(158,142,38,11),(166,146,36,10)][frame['frameIndex']]
  d.ellipse((ax-arx,ay-ary,ax+arx,ay+ary),fill=0)
 out.putalpha(ImageChops.multiply(out.getchannel('A'),ma))
 return out

# Candidate motion values are authored as an explicit test overlay. The center values use
# normalized top-left canvas coordinates; native renderer converts them to its SpriteKit axes.
book_centers={
 'walk':[(.700,.615),(.704,.610),(.708,.616),(.710,.622),(.706,.628),(.700,.622),(.696,.616),(.698,.610),(.702,.614)],
 'anticipate':[(.700,.620),(.702,.616),(.704,.612)],
 'execute':[(.706,.610),(.704,.614),(.700,.620)],
 'recover':[(.698,.622),(.700,.624),(.702,.620)],
 'idle':[(.702,.620),(.704,.616),(.702,.620)],
 'hit':[(.702,.620),(.708,.624),(.702,.620)],
 'resolve':[(.702,.620),(.702,.616),(.704,.620)]}
angles={'walk':[-3,0,3,-2,1,3,-3,0,2], 'anticipate':[-5,-2,0], 'execute':[2,7,4], 'recover':[1,-2,-1], 'idle':[-1,0,1], 'hit':[0,-5,1], 'resolve':[-2,0,2]}
scales={'walk':[1,.99,1.01,1,1.01,.99,1,.99,1.01], 'anticipate':[.98,1,1.02], 'execute':[1.02,1.04,1.01], 'recover':[1.01,1,.99], 'idle':[1,.99,1], 'hit':[1,1.03,1], 'resolve':[1,.99,1]}
registration={r['assetID']:r['hand'] for r in json.loads((ROOT/'tools/witch_native/luna_palm_registration_r002.json').read_text())['frames']}
frames=[];sourceRecords=[]
for atlasName,(filename,stateSequence) in ATLAS.items():
 srcPath=S/filename;source,boxes=nine_components(srcPath)
 atlasRec={'atlasPath':str(srcPath.relative_to(ROOT)),'atlasSHA256':sha(srcPath),'canvasPx':list(source.size),'componentBBoxesAlpha16Px':[list(x) for x in boxes]}
 sourceRecords.append(atlasRec)
 perStateIndex={}
 for cell,(state,bbox) in enumerate(zip(stateSequence,boxes)):
  n=perStateIndex.get(state,0)+1;perStateIndex[state]=n
  assetID=f'LUNA_BOOK_MOTION_{state.upper()}_F{n:02d}_CANDIDATE_R001'
  dest=O/f'{assetID}.png';body=pack(source,bbox,dest)
  hx,hy=registration[assetID]
  c=((hx-3)/256,(hy-20)/256); angle=angles[state][n-1]; scale=1.0
  # palm opening is on the same lower-left book edge. Ellipse values are normalized 0..1 on 256 canvas.
  palm={'shape':'ellipse','centerNormalized':[hx/256,hy/256],'radiiNormalized':[10/256,7/256], 'purpose':'foreground holding palm; runtime selectively masks face and casting forearm, never the full body; candidate registration R003'}
  duration_ms = ([450, 180, 450][n-1] if state == 'idle' else 100)
  frames.append({'state':state,'frameIndex':n-1,'sourceAtlasPath':str(srcPath.relative_to(ROOT)),'sourceComponentIndex':cell,'assetID':assetID,**body,
                 'book':{'centerNormalized':list(c),'rotationDegrees':angle,'scale':scale,'layerAssetByGearID':{'EQ_A_01':'BOOK_EQ_A_01','EQ_A_02':'BOOK_EQ_A_02','EQ_A_03':'BOOK_EQ_A_03'},'handOcclusionMask':palm},
                 'durationMs':duration_ms,'status':'UNAPPROVED_TEST_OVERLAY_CANDIDATE'})
# Contact sheet: all body poses over dark/light, without geometry changes.
rows=[]
for bg in [(36,33,41,255),(235,232,224,255)]:
 c=Image.new('RGBA',(9*176,3*216),bg);d=ImageDraw.Draw(c)
 for i,f in enumerate(frames):
  x=(i%9)*176+20;y=(i//9)*216+5
  c.alpha_composite(Image.open(ROOT/f['packedPath']).convert('RGBA').resize((136,136),Image.Resampling.NEAREST),(x,y))
  book=book_layer_state(f,'EQ_A_01').resize((136,136),Image.Resampling.NEAREST)
  c.alpha_composite(book,(x,y))
  d.text((x,y+144),f"{f['state']} {f['frameIndex']+1}",fill='white' if bg[0]<100 else (20,20,25,255))
 rows.append(c.convert('RGB'))
contact=ROOT/'docs/production/current/core/LUNA_BOOK_MOTION_CONTACT_R001.jpg'
canvas=Image.new('RGB',(9*176,6*216));canvas.paste(rows[0],(0,0));canvas.paste(rows[1],(0,3*216))
atomic_save(canvas,contact)
manifest={'schema':'luna_book_motion_candidates_r001','status':'UNAPPROVED_TEST_OVERLAY','actorID':'C_APPRENTICE','spriteActorID':'LUNA','canvasPx':list(SIZE),'footBaselineCanvasY':244,'sourceAtlases':sourceRecords,'frames':frames,'gearLayerSources':{gid:{'assetID':f'BOOK_{gid}','path':f'native/GeneratedArt/r001/BOOK_{gid}.png'} for gid in ['EQ_A_01','EQ_A_02','EQ_A_03']},'contactSheet':str(contact.relative_to(ROOT)),'runtimeContract':{'playStates':['walk','attack','anticipate','execute','recover','idle','hit','resolve'],'framesPerState':{'walk':9,'attack':9,'anticipate':3,'execute':3,'recover':3,'idle':3,'hit':3,'resolve':3},'bodyCanvasSameForAll':True,'perFrameBookTransform':True,'perFrameHandMask':True,'layerOrder':['body','book','foreground_palm_face_casting_forearm'],'normalizedOrigin':'top-left; x right, y down','duration':'100 ms/frame candidate; not Human-approved'},'notApproved':['Generated art style and motion are not Human-approved','R003 palm/face/forearm registration has sampled native review; complete naturalness and Human approval remain pending','Book position/rotation/scale and palm ellipses require close-up adjustment','No canonical animation acceptance','Original staff sprites/icons remain unchanged']}
mp=OUT/'LUNA_BOOK_MOTION_CANDIDATES_R001.json';tmp=mp.with_suffix(mp.suffix+'.tmp');tmp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');os.replace(tmp,mp)
swift=ROOT/'native/WitchGameCore/Sources/WitchGameCore/LunaBookMotionDataR001.swift'
def n(v): return f'{float(v):.4f}'
lines=['import Foundation','','enum LunaBookMotionDataR001 {','    static let frames: [LunaBookMotionFrameRecord] = [']
for f in frames:
 b=f['book'];mask=b['handOcclusionMask'];cx,cy=b['centerNormalized'];mx,my=mask['centerNormalized'];rx,ry=mask['radiiNormalized']
 lines.append('        LunaBookMotionFrameRecord(poseState: '+json.dumps(f['state'])+', frameIndex: '+str(f['frameIndex'])+', bodyAssetID: '+json.dumps(f['assetID'])+', durationMilliseconds: '+str(f['durationMs'])+', bookCenterX: '+n(cx)+', bookCenterY: '+n(cy)+', bookRotationDegrees: '+n(b['rotationDegrees'])+', bookScale: '+n(b['scale'])+', maskCenterX: '+n(mx)+', maskCenterY: '+n(my)+', maskRadiusX: '+n(rx)+', maskRadiusY: '+n(ry)+'),')
lines+=['    ]','}']
stmp=swift.with_suffix(swift.suffix+'.tmp');stmp.write_text('\n'.join(lines)+'\n');os.replace(stmp,swift)
print(json.dumps({'frameCount':len(frames),'states':manifest['runtimeContract']['framesPerState'],'contact':str(contact),'manifest':str(mp)},ensure_ascii=False,indent=2))

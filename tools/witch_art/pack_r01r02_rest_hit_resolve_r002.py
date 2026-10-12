#!/usr/bin/env python3
"""Pack the first R01/R02 three-state candidate batch using measured alpha gutters."""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib, json, os, statistics

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'native/Art'
OUT_STATUS='UNAPPROVED_AUTHORED_REST_HIT_RESOLVE_CANDIDATE'
ITEMS=[
 {'actor':'ACT_B_R01_B','atlas':'GeneratedCandidates/ACT_B_R01_B/rest_hit_resolve_r001/imagegen_atlas_repaired_r002.png','still':'ActorStills/ACT_B_R01_B/ACT_B_R01_B__still__B_R01_B_ANCIENT_TREE_base_v1.png','baselineIdle':['GeneratedCandidates/ACT_B_R01_B/pose_candidate_r002/frames/idle_a.png','GeneratedCandidates/ACT_B_R01_B/pose_candidate_r002/frames/idle_b.png'],'baselineCanvas':[512,512],'baselineAnchor':[256,490],'semantics':'Rooted ancient guardian tree: subtle canopy sway; non-gory branch and crown recoil with roots fixed; branches lower into a quiet rooted settle.','mode':'ground'},
 {'actor':'ACT_E_R02_01','atlas':'GeneratedCandidates/ACT_E_R02_01/rest_hit_resolve_r001/imagegen_atlas_source.png','still':'ActorStills/ACT_E_R02_01/ACT_E_R02_01__still__r002.png','baselineIdle':['GeneratedCandidates/ACT_E_R02_01/pose_candidate_r001/frames/idle_a.png','GeneratedCandidates/ACT_E_R02_01/pose_candidate_r001/frames/idle_b.png'],'baselineCanvas':[512,512],'baselineAnchor':[256,460],'semantics':'Soft spotted spore creature: subtle cap breathing; non-gory hit compresses and rocks the cap while feet brace; calm squat settle. Squash is intentional, do not normalize per frame.','mode':'ground'},
 {'actor':'ACT_E_R02_02','atlas':'GeneratedCandidates/ACT_E_R02_02/rest_hit_resolve_r001/imagegen_atlas_source.png','still':'ActorStills/ACT_E_R02_02/ACT_E_R02_02__still__r001.png','baselineIdle':['GeneratedCandidates/ACT_E_R02_02/pose_candidate_r001/frames/idle_a.png','GeneratedCandidates/ACT_E_R02_02/pose_candidate_r001/frames/idle_b.png'],'baselineCanvas':[512,512],'baselineAnchor':[256,490],'semantics':'Grounded frost-scaled quadruped: breath and tail-tip idle; non-gory head/shoulder recoil and brace on all feet; head lowers and tail relaxes at resolve.','mode':'ground'},
 {'actor':'ACT_E_R02_04','atlas':'GeneratedCandidates/ACT_E_R02_04/rest_hit_resolve_r001/imagegen_atlas_repaired_r002.png','still':'ActorStills/ACT_E_R02_04/ACT_E_R02_04__still__r001.png','baselineIdle':['GeneratedCandidates/ACT_E_R02_04/pose_candidate_r002/frames/idle_a.png','GeneratedCandidates/ACT_E_R02_04/pose_candidate_r002/frames/idle_b.png'],'baselineCanvas':[512,512],'baselineAnchor':[256,300],'semantics':'Airborne moon moth: wingbeat while hovering; non-gory wing-fold recoil; wings ease down as it settles into a quiet hover, never ground-walk.','mode':'hover'},
 {'actor':'ACT_B_R02_A','atlas':'GeneratedCandidates/ACT_B_R02_A/rest_hit_resolve_r001/imagegen_atlas_source.png','still':'ActorStills/ACT_B_R02_A/ACT_B_R02_A__still__r001.png','baselineIdle':['GeneratedCandidates/ACT_B_R02_A/pose_candidate_r001/frames/idle_a.png','GeneratedCandidates/ACT_B_R02_A/pose_candidate_r001/frames/idle_b.png'],'baselineCanvas':[512,512],'baselineAnchor':[256,490],'semantics':'Rooted mushroom guardian: slow cap sway; non-gory cap/stalk flinch with intact body; cap and roots lower into quiet settle.','mode':'ground'},
 {'actor':'ACT_B_R02_B','atlas':'GeneratedCandidates/ACT_B_R02_B/rest_hit_resolve_r001/imagegen_atlas_source.png','still':'ActorStills/ACT_B_R02_B/ACT_B_R02_B__still__r001.png','baselineIdle':['GeneratedCandidates/ACT_B_R02_B/pose_candidate_r002/frames/idle_a.png','GeneratedCandidates/ACT_B_R02_B/pose_candidate_r002/frames/idle_b.png'],'baselineCanvas':[512,512],'baselineAnchor':[256,490],'semantics':'Grounded leaf drake: subtle breathing and tail-tip idle; non-gory head/shoulder recoil with all feet braced; head and tail relax at resolve.','mode':'ground'},
]
STATES=('idle','hit','resolve')
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def atomic_bytes(path,data):
 path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);tmp=path.with_name(path.name+'.tmp');tmp.write_bytes(data);os.replace(tmp,path)
def atomic_json(path,obj):atomic_bytes(path,(json.dumps(obj,ensure_ascii=False,indent=2)+'\n').encode())
def alpha16(im):return im.getchannel('A').point(lambda a:255 if a>=16 else 0)
def bbox16(im):return alpha16(im).getbbox()
def gutter(alpha,axis,near):
 limit=alpha.width if axis=='x' else alpha.height;groups=[];current=[]
 for v in range(max(1,round(near-75)),min(limit-1,round(near+75))):
  box=(v,0,v+1,alpha.height) if axis=='x' else (0,v,alpha.width,v+1)
  if alpha.crop(box).getbbox() is None: current.append(v)
  elif current: groups.append(current);current=[]
 if current:groups.append(current)
 if not groups:raise ValueError(('no measured transparent gutter',axis,near))
 return round(statistics.mean(min(groups,key=lambda g:abs(statistics.mean(g)-near)-min(20,len(g))*.25)))
def main():
 overlays={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'human_approval':False,'entries':{}}
 audit=[]
 for cfg in ITEMS:
  actor=cfg['actor'];sheet_path=ART/cfg['atlas'];sheet=Image.open(sheet_path).convert('RGBA');mask=alpha16(sheet)
  if mask.getbbox() is None or sheet.getchannel('A').getextrema()[0]!=0:raise ValueError((actor,'alpha/background check failed'))
  ys=[0,gutter(mask,'y',sheet.height/3),gutter(mask,'y',sheet.height*2/3),sheet.height]
  out=ART/'GeneratedCandidates'/actor/'rest_hit_resolve_packed_r002';frames_dir=out/'frames';frames_dir.mkdir(parents=True,exist_ok=True)
  cells=[];grid=[]
  for row in range(3):
   band=mask.crop((0,ys[row],sheet.width,ys[row+1]));xs=[0,gutter(band,'x',sheet.width/3),gutter(band,'x',sheet.width*2/3),sheet.width]
   grid.append(xs)
   for col in range(3):
    box=(xs[col],ys[row],xs[col+1],ys[row+1]);cell=sheet.crop(box);b=bbox16(cell)
    if not b:raise ValueError((actor,row,col,'empty alpha16 cell'))
    margin=min(b[0],b[1],cell.width-b[2],cell.height-b[3])
    if margin<2:raise ValueError((actor,row,col,'alpha16 artwork reaches crop edge',box,b,margin))
    cells.append((cell,box,b,margin))
  baseline=[]
  for path in cfg['baselineIdle']:
   im=Image.open(ART/path).convert('RGBA');b=bbox16(im)
   if b:baseline.append({'path':path,'alpha16BBox':list(b),'height':b[3]-b[1]})
  if len(baseline)<2:raise ValueError((actor,'baseline idle missing'))
  targetHeight=statistics.median(x['height'] for x in baseline)
  old_h=cfg['baselineCanvas'][1];source_anchor=cfg['baselineAnchor'];anchor_y=round(source_anchor[1]/old_h*512)
  reference_scale=targetHeight/statistics.median(b[3]-b[1] for _,_,b,_ in cells[:3])
  fit_scale=min(reference_scale,470/max(b[2]-b[0] for _,_,b,_ in cells),460/max(b[3]-b[1] for _,_,b,_ in cells))
  if fit_scale<=0:raise ValueError((actor,'invalid scale'))
  frames=[];contact=Image.new('RGBA',(1536,1536),(31,40,37,255))
  for n,(cell,box,b,margin) in enumerate(cells):
   scaled=cell.resize((round(cell.width*fit_scale),round(cell.height*fit_scale)),Image.Resampling.NEAREST);sb=alpha16(scaled).getbbox()
   if not sb:raise ValueError((actor,n,'scaled empty'))
   dx=round(256-(sb[0]+sb[2])/2)
   if cfg['mode']=='hover':
    target_center=300 if n<6 else 320+(n-6)*24
    dy=round(min(target_center-(sb[1]+sb[3])/2,490-sb[3]))
   else:dy=round(anchor_y-sb[3])
   visible=(dx+sb[0],dy+sb[1],dx+sb[2],dy+sb[3])
   if min(visible[0],visible[1],512-visible[2],512-visible[3])<2:raise ValueError((actor,n,'visible art would clip',visible,scaled.size,dx,dy))
   frame=Image.new('RGBA',(512,512),(0,0,0,0));frame.alpha_composite(scaled,(dx,dy));export_bbox=alpha16(frame).getbbox()
   if min(export_bbox[0],export_bbox[1],512-export_bbox[2],512-export_bbox[3])<2:raise ValueError((actor,n,'exported artwork clipped',export_bbox))
   rel=f'GeneratedCandidates/{actor}/rest_hit_resolve_packed_r002/frames/{STATES[n//3]}_{n%3:03}.png';path=ART/rel;tmp=path.with_name(path.name+'.tmp.png');frame.save(tmp,format='PNG',optimize=True);os.replace(tmp,path)
   thumb=frame.resize((512,512),Image.Resampling.NEAREST);contact.alpha_composite(thumb,((n%3)*512,(n//3)*512))
   frames.append({'path':rel,'state':STATES[n//3],'index':n%3,'sourceCellBoundsPx':list(box),'sourceAlpha16BoundsPx':list(b),'sourceAlpha16MarginPx':margin,'exportedAlpha16BoundsPx':list(export_bbox),'packingTranslationPx':[dx,dy],'sha256':sha(path)})
  display_scale=round(reference_scale/fit_scale,6)
  entry={'selectedPNG':frames[0]['path'],'canvas_px':[512,512],'anchor':[256,anchor_y],'clips':{},'sequenceFrames':{}}
  for state,start,fps,loop in [('idle',0,4,True),('hit',3,12,False),('resolve',6,8,False)]:
   paths=[f['path'] for f in frames[start:start+3]];entry['sequenceFrames'][state]=paths;entry['clips'][state]={'frames':paths,'frame_count':3,'fps':fps,'duration_seconds':round(3/fps,6),'loop':loop,'canvas_px':[512,512],'anchor':[256,anchor_y],'display_scale':display_scale,'status':OUT_STATUS,'complete_animation':False,'movement_semantics':cfg['semantics'],'anchor_status':'BASELINE_NORMALIZED_ANCHOR_UNAPPROVED'}
  overlays['entries'][actor]=entry
  contact_path=out/'qa_contact_dark.jpg';tmp=contact_path.with_name(contact_path.name+'.tmp.jpg');contact.convert('RGB').save(tmp,format='JPEG',quality=95);os.replace(tmp,contact_path)
  still=ART/cfg['still'];manifest={'schema':'witch.enemy_rest_hit_resolve_candidate.v1','actorId':actor,'revision':'rest_hit_resolve_packed_r002','status':OUT_STATUS,'sourceApprovedStill':cfg['still'],'sourceApprovedStillSHA256':sha(still),'imagegenAtlas':cfg['atlas'],'imagegenAtlasSHA256':sha(sheet_path),'atlasPx':list(sheet.size),'gridYEdgesPx':ys,'gridXEdgesByRowPx':grid,'baselineIdleFrames':baseline,'baselineCanvasPx':cfg['baselineCanvas'],'baselineAnchorPx':cfg['baselineAnchor'],'targetIdleAlpha16HeightPx':targetHeight,'candidateAnchorPx':[256,anchor_y],'candidateFitScale':fit_scale,'candidateDisplayScale':display_scale,'commonScaleAcrossAllStatesAndFrames':True,'packing':'Measured alpha>=16 transparent gutters; full RGBA cells resized together and placed on transparent 512x512 canvas. No per-frame alpha cleanup or recoloring. All PNGs published atomically.','frameRecords':frames,'qaContactDark':'qa_contact_dark.jpg','runtimeOverlay':f'runtime_overlay_{actor.lower()}_rest_hit_resolve_candidate_r002.json','notRuntimeApproved':True,'naturalMotionComplete':False,'limitations':['Candidate drawn from imagegen; preserve source still and existing clips.','Native SpriteKit frame-by-frame review pending.']}
  atomic_json(out/'manifest.json',manifest)
  report_actor={'candidateManifest':str((out/'manifest.json').relative_to(ROOT)),'contactSheet':str(contact_path.relative_to(ROOT)),'sourceStill':cfg['still'],'sourceAtlasSHA256':manifest['imagegenAtlasSHA256'],'baselineIdleEvidence':baseline,'candidateFrameCountByState':{'idle':3,'hit':3,'resolve':3},'targetHeightPx':targetHeight,'candidateDisplayScale':display_scale,'candidateAnchorPx':[256,anchor_y],'minimumSourceAlpha16MarginPx':min(f['sourceAlpha16MarginPx'] for f in frames),'status':'UNAPPROVED_PARTIAL_CANDIDATE_PENDING_NATIVE_REVIEW'}
  atomic_json(ART/f'runtime_overlay_{actor.lower()}_rest_hit_resolve_candidate_r002.json',{'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'entries':{actor:entry}})
  audit.append({'actorId':actor,'priorStateEvidence':{s:{'frames':2,'status':'DISCRETE_POSE_CANDIDATE_INBETWEENS_PENDING'} for s in STATES},'candidate':report_actor})
 prior={'ACT_B_R01_B':['GeneratedCandidates/ACT_B_R01_B/pose_candidate_r002/frames/idle_a.png','GeneratedCandidates/ACT_B_R01_B/pose_candidate_r002/frames/idle_b.png'],'ACT_E_R02_01':['GeneratedCandidates/ACT_E_R02_01/pose_candidate_r001/frames/idle_a.png','GeneratedCandidates/ACT_E_R02_01/pose_candidate_r001/frames/idle_b.png'],'ACT_E_R02_02':['GeneratedCandidates/ACT_E_R02_02/pose_candidate_r001/frames/idle_a.png','GeneratedCandidates/ACT_E_R02_02/pose_candidate_r001/frames/idle_b.png'],'ACT_E_R02_04':['GeneratedCandidates/ACT_E_R02_04/pose_candidate_r002/frames/idle_a.png','GeneratedCandidates/ACT_E_R02_04/pose_candidate_r002/frames/idle_b.png'],'ACT_B_R02_A':['GeneratedCandidates/ACT_B_R02_A/pose_candidate_r001/frames/idle_a.png','GeneratedCandidates/ACT_B_R02_A/pose_candidate_r001/frames/idle_b.png'],'ACT_B_R02_B':['GeneratedCandidates/ACT_B_R02_B/pose_candidate_r002/frames/idle_a.png','GeneratedCandidates/ACT_B_R02_B/pose_candidate_r002/frames/idle_b.png']}
 for a,paths in prior.items():
  for p in paths:
   if not (ART/p).is_file():raise ValueError((a,'prior source frame missing',p))
 overlay_path=ART/'runtime_overlay_zzz_r01r02_rest_hit_resolve_r002.json';atomic_json(overlay_path,overlays)
 report={'schemaVersion':1,'status':'UNAPPROVED_PARTIAL_REST_HIT_RESOLVE_CANDIDATES_PENDING_NATIVE_REVIEW','scope':'Second QA batch: ACT_B_R01_B, ACT_E_R02_01, ACT_E_R02_02, ACT_E_R02_04, ACT_B_R02_A, ACT_B_R02_B.','priorAudit':'Fresh prepare_resources index showed two frames each for idle/hit/resolve, status DISCRETE_POSE_CANDIDATE_INBETWEENS_PENDING.','candidateOverlay':str(overlay_path.relative_to(ROOT)),'candidateOverlaySHA256':sha(overlay_path),'actors':audit,'excludedActors':['ACT_E_R01_01','ACT_E_R02_03','ACT_B_R01_A'],'assemblyRule':'Late partial-state overlay updates idle/hit/resolve only; existing attack, walk and other clips remain inherited.','alpha':'Measured alpha>=16 gutters; per-cell source bounds/margins and exported alpha16 bounds recorded.','humanApproval':False,'naturalMotionComplete':False,'limitations':['3 frames per state are candidates, not animation completion.','Native SpriteKit quality and scale review pending.']}
 atomic_json(ROOT/'docs/production/current/art/R01R02_rest_hit_resolve_r002.json',report)
 print(json.dumps({'overlay':str(overlay_path.relative_to(ROOT)),'sha256':sha(overlay_path),'actors':audit},ensure_ascii=False))
if __name__=='__main__':main()

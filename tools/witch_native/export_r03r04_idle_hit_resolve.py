#!/usr/bin/env python3
"""Slice generated 3x3 enemy idle/hit/resolve candidate atlases at measured alpha>=16 gutters."""
from pathlib import Path
from PIL import Image
import hashlib,json,os,shutil
ROOT=Path(__file__).resolve().parents[2]; ART=ROOT/'native/Art'
GEN=Path('/Users/PUBLIC_USER/.codex/generated_images/01a12399-5c96-7aa2-805f-d7e75a6df478')
ATLAS={
'ACT_E_R03_01':'exec-60590206-9de2-4f21-a688-2e5d60d19efc.png',
'ACT_E_R03_02':'exec-7b391fb6-9473-4422-99c6-907474517b34.png',
'ACT_E_R03_03':'exec-6bd84bb3-1a11-491f-b088-34bd8bfb5541.png',
'ACT_E_R03_04':'exec-88df0d07-215e-4ed4-8b22-b7fc9b0937d4.png',
'ACT_B_R03_B':'exec-79fe20d0-91e5-4795-a120-cce36f8e1447.png',
'ACT_E_R04_01':'exec-acd4f103-66a9-4c70-8187-ded8ece9c045.png',
'ACT_E_R04_02':'exec-3ab3b648-22ac-409c-ad32-30c6c6d9b0b5.png',
'ACT_E_R04_03':'exec-0e477098-5a6e-4add-a39d-0ce0a628a955.png',
'ACT_E_R04_04':'exec-a7bc9a3c-9707-4698-abcb-6c350f92a6c7.png',
'ACT_B_R04_A':'exec-f161cfb0-6176-446e-b6a9-c8d53bc88691.png'}
STATES=['idle','hit','resolve']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def atomic_bytes(p,b):tmp=p.with_name(p.name+'.tmp');tmp.write_bytes(b);os.replace(tmp,p)
def atomic_image(im,p,**kw):tmp=p.with_name(p.stem+'.tmp'+p.suffix);im.save(tmp,**kw);os.replace(tmp,p)
def split_at_gutter(alpha,axis,target_frac):
 w,h=alpha.size;n=w if axis==0 else h;length=h if axis==0 else w;target=round(n*target_frac);radius=round(n*.12);lo=max(1,target-radius);hi=min(n-2,target+radius)
 counts=[]
 for i in range(lo,hi+1):
  crop=alpha.crop((i,0,i+1,length) if axis==0 else (0,i,length,i+1))
  counts.append(sum(v>=16 for v in crop.getdata()))
 runs=[];start=None
 for j,count in enumerate(counts+[1]):
  if count==0 and start is None:start=lo+j
  elif count!=0 and start is not None:
   end=lo+j-1;runs.append((start,end,end-start+1));start=None
 if not runs:raise ValueError(f'No alpha>=16 zero gutter near {target_frac:.3f} axis={axis}')
 a,b,width=max(runs,key=lambda x:(x[2],-abs((x[0]+x[1]+1)/2-target)))
 return (a+b+1)//2,(a,b,width)
def grid_cuts(alpha):
 w,h=alpha.size;xs=[0];xmeta=[]
 for f in (1/3,2/3):p,g=split_at_gutter(alpha,0,f);xs.append(p);xmeta.append(g)
 xs.append(w);ys=[0];ymeta=[]
 for f in (1/3,2/3):p,g=split_at_gutter(alpha,1,f);ys.append(p);ymeta.append(g)
 ys.append(h);return xs,ys,xmeta,ymeta
def main():
 overlay={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE_OVERLAY','complete_animation':False,'entries':{}};summary=[]
 for actor,filename in ATLAS.items():
  raw=GEN/filename;srcs=sorted((ART/'ActorStills'/actor).glob(f'{actor}__still__r*.png'))
  if not raw.exists() or not srcs:raise FileNotFoundError((raw,actor))
  src=srcs[-1];im=Image.open(raw).convert('RGBA');alpha=im.getchannel('A');xs,ys,xmeta,ymeta=grid_cuts(alpha)
  dest=ART/'GeneratedCandidates'/actor/'idle_hit_resolve_r001';framesdir=dest/'frames';framesdir.mkdir(parents=True,exist_ok=True);shutil.copy2(raw,dest/'SOURCE_ATLAS.png');shutil.copy2(src,dest/'REFERENCE_STILL__preserved_copy.png')
  contacts=Image.new('RGBA',(768,768),(35,48,41,255)); entry={'clips':{},'sequenceFrames':{}};frames=[];minimum=999
  for r,state in enumerate(STATES):
   state_paths=[]
   for c in range(3):
    cellbox=(xs[c],ys[r],xs[c+1],ys[r+1]);cell=im.crop(cellbox);bbox=cell.getchannel('A').point(lambda v:255 if v>=16 else 0).getbbox()
    if bbox is None:raise ValueError(f'{actor} empty {state}/{c+1}')
    margins=[bbox[0],bbox[1],cell.width-bbox[2],cell.height-bbox[3]];minimum=min(minimum,*margins)
    if min(margins)<3:raise ValueError(f'{actor} unsafe gutter {state}/{c+1} margin={margins} cuts={xs},{ys}')
    crop=cell.crop(bbox);scale=min(480/crop.width,390/crop.height);size=(max(1,round(crop.width*scale)),max(1,round(crop.height*scale)));crop=crop.resize(size,Image.Resampling.NEAREST)
    x=256-size[0]//2;y=455-size[1];frame=Image.new('RGBA',(512,512),(0,0,0,0));frame.alpha_composite(crop,(x,y))
    path=framesdir/f'{state}_{c+1:03d}.png';atomic_image(frame,path);state_paths.append(str(path.relative_to(ART)))
    contact_crop=frame.resize((256,256),Image.Resampling.NEAREST);contacts.alpha_composite(contact_crop,(c*256,r*256))
    framealpha=frame.getchannel('A');edges={k:sum(v>0 for v in framealpha.crop(box).getdata()) for k,box in {'left':(0,0,4,512),'right':(508,0,512,512),'top':(0,0,512,4),'bottom':(0,508,512,512)}.items()}
    frames.append({'state':state,'frameIndex':c+1,'sourceCell':list(cellbox),'alpha16BBoxWithinCell':list(bbox),'alpha16Margins':margins,'normalizedSizePx':list(size),'scale':scale,'frameSHA256':sha(path),'edgeAlphaPixels4px':edges})
   entry['sequenceFrames'][state]=state_paths;entry['clips'][state]={'frames':state_paths,'fps':6 if state=='idle' else 8,'duration_seconds':0.5 if state=='idle' else 0.375,'frame_count':3,'loop':state=='idle','canvas_px':[512,512],'anchor':[256,455],'display_scale':1.0,'status':'UNAPPROVED_3X3_ATLAS_CANDIDATE','complete_animation':False}
  atomic_image(contacts.convert('RGB'),dest/'CONTACT_DARK.jpg',quality=95);overlay['entries'][actor]=entry
  manifest={'status':'UNAPPROVED_PARTIAL_MOTION_CANDIDATE','actorID':actor,'sourceStill':str(src.relative_to(ART)),'sourceStillSHA256':sha(src),'generatorAtlas':filename,'atlasSHA256':sha(raw),'atlasCanvasPx':list(im.size),'gridCuts':{'x':xs,'y':ys,'xGutters':xmeta,'yGutters':ymeta},'minimumCellAlpha16MarginPx':minimum,'states':STATES,'frames':frames,'darkContactSheet':str((dest/'CONTACT_DARK.jpg').relative_to(ROOT)),'limitations':['All poses remain unapproved generated candidates.','Clip naturalness and transition timing remain unverified.','Simulator playback and Human art review are pending.','Existing walk and attack sequences remain separately overlaid.']}
  atomic_bytes(dest/'manifest.json',json.dumps(manifest,ensure_ascii=False,indent=2).encode()+b'\n')
  summary.append({'actorID':actor,'candidateStates':STATES,'minimumCellAlpha16MarginPx':minimum,'outer4pxAlphaLeak':False,'atlasFile':filename,'contact':str((dest/'CONTACT_DARK.jpg').relative_to(ROOT))})
 atomic_bytes(ART/'runtime_overlay_zzz_r03r04_idle_hit_resolve_r001.json',json.dumps(overlay,ensure_ascii=False,indent=2).encode()+b'\n')
 print(json.dumps(summary,ensure_ascii=False))
if __name__=='__main__':main()

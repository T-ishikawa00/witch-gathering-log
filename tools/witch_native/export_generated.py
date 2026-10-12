from pathlib import Path
from PIL import Image
import json
ROOT=Path(__file__).resolve().parents[2]
source=ROOT/'native/GeneratedArt/enemy_r001'
overlay=json.loads((source/'runtime_index_overlay.json').read_text()); im=Image.open(source/overlay['selectedPNG'])
out=ROOT/'native/Art/GeneratedCandidates/ACT_E_R01_02';out.mkdir(parents=True,exist_ok=True)
paths={}
for name,data in overlay['poseStates'].items():
 x,y,w,h=data['sourceRectPixelsTopLeft'];tile=im.crop((x,y,x+w,y+h));p=out/(name+'.png');tile.save(p);paths[name]=str(p.relative_to(ROOT/'native/Art'))
states={'idle':(['idle_1','idle_2'],3,True),'walk':(['walk_1','walk_2'],6,True),'anticipate':(['idle_1','anticipate'],6,False),'execute':(['anticipate','execute'],8,False),'recover':(['execute','recover','idle_1'],8,False),'hit':(['hit','recover'],8,False),'resolve':(['hit','resolve'],3,False)}
entry={'selectedPNG':paths['idle_1'],'kind':'enemy_actor_kit','status':'GENERATED_POSE_CLIP_TEST_OVERLAY_NOT_ART_ACCEPTED','canvas_px':[512,341],'anchor':[256,330],'clips':{state:{'frames':[paths[f] for f in frames],'fps':fps,'loop':loop,'status':'DISCRETE_POSE_CANDIDATE_INBETWEENS_PENDING'} for state,(frames,fps,loop) in states.items()}}
# Separate additive runtime override keeps original index immutable.
(ROOT/'native/Art/generated_runtime_overlay.json').write_text(json.dumps({'entries':{'ACT_E_R01_02':entry},'status':'UNAPPROVED_TEST_OVERLAY','generated_source':str(source),'complete_animation':False},indent=2))
print('9 authored pose textures exported; 7 test state sequences; natural inbetweens remain pending')

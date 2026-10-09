"""Same rarity stream and inventory; change target role/copy capacity only."""
from after_draw_model import *
from run_study import stats
import json,time
out=ROOT/'results/TARGET_SENSITIVITY.json'
records={};t0=time.perf_counter();trials=items=0
for target in ['EQ_W_01','EQ_A_01','EQ_S_01','EQ_F_01','EQ_BODY_01','EQ_AMU_01']:
 for c in [candidates()[0],candidates()[2]]:
  keep=[];dust=[];q2=[]
  old=profile('established_box');known={x.template_id for x in old}
  for seed in range(450001,450501):
   n=1500//c.yen_equivalent_per_pull;new=Generator(c,seed,target,known=known).draw(n);p=offer_cleanup(old,new)
   ids=set(p['ids']);keep.append(n-len(ids));dust.append(sum([1,2,4,0,0][x.quality] for x in new if x.uid in ids));q2.append(sum(x.quality>=2 for x in new));trials+=1;items+=n
  records[target+'|'+c.id[0]]={'target_name':GEAR[target]['name'],'compatible_actor_count':len(GEAR[target]['actors']),'n':len(keep),'retained':stats(keep),'powder_low':stats(dust),'plus3_rate':sum(d>=30 for d in dust)/len(dust),'high_mean':sum(q2)/len(q2)}
out.write_text(json.dumps({'scope':'Target/copy-capacity sensitivity; 500 shared seeds across six targets and two plans. Same initial9-template fixture, not independent users or combat stats.','sessions':trials,'drawn_items':items,'records':records,'seconds':time.perf_counter()-t0},ensure_ascii=False,indent=2)+'\n')
for k,v in records.items():print(k,round(v['retained']['mean'],2),round(v['powder_low']['mean'],2),v['plus3_rate'])

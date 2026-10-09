"""Post-primary sensitivity: do not assume experienced players hoard low spares."""
from after_draw_model import *
from run_study import stats
out=ROOT/'results/INVENTORY_SENSITIVITY.json'
records={}
for mode in ('equipped_q2_only','one_low_spare_per_type','full_low_spares'):
 full=profile('established_box');eq=[x for x in full if x.equipped]
 if mode=='equipped_q2_only':old=eq
 elif mode=='full_low_spares':old=full
 else:old=eq+[x for x in full if not x.equipped and x.uid.endswith(':0')]
 for c in (candidates()[0],candidates()[2]):
  dust=[];keeps=[]
  for seed in range(460001,461001):
   new=Generator(c,seed,known={x.template_id for x in old}).draw(1500//c.yen_equivalent_per_pull);p=offer_cleanup(old,new);ids=set(p['ids'])
   dust.append(sum([1,2,4,0,0][x.quality] for x in new if x.uid in ids));keeps.append(len(new)-len(ids))
  records[mode+'|'+c.id[0]]={'existing_items':len(old),'retained_new':stats(keeps),'powder':stats(dust),'plus3_rate':sum(d>=30 for d in dust)/len(dust)}
out.write_text(json.dumps({'status':'POST_PRIMARY_SENSITIVITY_NOT_NEW_PRIMARY','scope':'SameQ2 equipped20, vary low spare stock. Same1000seeds acrosscases. Does not assume actual player behavior.','sessions':6000,'records':records},ensure_ascii=False,indent=2)+'\n')
for k,v in records.items():print(k,v['existing_items'],round(v['retained_new']['mean'],2),round(v['powder']['mean'],2),v['plus3_rate'])

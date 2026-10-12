from bootstrap import *
from fixtures_r6 import *
from support_ai_b import *
import sys,time,json,statistics
name=sys.argv[1]
pol=POLICIES['timed_support'] if name=='coordinated_full' else CANDIDATES['healing_ward_only']
rows=[];start=time.time()
for kind,h,p in [('protect',6,190),('offense',6,190),('protect',12,209)]:
 s=make_state(kind,h);t=upgrade(s);rs=[]
 for seed in range(300001,300101):
  pair=[]
  for st in [s,t]:pair.append(CoordinatedBattleR6(st.loadout(),boss_variant('redistribute_pause',p),seed,support_policy=pol).run()['outcome'])
  rs.append({'seed':seed,'before':pair[0],'after':pair[1]})
 row={'policy':name,'kind':kind,'hours':h,'power':p,'n':100,'before':sum(x['before']=='VICTORY' for x in rs),'after':sum(x['after']=='VICTORY' for x in rs),'win_to_loss':[x['seed'] for x in rs if x['before']=='VICTORY' and x['after']!='VICTORY'],'loss_to_win':sum(x['before']!='VICTORY' and x['after']=='VICTORY' for x in rs),'rows':rs};rows.append(row);print({k:v for k,v in row.items() if k!='rows'},flush=True)
s=make_state();t=upgrade(s);known=[]
for seed in [100049,100069]:known.append({'seed':seed,'before':CoordinatedBattleR6(s.loadout(),boss_variant('redistribute_pause'),seed,support_policy=pol).run()['outcome'],'after':CoordinatedBattleR6(t.loadout(),boss_variant('redistribute_pause'),seed,support_policy=pol).run()['outcome']})
(ROOT/'results'/f'DEV_{name}.json').write_text(json.dumps({'policy':name,'rows':rows,'known_cases':known,'seconds':time.time()-start,'development_only':True},indent=2));print(known)

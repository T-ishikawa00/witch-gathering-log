from bootstrap import *
from fixtures_r6 import *
from selected_final import FinalBattleR6
import json,copy,time
from collections import Counter

rows=[];start=time.time()
intro=intro_state();zero=copy.deepcopy(intro);zero.eco.roster_xp={aid:0 for aid in zero.eco.roster_xp};zero.equip('grant:C_WITCH','C_WITCH')
joined,_=post_miniboss()
cases=[('intro_lv6',intro,LOCAL['bosses']['B_R01_A'],set()),('start_lv1',zero,LOCAL['bosses']['B_R01_A'],set()),('joined_no_equipment',joined,boss_variant('redistribute_pause'),set()),('protect24',make_state('protect',24),boss_variant('redistribute_pause'),set()),('offense24',make_state('offense',24),boss_variant('redistribute_pause'),set()),('protect6_no_support',make_state(),boss_variant('redistribute_pause'),{'heal','ward','cover','counter','echo'})]
for label,state,boss,off in cases:
 for model,cls in [('r5',BattleR5),('r6b',FinalBattleR6)]:
  rs=[cls(state.loadout(),boss,seed,disabled=off).run() for seed in range(970001,970101)]
  row={'case':label,'model':model,'n':len(rs),'wins':sum(r['outcome']=='VICTORY' for r in rs),'outcomes':dict(Counter(r['outcome'] for r in rs)),'disabled':sorted(off),'boss':boss}
  rows.append(row);print(label,model,row['wins'],flush=True)
# Exact intro state with no support roles: no scheduling benefit accidentally introduced.
parity=[]
for seed in [970001,970002,970003]:
 a=BattleR5(intro.loadout(),LOCAL['bosses']['B_R01_A'],seed,True).run()
 b=FinalBattleR6(intro.loadout(),LOCAL['bosses']['B_R01_A'],seed,True).run()
 parity.append({'seed':seed,'log_equal':a['log']==b['log'],'hash_r5':a['log_sha256'],'hash_r6b':b['log_sha256']})
assert all(x['log_equal'] for x in parity)
(ROOT/'results/CONTROL_RESULTS.json').write_text(json.dumps({'battle_count':1200,'parity_battles':6,'cases':rows,'intro_exact_log_parity':parity,'wall_seconds':time.time()-start},ensure_ascii=False,indent=2))

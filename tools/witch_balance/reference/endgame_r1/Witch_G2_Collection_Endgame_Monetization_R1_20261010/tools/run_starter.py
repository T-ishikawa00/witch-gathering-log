"""Scope: exploratory comparison only, new starter-choice is not approved.
Same free10/bought10 stream before additional deterministic chosen SR amulet.
Uses original R6-B and H1; original no-gacha data untouched.
"""
from lab import *
from contracts import starter_choice
import argparse,statistics
ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);args=ap.parse_args();args.output.mkdir(exist_ok=False,parents=True)
rows=[];inputs=[]
for ls in range(12):
 s=b.build_state('fresh',0,'starter-value:'+str(ls));s.craft('EQ_A_01','starter:book','starter:craft',seed='starter:book'+str(ls));s.equip('starter:book','C_APPRENTICE');s.enhance('intro:relic','starter:first-enhance')
 draw=b.DrawBridge(b.C,'starter-value-draw:'+str(ls),s,affix_mode='growth',target='EQ_W_01').draw(20)
 for count,extra,label in [(10,False,'FREE10'),(20,False,'OLD_STARTER20'),(20,True,'CHOICE_STARTER21')]:
  st=copy.deepcopy(s);b.accept_draws(st,draw[:count],label)
  if extra:
   it=starter_choice('EQ_AMU_01','lab:'+str(ls));st.items[it.uid]=it
  with patch.object(b,'P',old.RarityRules(g,multipliers=old.MODELS['H1_RECOMMENDED'])):
   b.recommend_equipment(st);b.spend_for_enhancement(st,'after')
  inputs.append({'loot_seed':ls,'label':label,'items':[asdict(it) for it in st.items.values()],'loadout':[asdict(p) for p in st.loadout()],'remaining_powder':st.eco.dust})
  for cs in range(730000,730008):
   with patch.object(precision_rules,'PrecisionRules',partial(old.RarityRules,multipliers=old.MODELS['H1_RECOMMENDED'])):
    r=b.FinalBattleR6(st.loadout(),b.boss_variant('redistribute_pause'),cs).run()
   rows.append({'loot_seed':ls,'battle_seed':cs,'label':label,'outcome':r['outcome'],'elapsed_ms':r['elapsed_ms']})
summary=[]
for label in ('FREE10','OLD_STARTER20','CHOICE_STARTER21'):
 r=[x for x in rows if x['label']==label];wins=[x for x in r if x['outcome']=='VICTORY']
 summary.append({'label':label,'wins':len(wins),'n':len(r),'median_win_seconds':statistics.median(x['elapsed_ms']/1000 for x in wins) if wins else None})
(args.output/'ROWS.json').write_text(json.dumps(rows,indent=2));(args.output/'INPUTS.json').write_text(json.dumps(inputs,ensure_ascii=False,indent=2));(args.output/'SUMMARY.json').write_text(json.dumps(summary,indent=2));print(summary)

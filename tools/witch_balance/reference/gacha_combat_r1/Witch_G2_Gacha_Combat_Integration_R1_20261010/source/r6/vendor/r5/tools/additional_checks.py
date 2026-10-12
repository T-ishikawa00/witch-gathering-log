from compare_candidates import *
from run_holdout import expanded_stats
from dataclasses import asdict,replace
from progression_r5 import *
import csv

def main():
    cells=[];rows=[]
    def run(name,party,model,seeds):
        results=[]
        for seed in seeds:
            q=(LegacyBattle(party,LOCAL['bosses']['B_R01_B'],seed) if model=='r4' else BattleR5(party,boss_variant('redistribute_pause'),seed)).run();results.append(q)
            rows.append({'cell':name,'model':model,'seed':seed,'outcome':q['outcome'],'elapsed_ms':q['elapsed_ms']})
        rec={'label':name,'model':model,**expanded_stats(results)};cells.append(rec);print(name,rec['wins'],'/',rec['n'],flush=True)
    s=prepared_at('protect',6)
    for aid in s.equipped:s.equipped[aid]=[u for u in s.equipped[aid] if not u.startswith('craft:')]
    for i,aid in enumerate(['C_WITCH','C_APPRENTICE','C_SMITH','C_FAMILIAR']):s.equip(f'craft:{i}',aid)
    run('r5_same_four_reallocated_6h',s.loadout(),'r5',range(100001,100201))
    s,_=post_miniboss();s.advance(6*3600000)
    run('r5_6h_resources_unspent',s.loadout(),'r5',range(100001,100201))
    # Variance check: these seeds do not tune the selected design.
    st=prepared_at()
    for cseed in range(20):
        s=copy.deepcopy(st)
        for i in range(4):
            uid=f'craft:{i}';old=s.items[uid];s.items[uid]=g.create_item(uid,old.template_id,'Q2',seed='r5-craft-holdout-'+str(cseed),crafted=True)
        for model in ['r4','r5']:run(f'{model}_craft_roll_{cseed}',s.loadout(),model,range(200001,200021))
    # Actual R5 boar -> payment -> R5 tree victory -> idempotent commit.
    s=prepare_r5(12);q,receipt=s.battle('B_R01_B',100001,True);before=s.inventory_hash()
    assert q['outcome']=='VICTORY';s.commit_victory(receipt);after=s.inventory_hash();s.commit_victory(receipt);assert s.inventory_hash()==after
    evidence={'receipt':receipt,'before':before,'after':after,'repeat_identical':True,'materials':s.eco.materials,'gates':sorted(s.gates),'spent_materials':s.spent_materials,'spent_dust':s.spent_dust,'xp':s.eco.roster_xp,'history':s.history,'limits':'Onboarding totals/deep survey still fixtures, not normal-enemy fights; in-memory commit, not database or cryptographic trust.'}
    (OUT/'R5_PROGRESSION_RECEIPT.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2))
    (OUT/'GOLDEN_R5_TREE.json').write_text(json.dumps(q,ensure_ascii=False,indent=2))
    q=BattleR5(intro_state().loadout(),LOCAL['bosses']['B_R01_A'],100001,True).run()
    (OUT/'GOLDEN_R5_BOAR.json').write_text(json.dumps(q,ensure_ascii=False,indent=2))
    (OUT/'ADDITIONAL_RESULTS.json').write_text(json.dumps({'cells':cells,'battle_count':len(rows),'seed_ranges':{'paired_6h':[100001,100200],'gear_variation':[200001,200020]},'note':'Secondary checks after profile lock; no retuning'},ensure_ascii=False,indent=2))
    with (OUT/'ADDITIONAL_BATTLE_ROWS.csv').open('w',newline='',encoding='utf-8-sig') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
if __name__=='__main__':
    from datetime import datetime,timezone
    import argparse
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path);args=ap.parse_args()
    OUT=args.output.resolve() if args.output else ROOT/'reruns'/datetime.now(timezone.utc).strftime('additional_%Y%m%dT%H%M%S_%fZ')
    if OUT.resolve()==(ROOT/'results').resolve():ap.error('Choose a new output directory')
    OUT.mkdir(parents=True,exist_ok=True);main()

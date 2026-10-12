from bootstrap import *
from pathlib import Path
import json,csv,hashlib,statistics,math

def wilson(w,n):
    z=1.96;p=w/n;d=1+z*z/n;m=(p+z*z/2/n)/d;h=z*math.sqrt(p*(1-p)/n+z*z/(4*n*n))/d
    return [max(0,m-h),min(1,m+h)]

def summarize_dir(name,newmodel):
    files=sorted((ROOT/'results'/name).glob('*.json'));cells=[];flat=[];pool=[]
    for f in files:
        x=json.loads(f.read_text());flat+=x['rows'];job=x['job']
        for pair in x['paired']:
            row={'stage':newmodel,'job':job['id'],'set':job['set'],'kind':job['kind'],'hours':job['hours'],'power':job['power'],'hp_bp':job['hp_bp'],'model':pair['model'],'upgrade':pair['upgrade'],'n':pair['n'],'wins_before':pair['wins_before'],'wins_after':pair['wins_after'],'win_to_loss':len(pair['win_to_loss']),'loss_to_win':len(pair['loss_to_win']),'win_rate_after_wilson95':wilson(pair['wins_after'],pair['n'])}
            pool.append(row)
        for model in ['r5',newmodel]:
            for up in ['before',*job['upgrades']]:
                rs=[r for r in x['rows'] if r['model']==model and r['upgrade']==up]
                winners=[r for r in rs if r['outcome']=='VICTORY']
                cells.append({'job':job['id'],'set':job['set'],'kind':job['kind'],'hours':job['hours'],'power':job['power'],'hp_bp':job['hp_bp'],'model':model,'upgrade':up,'n':len(rs),'wins':len(winners),'win_rate':len(winners)/len(rs),'wilson95':wilson(len(winners),len(rs)),'median_win_seconds':statistics.median(r['elapsed_ms']/1000 for r in winners) if winners else None,'mean_heal_casts':statistics.mean(r['heal_casts'] for r in rs),'mean_cover_casts':statistics.mean(r['cover_casts'] for r in rs),'mean_ward_casts':statistics.mean(r['ward_casts'] for r in rs),'mean_unused_expired_barrier':statistics.mean(r['barrier_expired_unused']/10000 for r in rs)})
    totals={}
    for group in ['legacy_replay','heldout_combat_seeds','heldout_gear_and_combat']:
        totals[group]={}
        for model in ['r5',newmodel]:
            pp=[r for r in pool if r['set']==group and r['model']==model]
            totals[group][model]={'upgrade_comparisons':sum(r['n'] for r in pp),'win_to_loss':sum(r['win_to_loss'] for r in pp),'loss_to_win':sum(r['loss_to_win'] for r in pp)}
    return {'files':len(files),'battles':len(flat),'totals':totals,'paired':pool,'cells':cells},flat

A,arows=summarize_dir('validation_cells','r6');B,brows=summarize_dir('validation_b_cells','r6b')
assert A['files']==B['files']==15
controls=json.loads((ROOT/'results/CONTROL_RESULTS.json').read_text())
source=json.loads((ROOT/'data/SOURCE_LOCK_R6.json').read_text());mismatches=[]
for e in source['vendor_files']:
    if hashlib.sha256((ROOT/e['path']).read_bytes()).hexdigest()!=e['sha256']:mismatches.append(e['path'])
known=json.loads((ROOT/'results/BASELINE_REPRODUCTION.json').read_text())
remaining=json.loads((ROOT/'results/RESIDUAL_DIAGNOSES.json').read_text())
for e in remaining['entries']:assert e['before']['outcome']=='VICTORY' and e['after']['outcome']!='VICTORY'
summary={'status':'R6B_PREFERRED_REVIEW_CANDIDATE_WITH_RESIDUAL_REVERSALS','baseline_exact_log_reproduction':known,'known_two_reproduced_and_r6b_both_sides_win':True,'first_stage':A,'second_stage':B,'controls':controls,'completed_comparison_battles':A['battles']+B['battles'],'control_battles':controls['battle_count'],'exact_parity_extra_battles':controls['parity_battles'],'r6a_contract_tests':60,'r6b_contract_tests':30,'legacy_tests':{'R2':55,'R3':61,'R4':53,'R5':48},'source_preservation':{'files':len(source['vendor_files']),'mismatches':mismatches},'unresolved':{'F07_known_original_two':'CLOSED_IN_THIS_REFERENCE_INPUT','F07_general_pure_upgrade_reversal':'OPEN:6/2000 main heldout comparisons in B','F08_cross_loadout_winrate_dominance':'NOT_PROVED:one of ten held-out craft seeds is worse under B than R5','F09_complete_release_quality':'NOT_TESTED'},'limits':['R01 two bosses only; no multiple-enemy/late-awakening/region02-05 run','10 crafting seeds and50 repeated combat seeds are a clustered design, not2000 independent users','Same seed does not hold identical target sequence after one actor dies; report paired simulation, not causality of every event','R6B was locked after R6A holdout findings; B uses fresh900001..900500 and950001..950050 ranges','Stats, enemy patterns, costs, rewards, attack/cast/CD times unchanged; same-ms AI planning order deliberately changed','No production/GitHub/Mac writes, device, real DB or human playtest'],'production_approved':False}
(ROOT/'results/VALIDATION_SUMMARY_R6.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
for name,rows in [('PAIRED_SUMMARY_R6A.csv',A['paired']),('PAIRED_SUMMARY_R6B.csv',B['paired']),('BATTLE_ROWS_R6B.csv',brows)]:
    with (ROOT/'results'/name).open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
print(json.dumps({'A':A['battles'],'B':B['battles'],'B_totals':B['totals'],'controls':controls['battle_count'],'source':summary['source_preservation'],'residuals':remaining['count']},ensure_ascii=False,indent=2))

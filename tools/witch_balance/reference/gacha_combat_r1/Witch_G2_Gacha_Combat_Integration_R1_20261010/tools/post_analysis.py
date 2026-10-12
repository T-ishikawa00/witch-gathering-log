from bridge import *
import csv,gzip,statistics
R=ROOT/'results/main'
def dump(p,o):p.write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n')
def main():
    rows=list(csv.DictReader((R/'BATTLE_ROWS.csv').open(encoding='utf-8-sig')));ix={(x['case'],x['arm'],x['stage'],x['acquisition'],x['seed']):x for x in rows}
    neg=[];pos=[];speed=defaultdict(list)
    for x in rows:
        if x['stage']=='FULL':
            before=ix[x['case'],x['arm'],'EQUIP',x['acquisition'],x['seed']]
            if before['outcome']=='VICTORY' and x['outcome']!='VICTORY':neg.append(x)
            if before['outcome']!='VICTORY' and x['outcome']=='VICTORY':pos.append(x)
            base=ix[x['case'],'NO_GACHA','BASE',x['acquisition'],x['seed']]
            if base['outcome']==x['outcome']=='VICTORY':speed[x['case'],x['arm']].append(float(base['elapsed_ms'])-float(x['elapsed_ms']))
    byq=defaultdict(list);baseline=[];hidden=[]
    with gzip.open(R/'SCENARIOS_AND_DRAWS.jsonl.gz','rt') as f:
        for line in f:
            rec=json.loads(line);baseline.append({'case':rec['case']['id'],'acquisition':rec['acquisition'],'natural_items':rec['initial']['natural_items'],'dust_before':rec['initial']['dust'],'spent_before_gacha':rec['baseline_spend']['spent'],'equipped_slots_before_gacha':sum(len(p['items']) for p in rec['baseline']['loadout'])})
            for a in rec['arms']:
                arm=a['definition']['id'];count=Counter(it['quality'] for p in a['full_state']['loadout'] for it in p['items'] if it['uid'].startswith('gacha:'))
                byq[rec['case']['id'],arm].append(count)
                if len(hidden)<3 and a['cleanup']['hidden_future_difference_ids']:
                    uid=a['cleanup']['hidden_future_difference_ids'][0];wi=a['cleanup']['witnesses'][uid][0]
                    di={x['item']['uid']:x['item'] for x in a['draws']};original={it['uid']:it for p in rec['baseline']['loadout'] for it in p['items']}
                    if wi in di:
                        hidden.append({'case':rec['case']['id'],'arm':arm,'acquisition':rec['acquisition'],'discarded':di[uid],'retained':di[wi], 'note':'Same current visible qualities/effects, but different latent slots. Selection did not inspect hidden values; no guarantee of future optimality.'})
    data={'enhancement_after_equipping_pairs':sum(x['stage']=='FULL' for x in rows),'equip_loss_to_full_win':len(pos),'equip_win_to_full_loss':len(neg),'regressions':neg,
        'mean_new_equipped_by_quality':[{'case':k[0],'arm':k[1],'acquisition_count':len(v),'means':{q:statistics.mean(c[q] for c in v) for q in ('Q0','Q1','Q2','Q3','Q4')}} for k,v in byq.items()],
        'paired_clear_time_changes_both_win_only':[{'case':k[0],'arm':k[1],'n':len(v),'median_saved_seconds':statistics.median(v)/1000,'mean_saved_seconds':statistics.mean(v)/1000,'slower_after_count':sum(x<0 for x in v)} for k,v in speed.items()],
        'baseline_inventory_use':baseline,'hidden_future_disposal_examples':hidden,
        'interpretation':'No regression in this newly sampled first-region matrix is NOT resolution of the historical R6 six/2000 failures. Strong prepared controls saturate victory.'}
    dump(ROOT/'results/POST_ANALYSIS.json',data)
    # Declared post-hoc mechanism diagnostic, not used to select probabilities.
    tests=[];wins=0
    for index in range(24):
        s=build_state('fresh',0,'integration-heldout-economy-'+str(index));recommend_equipment(s);spend_for_enhancement(s,'original-powder')
        draws=DrawBridge(C,'integration-heldout-draw-'+str(index),s).draw(50)
        # Intentionally counterfactual: SAME drawn types; all new qualities Q0.
        # No scrap/enhance to isolate base gear/empty-slot coverage.
        draws=[{**r,'item':replace(r['item'],quality='Q0',locked=False)} for r in draws]
        accept_draws(s,draws,'mechanism-all-Q0');recommend_equipment(s)
        for j in range(8):
            seed=1700001+index*100+j;res=battle(s,seed);wins+=res['outcome']=='VICTORY'
            tests.append({'acquisition':index,'seed':seed,'outcome':res['outcome'],'elapsed_ms':res['elapsed_ms']})
    dump(ROOT/'results/POSTHOC_ALL_COMMON_DIAGNOSTIC.json',{'label':'mechanism_probe_not_a_sellable_gacha_rule','description':'FRESH4, same C50 template draws converted to Q0, no new-powder upgrades; baseline items unchanged. Shows basic-slot filling contribution, not isolated causal estimate in real players.','battles':len(tests),'wins':wins,'rows':tests})
    print('After-equip->upgrade',len(pos),'improve',len(neg),'regress; allcommon diagnostic',wins,'/',len(tests))
if __name__=='__main__':main()

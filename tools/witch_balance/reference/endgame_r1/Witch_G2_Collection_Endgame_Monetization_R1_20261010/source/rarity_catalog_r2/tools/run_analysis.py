"""Reproducible single-variable sensitivity + catalogue quantities, not sales forecast."""
from model import *
from dataclasses import replace
from collections import Counter
import statistics,time,csv

def write(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n')

def main(out):
    t=time.monotonic()
    # Exact parameter invariants, full legal enhancement domain.
    comparisons=0
    for tid in b.g.GEAR:
        initial=b.g.create_item('check:'+tid,tid)
        for rank,r in b.g.RANKS.items():
            for en in range(r['max_enhance']+1):
                previous=None
                for q in range(5):
                    it=replace(initial,rank=rank,enhancement=en,quality='Q'+str(q))
                    h0=RarityRules(b.g,multipliers=MODELS['H0_EXISTING']).item_primary(it)
                    assert h0==b.P.item_primary(it)
                    h1=RarityRules(b.g,multipliers=MODELS['H1_RECOMMENDED']).item_primary(it)
                    if previous:
                        assert all(h1[s]>previous[s] if previous[s]>0 else h1[s]==0 for s in previous)
                    previous=h1;comparisons+=1
    example=[]
    for tid in ['EQ_W_01','EQ_BODY_01']:
        item=b.g.create_item('example',tid)
        for q in range(5):
            it=replace(item,quality='Q'+str(q))
            example.append({'template':tid,'quality':it.quality,'H0':{k:v/10000 for k,v in b.P.item_primary(it).items()},'H1':{k:v/10000 for k,v in RarityRules(b.g,multipliers=MODELS['H1_RECOMMENDED']).item_primary(it).items()}})
    # Quality-only base contribution: same item source, latent rolls fixed;
    # final actor values include changing active affix counts. Show separately.
    single=b.g.create_item('example:wand','EQ_W_01')
    stat_examples=[]
    for model in MODELS:
        rule=RarityRules(b.g,multipliers=MODELS[model])
        for lev in [6,60]:
            for rank in ([1] if lev==6 else [5]):
                for q in [0,4]:
                    it=replace(single,quality='Q'+str(q),rank=rank)
                    st=rule.actor_stats('C_WITCH',lev,[it])
                    stat_examples.append({'model':model,'level':lev,'rank':rank,'quality':it.quality,'raw_base_power':b.g.ACTORS['C_WITCH']['base']['power']+b.g.ACTORS['C_WITCH']['per_level']['power']*(lev-1),'weapon_primary':rule.item_primary(it)['power']/10000,'final_power_including_affixes':st['power']/10000,'latent':asdict(it)})
    # Cases fixed before running, no reverse target tuning.
    records=[];snapshots=[]
    for case in ['JOINED_C50','SIX_HOUR_NO_GACHA','SIX_HOUR_C50']:
        for lootseed in range(61001,61009):
            state=prepare_case(case,lootseed)
            snapshots.append({'case':case,'loot_seed':lootseed,'state':b.state_record(state)})
            h=state.inventory_hash()
            for seed in range(71001,71009):
                for model in MODELS:
                    r=battle_with_rarity(state,seed,model)
                    records.append({'case':case,'loot_seed':lootseed,'combat_seed':seed,'model':model,'outcome':r['outcome'],'elapsed_ms':r['elapsed_ms'],'boss_remaining_hp':r['boss_remaining_hp'],'fingerprint':r['input_fingerprint']})
            assert state.inventory_hash()==h
        print(case,'done',flush=True)
    roll=[]
    for case in sorted({x['case'] for x in records}):
        for model in MODELS:
            a=[r for r in records if r['case']==case and r['model']==model];win=[r['elapsed_ms']/1000 for r in a if r['outcome']=='VICTORY']
            roll.append({'case':case,'model':model,'n':len(a),'wins':len(win),'median_victory_seconds':statistics.median(win) if win else None})
    # Also compare state identical old PrecisionRules vs H0 output.
    st=prepare_case('SIX_HOUR_NO_GACHA',61001)
    old=b.battle(st,71001,record=True);new=battle_with_rarity(st,71001,'H0_EXISTING',True)
    assert old['log']==new['log'] and old['outcome']==new['outcome']
    write(out/'H0_REPLAY_CHECK.json',{'exact_log_match':True,'case':'SIX_HOUR_NO_GACHA','loot_seed':61001,'combat_seed':71001,'old_log_sha':digest(old['log']),'H0_log_sha':digest(new['log'])})
    write(out/'RARITY_RESULTS.json',{'static_states':comparisons,'battle_count':len(records),'summary':roll,'item_examples':example,'actor_examples':stat_examples,'scope':'Fixed first-forest loadouts, eight loot fixtures and eight combat seeds per case. Equipment selector frozen to original H0. Not universal monotonicity, full progression, all 33-template combat, or payer behaviour.'})
    write(out/'BATTLE_INPUTS.json',snapshots)
    with (out/'BATTLE_ROWS.csv').open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(records[0]));w.writeheader();w.writerows(records)
    # Product quantity projection. Same known daily participation; no assumed region time.
    projections=[]
    from compare_gacha import selected_top_pmf
    target_pmf=selected_top_pmf(b.C)
    for days in [30,90]:
        for name,(buy,ads) in personas(days).items():
            p=plan_projection(buy,days)
            p.update({'persona':name,'free_tickets':days*5,'total_gacha_pulls_if_all_used':days*5+p['tickets_from_products'],'natural_equipment_items_at24h':48*days,'ads_or_skip_offers_used_in_scenario':days*3 if ads else 0,'ad_xp_dust_bonus_ratio':1/16 if ads else 0.,'ad_policy_source':'R3 offers from complete 8h blocks; same reward for view/skip; no equipment/material/ticket bonus','starting_grants_and_boss_tickets_excluded':True})
            n=p['total_gacha_pulls_if_all_used'];p['expected_LR_from_gacha_with_empty_pity']=top_expectation(n)
            p['prob_first_selected_LR_by_all_draws_same_target']=min(1.,sum(target_pmf[:n]))
            projections.append(p)
    write(out/'CATALOG_PROJECTIONS.json',{'rows':projections,'not_measured':['revenue','retention','conversion','30/90-day region progression','actual time to free bonus cap','full offline scheduling across devices'],'assumptions':['continuous24h exploration with daily settlement','5 free vouchers/day; no initial/boss grants in totals','products purchased at fixed listed schedules; no real user prediction','all vouchers used on same eligible target; selection guarantee follows original C','no cosmetics grant vouchers','same loaded rates/odds for all audiences'],'cosmetics_catalog_one_time_total_jpy':sum(p['price_jpy'] for p in PRODUCTS.values() if p.get('power_score_if_separately_approved'))})
    promotion=b.g.DATA['equipment_rules']['quality_upgrades'];powder_rate=b.e.RATES['R05']['dust_per_work']*12
    write(out/'OPEN_BALANCE_WARNINGS.json',{'quality_upgrade_costs':promotion,'R05_powder_per_hour':powder_rate,'UR_to_LR_single_hours_if_all_powder':promotion[-1]['dust']/powder_rate,'UR_to_LR_24_slots_hours_if_all_powder':promotion[-1]['dust']*24/powder_rate,'C_to_LR_24_slots_hours_if_all_powder':sum(x['dust'] for x in promotion)*24/powder_rate,'SR_to_LR_24_slots_hours_if_all_powder':sum(x['dust'] for x in promotion[2:])*24/powder_rate,'scope':'Powder-only arithmetic at existing gates, not calendar-clear forecast; no conflicting powder spend or salvage included. Rarity boost makes old promotion costs a new economy decision. Do not silently nerf free progression.'})
    print('battles',len(records),'static states',comparisons,'seconds',round(time.monotonic()-t,2),flush=True)

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();out=a.output.resolve()
    if out.exists() and any(out.iterdir()):p.error('Output must be new or empty; preserve evidence.')
    out.mkdir(parents=True,exist_ok=True);main(out)

"""R4 after-draw experiments; sources are frozen, output must be empty."""
from after_draw_model import *
import argparse,csv,math,statistics,time

def percentile(xs,p):
    x=sorted(xs)
    if not x:return None
    i=(len(x)-1)*p;lo=int(i);return x[lo]+(x[min(lo+1,len(x)-1)]-x[lo])*(i-lo)
def mean(xs):return statistics.mean(xs)
def stats(xs):return {'mean':mean(xs),'p10':percentile(xs,.1),'p50':percentile(xs,.5),'p90':percentile(xs,.9),'min':min(xs),'max':max(xs)}
def wilson(k,n):
    z=1.96;p=k/n;den=1+z*z/n;mid=(p+z*z/(2*n))/den;half=z*math.sqrt(p*(1-p)/n+z*z/(4*n*n))/den
    return [mid-half,mid+half]
def aggregate(rows):
    out={'sessions':len(rows),'quality_mean':[mean([r['quality_counts'][i] for r in rows]) for i in range(5)]}
    for key in ('draws','retained','offered_for_optional_scrap','retained_low','higher_quality_for_review','new_types','same_quality_affix_noninferior_candidates'):
        out[key]=stats([r[key] for r in rows])
    for name in ('target_legendary','no_new_type_high_or_plus1'):
        k=sum(bool(r[name]) for r in rows);out[name]={'count':k,'rate':k/len(rows),'wilson95':wilson(k,len(rows))}
    out['powder']={k:stats([r['powder'][k] for r in rows]) for k in PLAN['powder_schedules']}
    out['progress']={k:{'mean_steps':mean([r['enhancement_probe'][k]['affordable_steps'] for r in rows]),'at_least_plus1_rate':mean([r['powder'][k]>=5 for r in rows]),'one_plus3_rate':mean([r['powder'][k]>=30 for r in rows]),'three_plus3_rate':mean([r['powder'][k]>=90 for r in rows])} for k in PLAN['powder_schedules']}
    out['protected_offered_total']=sum(r['proof_protected_offered'] for r in rows)
    return out

def storage_probe(c,seed):
    rng=rng_for(seed,'natural');rg=rng_for(seed,'daily');s=Counters();miss=0;naturalhigh=gachahigh=0;rows=[]
    for day in range(1,31):
        for _ in range(48):
            z=rng.randrange(10000)
            if miss==99:q=4
            elif z<100:q=4
            elif z<700:q=3
            elif z<2500:q=2
            elif z<5500:q=1
            else:q=0
            miss=0 if q==4 else miss+1;naturalhigh+=q>=2
        for _ in range(c.free_pulls_per_day):
            q,t,s=step(c,s,rg.randrange(10000),rg.randrange(10000));gachahigh+=q>=2
        rows.append({'day':day,'natural_high':naturalhigh,'gacha_high':gachahigh,'held_high':naturalhigh+gachahigh})
    return rows

def main(out):
    t0=time.perf_counter();out.mkdir(parents=True,exist_ok=True)
    if any(out.iterdir()):raise ValueError('Output must be empty')
    allrows=[];summary={};secondary={};sample_cells={};cand={x.id:x for x in candidates()}
    chosen=[cand[x] for x in PLAN['primary']['candidates']]
    cells=[]
    for p in PLAN['primary']['profiles']:
        for c in chosen:cells.append(('budget1500',p,c,1500//c.yen_equivalent_per_pull,range(410001,412001)))
    for p in PLAN['daily']['profiles']:
        for c in chosen:cells.append(('daily',p,c,c.free_pulls_per_day,range(420001,421001)))
    for b in (300,6000):
        for c in chosen:cells.append((f'budget{b}','established_box',c,b//c.yen_equivalent_per_pull,range(430001,430501)))
    for scenario,p,c,n,seeds in cells:
        key=f'{scenario}|{p}|{c.id[0]}';rows=[];q2rows=[]
        for seed in seeds:
            r,new,proposal=summarize_session(c,seed,p,n);r['scenario']=scenario;rows.append(r);allrows.append(r)
            if scenario=='budget1500':
                r2,_,_=summarize_session(c,seed,p,n,2);q2rows.append(r2)
        summary[key]=aggregate(rows)
        if q2rows:secondary[key]=aggregate(q2rows)
        # Select a median-powder example without claiming typical in every dimension.
        median=summary[key]['powder']['low']['p50'];chosenrow=min(rows,key=lambda r:(abs(r['powder']['low']-median),r['seed']))
        ex,new,pq=summarize_session(c,chosenrow['seed'],p,n)
        sample_cells[key]={'summary':ex,'items':[i.as_json() for i in new],'existing':[i.as_json() for i in profile(p)],'proposal':pq,'selection_rule':'closest to cell median low-schedule powder, then smallest seed'}
        print(key,'keep',round(summary[key]['retained']['mean'],2),'powder',round(summary[key]['powder']['low']['mean'],2),'plus3',summary[key]['progress']['low']['one_plus3_rate'],flush=True)
    # Paired comparisons share stream seeds, not outcomes: different rarity tables.
    paired={}
    for p in PLAN['primary']['profiles']:
        a=[r for r in allrows if r['scenario']=='budget1500' and r['profile']==p and r['candidate'][0]=='A']
        c=[r for r in allrows if r['scenario']=='budget1500' and r['profile']==p and r['candidate'][0]=='C']
        a.sort(key=lambda r:r['seed']);c.sort(key=lambda r:r['seed'])
        d=[y['retained']-x['retained'] for x,y in zip(a,c)];paired[p]={'paired_retained_C_minus_A':stats(d),'mean_difference_95_normal_interval':[mean(d)-1.96*statistics.stdev(d)/math.sqrt(len(d)),mean(d)+1.96*statistics.stdev(d)/math.sqrt(len(d))]}
    storage={}
    for c in chosen:
        samples=[storage_probe(c,s) for s in range(440001,440501)]
        storage[c.id[0]]={'condition':'All Q2+ held, natural48/day + candidate free daily. No intro, paid, starting gear or retained low included. Fixed gates; not original economy.',
            'days':{str(d):{k:stats([s[d-1][k] for s in samples]) for k in ('natural_high','gacha_high','held_high')} for d in (7,30)},
            'first_over_capacity':{str(cap):{'reached':sum(any(x['held_high']>cap for x in s) for s in samples),'day_stats_if_reached':stats([next(x['day'] for x in s if x['held_high']>cap) for s in samples if any(x['held_high']>cap for x in s)])} for cap in (120,240)}}
    exact={}
    for c in chosen:
        n=1500//c.yen_equivalent_per_pull;counts=quality_horizons(c,[n])[n]['expected_quality_counts']
        exact[c.id[0]]={'quality_counts':counts,'all_low_discard_powder_upper':{k:counts[0]*v[0]+counts[1]*v[1] for k,v in PLAN['powder_schedules'].items()}}
    # Calculate human ranges from explicit assumptions; NOT observed users.
    time_assumptions=PLAN['ui']['human_timing_assumptions_seconds']
    times={}
    for key,cell in summary.items():
        n=cell['draws']['mean'];hi=cell['higher_quality_for_review']['mean'];lo=n-hi
        group_clicks=4 if cell['offered_for_optional_scrap']['max'] else 0
        # Two generic end actions: advance to forge and one displayed affordable enhancement; separate no-dust case.
        minimal_clicks=group_clicks+2
        high_checks=min(3,hi)
        def estimate(aggregated):
            values=[]
            for b in (0,1):
                base=time_assumptions['summary_read'][b]+time_assumptions['enhancement_decision'][b]
                if aggregated:sec=base+high_checks*time_assumptions['high_item_compare_each'][b]+minimal_clicks*time_assumptions['click_each'][b]+(time_assumptions['bulk_scrap_confirmation'][b] if group_clicks else 0)
                else:sec=base+hi*time_assumptions['high_item_compare_each'][b]+lo*time_assumptions['low_item_inspect_each'][b]+(2*n+2)*time_assumptions['click_each'][b]
                values.append(sec)
            return values
        times[key]={'grouped_first_pass_seconds_assumption':estimate(True),'all_individual_details_seconds_assumption':estimate(False),'scope':'first-pass <=3 highlighted high items; ALL others safely retained; not full curation. No animation/network time. No players measured.','grouped_click_path_upper_for_scrap_and_forge':minimal_clicks}
    results={'status':'AFTER_DRAW_REFERENCE_PROBE_NOT_FINAL_BALANCE','source_plan_sha256':digest(PLAN),'primary_summaries':summary,'optional_q2_duplicate_sensitivity':secondary,'paired':paired,'storage_pressure':storage,'analytic_quality_reference':exact,'human_time_model':times,
      'sessions':len(allrows),'mock_acquired_items':sum(r['draws'] for r in allrows),'secondary_repeated_sessions':sum(len(range(410001,412001)) for x in secondary),'secondary_scope':'same seeds redrawn for cleanup policy only; not new independent trials',
      'known_source_correction':{'file':'source/research_r3/tools/compare_gacha.py','original_fields':['forest_powder_per_day=144','ratio_to_R3_forest_144_per_day'],'rule':'12/hour * 24hours = 288/day. 144 is12hours, not24. Prior relative daily powder ratio had denominator2x too small. Absolute 1500yen low-powder counts unaffected.','source_edited':False},
      'limits':PLAN['not_tested'],'elapsed_seconds':time.perf_counter()-t0}
    (out/'ANALYSIS_R4.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
    (out/'FIXED_REVIEW_SAMPLES.json').write_text(json.dumps(sample_cells,ensure_ascii=False,indent=2)+'\n')
    # Full per-session outcomes can be independently re-aggregated.
    (out/'SESSION_ROWS.jsonl').write_text(''.join(json.dumps(x,ensure_ascii=False,separators=(',',':'))+'\n' for x in allrows))
    csvrows=[]
    for key,s in summary.items():
        csvrows.append({'cell':key,'n':s['sessions'],'draws':s['draws']['mean'],'retained':s['retained']['mean'],'offered':s['offered_for_optional_scrap']['mean'],'retained_low':s['retained_low']['mean'],'q2plus':s['higher_quality_for_review']['mean'],'powder_low_mean':s['powder']['low']['mean'],'powder_low_p10':s['powder']['low']['p10'],'powder_low_p90':s['powder']['low']['p90'],'plus3_rate_low':s['progress']['low']['one_plus3_rate'],'target_legendary_rate':s['target_legendary']['rate'],'no_new_type_high_plus1_rate':s['no_new_type_high_or_plus1']['rate']})
    with (out/'COMPARISON.csv').open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(csvrows[0]));w.writeheader();w.writerows(csvrows)
    print('DONE',len(allrows),'sessions',results['mock_acquired_items'],'items',results['elapsed_seconds'],flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);a=p.parse_args();main(a.output)

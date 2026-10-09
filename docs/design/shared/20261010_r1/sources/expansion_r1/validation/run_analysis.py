"""Exact probability/scope arithmetic for design discussion, not live game metrics."""
from pathlib import Path
from fractions import Fraction
import json,sys
from expansion_model import high_pity_mean, high_pity_distribution
ROOT=Path(__file__).resolve().parents[1]

def percentile_first_high(p,n,q):
    acc=Fraction(0)
    for i,w in enumerate(high_pity_distribution(p,n),1):
        acc+=w
        if acc>=q:return i

p=Fraction(1,100);n=100;mean=high_pity_mean(p,n)
old={'source_status':'Conversation R3 numerical proposal, not re-read from absent R3 data archive and not a combat run',
     'base_high_rate':float(p),'natural_hard_pity':n,'drops_per_active_day':48,
     'first_high_expected_draws':float(mean),'first_high_expected_active_hours':float(mean)/2,
     'long_run_high_fraction':float(1/mean),'long_run_highs_per_active_day':float(48/mean)}
cases=[]
for rate in (1,3,5):
    p=Fraction(rate,100)
    for cap in (40,60,80,100):
        m=high_pity_mean(p,cap)
        cases.append({'base_rate_percent':rate,'top_guarantee_limit':cap,'expected_first_top':float(m),'long_run_top_fraction':float(1/m),
                      'p50_first_top':percentile_first_high(p,cap,Fraction(1,2)),
                      'p90_first_top':percentile_first_high(p,cap,Fraction(9,10)),
                      'note':'Sensitivity example only. Does not include desired-item pity, actual pool or price.'})
no_target=[]
for count in (8,16):
    p=Fraction(3,100)/count
    no_target.append({'top_types':count,'top_rate':.03,'target_per_draw':float(p),'expected_target_draws_no_guarantees':float(1/p),
                      'prob_no_target_after_100_no_guarantees':float((1-p)**100),
                      'note':'Uniform top types and NO pity of any kind in this illustration.'})
report={'status':'LIMITED_SPECIFICATION_TEST_AND_EXACT_ARITHMETIC_NOT_GAME_BALANCE_CERTIFICATION',
        'invariant_tests':46,'invariant_result':'PASS','old_natural_proposal_arithmetic':old,
        'probability_sensitivity_cases':cases,'pool_dilution_examples':no_target,
        'nested_lottery_example':{'top_rate':.03,'types':8,'useful_roll_probability':.2,'expected_target_and_roll_no_guarantees':float(1/(Fraction(3,100)/8*Fraction(1,5)))},
        'collection_effect_sensitivity':{'100_unique_items_one_percent_additive_gain':1.0,'100_unique_items_one_percent_multiplicative_gain':float(Fraction(101,100)**100-1),
                                         'tested_cap_bp':300,'tested_cap_is_not_approved':True},
        'art_scope_examples':{'actors':4,'looks_including_base_per_actor':3,'combat_states':6,'home_actions':3,'portrait_views':1,
                              'look_context_coverage_cells':4*3*(6+3+1),'weapon_looks_per_actor':4,'look_weapon_context_combinations':4*3*4*(6+3+1),
                              'meaning':'Coverage cells/QA combinations, not counts of completed images, hours, or mandatory launch scope.'},
        'memory_arithmetic':{'width_px':512,'height_px':512,'channels_bytes':4,'frames':120,'uncompressed_base_mib_one_set':512*512*4*120/1048576,
                              'four_sets_mib':4*512*512*4*120/1048576,
                              'excludes':['compression','texture atlas reuse','GPU compression','mipmaps','CPU/GPU copies','actual device measurements']},
        'not_run':['R1-R6 battle regressions','30/90-day economic progression','actual StoreKit purchases','real concurrency or database failure','real refund of spent draws','visual quality/rigging','iPhone performance','revenue/retention tests']}
(ROOT/'data/ANALYSIS_RESULTS.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'old':old,'target':no_target,'scope':report['art_scope_examples'],'memory':report['memory_arithmetic']},ensure_ascii=False,indent=2))

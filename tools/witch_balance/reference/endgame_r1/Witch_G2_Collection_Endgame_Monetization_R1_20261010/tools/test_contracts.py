import unittest,copy,json,math,hashlib,itertools
from dataclasses import replace,asdict
from pathlib import Path
import numpy as np
from lab import *
from contracts import *
from collection import *

class Contracts(unittest.TestCase):
 def setUp(self):
  self.spec={s['id']:s for s in json.loads((ROOT/'data/CHALLENGE_CATALOG.json').read_text())['challenges']}
  self.inv={it.uid:it for p in party() for it in p.items}
  self.slots={p.actor_id:[it.uid for it in p.items] for p in party()}
 def test_source_preservation(self):
  rows=json.loads((ROOT/'data/SOURCE_LOCK.json').read_text())['files']
  self.assertEqual(len(rows),55)
  for row in rows:self.assertEqual(hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest(),row['sha256'])
 def test_15_stable_challenge_candidates(self):self.assertEqual(len(self.spec),15)
 def test_existing_enemy_ids(self):
  ids={x['id'] for x in e.WORLD['enemies']}
  self.assertTrue(all(set(x['enemy_ids'])<=ids for x in self.spec.values()))
 def test_no_paid_or_rarity_gate(self):self.assertTrue(all(not x['paid_entry'] and x['required_rarity'] is None and not x['required_item_ids'] for x in self.spec.values()))
 def test_first_clear_total(self):self.assertEqual(sum(x['first_clear_powder'] for x in self.spec.values()),3000)
 def test_free_alternatives(self):self.assertTrue(all(len(x['alternative_solutions'])>=2 for x in self.spec.values()))
 def test_future_gate_blocked(self):
  with self.assertRaises(ValueError):record_challenge(Progress({'G_R01_A'}),'CH_R01_01','b',{'outcome':'VICTORY','elapsed_ms':100},'o',self.spec)
 def test_first_clear_once(self):
  a=Progress({'G_R05_B'});b1=record_challenge(a,'CH_R01_01','b',{'outcome':'VICTORY','elapsed_ms':100},'o',self.spec);b2=record_challenge(b1,'CH_R01_01','b2',{'outcome':'VICTORY','elapsed_ms':90},'o2',self.spec)
  self.assertEqual(a.powder,0);self.assertEqual(b2.powder,200);self.assertEqual(b2.records['CH_R01_01']['elapsed_ms'],90)
 def test_same_operation_idempotent(self):
  r={'outcome':'VICTORY','elapsed_ms':100};a=record_challenge(Progress({'G_R05_B'}),'CH_R01_01','b',r,'o',self.spec);self.assertEqual(a,record_challenge(a,'CH_R01_01','b',r,'o',self.spec))
 def test_collision_is_error(self):
  a=record_challenge(Progress({'G_R05_B'}),'CH_R01_01','b',{'outcome':'VICTORY','elapsed_ms':100},'o',self.spec)
  with self.assertRaises(ValueError):record_challenge(a,'CH_R01_02','b',{'outcome':'VICTORY','elapsed_ms':100},'x',self.spec)
 def test_failure_is_no_reward(self):
  for outcome in ('DEFEAT','TIMEOUT'):self.assertEqual(record_challenge(Progress({'G_R05_B'}),'CH_R01_01','b',{'outcome':outcome,'elapsed_ms':100},'o',self.spec).powder,0)
 def test_precommit_failure_preserves_input(self):
  a=Progress({'G_R05_B'});before=copy.deepcopy(a)
  with self.assertRaises(RuntimeError):record_challenge(a,'CH_R01_01','b',{'outcome':'VICTORY','elapsed_ms':100},'o',self.spec,True)
  self.assertEqual(a,before)
 def test_preset_share_across_presets(self):
  a=save_preset({},'a',self.inv,self.slots);a=save_preset(a,'b',self.inv,self.slots);self.assertEqual(a['a'],a['b'])
 def test_no_one_item_two_owners(self):
  s=copy.deepcopy(self.slots);s['C_FAMILIAR'].append(s['C_WITCH'][0])
  with self.assertRaises(ValueError):validate_preset(self.inv,s)
 def test_missing_item_blocks_switch(self):
  self.inv.pop(next(iter(self.inv)))
  with self.assertRaises(ValueError):validate_preset(self.inv,self.slots)
 def test_snapshot_not_changed_by_later_inventory(self):
  a=battle_snapshot(self.inv,self.slots);before=digest(a);self.inv.clear();self.assertEqual(digest(a),before)
 def test_protect_saved_presets(self):
  self.assertEqual(protected_ids(self.inv,{}, {'a':self.slots}),set(self.inv))
 def test_locked_or_invested_protected(self):
  it=next(iter(self.inv.values()));inv={it.uid:replace(it,locked=False,invested_dust=40,enhancement=0)};self.assertIn(it.uid,protected_ids(inv,{},{}))
 def test_dispose_needs_confirmation(self):
  with self.assertRaises(ValueError):bulk_dispose(self.inv,[],{}, {},False)
 def test_dispose_cannot_remove_preset(self):
  with self.assertRaises(ValueError):bulk_dispose(self.inv,[next(iter(self.inv))],{}, {'a':self.slots},True)
 def test_no_fabricated_investment_refund(self):
  it=g.create_item('extra','EQ_W_01');inv,amount=bulk_dispose({it.uid:it},[it.uid],{}, {},True);self.assertEqual(amount,1);self.assertFalse(inv)
 def test_starter_pool_base_13(self):self.assertEqual(len(STARTER_POOL),13)
 def test_starter_all_choice_values_valid(self):
  for t in STARTER_POOL:
   it=starter_choice(t,'g');g.validate_item(it);self.assertEqual(it.quality,'Q2');self.assertEqual(it.rank,1);self.assertEqual(it.invested_dust,0)
 def test_future_choice_blocked(self):
  with self.assertRaises(ValueError):starter_choice('EQ_W_P2','g')
 def test_one_choice_once(self):
  en={'r':{'used':False}};a,inv=use_choice_grant(en,'r','EQ_AMU_01',{})
  aa,ii=use_choice_grant(a,'r','EQ_AMU_01',inv);self.assertEqual(a,aa);self.assertEqual(inv,ii)
  with self.assertRaises(ValueError):use_choice_grant(a,'r','EQ_W_01',inv)
 def test_choice_does_not_grant_itself(self):
  with self.assertRaises(ValueError):use_choice_grant({},'r','EQ_W_01',{})
 def test_build_inputs_same_scale(self):
  for name in BUILD_NAMES:
   pp=party(name);self.assertEqual(sum(len(p.items) for p in pp),24)
   self.assertTrue(all(p.level==60 and p.awakening==0 for p in pp))
   self.assertTrue(all(it.rank==5 and it.enhancement==10 and it.quality=='Q4' for p in pp for it in p.items))
 def test_reuse_16_items(self):
  base={it.uid for p in party() for it in p.items}
  for name in ('BURST','TOXIN','FORTRESS'):self.assertEqual(len(base&{it.uid for p in party(name) for it in p.items}),16)
 def test_no_new_core_implemented(self):self.assertTrue(all(not g.GEAR[it.template_id]['core_rules'] for name in BUILD_NAMES for p in party(name) for it in p.items))
 def test_original_engine_still_rejects_evolved(self):
  pp=party();p=pp[0];it=g.create_item('future','EQ_W_P2','Q4');pp[0]=replace(p,items=(it,)+p.items[1:])
  with self.assertRaises(ValueError):b.FinalBattleR6(pp,bosses()['OPENINGS'],1)
 def test_vector_quality_matches_original_boundaries(self):
  cases=list(itertools.product((0,98,99),(0,18,19),(False,True),(0,99,100,499,500,2499,2500,6499,6500,9999),(0,4999,5000,9999)))
  top=np.array([x[0] for x in cases]);mid=np.array([x[1] for x in cases]);f=np.array([x[2] for x in cases]);qr=np.array([x[3] for x in cases]);tr=np.array([x[4] for x in cases]);q,t,hi,mi,ff=vector_step(top,mid,f,qr,tr)
  for j,x in enumerate(cases):
   a,b1,c=b.step(b.C,b.Counters(x[0],x[1],x[2]),x[3],x[4]);self.assertEqual((int(q[j]),bool(t[j]),int(hi[j]),int(mi[j]),bool(ff[j])),(a,b1,c.top_miss,c.mid_miss,c.force_target))
 def test_target_probability_uses_catalog(self):self.assertAlmostEqual(natural_prob('EQ_W_P2'),.6/7+.4/33)
 def test_oracle_natural(self):self.assertAlmostEqual(combinatorial('EQ_W_P2')['natural_latent_2'],31/286)
 def test_oracle_forced_core(self):self.assertAlmostEqual(combinatorial('EQ_W_P2')['gacha_latent_2'],21/66)
 def test_sampling_affix_distribution_oracle(self):
  n=250000;tid='EQ_W_P2';o=combinatorial(tid)
  for kind in ('natural','gacha'):
   for q in (2,4):
    flags=affix_flags(np.random.default_rng(122+q),n,13,np.full(n,q),kind)
    self.assertLess(abs(float(flags[:,1].mean())-o[kind+'_latent_2']),.006)
    if q==2:self.assertLess(abs(float(flags[:,0].mean())-o[kind+'_SR_visible2']),.006)
 def test_goals_nested(self):
  for source in ('natural','gacha'):
   q=np.tile(np.arange(5),1000);f=affix_flags(np.random.default_rng(1),len(q),13,q,source)
   self.assertTrue(np.all(~f[:,0]|f[:,1]));self.assertTrue(np.all(~f[:,3]|f[:,2]));self.assertTrue(np.all(~f[:,2]|f[:,1]))
 def test_cosmetics_do_not_turn_into_tickets(self):
  for who in ('FREE_NO_AD','AD_ONLY','ONE_OUTFIT'):
   sched=old.personas(90)[who][0];self.assertEqual(old.plan_projection(sched,90)['tickets_from_products'],0)
 def test_paid_bundles_not_repeated_once_items(self):
  x=old.plan_projection(old.personas(90)['ONE_SMALL_PURCHASE'][0],90);self.assertEqual(x['spend_jpy'],160);self.assertEqual(x['tickets_from_products'],10)
 def test_results_counts(self):
  rows=json.loads((ROOT/'results/lab/BATTLE_ROWS.json').read_text());self.assertEqual(len(rows),1024)
  self.assertEqual(len({(x['scenario'],x['build'],x['seed']) for x in rows}),1024)
 def test_reported_failed_battle_condition_retained(self):
  x=json.loads((ROOT/'results/LAB_PRESSURE_DIAGNOSTIC.json').read_text());self.assertTrue(any(z['wins']==0 for z in x))
 def test_collection_equivalence(self):
  data=json.loads((ROOT/'results/collection/COLLECTION_RESULTS.json').read_text())
  for t in data['targets']:
   for d in (7,30,90):
    grouped={x['persona']:x['goals'] for x in t['rows'] if x['day']==d};self.assertEqual(grouped['FREE_NO_AD'],grouped['ONE_OUTFIT']);self.assertEqual(grouped['FREE_NO_AD'],grouped['AD_ONLY'])
 def test_replay_golden_exact(self):
  for scenario,build in [('OPENINGS','BURST'),('ARMORED','TOXIN'),('COUNTERS','FORTRESS')]:
   old=json.loads((ROOT/'results/lab'/f'GOLDEN_{scenario}_{build}.json').read_text());new=fight(build,bosses()[scenario],710000,record=True);self.assertEqual(old['log_sha256'],new['log_sha256']);self.assertEqual(old['outcome'],new['outcome'])

if __name__=='__main__':unittest.main(verbosity=2)

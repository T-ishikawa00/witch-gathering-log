import unittest,copy,json
from fractions import Fraction
from commerce_model import *

class GachaRules(unittest.TestCase):
 def setUp(self):self.a=Account(free=100)
 def test_first_pool_is_nine_world_templates(self):self.assertEqual(len(self.a.eligible()),9)
 def test_fourteen_weapon_presentations_world_metadata(self):self.assertEqual(sum(t['slot']=='weapon' for t in GEAR.values()),14)
 def test_29_metadata_ids_unique(self):self.assertEqual(len(GEAR),29)
 def test_old_159_not_extended(self):self.assertTrue(PRODUCTION['region159_unchanged'])
 def test_two_characters_cannot_open(self):
  self.a.roster=('C_WITCH','C_FAMILIAR')
  with self.assertRaises(Rejected):self.a.quote('EQ_W_01')
 def test_not_linked_blocks_quote(self):
  self.a.linked=False
  with self.assertRaises(Rejected):self.a.quote('EQ_W_01')
 def test_future_evolution_not_in_pool(self):
  self.a.gates.add('G_R01_B');self.assertNotIn('EQ_W_G1',self.a.eligible())
 def test_first_craft_with_gate_unlocks_evolved(self):
  self.a.gates.add('G_R01_B');self.a.first_crafted.add('EQ_W_G1');self.assertIn('EQ_W_G1',self.a.eligible())
 def test_craft_without_gate_does_not_unlock(self):
  self.a.first_crafted.add('EQ_W_G1');self.assertNotIn('EQ_W_G1',self.a.eligible())
 def test_no_unjoined_weapon_in_eligibility(self):
  self.a.roster=('C_WITCH','C_FAMILIAR');self.assertNotIn('EQ_A_01',self.a.eligible())
 def test_guaranteed_top_on_40(self):
  p=Pity();qs=[p.resolve(9999,9999,0,'a',('a','b'))[0] for _ in range(40)]
  self.assertEqual(qs[-1],'Q4');self.assertNotIn('Q4',qs[:-1])
 def test_no_ten_sequential_Q2(self):
  p=Pity();qs=[p.resolve(9999,9999,0,'a',('a','b'))[0] for _ in range(400)]
  self.assertTrue(all('Q2'!=q or i<9 or set(qs[i-9:i+1])!={'Q2'} for i,q in enumerate(qs)))
 def test_top_priority_at_both_boundaries(self):
  p=Pity(39,9);self.assertEqual(p.resolve(9999,9999,0,'a',('a','b'))[0],'Q4')
 def test_target_guarantee_by_80(self):
  p=Pity();hits=[p.resolve(9999,9999,0,'a',('a','b')) for _ in range(80)]
  self.assertEqual(hits[39][:2],('Q4','b'));self.assertEqual(hits[79][:2],('Q4','a'))
 def test_non_top_does_not_consume_target_guarantee(self):
  p=Pity(force_target_on_top=True);p.resolve(9999,0,0,'a',('a','b'));self.assertTrue(p.force_target_on_top)
 def test_target_change_preserves_guarantee(self):
  p=Pity();p.resolve(0,9999,0,'a',('a','b','c'));q,t,f=p.resolve(0,9999,0,'c',('a','b','c'));self.assertEqual(t,'c');self.assertTrue(f)
 def test_remaining_count_bound(self):
  self.assertEqual(Pity(12,2,False).maximum_remaining(),{'any_top':28,'selected_top':68})
  self.assertEqual(Pity(12,2,True).maximum_remaining()['selected_top'],28)
 def test_pity_odds_sum_each_state(self):
  # full-resolution 10k quality outcomes for selected representative counters
  for p in (Pity(),Pity(0,9),Pity(39,9)):
   counts={x:0 for x in ('Q2','Q3','Q4')}
   for i in range(10000):counts[copy.deepcopy(p).resolve(i,0,0,'a',('a','b'))[0]]+=1
   self.assertEqual(sum(counts.values()),10000)
   if p.top_miss==39:self.assertEqual(counts['Q4'],10000)
   elif p.mid_miss==9:self.assertEqual(counts,{'Q2':0,'Q3':9700,'Q4':300})
   else:self.assertEqual(counts,{'Q2':8000,'Q3':1700,'Q4':300})
 def test_target_probability_not_diluted_by_catalog(self):
  for n in (2,8,16,29):
   pool=tuple(map(str,range(n)));hits=sum(Pity().resolve(5000,i,0,'0',pool)[1]=='0' for i in range(10000));self.assertEqual(hits,5000)
 def test_pity_enumerated_worst_case_every_start(self):
  for miss in range(40):
   for forced in (False,True):
    p=Pity(miss,0,forced);bound=p.maximum_remaining()['selected_top']
    for i in range(bound):
     q,t,_=p.resolve(9999,9999,0,'a',('a','b'))
     if q=='Q4' and t=='a':break
    self.assertEqual(i+1,bound)
 def test_no_furniture_in_gear_draw(self):
  out=self.a.draw('x',self.a.quote('EQ_W_01'),10);self.assertTrue(all(x['template_id'] in GEAR for x in out['items']))
 def test_useful_affix_first_and_quality_floor(self):
  out=self.a.draw('x',self.a.quote('EQ_W_01'),10)
  for it in out['items']:
   self.assertEqual(it['affixes'][0]['id'],GEAR[it['template_id']]['core_affix'])
   self.assertTrue(all(5000<=x['quantile_within_existing_quality_range_bp']<=10000 for x in it['affixes']))
   self.assertEqual(len(it['affixes']),2 if it['quality']=='Q2' else 3)
   self.assertEqual(len({x['id'] for x in it['affixes']}),len(it['affixes']))
 def test_does_not_mint_past_investment(self):
  self.a.refinement_cap=3;out=self.a.draw('x',self.a.quote('EQ_W_01'),10)
  for it in out['items']:self.assertEqual(it['native_refinement_rank'],3);self.assertEqual(it['enhancement'],0);self.assertEqual(it['actual_investment_dust'],0)

class WalletAndTransactions(unittest.TestCase):
 def test_free_and_paid_same_draws(self):
  a=Account(free=10);b=Account();b.purchase_tickets_mock('paid',10)
  x=a.draw('x',a.quote('EQ_W_01'),10)['items'];y=b.draw('y',b.quote('EQ_W_01'),10)['items']
  for i,j in zip(x,y):i.pop('funding');j.pop('funding');self.assertEqual(i,j)
 def test_ten_matches_ten_singles(self):
  a=Account(free=10);b=copy.deepcopy(a);x=a.draw('batch',a.quote('EQ_W_01'),10)['items'];y=[]
  for k in range(10):y+=b.draw(str(k),b.quote('EQ_W_01'))['items']
  self.assertEqual(x,y);self.assertEqual(a.pity,b.pity)
 def test_replay_after_version_and_revision_change(self):
  a=Account(free=10);q=a.quote('EQ_W_01');x=a.draw('x',q,10);a.authoritative_version='new';a.revision+=1
  self.assertEqual(a.draw('x',q,10,secret='different'),x)
 def test_request_collision(self):
  a=Account(free=20);q=a.quote('EQ_W_01');a.draw('x',q,10)
  with self.assertRaises(Rejected):a.draw('x',q,1)
 def test_stale_quote_no_charge(self):
  a=Account(free=20);q=a.quote('EQ_W_01');a.purchase_tickets_mock('paid',1);h=a.state_hash()
  with self.assertRaises(Rejected):a.draw('x',q,10)
  self.assertEqual(h,a.state_hash())
 def test_gates_changed_quote_no_charge(self):
  a=Account(free=20);q=a.quote('EQ_W_01');a.gates.add('G_R01_B');a.first_crafted.add('EQ_W_G1');h=a.state_hash()
  with self.assertRaises(Rejected):a.draw('x',q,10)
  self.assertEqual(h,a.state_hash())
 def test_wallet_free_first(self):
  a=Account(free=3);a.purchase_tickets_mock('p',10);out=a.draw('x',a.quote('EQ_W_01'),10)
  self.assertEqual((out['free_used'],out['paid_used'],a.free,a.paid),(3,7,0,3))
 def test_purchase_replay(self):
  a=Account();a.purchase_tickets_mock('p',10);a.purchase_tickets_mock('p',10);self.assertEqual(a.paid,10)
 def test_bad_receipt(self):
  a=Account()
  with self.assertRaises(Rejected):a.purchase_tickets_mock('p',10,False)
  self.assertEqual(a.paid,0)
 def test_insufficient_does_not_change(self):
  a=Account(free=9);h=a.state_hash()
  with self.assertRaises(Rejected):a.draw('x',a.quote('EQ_W_01'),10)
  self.assertEqual(h,a.state_hash())
 def test_precommit_failure_then_retry(self):
  a=Account(free=10);b=copy.deepcopy(a);q=a.quote('EQ_W_01');h=a.state_hash()
  with self.assertRaises(RuntimeError):a.draw('x',q,10,fail_before_commit=True)
  self.assertEqual(h,a.state_hash());self.assertEqual(a.draw('x',q,10),b.draw('x',q,10))
 def test_result_copy_not_mutable(self):
  a=Account(free=10);q=a.quote('EQ_W_01');r=a.draw('x',q,10);r['items'][0]['quality']='CHEAT'
  self.assertNotEqual(a.draw('x',q,10)['items'][0]['quality'],'CHEAT')
 def test_offline_block_no_charge(self):
  a=Account(free=10);q=a.quote('EQ_W_01');h=a.state_hash()
  with self.assertRaises(Rejected):a.draw('x',q,10,online=False)
  self.assertEqual(h,a.state_hash())
 def test_pending_journal_blocked(self):
  a=Account();a.pending_local_journal=True
  with self.assertRaises(Rejected):a.quote('EQ_W_01')
 def test_natural_counter_unchanged(self):
  a=Account(free=10,natural_pity=85);a.draw('x',a.quote('EQ_W_01'),10);self.assertEqual(a.natural_pity,85)
 def test_spent_refund_not_silently_handled(self):
  a=Account();a.purchase_tickets_mock('p',10);a.draw('x',a.quote('EQ_W_01'));h=a.state_hash()
  with self.assertRaises(Rejected):a.refund_unspent_ticket_mock('p')
  self.assertEqual(h,a.state_hash())
 def test_unspent_refund_idempotent(self):
  a=Account();a.purchase_tickets_mock('p',10);a.refund_unspent_ticket_mock('p');a.refund_unspent_ticket_mock('p');self.assertEqual(a.paid,0)

class LivingAndProducts(unittest.TestCase):
 def setUp(self):self.o=LIVING['outfits'][0]['id'];self.f=LIVING['furniture'][0]['id']
 def test_each_boss_twenty_points(self):
  a=Account();got=[]
  for gate in BOSSES:a.gates.add(gate);got.append(a.living_bp())
  self.assertEqual(got,[60,120,180,240,300])
 def test_product_all_cap(self):
  a=Account();a.grant_content_mock('all',tuple(PRODUCTS));self.assertEqual(a.living_score(),100);self.assertEqual(a.living_bp(),300)
 def test_new1000_identical_grants_not_stack(self):
  a=Account()
  for n in range(1000):a.grant_content_mock(str(n),(self.o,))
  self.assertEqual(a.living_bp(),60)
 def test_same_bonus_dressed_or_not(self):
  a=Account();a.grant_content_mock('o',(self.o,));before=a.living_bp();a.select_outfit('C_WITCH',self.o);a.select_outfit('C_WITCH','DEFAULT:C_WITCH');self.assertEqual(a.living_bp(),before)
 def test_placement_not_bonus_condition(self):
  a=Account();a.grant_content_mock('f',(self.f,));before=a.living_bp();a.place('DESK',self.f);a.placed_furniture.clear();self.assertEqual(a.living_bp(),before)
 def test_percent_same_group_not_extra_multiplier(self):
  a=Account();a.gates.update(BOSSES);s=a.stats_snapshot_mock({'hp':100,'power':100,'defense':100},{},{'power':5000})
  self.assertEqual(s['power'],153);self.assertNotEqual(s['power'],Fraction(150)*103/100)
 def test_original_caps_respected(self):
  a=Account();a.gates.update(BOSSES);s=a.stats_snapshot_mock(dict.fromkeys(('hp','power','defense'),100),{},dict.fromkeys(('hp','power','defense'),5000),dict.fromkeys(('hp','power','defense'),5000))
  self.assertEqual(set(s.values()),{150})
 def test_snapshot_frozen(self):
  a=Account();s=a.stats_snapshot_mock(dict.fromkeys(('hp','power','defense'),100),{},{});a.grant_content_mock('o',(self.o,));self.assertEqual(s['power'],100)
 def test_zero_extra_when_free_cap_reached(self):
  a=Account();a.gates.update(BOSSES);b=a.living_bp();a.grant_content_mock('o',(self.o,));self.assertEqual(a.living_bp(),b)
 def test_default_no_ownership_required(self):Account().select_outfit('C_WITCH','DEFAULT:C_WITCH')
 def test_cannot_wear_unowned(self):
  with self.assertRaises(Rejected):Account().select_outfit('C_WITCH',self.o)
 def test_cannot_wear_wrong_actor(self):
  a=Account();a.grant_content_mock('o',(self.o,))
  with self.assertRaises(Rejected):a.select_outfit('C_SMITH',self.o)
 def test_not_downloaded_is_not_not_owned(self):
  a=Account();a.grant_content_mock('o',(self.o,))
  with self.assertRaises(Rejected):a.select_outfit('C_WITCH',self.o,downloaded=False)
  self.assertIn(self.o,a.active_content())
 def test_overlapping_grant_one_revoke_keeps_right(self):
  a=Account();a.grant_content_mock('a',(self.o,));a.grant_content_mock('b',(self.o,));a.select_outfit('C_WITCH',self.o);a.revoke_content_mock('a');self.assertEqual(a.selected_outfits['C_WITCH'],self.o)
 def test_last_revoke_fallback(self):
  a=Account();a.grant_content_mock('a',(self.o,self.f));a.select_outfit('C_WITCH',self.o);a.place('DESK',self.f);a.revoke_content_mock('a');self.assertEqual(a.selected_outfits['C_WITCH'],'DEFAULT:C_WITCH');self.assertEqual(a.placed_furniture['DESK'],'DEFAULT:DESK');self.assertEqual(a.living_bp(),0)
 def test_furniture_wrong_slot(self):
  a=Account();a.grant_content_mock('a',(self.f,))
  with self.assertRaises(Rejected):a.place('RUG',self.f)

class Rewards(unittest.TestCase):
 def test_intro_once(self):
  a=Account();a.reward_intro();a.reward_intro();self.assertEqual(a.free,10)
 def test_region_once(self):
  a=Account();a.gates.add('G_R01_B');a.reward_region('G_R01_B');a.reward_region('G_R01_B');self.assertEqual(a.free,5)
 def test_region_requires_clear(self):
  with self.assertRaises(Rejected):Account().reward_region('G_R05_B')
 def test_daily_seven_not_reclaimable(self):
  a=Account();self.assertEqual(a.accrue_free(DAY*10),7);self.assertEqual(a.accrue_free(DAY*10),0)
 def test_daily_roll_back(self):
  with self.assertRaises(Rejected):Account(daily_last=DAY).accrue_free(0)
 def test_daily_locked(self):
  with self.assertRaises(Rejected):Account(tutorial_done=False).accrue_free(DAY)
 def test_daily_partial_retained(self):
  a=Account();a.accrue_free(DAY+100);self.assertEqual(a.daily_last,DAY);self.assertEqual(a.accrue_free(2*DAY),1)
 def test_30day_possible_supply_not_forecast(self):
  a=Account();a.reward_intro()
  for d in range(1,31):a.accrue_free(d*DAY)
  a.gates.update(BOSSES)
  for gate in BOSSES:a.reward_region(gate)
  self.assertEqual(a.free,65)

class ProductionAndProbability(unittest.TestCase):
 def manifest(self):
  m={k:'fixture-only' for k in PRODUCTION['content_manifest_fields']};m.update({'contexts':['home','detail','combat'],'action_coverage':{'combat':PRODUCTION['required_combat'],'home':PRODUCTION['required_home'],'detail':PRODUCTION['required_detail']},'bindings':PRODUCTION['required_bindings'],'compatible_weapon_ids':['EQ_W_01'],'editable_components':['body','front_hand','garment'],'underpaint':True});return m
 def test_full_manifest_shape(self):self.assertEqual(check_outfit_manifest(self.manifest()),[])
 def test_missing_hit_fails(self):
  m=self.manifest();m['action_coverage']['combat']=[x for x in PRODUCTION['required_combat'] if x!='hit'];self.assertIn('action:combat/hit',check_outfit_manifest(m))
 def test_flat_ora_not_rig(self):
  m=self.manifest();m['editable_components']=['flat.ora'];self.assertIn('flat_source_not_rig',check_outfit_manifest(m))
 def test_home_missing_fails(self):
  m=self.manifest();m['contexts']=['detail','combat'];self.assertIn('context:home',check_outfit_manifest(m))
 def test_weapon_binding_required(self):
  m=self.manifest();m['bindings']=[];self.assertIn('binding:weapon_grip',check_outfit_manifest(m))
 def test_cosmetic_speed_change_fails(self):
  m=self.manifest();m['changes_combat_logic']=True;self.assertIn('visual_must_not_change_combat',check_outfit_manifest(m))
 def test_furniture_interaction_and_underdraw(self):
  socket=PRODUCTION['home_slots'][0];f={'category':'desk','supported_interactions':['sit_read','mix'],'has_underpaint':True,'anchors_valid':True,'within_bounds':True};self.assertTrue(check_furniture_fit(socket,f));f['has_underpaint']=False;self.assertFalse(check_furniture_fit(socket,f))
 def test_exact_target_expected(self):
  r=target_top_distribution();e=(1-.97**40)/.03;self.assertAlmostEqual(r['mean'],1.5*e,10);self.assertAlmostEqual(r['mass'],1,12);self.assertLess(r['residual_mass'],1e-10)
 def test_counts_sum_for_horizon(self):
  for n in (1,10,40,65,90,200):self.assertAlmostEqual(sum(quality_horizon(n)['expected_counts'].values()),n,9)
 def test_state_coverage_is_not_frame_count(self):
  self.assertEqual(2*2*(7+3+1),44);self.assertEqual(4*2*(7+3+1),88)

if __name__=='__main__':unittest.main(verbosity=2)

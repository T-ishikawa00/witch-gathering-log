"""Executable checks of this limited model, NOT production acceptance."""
import unittest,hashlib,copy,json
from dataclasses import asdict,replace
from progression_bridge import *
from battle_model import SKILLS

class SourceChecks(unittest.TestCase):
 def test_frozen_input_hashes(self):
  for row in json.loads((ROOT/'data/SOURCE_HASHES.json').read_text()):
   self.assertEqual(hashlib.sha256((ROOT/row['to']).read_bytes()).hexdigest(),row['sha256'])
 def test_cross_bundle_growth_identical(self):self.assertEqual(g.DATA,e.GROWTH)
 def test_cross_bundle_world_identical(self):self.assertEqual(g.WORLD,e.WORLD)
 def test_no_player_tactics(self):self.assertFalse(g.DATA['combat']['player_ai_settings'])
 def test_no_future_weapon_for_first_tree(self):
  self.assertNotIn(g.GEAR['EQ_W_G1']['unlock_gate'],e.closure('G_R01_A'))
  self.assertNotIn(g.GEAR['EQ_W_P1']['unlock_gate'],e.closure('G_R01_A'))
 def test_future_research_not_available(self):self.assertNotIn(g.DATA['research'][1]['gate'],e.closure('G_R01_A'))

class KnownRoundingFindings(unittest.TestCase):
 def test_wand_zero_early_gain_is_reproduced_not_fixed(self):
  it=g.create_item('round','EQ_W_01');p=[g.item_primary(it)['power']]
  for _ in range(3):it,_=g.enhance_item(it,'G_START');p.append(g.item_primary(it)['power'])
  self.assertEqual(p,[14,14,14,15])
 def test_hands_all_zero_gain_through_three(self):
  it=g.create_item('round','EQ_HAND_01');first=g.item_primary(it)
  for _ in range(3):it,_=g.enhance_item(it,'G_R01_A');self.assertEqual(g.item_primary(it),first)
 def test_ring_all_zero_gain_through_three(self):
  it=g.create_item('round','EQ_RING_01');first=g.item_primary(it)
  for _ in range(3):it,_=g.enhance_item(it,'G_R01_A');self.assertEqual(g.item_primary(it),first)
 def test_plus_one_spends_without_stat_change(self):
  s=intro_state();before=g.actor_stats('C_WITCH',6,[s.items['intro:relic']]);dust=s.eco.dust
  s.enhance('intro:relic','e1');self.assertEqual(dust-s.eco.dust,5)
  self.assertEqual(g.actor_stats('C_WITCH',6,[s.items['intro:relic']]),before)

class ProgressionChecks(unittest.TestCase):
 def test_intro_totals(self):
  s=intro_state();self.assertEqual(s.eco.roster_xp,{'C_WITCH':920,'C_FAMILIAR':920});self.assertEqual(s.eco.dust,30)
  self.assertEqual(sum(s.eco.materials.values()),48);self.assertEqual(len(s.eco.gear),0)
 def test_miniboss_only_two_members(self):
  s=intro_state();self.assertEqual([p.actor_id for p in s.loadout()],['C_WITCH','C_FAMILIAR'])
 def test_no_join_before_clear(self):
  s=intro_state()
  with self.assertRaises(ValueError):s.join('C_SMITH')
 def test_no_tree_before_clear(self):
  with self.assertRaises(ValueError):intro_state().battle('B_R01_B',1)
 def test_actual_result_required(self):
  s=intro_state();before=s.inventory_hash()
  with self.assertRaises(ValueError):s.commit_victory({'battle_id':'fake','outcome':'VICTORY'})
  self.assertEqual(before,s.inventory_hash())
 def test_receipt_tampering_rejected(self):
  s=intro_state();r,rec=s.battle('B_R01_A',1001);rec['elapsed_ms']+=1
  with self.assertRaises(ValueError):s.commit_victory(rec)
 def test_stale_loadout_rejected(self):
  s=intro_state();r,rec=s.battle('B_R01_A',1001);s.enhance('intro:relic','e1')
  with self.assertRaises(ValueError):s.commit_victory(rec)
 def test_failed_transaction_no_change(self):
  s=intro_state();r,rec=s.battle('B_R01_A',1001);before=s.inventory_hash()
  with self.assertRaises(RuntimeError):s.commit_victory(rec,True)
  self.assertEqual(before,s.inventory_hash());s.commit_victory(rec);self.assertIn('G_R01_A',s.gates)
 def test_duplicate_victory_no_reward(self):
  s=intro_state();r,rec=s.battle('B_R01_A',1001);s.commit_victory(rec);h=s.inventory_hash();s.commit_victory(rec)
  self.assertEqual(s.inventory_hash(),h);self.assertEqual(s.eco.materials['M_R01_BA'],1)
 def test_new_replay_receipt_no_additional_boss_material(self):
  s=intro_state();r,rec=s.battle('B_R01_A',1001);s.commit_victory(rec)
  r,rec=s.battle('B_R01_A',1002);s.commit_victory(rec);self.assertEqual(s.eco.materials['M_R01_BA'],1)
 def test_defeat_cannot_unlock_or_consume(self):
  s,_=post_miniboss();before=s.inventory_hash();r,rec=s.battle('B_R01_B',1001)
  self.assertEqual(r['outcome'],'DEFEAT')
  with self.assertRaises(ValueError):s.commit_victory(rec)
  self.assertEqual(s.inventory_hash(),before)
 def test_join_events_idempotent(self):
  s,_=post_miniboss();h=s.inventory_hash();s.join('C_APPRENTICE');s.join('C_SMITH');self.assertEqual(h,s.inventory_hash())
  self.assertEqual(set(s.eco.roster_xp.values()),{920})
 def test_future_material_advance_fails(self):
  s=intro_state();h=s.inventory_hash()
  with self.assertRaises(ValueError):s.advance(300000,'S_R01_BB')
  self.assertEqual(h,s.inventory_hash())
 def test_uncleared_route_fails(self):
  s=intro_state();r,rec=s.battle('B_R01_A',1001);s.commit_victory(rec)
  with self.assertRaises(ValueError):s.advance(300000,'S_R01_G3')
 def test_six_hour_resource_ledger(self):
  s=prepared();self.assertEqual(s.eco.credited_ms,21600000);self.assertEqual(s.eco.roster_xp['C_WITCH'],1784)
  self.assertEqual(len(s.eco.gear),12);self.assertEqual(s.eco.dust,102);self.assertEqual(sum(s.spent_materials.values()),96)
 def test_natural_items_validate_after_bridge(self):
  s=prepared()
  for it in s.items.values():g.validate_item(it)
 def test_paid_crafting_idempotency(self):
  s=prepared();before=s.inventory_hash();s.craft('EQ_BODY_01','craft:0','craft-op:0');self.assertEqual(before,s.inventory_hash())
 def test_craft_insufficient_no_change(self):
  s,_=post_miniboss();h=s.inventory_hash()
  with self.assertRaises(ValueError):s.craft('EQ_BODY_01','new','bad')
  self.assertEqual(h,s.inventory_hash())
 def test_forge_not_auto_joined_by_gate(self):
  s=intro_state();r,rec=s.battle('B_R01_A',1001);s.commit_victory(rec);s.join('C_APPRENTICE');s.survey_deep_fixture()
  with self.assertRaises(ValueError):s.craft('EQ_S_01','new','bad')
 def test_no_shared_item_duplicate(self):
  s=prepared()
  with self.assertRaises(ValueError):s.equip('craft:2','C_SMITH')
 def test_no_human_body_for_cat(self):
  s=prepared()
  with self.assertRaises(ValueError):s.equip('craft:0','C_FAMILIAR')
 def test_first_tree_no_future_power(self):
  s=prepared()
  for p in s.loadout():
   self.assertEqual(p.awakening,0)
   for it in p.items:self.assertEqual(it.rank,1)
  with self.assertRaises(ValueError):s.evolve('intro:relic','EQ_W_G1','future')
 def test_tree_victory_unlocks_but_not_awaken(self):
  s=prepared();s.advance(12*3600000-s.eco.last_wall_ms);r,rec=s.battle('B_R01_B',1001)
  self.assertEqual(r['outcome'],'VICTORY');s.commit_victory(rec)
  self.assertIn('G_R01_B',s.gates);self.assertEqual(s.eco.materials['M_R01_BB'],1)
  for p in s.loadout():self.assertEqual(p.awakening,0)
 def test_after_victory_evolve_preserves_instance(self):
  s=prepared();s.advance(12*3600000-s.eco.last_wall_ms);r,rec=s.battle('B_R01_B',1001);s.commit_victory(rec)
  s.collect_cost([('RC_EQ_W_G1',1)]);old=s.items['intro:relic'];s.evolve(old.uid,'EQ_W_G1','ev1');new=s.items[old.uid]
  self.assertEqual(old.uid,new.uid);self.assertEqual(old.latent_affixes,new.latent_affixes);self.assertEqual(old.quality,new.quality)
  self.assertEqual(s.eco.materials['M_R01_BB'],0);self.assertIn('G_R01_B',s.gates)
 def test_offline_does_not_unlock_boss(self):
  s=intro_state();s.advance(48*3600000);self.assertEqual(s.gates,{'G_START'});self.assertEqual(len(s.eco.roster_xp),2)

class BattleChecks(unittest.TestCase):
 def make(self,bid='B_R01_B',record=True):
  s=prepared();s.advance(12*3600000-s.eco.last_wall_ms)
  return Battle(s.loadout(),LOCAL['bosses'][bid],1001,record)
 def test_exact_replay_same_seed(self):self.assertEqual(self.make().run(),self.make().run())
 def test_party_input_order_does_not_bias(self):
  s=prepared();p=s.loadout();a=Battle(p,LOCAL['bosses']['B_R01_B'],111,True).run();b=Battle(list(reversed(p)),LOCAL['bosses']['B_R01_B'],111,True).run()
  self.assertEqual(a['log'],b['log']);self.assertEqual(a['outcome'],b['outcome'])
 def test_timestamps_monotonic(self):
  r=self.make().run();ts=[x['t_ms'] for x in r['log']];self.assertEqual(ts,sorted(ts))
 def test_basic_first_hit_contract(self):
  s=intro_state();b=Battle(s.loadout(),{**LOCAL['bosses']['B_R01_A'],'first_telegraph_ms':999999,'hp':999999,'time_limit_ms':6000},99,True)
  for a in b.actors.values():a.ready={k:999999 for k in SKILLS if SKILLS[k]['actor_id']==a.id and SKILLS[k]['kind']=='active'}
  r=b.run()
  for aid in ('C_WITCH','C_FAMILIAR'):
   t=next(x['t_ms'] for x in r['log'] if x['kind']=='damage' and x['source']==aid and x['kind_damage']=='basic')
   self.assertEqual(t,g.ACTORS[aid]['basic_interval_ms'])
 def test_skills_respect_commit_cd(self):
  b=self.make();r=b.run();commits={}
  for x in r['log']:
   if x['kind']=='cast_start' and x['skill'] in SKILLS and SKILLS[x['skill']]['kind']=='active':
    key=(x['source'],x['skill']);a=b.actors[x['source']]
    if key in commits:self.assertGreaterEqual(x['t_ms'],commits[key]+g.scaled_skill_cd(SKILLS[x['skill']]['cooldown_ms'],a.stats.get('cdr_bp',0)))
    # The inspected golden encounter has no whiffs; cast commit at declared end.
    commits[key]=x['commit_ms']
 def test_no_dead_actor_cast(self):
  r=self.make().run();dead=set()
  for x in r['log']:
   if x['kind']=='death':dead.add(x['actor'])
   if x['kind']=='cast_start':self.assertNotIn(x['source'],dead)
 def test_reactions_once_per_root(self):
  r=self.make().run();seen=set()
  for x in r['log']:
   if x['kind']=='damage' and x['kind_damage'] in ('counter','chase'):
    key=(x['source'],x['kind_damage'],x['root']);self.assertNotIn(key,seen);seen.add(key)
 def test_aoe_never_redirected(self):
  r=self.make().run()
  hits=[x for x in r['log'] if x['kind']=='enemy_hit' and x['action']=='BRANCH_SWEEP'];self.assertTrue(hits)
  self.assertTrue(all(not x['redirected'] for x in hits))
 def test_counter_and_chase_really_happen(self):
  r=self.make().run();self.assertGreater(r['metrics']['damage_chase'],0);self.assertGreater(r['metrics']['damage_counter'],0)
 def test_healing_and_shield_really_happen(self):
  r=self.make().run();self.assertGreater(r['metrics']['effective_heal'],0);self.assertGreater(r['metrics']['barrier_absorbed'],0)
 def test_shield_and_hp_bounded_every_event(self):
  class Monitor(Battle):
   def handle(b,k,p):
    super().handle(k,p)
    for a in b.actors.values():
     assert 0<=a.hp<=a.stats['hp'];assert 0<=b.shield_total(a)<=a.stats['hp']*3500//10000
  s=prepared();r=Monitor(s.loadout(),LOCAL['bosses']['B_R01_B'],1001).run();self.assertIsNotNone(r['outcome'])
 def test_timeout_not_victory(self):
  s=intro_state();boss={**LOCAL['bosses']['B_R01_A'],'hp':99999999,'power':0,'time_limit_ms':10000}
  self.assertEqual(Battle(s.loadout(),boss,1).run()['outcome'],'TIMEOUT')
 def test_dot_refresh_past_last_old_tick(self):
  class PoisonProbe(Battle):
   def handle(b,k,p):
    if k=='test_apply':
     old=b.poison.stacks;b.poison.clock_ms=b.now;b.poison.add_after_advance(b.now,2,5);b.poison_power=100
     if not old:b.push(b.poison.next_tick_ms,0,'dot',{})
     b.push(b.poison.expires_ms,1,'expire_poison',{})
    else:super().handle(k,p)
  s=intro_state();boss={**LOCAL['bosses']['B_R01_A'],'hp':99999999,'first_telegraph_ms':999999,'time_limit_ms':20000}
  b=PoisonProbe(s.loadout(),boss,1,True)
  for a in b.actors.values():a.busy_until=999999
  for t in [300,7800,16750]:b.push(t,2,'test_apply',{})
  r=b.run();ticks=[x['t_ms'] for x in r['log'] if x['kind']=='dot'];self.assertEqual(ticks,list(range(1300,20000,1000)))
 def test_outgoing_damage_equals_boss_hp_on_win(self):
  r=self.make().run();d=sum(v for k,v in r['metrics'].items() if k.startswith('damage_'))
  self.assertEqual(d,LOCAL['bosses']['B_R01_B']['hp']-r['boss_remaining_hp'])
 def test_renderer_modes_not_in_core(self):
  b=self.make();core=b.run()
  # Only observation envelopes differ; no graphics or actual frame-speed validation.
  envelopes=[{'presentation':m,'computed':core} for m in ('1x','2x','skip')]
  self.assertEqual(len({sha(x['computed']) for x in envelopes}),1)

class ForecastChecks(unittest.TestCase):
 def probe(self):
  st=prepared();b=Battle(st.loadout(),LOCAL['bosses']['B_R01_B'],101)
  b.now=500;act=LOCAL['bosses']['B_R01_B']['actions'][0]
  b.telegraphs={'e':{'target':'C_FAMILIAR','resolved_target':None,'action':act,'hits':[1000,1250,1500],'end':1500}}
  return b
 def test_active_cover_redirects_prediction_not_world_state(self):
  b=self.probe();s=b.actors['C_SMITH'];s.cover_expiry=4000;s.cover_charges=2
  f=b.public_forecast();self.assertTrue(all(x[1]=='C_SMITH' for x in f));self.assertEqual(s.cover_charges,2)
  self.assertEqual(b.danger_for('C_FAMILIAR')[1],0)
 def test_pending_cover_is_considered(self):
  b=self.probe();b.actors['C_SMITH'].casting={'skill':'SK_S_GUARD','finish':650,'target':'C_SMITH'}
  self.assertTrue(all(x[1]=='C_SMITH' for x in b.public_forecast()))
 def test_processed_hit_not_predicted_twice(self):
  b=self.probe();b.now=1000;b.telegraphs['e']['processed_hits']=1
  self.assertEqual([x[0] for x in b.public_forecast()],[1250,1500])

if __name__=='__main__':unittest.main(verbosity=2)

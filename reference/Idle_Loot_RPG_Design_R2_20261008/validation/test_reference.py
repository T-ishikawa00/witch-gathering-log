from __future__ import annotations
import unittest,json,copy
from core import DATA,make_stats,fight,Rng,SLOTS
from progression import initial_state,settle,switch_route,rebase_clock,dismantle,craft
HOUR=3600000
class CombatTests(unittest.TestCase):
 def test_seed_reproducible(self):
  for b in DATA['bosses']:
   for p in DATA['presets'].values(): self.assertEqual(fight(p,b,12,trace=True),fight(p,b,12,trace=True))
 def test_damage_accounting(self):
  for b in DATA['bosses']:
   for p in DATA['presets'].values():
    for seed in range(1,31):
     r=fight(p,b,seed)
     self.assertEqual(sum(r['totals'][x] for x in ('normal','poison','counter')),DATA['bosses'][b]['hp']-r['boss_hp_remaining'])
     self.assertEqual(r['totals']['incoming'],r['stats']['hp']-r['hp_remaining'])
 def test_no_postmortem_events(self):
  r=fight(DATA['presets']['critical'],'sentinels',1,trace=True)
  self.assertFalse(r['win']);self.assertEqual(r['trace'][-1]['player_hp'],0)
 def test_no_unearned_poison_or_counter(self):
  r=fight(DATA['presets']['critical'],'gatekeeper',1)
  self.assertEqual(r['totals']['poison']+r['totals']['counter'],0)
 def test_counter_not_critical_or_recursive(self):
  r=fight(DATA['presets']['counter'],'sentinels',4,trace=True)
  self.assertTrue(r['win']);self.assertLessEqual(sum(v['kind']=='counter' for v in r['trace']),r['totals']['blocks'])
  self.assertTrue(all(not v.get('critical') for v in r['trace'] if v['kind']=='counter'))
 def test_bad_slot_rejected(self):
  with self.assertRaises(ValueError): make_stats(['weapon_c']*6)
 def test_equal_equipment_cost(self):
  self.assertEqual({sum(DATA['items'][i]['cost'] for i in p) for p in DATA['presets'].values()},{720})
 def test_time_limit(self):
  for p in DATA['presets'].values(): self.assertLessEqual(fight(p,'stonebeast',20)['time_ms'],90000)
 def test_rng_zero_defined(self): self.assertEqual(Rng(0).next(),Rng(0x6D2B79F5).next())
 def test_lower_attack_can_win(self):
  p=DATA['presets']['poison'];q=p.copy();q[3]='boots_g';q[5]='ring_g'
  self.assertLess(make_stats(q)['attack'],make_stats(p)['attack'])
  for seed in range(1001,1101):
   self.assertFalse(fight(p,'sentinels',seed)['win']);self.assertTrue(fight(q,'sentinels',seed)['win'])
class OfflineTests(unittest.TestCase):
 def test_eight_hours(self):
  s,r=settle(initial_state(),8*HOUR,'a');self.assertEqual(r['awarded_steps'],32);self.assertGreaterEqual(s['essence'],160)
 def test_fraction(self):
  s,r=settle(initial_state(),899999,'a');self.assertEqual(r['awarded_steps'],0)
  s,r=settle(s,900000,'b');self.assertEqual(r['awarded_steps'],1)
 def test_same_request(self):
  s,_=settle(initial_state(),HOUR,'a');t,r=settle(s,2*HOUR,'a');self.assertEqual(s,t);self.assertEqual(r['status'],'ALREADY_APPLIED')
 def test_same_time_new_request_no_reward(self):
  s,_=settle(initial_state(),HOUR,'a');t,r=settle(s,HOUR,'b');self.assertEqual(r['awarded_steps'],0);self.assertEqual(s['essence'],t['essence'])
 def test_cap_no_repeated_excess(self):
  s,r=settle(initial_state(),48*HOUR,'a');self.assertEqual(r['awarded_steps'],96)
  s,r=settle(s,48*HOUR,'b');self.assertEqual(r['awarded_steps'],0)
 def test_split_equivalent_loot(self):
  s=initial_state();a,_=settle(s,8*HOUR,'all')
  for n in range(1,33):s,_=settle(s,n*900000,f'part{n}')
  for k in ['inventory','essence','draws','remainders_ms','overflow']:self.assertEqual(s[k],a[k])
 def test_no_input_mutation(self):
  s=initial_state();old=copy.deepcopy(s);settle(s,HOUR,'a');self.assertEqual(s,old)
 def test_rollback(self):
  s=initial_state(HOUR);t,r=settle(s,0,'a');self.assertEqual(s,t);self.assertEqual(r['status'],'TIME_ANOMALY')
 def test_rebase_explicit(self):
  s=initial_state(HOUR)
  with self.assertRaises(PermissionError):rebase_clock(s,0,explicit_user_confirmation=False)
  t=rebase_clock(s,0,explicit_user_confirmation=True);self.assertEqual(t['last_ms'],0);self.assertEqual(t['essence'],0)
 def test_route_change_preserves_old_remainder(self):
  s,r=switch_route(initial_state(),899999,'fen','a')
  self.assertEqual(s['remainders_ms']['ash'],899999)
  s,r=settle(s,900000,'b');self.assertEqual(r['awarded_steps'],0)
  s,r=switch_route(s,900000,'ash','c');s,r=settle(s,900001,'d');self.assertEqual(r['awarded_steps'],1)
 def test_invalid_route(self):
  with self.assertRaises(ValueError):switch_route(initial_state(),0,'bad','a')
 def test_seed_partition_loot(self):
  a,_=settle(initial_state(seed=5),24*HOUR,'a');b,_=settle(initial_state(seed=5),24*HOUR,'a');self.assertEqual(a,b)
 def test_overflow_continues(self):
  s=initial_state();s['auto_duplicates']=False;s,r=settle(s,24*HOUR,'a')
  self.assertEqual(len(s['inventory']),72);self.assertEqual(sum(s['overflow'].values()),24)
  s,r=settle(s,48*HOUR,'b');self.assertEqual(r['awarded_steps'],96);self.assertEqual(sum(s['overflow'].values()),120)
 def test_locked_survives(self):
  s,_=settle(initial_state(),HOUR,'a');i=next(iter(s['inventory']));s['inventory'][i]['locked']=True
  with self.assertRaises(PermissionError):dismantle(s,[i])
 def test_equipped_survives(self):
  s,_=settle(initial_state(),HOUR,'a');i=next(iter(s['inventory']));s['equipped']=[i]
  with self.assertRaises(PermissionError):dismantle(s,[i])
 def test_preset_survives(self):
  s,_=settle(initial_state(),HOUR,'a');i=next(iter(s['inventory']));s['presets']={'test':[i]}
  with self.assertRaises(PermissionError):dismantle(s,[i])
 def test_final_copy_survives(self):
  s,_=settle(initial_state(),HOUR,'a');i=next(iter(s['inventory']))
  with self.assertRaises(PermissionError):dismantle(s,[i])
 def test_duplicate_dismantle(self):
  s=initial_state();s['auto_duplicates']=False;s,_=settle(s,24*HOUR,'a')
  i=next(iter(s['inventory']));t=dismantle(s,[i]);self.assertEqual(len(t['inventory']),71);self.assertEqual(t['essence'],s['essence']+2)
 def test_craft_exact_target(self):
  s=initial_state();s['essence']=120;t=craft(s,'weapon_g');self.assertEqual(t['essence'],0);self.assertEqual(next(iter(t['inventory'].values()))['template_id'],'weapon_g')
 def test_failed_craft_does_not_charge(self):
  s=initial_state();s['auto_duplicates']=False;s,_=settle(s,24*HOUR,'a');old=copy.deepcopy(s)
  with self.assertRaises(ValueError):craft(s,'weapon_g')
  self.assertEqual(s,old)
if __name__=='__main__':unittest.main(verbosity=2)

"""R6 contract checks. These are not gameplay, hardware or statistical proofs."""
from bootstrap import *
from fixtures_r6 import *
from selected_model import SelectedBattleR6
from support_ai import *
from dataclasses import asdict,replace
from fractions import Fraction
from pathlib import Path
import unittest,copy,json,hashlib

class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.state=make_state();self.b=SelectedBattleR6(self.state.loadout(),boss_variant('redistribute_pause'),42)
        self.b.now=1000
        for a in self.b.actors.values():a.shields=[];a.casting=None
        self.b.telegraphs={};self.b.forecast_cache={}
        self.s=self.b.actors['C_SMITH'];self.h=self.b.actors['C_APPRENTICE'];self.w=self.b.actors['C_WITCH']
    def tele(self,target='C_WITCH',times=(2000,2250,2500),aoe=False,root='public:0'):
        action=copy.deepcopy(self.b.boss['actions'][1 if aoe else 0])
        self.b.telegraphs[root]={'action':action,'target':None if aoe else target,'resolved_target':None,'hits':list(times),'processed_hits':0}
        self.b.forecast_cache={};return action
    def test_no_player_ai_setting_added(self):self.assertFalse(g.DATA['combat']['player_ai_settings'])
    def test_selected_policy_matches_preheldout_lock(self):
        lock=json.loads((ROOT/'data/EXPERIMENT_LOCK_R6.json').read_text());self.assertEqual(asdict(self.b.support_policy),lock['selected'])
    def test_unchanged_stats(self):
        old=BattleR5(self.state.loadout(),boss_variant('redistribute_pause'),42)
        self.assertEqual({a:x.stats for a,x in old.actors.items()},{a:x.stats for a,x in self.b.actors.items()})
    def test_no_guard_without_public_telegraph(self):self.assertFalse(self.b.guard_needed(self.s))
    def test_guard_responds_to_disclosed_packet_at_full_hp(self):
        self.tele();self.assertTrue(self.b.guard_needed(self.s))
    def test_guard_not_removed_at_target_35_boundary(self):
        self.tele()
        results=[]
        for bp in [3490,3500,3510,3600]:
            self.w.hp=self.w.stats['hp']*bp//10000;self.b.forecast_cache={};results.append(self.b.guard_needed(self.s))
        self.assertEqual(results,[True]*4)
    def test_guard_not_too_late(self):
        self.tele(times=(1100,1200,1300));self.assertFalse(self.b.guard_needed(self.s))
    def test_guard_conservative_same_ms_commit(self):
        self.tele(times=(1150,));self.assertFalse(self.b.guard_needed(self.s))
    def test_guard_not_before_window(self):
        self.tele(times=(2501,2751,3001));self.assertFalse(self.b.guard_needed(self.s))
    def test_no_cover_for_aoe(self):
        self.tele(aoe=True);self.assertFalse(self.b.guard_needed(self.s))
    def test_no_duplicate_cover_stance(self):
        self.tele();self.s.cover_expiry=5000;self.s.cover_charges=2;self.assertFalse(self.b.guard_needed(self.s))
    def test_cover_switch_off_is_diagnostic_only(self):
        self.tele();self.b.disabled.add('cover');self.assertFalse(self.b.guard_needed(self.s))
    def test_guard_keeps_self_safety_35_rule(self):
        self.tele();self.s.hp=self.s.stats['hp']*3500//10000;self.assertFalse(self.b.guard_needed(self.s))
    def test_guard_refuses_predicted_lethal_intercept(self):
        action=self.tele();action['coefficient_bp']=1000000
        self.assertFalse(self.b.guard_needed(self.s))
    def test_no_guard_for_fully_absorbed_attack(self):
        self.tele(times=(2000,))
        self.w.shields=[Shield(self.w.id,10**10,4000,99)]
        self.assertFalse(self.b.guard_needed(self.s))
    def test_public_forecast_includes_tail_of_same_combo(self):
        self.tele(times=(2400,2650,2900))
        self.assertEqual([x[0] for x in self.b.public_forecast()],[2400,2650,2900])
    def test_no_more_than_three_second_horizon(self):
        self.tele(times=(2400,4100));self.assertEqual([x[0] for x in self.b.public_forecast()],[2400])
    def test_unannounced_actions_not_consulted(self):
        self.tele();a=copy.deepcopy(self.b.public_forecast())
        self.b.boss['actions']=[{'id':'future_secret','coefficient_bp':9999999}]
        self.b.forecast_cache={};self.assertEqual(a,self.b.public_forecast())
    def test_future_rng_not_used_by_support_selection(self):
        self.tele();a=self.b.choose(self.s);self.b.seed='unrelated-seed';self.b.forecast_cache={};self.assertEqual(a,self.b.choose(self.s))
    def test_no_past_hits_returned(self):
        self.tele(times=(800,2000));self.b.telegraphs['public:0']['processed_hits']=1
        self.assertEqual([x[0] for x in self.b.public_forecast()],[2000])
    def test_dead_target_excluded(self):
        self.tele();self.w.hp=0;self.assertEqual(self.b.public_forecast(),[])
    def test_heal_does_not_cast_on_full_hp(self):self.assertIsNone(self.b.heal_target(self.h))
    def test_heal_uses_effective_amount_not_70_percent_hp(self):
        self.s.hp-=self.b.heal_nominal(self.h)//2+1
        self.assertGreater(self.s.hp*10000,self.s.stats['hp']*7000)
        self.assertEqual(self.b.heal_target(self.h),self.s.id)
    def test_heal_avoids_trivial_missing_hp(self):
        self.s.hp-=1;self.assertIsNone(self.b.heal_target(self.h))
    def test_heal_same_shortfall_after_max_hp_upgrade(self):
        self.s.hp-=self.b.heal_nominal(self.h)//2+1
        lo=self.b.heal_target(self.h)
        self.s.hp+=10000;self.s.stats['hp']+=10000
        self.assertEqual(lo,self.b.heal_target(self.h))
    def test_heal_does_not_revive_dead(self):
        self.s.hp=0;self.assertIsNone(self.b.heal_target(self.h))
    def test_heal_prefers_lower_fraction_when_both_effective(self):
        self.s.hp=self.s.stats['hp']//2;self.w.hp=self.w.stats['hp']//3
        self.assertEqual(self.b.heal_target(self.h),self.w.id)
    def test_heal_pending_reservation_avoids_duplicate(self):
        self.w.hp-=self.b.heal_nominal(self.h)//2+1
        self.h.casting={'skill':'SK_A_HEAL','target':self.w.id,'finish':1100}
        self.assertIsNone(self.b.heal_target(self.h))
    def test_ward_not_cast_merely_below_50_percent_hp(self):
        self.w.hp=self.w.stats['hp']//3;self.assertIsNone(self.b.ward_target(self.h))
    def test_ward_can_protect_full_hp_against_visible_attack(self):
        self.tele();self.assertEqual(self.b.ward_target(self.h),self.w.id)
    def test_ward_not_cast_too_late(self):
        self.tele(times=(1100,));self.assertIsNone(self.b.ward_target(self.h))
    def test_ward_same_ms_not_counted(self):
        self.tele(times=(1250,));self.assertIsNone(self.b.ward_target(self.h))
    def test_ward_full_cap_not_wasted(self):
        self.tele();self.w.shields=[Shield(self.w.id,self.w.stats['hp']*3500//10000,5000,99)]
        self.assertIsNone(self.b.ward_target(self.h))
    def test_ward_excludes_dead_target(self):
        self.tele();self.w.hp=0;self.assertIsNone(self.b.ward_target(self.h))
    def test_expired_shield_not_protection(self):
        self.tele();self.w.shields=[Shield(self.w.id,1000000,1900,99)]
        self.assertGreater(self.b.danger_for(self.w.id)[1],0)
    def test_proposed_ward_value_does_not_mutate_state(self):
        self.tele();before=asdict(self.w);ts=copy.deepcopy(self.b.telegraphs)
        self.b.forecast_ward_value(self.w.id,self.h)
        self.assertEqual(before,asdict(self.w));self.assertEqual(ts,self.b.telegraphs)
    def test_ward_value_respects_death_before_cast(self):
        self.tele(times=(1100,2000));self.w.hp=1
        self.assertEqual(self.b.forecast_ward_value(self.w.id,self.h)['absorbed'],0)
    def test_ward_value_independent_one_hit_oracle(self):
        action=self.tele(times=(2000,));pred=self.b.forecast_ward_value(self.w.id,self.h)
        nominal=self.b.ward_nominal(self.h)*(10000+self.w.stats.get('barrier_received_bp',0))//10000
        grant=min(nominal,self.w.stats['hp']*3500//10000)
        raw=self.b.boss['power']*action['coefficient_bp']//10000
        incoming=self.b.rules.direct_incoming(raw,self.w.stats['defense'],self.b.boss['level'])
        self.assertEqual(pred['absorbed'],min(grant,incoming))
    def test_ward_value_existing_shield_used_first(self):
        self.tele(times=(2000,));self.w.shields=[Shield(self.w.id,1000000,3000,99)]
        pred=self.b.forecast_ward_value(self.w.id,self.h)
        self.assertLess(pred['absorbed'],pred['granted'])
    def test_expiring_weaken_not_used_in_prediction(self):
        action=self.tele(times=(2000,));self.b.weaken_expiry=1900
        damage=self.b.forecast_incoming_at(self.w,action,2000)
        self.b.weaken_expiry=0
        self.assertEqual(damage,self.b.forecast_incoming_at(self.w,action,2000))
    def test_future_heal_does_not_save_prior_lethal_hit(self):
        self.tele(times=(1100,));self.w.hp=1
        self.h.casting={'skill':'SK_A_HEAL','target':self.w.id,'finish':1200}
        self.assertEqual(self.b.forecast_ward_value(self.w.id,self.h)['hp_after'],0)
    def test_ward_priority_not_runtime_ai_config(self):
        with self.assertRaises(ValueError):SelectedBattleR6(self.state.loadout(),boss_variant('redistribute_pause'),0,support_policy=POLICIES['utility'])

class CombatContractTests(unittest.TestCase):
    def setUp(self):self.state=make_state();self.boss=boss_variant('redistribute_pause')
    def runone(self,seed=100049,up=False,record=True):
        s=upgrade(self.state) if up else self.state
        return SelectedBattleR6(s.loadout(),self.boss,seed,record=record).run()
    def test_known_100049_before_and_after_win(self):
        self.assertEqual([self.runone(100049,x)['outcome'] for x in [False,True]],['VICTORY','VICTORY'])
    def test_known_100069_before_and_after_win(self):
        self.assertEqual([self.runone(100069,x)['outcome'] for x in [False,True]],['VICTORY','VICTORY'])
    def test_deterministic_full_log_replay(self):self.assertEqual(self.runone(),self.runone())
    def test_support_changes_do_not_read_or_mutate_gear(self):
        snapshot=input_record(self.state);self.runone();self.assertEqual(snapshot,input_record(self.state))
    def test_diagnostic_support_off_parity_with_r5(self):
        disabled={'heal','ward','cover','counter','echo'}
        a=BattleR5(self.state.loadout(),self.boss,40003,record=True,disabled=disabled).run()
        b=SelectedBattleR6(self.state.loadout(),self.boss,40003,record=True,disabled=disabled).run()
        self.assertEqual(a['log'],b['log'])
    def test_attack_cooldowns_and_unit_scale_unchanged(self):
        b=SelectedBattleR6(self.state.loadout(),self.boss,42,record=True);r=b.run();last={}
        for e in r['log']:
            if e['kind']=='cast_start' and SKILLS[e['skill']]['kind']=='active':
                key=(e['source'],e['skill']);spec=SKILLS[e['skill']]
                if key in last:
                    self.assertGreaterEqual(e['t_ms'],last[key]+g.scaled_skill_cd(spec['cooldown_ms'],b.actors[e['source']].stats.get('cdr_bp',0)))
                last[key]=e['commit_ms']
        self.assertEqual(r['unit_scale'],10000)
    def test_every_hp_and_shield_in_bounds(self):
        class Checked(SelectedBattleR6):
            def handle(b,k,p):
                super().handle(k,p)
                for a in b.actors.values():
                    assert 0<=a.hp<=a.stats['hp']
                    assert 0<=b.shield_total(a)<=a.stats['hp']*3500//10000
        for seed in [42,100049,100069]:Checked(self.state.loadout(),self.boss,seed).run()
    def test_damage_conservation(self):
        r=self.runone();self.assertEqual(sum(v for k,v in r['metrics'].items() if k.startswith('damage_')),self.boss['hp']*10000-r['boss_remaining_hp'])
    def test_no_actions_after_death(self):
        dead=set()
        for e in self.runone()['log']:
            if e['kind']=='death':dead.add(e['actor'])
            if e['kind']=='cast_start':self.assertNotIn(e['source'],dead)
    def test_event_times_integer_ordered(self):
        times=[e['t_ms'] for e in self.runone()['log']]
        self.assertEqual(times,sorted(times));self.assertTrue(all(isinstance(t,int) for t in times))
    def test_no_reaction_recursion(self):
        seen=set()
        for e in self.runone()['log']:
            if e['kind']=='damage' and e['kind_damage'] in ['counter','chase']:
                key=(e['source'],e['kind_damage'],e['root']);self.assertNotIn(key,seen);seen.add(key)
    def test_order_of_party_input_not_combat_bias(self):
        a=self.runone();b=SelectedBattleR6(list(reversed(self.state.loadout())),self.boss,100049,record=True).run()
        self.assertEqual(a['log'],b['log'])
    def test_boss_numbers_unchanged(self):
        b=SelectedBattleR6(self.state.loadout(),self.boss,42)
        for k in ['hp','power','defense']:self.assertEqual(b.boss[k],self.boss[k]*10000)
        self.assertEqual(b.boss['actions'],self.boss['actions'])
    def test_paid_resources_preserved(self):
        t=upgrade(self.state);self.assertEqual(self.state.eco.dust-t.eco.dust,90)
        self.assertEqual(self.state.eco.materials,t.eco.materials)
        for uid,item in self.state.items.items():self.assertEqual(item.latent_affixes,t.items[uid].latent_affixes)
    def test_original_vendor_all_hashes_unchanged(self):
        lock=json.loads((ROOT/'data/SOURCE_LOCK_R6.json').read_text())
        for entry in lock['vendor_files']:
            self.assertEqual(hashlib.sha256((ROOT/entry['path']).read_bytes()).hexdigest(),entry['sha256'])
    def test_future_gear_rejected(self):
        party=self.state.loadout();party[0]=replace(party[0],items=(g.create_item('future','EQ_W_G1'),))
        with self.assertRaises(ValueError):SelectedBattleR6(party,self.boss,1)
    def test_awakening_unsupported_not_silently_accepted(self):
        party=self.state.loadout();party[0]=replace(party[0],awakening=1)
        with self.assertRaises(ValueError):SelectedBattleR6(party,self.boss,1)
    def test_timeout_not_reclassified_as_victory(self):
        boss={**self.boss,'hp':10**8,'power':0,'time_limit_ms':10000}
        self.assertEqual(SelectedBattleR6(self.state.loadout(),boss,1).run()['outcome'],'TIMEOUT')

if __name__=='__main__':unittest.main(verbosity=2)

"""Reference-contract tests, not engine/device/retention acceptance."""
import unittest,sys,json,hashlib,copy
from dataclasses import replace
from fractions import Fraction
from compare_candidates import *
from precision_rules import PrecisionRules
from battle_r5 import Shield,SKILLS

class PrecisionTests(unittest.TestCase):
    def setUp(self):self.rules=PrecisionRules(g)
    def item(self,tid='EQ_W_01',**kw):return replace(g.create_item('unit:'+tid,tid),**kw)
    def test_wand_gain_from_first_step(self):
        self.assertEqual([self.rules.item_primary(self.item(enhancement=i))['power'] for i in range(4)],[140000,144200,148400,152600])
    def test_hands_and_ring_no_dead_steps(self):
        self.assertEqual(self.rules.item_primary(self.item('EQ_HAND_01',enhancement=1))['power'],41200)
        self.assertEqual(self.rules.item_primary(self.item('EQ_RING_01',enhancement=1))['power'],51500)
    def test_all_1122_legal_enhancement_transitions(self):
        transitions=0
        for tid in g.GEAR:
            for rank in g.RANKS:
                item=self.item(tid,rank=rank)
                for plus in range(g.RANKS[rank]['max_enhance']):
                    lo=self.rules.item_primary(replace(item,enhancement=plus));hi=self.rules.item_primary(replace(item,enhancement=plus+1))
                    for stat,base in g.GEAR[tid]['item_stat_budget'].items():
                        self.assertTrue(hi[stat]>lo[stat] if base>0 else hi[stat]==lo[stat]==0)
                    transitions+=1
        self.assertEqual(transitions,1122)
    def test_independent_rational_primary_oracle(self):
        for tid in g.GEAR:
            for rank in g.RANKS:
                for plus in range(g.RANKS[rank]['max_enhance']+1):
                    it=self.item(tid,rank=rank,enhancement=plus);actual=self.rules.item_primary(it)
                    for stat,base in g.GEAR[tid]['item_stat_budget'].items():
                        oracle=Fraction(base)*Fraction(g.RANKS[rank]['multiplier_bp'],10000)*Fraction(100+3*plus,100)
                        self.assertEqual(Fraction(actual[stat],10000),oracle)
    def test_plus10_is_additive_30_percent(self):
        it=self.item(rank=5,enhancement=10);self.assertEqual(self.rules.item_primary(it)['power'],837200)
    def test_actor_fraction_preserved_after_pct(self):
        it=self.item(quality='Q2',latent_affixes=(g.Affix('AF_POWER',350),g.Affix('AF_HP',350),g.Affix('AF_DEF',350)),enhancement=1)
        st=self.rules.actor_stats('C_WITCH',6,[it]);self.assertEqual(st['power'],753530) # floor((58+14.42)*1.0405*10000)
    def test_dust_and_uuid_not_changed(self):
        s=intro_state();before=copy.deepcopy(s.items['intro:relic']);dust=s.eco.dust
        s.enhance('intro:relic','r5-test');after=s.items[before.uid]
        self.assertEqual(dust-s.eco.dust,5);self.assertEqual(before.uid,after.uid);self.assertEqual(before.latent_affixes,after.latent_affixes)
        self.assertGreater(self.rules.item_primary(after)['power'],self.rules.item_primary(before)['power'])
    def test_no_cost_or_recipe_patch(self):
        original=json.loads((ROOT/'vendor/r01_r4/source/growth_r2/data/growth_gear_skills_R2.json').read_text());self.assertEqual(g.DATA,original)
    def test_levels_do_not_regress(self):
        for aid in g.ACTORS:
            prev=None
            for level in range(1,61):
                st=self.rules.actor_stats(aid,level,[])
                if prev:
                    for k in ['hp','power','defense']:self.assertGreater(st[k],prev[k])
                prev=st
    def test_defense_scaled_oracle_and_cap(self):
        for level in [1,6,12,32,60]:
            for d in [0,1,62,105,1000,1000000]:
                self.assertEqual(self.rules.defense_fraction(d*10000,level),g.defense_fraction(d,level))
    def test_reduction_is_monotonic(self):
        for level in [1,12,60]:
            prev=10**12
            for d in range(0,1001):
                hit=self.rules.direct_incoming(1000000,d*10000,level);self.assertLessEqual(hit,prev);prev=hit
    def test_rounding_loss_under_one_micro_unit(self):
        raw=912345;d=642123;level=12
        exact=Fraction(raw)*(1-self.rules.defense_fraction(d,level))*Fraction(65,100)*Fraction(85,100)
        actual=self.rules.direct_incoming(raw,d,level,True,1500)
        self.assertLess(exact-actual,1);self.assertGreaterEqual(exact-actual,0)
    def test_zero_damage_not_forced_to_one(self):self.assertEqual(self.rules.direct_incoming(0,10000,1),0)
    def test_dead_heal_no_resurrection(self):self.assertEqual(self.rules.apply_heal(0,1000000,200000)['effective'],0)
    def test_invalid_precision_rejected(self):
        with self.assertRaises(ValueError):PrecisionRules(g,100)

class ContractTests(unittest.TestCase):
    def setUp(self):self.s=prepared_at();self.boss=boss_variant('redistribute_pause')
    def battle(self,seed=100001,record=False):return BattleR5(self.s.loadout(),self.boss,seed,record)
    def test_selected_profile_matches_data_lock(self):
        from dataclasses import asdict
        lock=json.loads((ROOT/'data/EXPERIMENT_LOCK_R5.json').read_text())
        self.assertEqual(asdict(Profile()),lock['selected_profile'])
    def test_selected_boss_matches_data_lock(self):
        lock=json.loads((ROOT/'data/EXPERIMENT_LOCK_R5.json').read_text())['boss'];b=self.boss
        for k in ['hp','power','defense','level']:self.assertEqual(b[k],lock[k])
        self.assertEqual(b['actions'][0]['coefficient_bp'],lock['root_hit_coefficient_bp'])
        self.assertEqual(b['actions'][1]['coefficient_bp'],lock['sweep_each_target_coefficient_bp'])
        self.assertEqual(b['actions'][1]['rest_ms'],lock['sweep_rest_ms'])
    def test_legacy_parity_when_all_changes_off(self):
        p=self.s.loadout();old=LegacyBattle(p,LOCAL['bosses']['B_R01_B'],2001).run();new=BattleR5(p,LOCAL['bosses']['B_R01_B'],2001,profile=Profile(1,False,False,False)).run()
        for k in ['outcome','elapsed_ms','boss_remaining_hp','party_remaining_hp']:self.assertEqual(old[k],new[k])
        for k,v in old['metrics'].items():self.assertEqual(v,new['metrics'][k])
    def test_original_golden_reproduces(self):
        saved=json.loads((ROOT/'vendor/r01_r4/results/GOLDEN_TREE_LOG.json').read_text());q=LegacyBattle(self.s.loadout(),LOCAL['bosses']['B_R01_B'],1001,True).run()
        self.assertEqual(q['log_sha256'],saved['log_sha256'])
    def test_identical_replay(self):self.assertEqual(self.battle(record=True).run(),self.battle(record=True).run())
    def test_input_reorder_no_combat_bias(self):
        p=self.s.loadout();q=BattleR5(list(reversed(p)),self.boss,100001,True).run();self.assertEqual(q['log'],self.battle(record=True).run()['log'])
    def test_explicit_output_unit_scale(self):self.assertEqual(self.battle().run()['unit_scale'],10000)
    def test_damage_conservation(self):
        r=self.battle().run();self.assertEqual(sum(v for k,v in r['metrics'].items() if k.startswith('damage_')),self.boss['hp']*10000-r['boss_remaining_hp'])
    def test_every_hp_and_shield_in_bounds(self):
        class B(BattleR5):
            def handle(b,k,p):
                super().handle(k,p)
                for a in b.actors.values():
                    assert 0<=a.hp<=a.stats['hp']
                    assert 0<=b.shield_total(a)<=a.stats['hp']*3500//10000
        B(self.s.loadout(),self.boss,100001).run()
    def test_reaction_single_stage(self):
        seen=set()
        for x in self.battle(record=True).run()['log']:
            if x['kind']=='damage' and x['kind_damage'] in ['counter','chase']:
                key=(x['source'],x['kind_damage'],x['root']);self.assertNotIn(key,seen);seen.add(key)
    def test_no_dead_actions(self):
        dead=set()
        for x in self.battle(100033,True).run()['log']:
            if x['kind']=='death':dead.add(x['actor'])
            if x['kind']=='cast_start':self.assertNotIn(x['source'],dead)
    def test_time_is_integer_nondecreasing(self):
        ts=[x['t_ms'] for x in self.battle(record=True).run()['log']];self.assertEqual(ts,sorted(ts));self.assertTrue(all(isinstance(t,int) for t in ts))
    def test_basic_first_and_subsequent_impact(self):
        s=intro_state();boss={**LOCAL['bosses']['B_R01_A'],'hp':10000000,'first_telegraph_ms':999999,'time_limit_ms':10000}
        b=BattleR5(s.loadout(),boss,1,True)
        for a in b.actors.values():a.ready={sk:999999 for sk,sp in SKILLS.items() if sp['kind']=='active' and sp['actor_id']==a.id}
        q=b.run()
        for aid in b.actors:
            interval=g.ACTORS[aid]['basic_interval_ms'];ts=[x['t_ms'] for x in q['log'] if x['kind']=='damage' and x['source']==aid and x['kind_damage']=='basic']
            self.assertEqual(ts[0],interval);self.assertTrue(all(y-x==interval for x,y in zip(ts,ts[1:])))
    def test_skill_cd_starts_on_commit(self):
        b=self.battle(record=True);q=b.run();previous={}
        for x in q['log']:
            if x['kind']=='cast_start' and SKILLS[x['skill']]['kind']=='active':
                key=(x['source'],x['skill']);sp=SKILLS[x['skill']]
                if key in previous:self.assertGreaterEqual(x['t_ms'],previous[key]+g.scaled_skill_cd(sp['cooldown_ms'],b.actors[x['source']].stats.get('cdr_bp',0)))
                previous[key]=x['commit_ms']
    def test_no_player_tactics_added(self):self.assertFalse(g.DATA['combat']['player_ai_settings'])
    def test_future_gear_rejected(self):
        p=self.s.loadout();future=g.create_item('future','EQ_W_G1');p[0]=replace(p[0],items=(future,))
        with self.assertRaises(ValueError):BattleR5(p,self.boss,1)
    def test_awakening_rejected_not_silently_ignored(self):
        p=self.s.loadout();p[0]=replace(p[0],awakening=1)
        with self.assertRaises(ValueError):BattleR5(p,self.boss,1)
    def test_timeout_still_not_victory(self):
        boss={**self.boss,'hp':10**8,'power':0,'time_limit_ms':5000};self.assertEqual(BattleR5(self.s.loadout(),boss,1).run()['outcome'],'TIMEOUT')
    def test_current_consumable_gate_is_post_first_tree(self):self.assertEqual(g.GEAR['EQ_W_G1']['unlock_gate'],'G_R01_B')

class ForecastTests(unittest.TestCase):
    def setUp(self):
        self.b=BattleR5(prepared_at().loadout(),boss_variant('redistribute_pause'),100001);self.b.now=5500
        act=self.b.boss['actions'][0]
        self.b.telegraphs={'probe':{'target':'C_FAMILIAR','resolved_target':None,'action':act,'hits':[7000],'end':7000}}
        self.a=self.b.actors['C_FAMILIAR'];self.a.shields=[]
    def test_expired_before_hit_not_counted(self):
        self.a.shields=[Shield('C_APPRENTICE',2000000,6500,91)];loss=self.b.danger_for(self.a.id)[1]
        self.a.shields=[];self.assertEqual(loss,self.b.danger_for(self.a.id)[1])
    def test_expiring_at_hit_not_counted(self):
        self.a.shields=[Shield('C_APPRENTICE',2000000,7000,91)];loss=self.b.danger_for(self.a.id)[1]
        self.a.shields=[];self.assertEqual(loss,self.b.danger_for(self.a.id)[1])
    def test_live_shield_counts(self):
        before=self.b.danger_for(self.a.id)[1];self.a.shields=[Shield('C_APPRENTICE',2000000,7001,91)]
        self.assertLess(self.b.danger_for(self.a.id)[1],before)
    def test_expired_weakening_not_assumed(self):
        act=self.b.boss['actions'][0];self.b.weaken_expiry=6500
        after=self.b.forecast_incoming_at(self.a,act,7000);self.b.weaken_expiry=7500
        self.assertLess(self.b.forecast_incoming_at(self.a,act,7000),after)
    def test_late_reserved_heal_not_counted(self):
        self.a.hp=100000;healer=self.b.actors['C_APPRENTICE'];proj=self.b.danger_for(self.a.id)[2]
        healer.casting={'target':self.a.id,'skill':'SK_A_HEAL','finish':7001};self.assertEqual(self.b.danger_for(self.a.id)[2],proj)
    def test_on_time_heal_is_counted(self):
        self.a.hp=100000;healer=self.b.actors['C_APPRENTICE'];proj=self.b.danger_for(self.a.id)[2]
        healer.casting={'target':self.a.id,'skill':'SK_A_HEAL','finish':6900};self.assertGreater(self.b.danger_for(self.a.id)[2],proj)
    def test_forecast_does_not_mutate(self):
        import dataclasses
        before=copy.deepcopy(self.a);self.b.danger_for(self.a.id);self.assertEqual(self.a,before)
    def test_own_target_does_not_consume_cover(self):
        b=self.b;a=b.actors['C_SMITH'];b.now=7000;a.cover_expiry=9000;a.cover_charges=2
        b.telegraphs['probe']['target']=a.id;b.hit_enemy({'root':'probe','hit_index':0})
        self.assertEqual(a.cover_charges,2)
    def test_ally_cover_consumes_one_per_multihit(self):
        b=self.b;a=b.actors['C_SMITH'];b.now=7000;a.cover_expiry=9000;a.cover_charges=2
        b.telegraphs['probe']['hits']=[7000,7250,7500]
        for i,t in enumerate([7000,7250,7500]):b.now=t;b.hit_enemy({'root':'probe','hit_index':i})
        self.assertEqual(a.cover_charges,1)
    def test_aoe_no_redirect(self):
        b=self.b;a=b.actors['C_SMITH'];a.cover_expiry=9000;a.cover_charges=2;b.now=7000
        b.telegraphs['probe'].update({'target':None,'action':b.boss['actions'][1]});b.hit_enemy({'root':'probe','hit_index':0});self.assertEqual(a.cover_charges,2)

class ProgressionR5Tests(unittest.TestCase):
    def setUp(self):
        from progression_r5 import prepare_r5
        self.s=prepare_r5(12)
    def test_actual_victory_commit_idempotent(self):
        result,receipt=self.s.battle('B_R01_B',100001)
        self.assertEqual(result['outcome'],'VICTORY');self.s.commit_victory(receipt);h=self.s.inventory_hash();self.s.commit_victory(receipt)
        self.assertEqual(self.s.inventory_hash(),h);self.assertEqual(self.s.eco.materials['M_R01_BB'],1)
    def test_r5_tampered_receipt_rejected(self):
        _,receipt=self.s.battle('B_R01_B',100001);h=self.s.inventory_hash();receipt['elapsed_ms']+=1
        with self.assertRaises(ValueError):self.s.commit_victory(receipt)
        self.assertEqual(h,self.s.inventory_hash())
    def test_r5_before_commit_failure_preserves_state(self):
        _,receipt=self.s.battle('B_R01_B',100001);h=self.s.inventory_hash()
        with self.assertRaises(RuntimeError):self.s.commit_victory(receipt,True)
        self.assertEqual(h,self.s.inventory_hash())
    def test_new_rules_version_recorded(self):
        _,receipt=self.s.battle('B_R01_B',100001);self.assertEqual(receipt['combat_rules_version'],'G2C_R5_FIXED10000_CANDIDATE')

if __name__=='__main__':unittest.main(verbosity=2)

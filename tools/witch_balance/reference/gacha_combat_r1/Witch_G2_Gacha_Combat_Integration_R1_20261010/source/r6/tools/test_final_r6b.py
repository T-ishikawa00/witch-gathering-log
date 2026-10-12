"""Contract checks of locked R6-B, not approval of general monotonicity."""
from bootstrap import *
from fixtures_r6 import *
from selected_final import FinalBattleR6
from dataclasses import replace,asdict
import copy,heapq,json,hashlib,unittest

class FinalSupportTests(unittest.TestCase):
    def setUp(self):
        self.state=make_state();self.boss=boss_variant('redistribute_pause')
    def battle(self,seed=100049,upgrade_it=False,record=True):
        s=upgrade(self.state) if upgrade_it else self.state
        return FinalBattleR6(s.loadout(),self.boss,seed,record=record)
    def synthetic(self):
        b=self.battle();b.queue=[];b.pending_wakes=set();b.now=1000;b.telegraphs={};b.forecast_cache={}
        for a in b.actors.values():a.shields=[];a.casting=None;a.busy_until=0;a.basic_at=100000
        return b
    def publish(self,b,target='C_WITCH',time=2000,aoe=False):
        action=copy.deepcopy(b.boss['actions'][1 if aoe else 0]);action['coefficient_bp']=20000
        b.telegraphs={'visible':{'action':action,'target':None if aoe else target,'resolved_target':None,'hits':[time],'processed_hits':0}}
        b.forecast_cache={};return action
    def test_locked_policy(self):
        lock=json.loads((ROOT/'data/EXPERIMENT_LOCK_R6B.json').read_text())
        self.assertEqual(asdict(self.battle().support_policy),lock['selected'])
    def test_fixed_stats_and_enemy(self):
        a=BattleR5(self.state.loadout(),self.boss,100049);b=self.battle()
        self.assertEqual({k:x.stats for k,x in a.actors.items()},{k:x.stats for k,x in b.actors.items()});self.assertEqual(a.boss,b.boss)
    def test_known_100049(self):self.assertEqual([self.battle(100049,u).run()['outcome'] for u in [False,True]],['VICTORY']*2)
    def test_known_100069(self):self.assertEqual([self.battle(100069,u).run()['outcome'] for u in [False,True]],['VICTORY']*2)
    def test_same_log_replay(self):self.assertEqual(self.battle().run(),self.battle().run())
    def test_new_fingerprint_distinguishes_coordinator(self):
        from support_ai import BattleR6
        from support_ai_b import CANDIDATES
        a=BattleR6(self.state.loadout(),self.boss,100049,support_policy=CANDIDATES['healing_ward_only']).run()
        self.assertNotEqual(a['input_fingerprint'],self.battle().run()['input_fingerprint'])
    def test_same_time_ai_order(self):
        b=self.synthetic();b.wake_all()
        q=[heapq.heappop(b.queue) for _ in range(len(b.queue))]
        self.assertEqual([p[4]['aid'] for p in q],['C_SMITH','C_APPRENTICE','C_WITCH','C_FAMILIAR'])
        self.assertEqual({p[0] for p in q},{1000})
    def test_existing_event_classes_keep_order(self):
        b=self.synthetic()
        for pr,k in [(6,'timeout'),(2,'enemy_hit'),(1,'expire'),(0,'dot'),(3,'reaction')]:b.push(1000,pr,k,{})
        b.wake_all();q=[heapq.heappop(b.queue)[3] for _ in range(len(b.queue))]
        self.assertEqual(q,['dot','expire','enemy_hit','reaction','ai','ai','ai','ai','timeout'])
    def test_ward_observes_real_cover_reservation(self):
        b=self.synthetic();self.publish(b);b.actors['C_APPRENTICE'].ready['SK_A_HEAL']=999999;b.wake_all()
        while b.queue and b.queue[0][0]==1000:
            t,_,_,k,p=heapq.heappop(b.queue);b.now=t;b.handle(k,p)
        self.assertEqual(b.actors['C_SMITH'].casting['skill'],'SK_S_GUARD')
        h=b.actors['C_APPRENTICE'].casting
        self.assertEqual(h['skill'],'SK_A_WARD');self.assertEqual(h['target'],'C_SMITH')
    def test_no_cover_assumed_if_guard_unavailable(self):
        b=self.synthetic();self.publish(b);b.actors['C_SMITH'].ready['SK_S_GUARD']=999999
        b.actors['C_APPRENTICE'].ready['SK_A_HEAL']=999999;b.wake_all()
        while b.queue and b.queue[0][0]==1000:
            t,_,_,k,p=heapq.heappop(b.queue);b.now=t;b.handle(k,p)
        h=b.actors['C_APPRENTICE'].casting
        self.assertEqual(h['skill'],'SK_A_WARD');self.assertEqual(h['target'],'C_WITCH')
    def test_no_skill_instantly_commits_by_coordination(self):
        b=self.synthetic();self.publish(b);b.wake_all()
        while b.queue and b.queue[0][0]==1000:
            t,_,_,k,p=heapq.heappop(b.queue);b.now=t;b.handle(k,p)
        self.assertEqual(b.actors['C_SMITH'].cover_charges,0)
        self.assertEqual(b.actors['C_SMITH'].casting['finish'],1150)
    def test_heal_eligibility_uses_shortfall(self):
        b=self.synthetic();h=b.actors['C_APPRENTICE'];s=b.actors['C_SMITH'];s.hp-=b.heal_nominal(h)//2+1
        self.assertGreater(s.hp/s.stats['hp'],.7);self.assertEqual(b.heal_target(h),s.id)
    def test_ward_has_no_empty_future_speculation(self):
        b=self.synthetic();b.actors['C_WITCH'].hp//=4
        self.assertIsNone(b.ward_target(b.actors['C_APPRENTICE']))
    def test_same_shortfall_same_heal_eligibility(self):
        b=self.synthetic();s=b.actors['C_SMITH'];h=b.actors['C_APPRENTICE'];s.hp-=b.heal_nominal(h)//2+1
        old=b.heal_target(h);s.hp+=100000;s.stats['hp']+=100000;self.assertEqual(old,b.heal_target(h))
    def test_no_heal_for_dead(self):
        b=self.synthetic();b.actors['C_SMITH'].hp=0;self.assertIsNone(b.heal_target(b.actors['C_APPRENTICE']))
    def test_no_heal_for_full(self):
        b=self.synthetic();self.assertIsNone(b.heal_target(b.actors['C_APPRENTICE']))
    def test_no_forecast_of_unpublished_enemy_action(self):
        b=self.synthetic();self.assertEqual(b.public_forecast(),[])
        b.boss['actions'][0]['coefficient_bp']=999999;self.assertEqual(b.public_forecast(),[])
    def test_future_rng_not_seen(self):
        b=self.synthetic();self.publish(b);x=b.choose(b.actors['C_APPRENTICE']);b.seed='different'
        self.assertEqual(x,b.choose(b.actors['C_APPRENTICE']))
    def test_support_snapshot_read_only(self):
        b=self.synthetic();self.publish(b);before={k:asdict(a) for k,a in b.actors.items()}
        b.forecast_ward_value('C_WITCH',b.actors['C_APPRENTICE']);self.assertEqual(before,{k:asdict(a) for k,a in b.actors.items()})
    def test_cooldown_not_shortened(self):
        b=self.battle();r=b.run();last={}
        for e in r['log']:
            if e['kind']=='cast_start' and SKILLS[e['skill']]['kind']=='active':
                k=(e['source'],e['skill']);sp=SKILLS[e['skill']]
                if k in last:self.assertGreaterEqual(e['t_ms'],last[k]+g.scaled_skill_cd(sp['cooldown_ms'],b.actors[e['source']].stats.get('cdr_bp',0)))
                last[k]=e['commit_ms']
    def test_actor_windup_not_shortened(self):
        for e in self.battle().run()['log']:
            if e['kind']=='cast_start':self.assertEqual(e['commit_ms']-e['t_ms'],SKILLS[e['skill']]['windup_ms'])
    def test_damage_conservation(self):
        r=self.battle().run();self.assertEqual(sum(v for k,v in r['metrics'].items() if k.startswith('damage_')),12500*10000-r['boss_remaining_hp'])
    def test_hp_and_shield_bounds(self):
        class Checked(FinalBattleR6):
            def handle(b,k,p):
                super().handle(k,p)
                for a in b.actors.values():
                    assert 0<=a.hp<=a.stats['hp'];assert 0<=b.shield_total(a)<=a.stats['hp']*3500//10000
        for seed in [100049,100069,54321]:Checked(self.state.loadout(),self.boss,seed).run()
    def test_no_recursive_reaction(self):
        seen=set()
        for e in self.battle().run()['log']:
            if e['kind']=='damage' and e['kind_damage'] in ['counter','chase']:
                k=(e['source'],e['kind_damage'],e['root']);self.assertNotIn(k,seen);seen.add(k)
    def test_integer_nondecreasing_times(self):
        ts=[e['t_ms'] for e in self.battle().run()['log']];self.assertEqual(ts,sorted(ts));self.assertTrue(all(type(t)==int for t in ts))
    def test_gear_and_resources_not_modified(self):
        before=input_record(self.state);self.battle().run();self.assertEqual(before,input_record(self.state))
    def test_future_gear_and_awakening_rejected(self):
        p=self.state.loadout();p[0]=replace(p[0],awakening=1)
        with self.assertRaises(ValueError):FinalBattleR6(p,self.boss,42)
        p=self.state.loadout();p[0]=replace(p[0],items=(g.create_item('notyet','EQ_W_G1'),))
        with self.assertRaises(ValueError):FinalBattleR6(p,self.boss,42)
    def test_same_party_reordered(self):
        a=self.battle().run();b=FinalBattleR6(list(reversed(self.state.loadout())),self.boss,100049,record=True).run()
        self.assertEqual(a['log'],b['log'])
    def test_no_manual_ai_options(self):
        self.assertFalse(g.DATA['combat']['player_ai_settings'])
        with self.assertRaises(ValueError):FinalBattleR6(self.state.loadout(),self.boss,1,support_policy=None)
    def test_r5_source_bytes_preserved(self):
        lock=json.loads((ROOT/'data/SOURCE_LOCK_R6.json').read_text())
        for f in lock['vendor_files']:self.assertEqual(hashlib.sha256((ROOT/f['path']).read_bytes()).hexdigest(),f['sha256'])

if __name__=='__main__':unittest.main(verbosity=2)

import unittest, copy, json, random
from dataclasses import asdict, replace
import economy_model as e
H=3600000

def progress(st):
    d=asdict(st);d.pop('receipts');return d

def four_state(seed='fixture'):
    st=e.State(seed=seed)
    for a in ['C_APPRENTICE','C_SMITH']:st=e.join_actor(st,a,e.closure('G_R01_A'))
    return st

class LedgerTests(unittest.TestCase):
    def test_zero(self):
        x=e.advance_to(e.State(),0,e.snapshot(),'z');self.assertEqual(x.work_index,0)
    def test_partial(self):
        x=e.advance_to(e.State(),299999,e.snapshot(),'a');self.assertEqual(x.partial_ms,299999);self.assertEqual(x.materials,{})
    def test_work_boundary(self):
        x=e.advance_to(e.State(),300000,e.snapshot(),'a');self.assertEqual(sum(x.materials.values()),1)
    def test_gear_boundary(self):
        x=e.advance_to(e.State(),1800000,e.snapshot(),'a');self.assertEqual(len(x.gear),1)
    def test_eight_hour(self):
        x=e.advance_to(e.State(),8*H,e.snapshot(),'a');self.assertEqual((x.earned_xp,x.dust,len(x.gear),sum(x.materials.values())),(1152,96,16,96))
    def test_8_sources_balanced(self):
        x=e.advance_to(four_state(),8*H,e.snapshot(gate='G_R01_A'),'a');self.assertEqual(set(x.materials.values()),{12})
    def test_partition(self):
        s=e.snapshot();one=e.advance_to(e.State(),24*H,s,'all');st=e.State()
        for t in [123,222222,28800001,55000000,24*H]:st=e.advance_to(st,t,s,str(t))
        self.assertEqual(progress(one),progress(st))
    def test_random_partitions(self):
        for seed in range(10):
            s=e.snapshot();rng=random.Random(seed);cuts=sorted(set([24*H]+[rng.randrange(24*H) for _ in range(30)]));st=e.State(seed=str(seed))
            for t in cuts:st=e.advance_to(st,t,s,str(t))
            one=e.advance_to(e.State(seed=str(seed)),24*H,s,'all');self.assertEqual(progress(st),progress(one))
    def test_cap(self):
        x=e.advance_to(e.State(),72*H,e.snapshot(),'a');self.assertEqual(x.work_index,576);self.assertEqual(x.resting_ms,24*H)
    def test_no_claim_recredit(self):
        x=e.advance_to(e.State(),72*H,e.snapshot(),'a');y=e.advance_to(x,72*H,e.snapshot(),'b');self.assertEqual(x.gear,y.gear)
    def test_op_idempotent(self):
        x=e.advance_to(e.State(),H,e.snapshot(),'a');self.assertEqual(x,e.advance_to(x,H,e.snapshot(),'a'))
    def test_op_collision(self):
        x=e.advance_to(e.State(),H,e.snapshot(),'a')
        with self.assertRaises(ValueError):e.advance_to(x,2*H,e.snapshot(),'a')
    def test_rewind(self):
        x=e.advance_to(e.State(),H,e.snapshot(),'a')
        with self.assertRaises(ValueError):e.advance_to(x,0,e.snapshot(),'b')
    def test_reanchor_no_gain(self):
        x=e.advance_to(e.State(),H,e.snapshot(),'a');y=e.reanchor_without_credit(x,0,True)
        self.assertEqual(x.gear,y.gear);self.assertEqual(x.dust,y.dust)
    def test_reanchor_needs_ack(self):
        with self.assertRaises(ValueError):e.reanchor_without_credit(e.State(),0,False)
    def test_atomic_memory_failure(self):
        st=e.State();before=asdict(st)
        with self.assertRaises(RuntimeError):e.advance_to(st,H,e.snapshot(),'a',True)
        self.assertEqual(asdict(st),before)
    def test_state_roundtrip(self):
        s=e.snapshot();a=e.advance_to(e.State(),H+150000,s,'a');b=e.State(**json.loads(json.dumps(asdict(a))))
        self.assertEqual(e.advance_to(a,2*H,s,'b'),e.advance_to(b,2*H,s,'b'))
    def test_snapshot_not_retroactive(self):
        a=e.advance_to(four_state(),H,e.snapshot(gate='G_R01_B'),'a')
        with self.assertRaises(ValueError):e.advance_to(a,9*H,e.snapshot('R02','G_R01_B'),'b')
    def test_partial_old_source(self):
        a=e.snapshot(focus='S_R01_G1');b=e.snapshot(focus='S_R01_E2');x=e.advance_to(e.State(),299000,a,'a');x=e.select_route(x,b,299000);x=e.advance_to(x,300000,b,'b')
        self.assertEqual(x.materials,{'M_R01_G1':1});x=e.advance_to(x,600000,b,'c');self.assertEqual(x.materials['M_R01_E2'],1)
    def test_boss_needs_24(self):
        s=e.snapshot(gate='G_R01_A',focus='S_R01_BA');x=e.advance_to(four_state(),23*300000,s,'a');self.assertNotIn('M_R01_BA',x.materials)
        x=e.advance_to(x,24*300000,s,'b');self.assertEqual(x.materials['M_R01_BA'],1)
    def test_boss_progress_per_source(self):
        a=e.snapshot(gate='G_R01_B',focus='S_R01_BA');b=e.snapshot(gate='G_R01_B',focus='S_R01_BB');x=e.advance_to(four_state(),23*300000,a,'a');x=e.select_route(x,b,x.last_wall_ms);x=e.advance_to(x,24*300000,b,'b');self.assertEqual(x.materials,{})
    def test_future_boss_rejected(self):
        with self.assertRaises(ValueError):e.snapshot(focus='S_R01_BA')
    def test_future_region_rejected(self):
        with self.assertRaises(ValueError):e.snapshot('R05','G_START')
    def test_uncleared_route(self):
        s=replace(e.snapshot(),cleared_area_ids=())
        with self.assertRaises(ValueError):s.validate()
    def test_one_party_materials(self):
        s=e.snapshot(gate='G_R01_A');x=e.advance_to(four_state(),H,s,'a');self.assertEqual(sum(x.materials.values()),12);self.assertEqual(set(x.roster_xp.values()),{144})
    def test_join_sync_once(self):
        x=e.State(roster_xp={'C_WITCH':900,'C_FAMILIAR':800});x=e.join_actor(x,'C_APPRENTICE',e.closure('G_R01_A'));self.assertEqual(x.roster_xp['C_APPRENTICE'],900);x.roster_xp['C_WITCH']=950;x=e.join_actor(x,'C_APPRENTICE',e.closure('G_R01_A'));self.assertEqual(x.roster_xp['C_APPRENTICE'],900)
    def test_first_boss_once(self):
        x=e.first_boss_reward(e.State(),'B_R01_A',False,victory_confirmed=True,gates={'G_START'});y=e.first_boss_reward(x,'B_R01_A',False,victory_confirmed=True,gates={'G_START'});self.assertEqual(x.materials,y.materials)
    def test_repeat_has_no_instant_material(self):
        x=e.first_boss_reward(e.State(),'B_R01_A',True,victory_confirmed=True,gates={'G_START'});self.assertEqual(x.materials,{})

    def test_open_background_poll_no_cap_bypass(self):
        x=e.State();s=e.snapshot()
        for t in range(1,73):x=e.advance_to(x,t*H,s,str(t))
        self.assertEqual(x.work_index,576)
    def test_return_resumes_cap(self):
        x=e.advance_to(e.State(),72*H,e.snapshot(),'a');x=e.acknowledge_presence(x,72*H,'return');x=e.advance_to(x,80*H,e.snapshot(),'b');self.assertEqual(x.work_index,672)
    def test_presence_event_cannot_reuse(self):
        x=e.advance_to(e.State(),H,e.snapshot(),'a');x=e.acknowledge_presence(x,H,'one');x=e.advance_to(x,2*H,e.snapshot(),'b');x=e.acknowledge_presence(x,2*H,'one');self.assertEqual(x.unacknowledged_credit_ms,H)
    def test_no_unconfirmed_first_clear(self):
        with self.assertRaises(ValueError):e.first_boss_reward(e.State(),'B_R01_A',False,victory_confirmed=False,gates={'G_START'})

class LootTests(unittest.TestCase):
    def test_pity_boundary(self):self.assertEqual(e.choose_quality('a',1,99),('Q4',0,True))
    def test_no_more_than_99_misses(self):
        for s in range(25):
            miss=0
            for i in range(1,1001):q,miss,p=e.choose_quality(str(s),i,miss);self.assertLess(miss,100)
    def test_base_weight_preserved(self):self.assertEqual(e.CFG['loot']['base_weights'],{x['id']:x['drop_weight'] for x in e.GROWTH['rarities']})
    def test_rng_repeatable(self):self.assertEqual(e.randbelow('s','a',2,1000),e.randbelow('s','a',2,1000))
    def test_domain_independent(self):
        before=e.choose_quality('s',1,0);[e.randbelow('s','craft',i,1000) for i in range(20)];self.assertEqual(before,e.choose_quality('s',1,0))
    def test_wish_sixth(self):
        x,_=e.gear_roll('s',6,e.snapshot(wish='EQ_F_01'),0);self.assertEqual(x['template_id'],'EQ_F_01');self.assertTrue(x['wish'])
    def test_future_wish_not_granted(self):
        x,_=e.gear_roll('s',6,e.snapshot(wish='EQ_W_P2'),0);self.assertNotEqual(x['template_id'],'EQ_W_P2')
    def test_evolution_recipe_first(self):
        s=e.snapshot('R05','G_R05_B');self.assertNotIn('EQ_W_P2',e.eligible_templates(s));s=replace(s,known_evolved=('EQ_W_P2',));self.assertIn('EQ_W_P2',e.eligible_templates(s))
    def test_native_rank_no_refund(self):
        x,_=e.gear_roll('s',1,e.snapshot('R05','G_R05_B'),0);self.assertEqual((x['rank'],x['invested_dust']),(5,0))
    def test_future_party_weapon_excluded(self):self.assertEqual(e.eligible_templates(e.snapshot()),['EQ_F_01','EQ_W_01'])
    def test_affixes_unique(self):
        x,_=e.gear_roll('s',1,e.snapshot(),0);self.assertEqual(len({a['affix_id'] for a in x['latent_affixes']}),3)
    def test_no_healer_affix_at_start(self):
        for i in range(1,60):
            x,_=e.gear_roll('s',i,e.snapshot(),0);self.assertNotIn('AF_HEAL',[a['affix_id'] for a in x['latent_affixes']])
    def test_gear_period_snapshot(self):
        s=e.snapshot(gate='G_R01_B');t=e.snapshot('R02','G_R01_B');x=e.advance_to(four_state(),5*300000,s,'a');x=e.select_route(x,t,x.last_wall_ms);x=e.advance_to(x,6*300000,t,'b');self.assertEqual(x.gear[0]['rank'],1)

class AdsTests(unittest.TestCase):
    def setUp(self):self.s=e.snapshot();self.x=e.advance_to(e.State(),8*H,self.s,'a')
    def test_reward_math(self):self.assertEqual((self.x.offers[0]['xp'],self.x.offers[0]['dust']),(72,6))
    def test_free_paid_equal(self):
        a=e.redeem_offer(self.x,'offer-1','rewarded_verified','x');b=e.redeem_offer(self.x,'offer-1','premium_entitled','x');self.assertEqual(progress(a),progress(b))
    def test_no_extra_loot(self):
        y=e.redeem_offer(self.x,'offer-1','rewarded_verified','x');self.assertEqual(self.x.gear,y.gear);self.assertEqual(self.x.materials,y.materials);self.assertEqual(self.x.work_index,y.work_index)
    def test_no_duplicate_offer(self):
        x=e.redeem_offer(self.x,'offer-1','premium_entitled','x')
        with self.assertRaises(ValueError):e.redeem_offer(x,'offer-1','premium_entitled','y')
    def test_callback_idempotent(self):
        x=e.redeem_offer(self.x,'offer-1','premium_entitled','x');self.assertEqual(x,e.redeem_offer(x,'offer-1','premium_entitled','x'))
    def test_decline_no_base_loss(self):self.assertEqual((self.x.dust,len(self.x.gear)),(96,16))
    def test_bank_cap(self):
        a=e.acknowledge_presence(self.x,8*H,'foreground-2');x=e.advance_to(a,56*H,self.s,'b');self.assertEqual(len(x.offers),6);self.assertEqual(x.work_index,56*12)
    def test_offer_no_revalue(self):
        x=four_state();s=e.snapshot(gate='G_R01_B');x=e.advance_to(x,8*H,s,'a');t=e.snapshot('R05','G_R05_B');x=e.select_route(x,t,x.last_wall_ms);y=e.redeem_offer(x,'offer-1','premium_entitled','z');self.assertEqual(y.ad_dust,6)

class CostTests(unittest.TestCase):
    def test_fifty_sources(self):self.assertEqual(len(e.SOURCES),50)
    def test_cost_refs(self):
        for c in e.COSTS.values():
            for x in c['ingredients']:self.assertIn(x['material_id'],{s['material_id'] for s in e.SOURCES.values()});self.assertGreater(x['quantity'],0)
    def test_known_poison_cost_hours(self):
        m,d=e.aggregate_cost([('RC_EQ_W_P1',1)]);jobs=e.goal_units(m,{});self.assertEqual(sum(j['units'] for j in jobs),56)
    def test_preowned_boss_cost(self):
        m,d=e.aggregate_cost([('RC_EQ_W_P1',1)]);jobs=e.goal_units(m,{'M_R02_BA':1});self.assertEqual(sum(j['units'] for j in jobs),32)
    def test_awaken_four_repeat(self):
        ops=[(f'AW_{a}_1',1) for a in e.ACTORS];m,d=e.aggregate_cost(ops);self.assertEqual(m['M_R01_BB'],4)
    def test_job_progress(self):
        j=e.goal_units({'M_R01_BA':1},{},{'S_R01_BA':23});self.assertEqual(j,[{'source_id':'S_R01_BA','units':1}])
    def test_goal_no_negative(self):
        with self.assertRaises(ValueError):e.goal_units({'M_R01_G1':-1},{})
    def test_lv60_xp(self):self.assertEqual(e.xp_threshold(60),324146)

if __name__=='__main__':unittest.main(verbosity=2)

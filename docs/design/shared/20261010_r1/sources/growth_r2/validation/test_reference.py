from __future__ import annotations
import unittest, copy
from dataclasses import replace
from reference_model import *

class GrowthTests(unittest.TestCase):
    def test_level_thresholds(self):
        for lv in range(1,61):self.assertEqual(level_from_xp(xp_threshold(lv)),lv)
    def test_below_threshold(self):
        for lv in range(2,61):self.assertEqual(level_from_xp(xp_threshold(lv)-1),lv-1)
    def test_level_cap(self):self.assertEqual(level_from_xp(10**12),60)
    def test_invalid_xp(self):
        with self.assertRaises(ValueError):level_from_xp(-1)
    def test_xp_not_divided_by_party_size(self):
        two={'C_WITCH':100,'C_FAMILIAR':100};four={a:100 for a in ACTORS}
        self.assertEqual(allocate_sortie_xp(two,90)['C_WITCH'],allocate_sortie_xp(four,90)['C_WITCH'])
    def test_join_catchup_and_idempotent(self):
        r={'C_WITCH':400,'C_FAMILIAR':300}
        r=join_actor(r,'C_APPRENTICE');self.assertEqual(r['C_APPRENTICE'],400)
        r['C_WITCH']=900;self.assertEqual(join_actor(r,'C_APPRENTICE')['C_APPRENTICE'],400)
    def test_levels_dont_require_awakening(self):
        validate_progression('C_WITCH',60,0,'G_START',[])
    def test_awakening_not_before_gate(self):
        with self.assertRaises(ValueError):validate_progression('C_WITCH',60,1,'G_START',[])
    def test_awakening_not_before_level(self):
        with self.assertRaises(ValueError):validate_progression('C_WITCH',11,1,'G_R01_B',[])
    def test_awakening_after_final(self):validate_progression('C_WITCH',55,3,'G_R05_B',[])

class ItemTests(unittest.TestCase):
    def setUp(self):self.it=create_item('u1','EQ_W_01','Q2','s',crafted=True)
    def test_deterministic_draw(self):self.assertEqual(self.it,create_item('u1','EQ_W_01','Q2','s',crafted=True))
    def test_no_duplicate_groups(self):
        for g in GEAR:
            for i in range(10):self.assertEqual(len({a.affix_id for a in create_item(str(i),g).latent_affixes}),3)
    def test_rarity_not_primary(self):
        for q in QUALITIES:self.assertEqual(item_primary(replace(self.it,quality=q)),item_primary(self.it))
    def test_visible_slots(self):
        for q,n in [('Q0',0),('Q1',1),('Q2',2),('Q3',3),('Q4',3)]:self.assertEqual(len(visible_affixes(replace(self.it,quality=q))),n)
    def test_legend_floor_and_raw_unchanged(self):
        low=replace(self.it,quality='Q3',latent_affixes=tuple(Affix(a.affix_id,0) for a in self.it.latent_affixes))
        high,cost=promote_quality(low,'G_R04_B')
        self.assertEqual(high.latent_affixes,low.latent_affixes)
        for af in high.latent_affixes:self.assertGreaterEqual(affix_value_bp(high,af),affix_value_bp(low,af))
    def test_enhance_cap(self):
        with self.assertRaises(ValueError):enhance_item(replace(self.it,enhancement=3),'G_START')
    def test_attune_preserves_rolls(self):
        old=replace(self.it,enhancement=3,locked=True,invested_dust=30)
        new,cost=tune_item(old,'G_R01_B')
        self.assertEqual(new.latent_affixes,old.latent_affixes);self.assertEqual(new.enhancement,3);self.assertTrue(new.locked)
        self.assertGreater(item_primary(new)['power'],item_primary(old)['power'])
    def test_evolution_preserves_identity_and_investment(self):
        old=replace(self.it,rank=2,enhancement=5,invested_dust=150,locked=True,referenced_by_loadout=True,equipped_by='C_WITCH')
        new,_=evolve_preview(old,'EQ_W_G1','G_R01_B')
        for field in ['uid','rank','enhancement','latent_affixes','origin_roll_floor','quality','invested_dust','locked','referenced_by_loadout','equipped_by']:self.assertEqual(getattr(old,field),getattr(new,field))
    def test_future_evolution_rejected(self):
        with self.assertRaises(ValueError):evolve_preview(self.it,'EQ_W_P1','G_START')
    def test_sibling_or_reverse_rejected(self):
        p,_=evolve_preview(self.it,'EQ_W_P1','G_R02_A')
        for target in ['EQ_W_G1','EQ_W_01']:
            with self.assertRaises(ValueError):evolve_preview(p,target,'G_R05_B')
    def test_illegal_affix_not_rerolled(self):
        bad=replace(self.it,latent_affixes=(Affix('AF_DOT',1000),Affix('AF_HP',100),Affix('AF_POWER',100)))
        with self.assertRaises(ValueError):evolve_preview(bad,'EQ_W_G1','G_R01_B')
    def test_blacksmith_required_for_forge(self):
        it=create_item('h','EQ_S_01')
        with self.assertRaises(ValueError):evolve_preview(it,'EQ_S_02','G_R03_B')
        evolve_preview(it,'EQ_S_02','G_R03_B',frozenset({'C_SMITH'}))
    def test_human_boots_rejected_for_cat(self):
        it=create_item('boot','EQ_FEET_01')
        with self.assertRaises(ValueError):actor_stats('C_FAMILIAR',20,[it])
    def test_cat_has_six_legal_slots(self):
        ts=['EQ_F_01','EQ_F_BODY_01','EQ_F_HAND_01','EQ_F_FEET_01','EQ_AMU_01','EQ_F_RING_01']
        actor_stats('C_FAMILIAR',20,[create_item(t,t) for t in ts])
    def test_same_slot_rejected(self):
        with self.assertRaises(ValueError):actor_stats('C_WITCH',20,[self.it,create_item('u2','EQ_W_01')])
    def test_same_item_two_actors_rejected(self):
        am=create_item('a','EQ_AMU_01')
        with self.assertRaises(ValueError):validate_party_loadout({'C_WITCH':[am],'C_FAMILIAR':[am]})
    def test_locked_equipped_or_preset_prevents_salvage(self):
        for kw in [{'locked':True},{'equipped_by':'C_WITCH'},{'referenced_by_loadout':True}]:
            with self.assertRaises(ValueError):salvage_return(replace(self.it,**kw))
    def test_free_grant_not_free_dust(self):self.assertEqual(salvage_return(replace(self.it,starter_grant=True)),0)
    def test_no_refining_profit(self):
        old=self.it
        for target in [2,3,4,5]:
            new,c=tune_item(old,'G_R05_B')
            self.assertLess(salvage_return(new)-salvage_return(old),c['RES_REFINING_DUST']);old=new
    def test_no_enhancing_profit(self):
        old=replace(self.it,rank=5)
        for i in range(10):
            new,c=enhance_item(old,'G_R05_B');self.assertLess(salvage_return(new)-salvage_return(old),c);old=new
    def test_no_rarity_promotion_profit(self):
        old=replace(self.it,quality='Q0')
        for i in range(4):
            new,c=promote_quality(old,'G_R05_B');self.assertLess(salvage_return(new)-salvage_return(old),c);old=new
    def test_invalid_rank_and_enhancement(self):
        for kw in [{'rank':0},{'rank':6},{'enhancement':-1},{'enhancement':11}]:
            with self.assertRaises(ValueError):item_primary(replace(self.it,**kw))
    def test_rank_gate_enforced(self):
        with self.assertRaises(ValueError):validate_progression('C_WITCH',30,0,'G_START',[replace(self.it,rank=5)])

class TransactionTests(unittest.TestCase):
    def setUp(self):
        self.it=create_item('x','EQ_W_01','Q2');self.resources={m['id']:100 for m in WORLD['materials']}
        self.l=Ledger({'x':self.it},self.resources)
    def test_repeated_evolution_same_receipt(self):
        new=self.l.evolve('op','x','EQ_W_G1','G_R01_B',1);balance=dict(self.l.resources)
        self.assertEqual(new,self.l.evolve('op','x','EQ_W_G1','G_R01_B',1));self.assertEqual(balance,self.l.resources)
    def test_reused_operation_id_rejected(self):
        self.l.evolve('op','x','EQ_W_G1','G_R01_B',1)
        with self.assertRaises(ValueError):self.l.evolve('op','x','EQ_W_P1','G_R02_A',1)
    def test_insufficient_resources_atomic(self):
        self.l.resources={};old=copy.deepcopy(self.l)
        with self.assertRaises(ValueError):self.l.evolve('op','x','EQ_W_G1','G_R01_B',1)
        self.assertEqual(old,self.l)
    def test_revision_conflict_atomic(self):
        old=copy.deepcopy(self.l)
        with self.assertRaises(ValueError):self.l.evolve('op','x','EQ_W_G1','G_R01_B',3)
        self.assertEqual(old,self.l)
    def test_salvage_idempotent(self):
        r=self.l.salvage('sal','x');b=dict(self.l.resources)
        self.assertEqual(r,self.l.salvage('sal','x'));self.assertEqual(b,self.l.resources)
    def test_consumed_item_cannot_salvage_again(self):
        self.l.salvage('sal','x')
        with self.assertRaises(KeyError):self.l.salvage('other','x')

class CombatFormulaTests(unittest.TestCase):
    def test_mitigation_then_barrier(self):
        # Lv1/K100, DEF100 gives 50%: damage100 ->50, shield30 -> HP20 lost.
        incoming=direct_incoming(100,100,1)
        self.assertEqual(shield_and_hp(incoming,30,200),{'absorbed':30,'hp_damage':20,'shield_after':0,'hp_after':180})
    def test_defense_cap_never_invulnerable(self):
        self.assertEqual(defense_fraction(10**12,60),Fraction(7,10))
        self.assertGreater(direct_incoming(10000,10**12,60,True,10000),0)
    def test_haste_cd_caps(self):
        self.assertEqual(scaled_basic_interval(1800,90000),1200)
        self.assertEqual(scaled_skill_cd(6000,90000),4500)
    def test_shield_total_cap(self):
        self.assertEqual(barrier_add(300,1000,1000),50);self.assertEqual(barrier_add(350,1000,1),0)
    def test_dot_ignores_shield_not_hp(self):
        self.assertEqual(shield_and_hp(50,100,100,True)['shield_after'],100)
        self.assertEqual(shield_and_hp(50,100,100,True)['hp_after'],50)
    def test_overheal_no_effect(self):self.assertEqual(apply_heal(100,100,50)['effective'],0)
    def test_heal_does_not_revive(self):self.assertEqual(apply_heal(0,100,50)['hp_after'],0)
    def test_heal_not_exceed_max(self):self.assertEqual(apply_heal(90,100,50),{'effective':10,'waste':40,'hp_after':100})
    def test_reactions_do_not_chain(self):
        for orig in ['poison','counter','chase','reflect','derived_heal','basic']:
            self.assertFalse(can_react(orig,1,10,True,5000,0,'r',set()))
    def test_root_can_react_only_once(self):
        self.assertTrue(can_react('root_active',0,10,True,5000,0,'r',set()))
        self.assertFalse(can_react('root_active',0,10,True,5000,0,'r',{'r'}))
    def test_no_reaction_dead_zero_or_cooldown(self):
        for effective,alive,now,ready in [(0,True,100,0),(10,False,100,0),(10,True,100,101)]:
            self.assertFalse(can_react('root_active',0,effective,alive,now,ready,'r',set()))
    def test_poison_clamp_and_scaling(self):
        self.assertEqual(poison_tick(100,5),30)
        self.assertEqual(poison_tick(100,5,5,10000,5000),39)
        with self.assertRaises(ValueError):poison_tick(100,9)

class PoisonTimingTests(unittest.TestCase):
    def test_inclusive_last_tick(self):
        p=PoisonSchedule();p.add_after_advance(0)
        ev=p.advance(9000)
        self.assertEqual(len(ev),9);self.assertEqual(ev[-1],(9000,2));self.assertEqual(p.stacks,0)
    def test_refresh_does_not_reset_tick(self):
        p=PoisonSchedule();p.add_after_advance(0);p.advance(2500)
        p.add_after_advance(2500)
        self.assertEqual(p.next_tick_ms,3000);self.assertEqual(p.advance(3000),[(3000,4)])
    def test_stacks_capped(self):
        p=PoisonSchedule()
        for t in [0,1000,2000,3000,4000]:p.advance(t);p.add_after_advance(t,2,8)
        self.assertEqual(p.stacks,8)
    def test_clock_reversal_rejected(self):
        p=PoisonSchedule();p.advance(2000)
        with self.assertRaises(ValueError):p.advance(1000)

if __name__=='__main__':unittest.main(verbosity=2)

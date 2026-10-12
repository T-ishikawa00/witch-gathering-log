import unittest, copy, json, hashlib
from dataclasses import replace, asdict
from bridge import *

class CatalogTests(unittest.TestCase):
    def test_29_plus4(self):self.assertEqual(set(catalog())-set(catalog('29')),set(CAT_ANALOGUES));self.assertEqual(len(catalog()),33)
    def test_all_world_metadata_preserved(self):
        for tid,old in OLD_META.items():
            gt=g.GEAR[tid];self.assertEqual((gt['name'],gt['slot'],gt['actor_ids'],gt['unlock_gate'],gt['parent_template_id']),(old['name'],old['slot'],old['actors'],old['gate'],old['parent']))
    def test_alias_explicit(self):self.assertEqual(mapped('AF_BARRIER'),'AF_WARD');self.assertEqual(g.AFFIXES['AF_WARD']['stat'],'barrier_bonus_bp')
    def test_unknown_affix_rejected(self):
        with self.assertRaises(ValueError):mapped('AF_DOES_NOT_EXIST')
    def test_core_and_pools_valid(self):
        for tid,m in catalog().items():self.assertIn(m['core'],m['pool']);self.assertTrue(set(m['pool'])<=set(g.eligible_affixes(tid)))
    def test_gacha_does_not_silently_expand_natural_affixes(self):self.assertNotIn('AF_HASTE',catalog()['EQ_W_01']['pool']);self.assertIn('AF_HASTE',catalog(affix_mode='growth')['EQ_W_01']['pool'])
    def test_cats_use_cat_only(self):
        for t in CAT_ANALOGUES:self.assertEqual(g.GEAR[t]['actor_ids'],['C_FAMILIAR'])
    def test13_vs9_forest_pool(self):
        s=build_state('fresh',0);self.assertEqual(len(eligible(s)),13);self.assertEqual(len(eligible(s,'29')),9)
    def test_early_start_2(self):self.assertEqual(len(eligible(intro_state())),2)
    def test_unjoined_weapon_excluded(self):self.assertNotIn('EQ_A_01',eligible(intro_state()))
    def test_locked_target_rejected(self):
        with self.assertRaises(ValueError):DrawBridge(C,1,build_state('fresh',0),target='EQ_W_G1')
    def test_evolution_needs_creation_flag(self):
        s=build_state('fresh',0);s.gates=e.closure('G_R01_B');self.assertNotIn('EQ_W_G1',eligible(s));s.known_evolved.add('EQ_W_G1');self.assertIn('EQ_W_G1',eligible(s))

class DrawTests(unittest.TestCase):
    def setUp(self):self.s=build_state('fresh',0)
    def test_batch_equals_singles(self):
        a=DrawBridge(C,10,self.s);b=DrawBridge(C,10,self.s);self.assertEqual(a.draw(50),sum([b.draw(1) for _ in range(50)],[]))
    def test_immutable_three_latent_slots_every_quality(self):
        for r in DrawBridge(C,50,self.s).draw(400):
            it=r['item'];self.assertEqual(len(it.latent_affixes),3);self.assertEqual(len(set(a.affix_id for a in it.latent_affixes)),3);g.validate_item(it)
    def test_core_not_alphabetically_reordered(self):
        for r in DrawBridge(C,21,self.s).draw(200):self.assertEqual(r['item'].latent_affixes[0].affix_id,catalog()[r['item'].template_id]['core'])
    def test_common_has_no_active_affix(self):
        i=next(r['item'] for r in DrawBridge(C,20,self.s).draw(80) if r['item'].quality=='Q0');self.assertEqual(g.visible_affixes(i),())
    def test_one_slot_good_quality(self):
        i=next(r['item'] for r in DrawBridge(C,20,self.s).draw(80) if r['item'].quality=='Q1');self.assertEqual(len(g.visible_affixes(i)),1)
    def test_legend_upper_half600_to1000(self):
        gen=DrawBridge(C,1,self.s);gen.counters=Counters(99,0,False);i=gen.draw(1)[0]['item'];self.assertEqual(i.quality,'Q4');self.assertTrue(all(800<=a.roll_q<=1000 for a in i.latent_affixes))
    def test_other_quality_upper_half0_to1000(self):
        for r in DrawBridge(C,50,self.s).draw(80):self.assertTrue(all(500<=a.roll_q<=1000 for a in r['item'].latent_affixes))
    def test_target_pity_kept_on_change(self):
        d=DrawBridge(C,1,self.s);d.counters=Counters(99,0,True);d.change_target('EQ_A_01');r=d.draw(1)[0];self.assertEqual(r['item'].template_id,'EQ_A_01');self.assertEqual(r['item'].quality,'Q4')
    def test_pity100(self):
        d=DrawBridge(C,1,self.s);d.counters=Counters(99,19,False);self.assertEqual(d.draw(1)[0]['item'].quality,'Q4')
    def test_mid20(self):
        for x in range(20):
            d=DrawBridge(C,x,self.s);d.counters=Counters(0,19,False);self.assertIn(d.draw(1)[0]['item'].quality,('Q3','Q4'))
    def test_price_not_in_gear_stats(self):
        z=replace(C,yen_equivalent_per_pull=123);self.assertEqual(DrawBridge(C,21,self.s).draw(5),DrawBridge(z,21,self.s).draw(5))
    def test_no_investment_refund_for_spawn_rank(self):
        s=copy.deepcopy(self.s);s.gates=e.closure('G_R04_B');r=DrawBridge(C,31,s).draw(20)
        for x in r:
            it=replace(x['item'],locked=False);self.assertEqual(it.rank,5);self.assertEqual(it.invested_dust,0);self.assertEqual(g.salvage_return(it),g.QUALITIES[it.quality]['salvage_base'])
    def test_quality_does_not_multiply_flat_budget(self):
        it=DrawBridge(C,1,self.s).draw(1)[0]['item'];self.assertEqual(P.item_primary(replace(it,quality='Q0')),P.item_primary(replace(it,quality='Q4')))
    def test_upgrade_does_not_reroll_hidden(self):
        it=next(r['item'] for r in DrawBridge(C,1,self.s).draw(50) if r['item'].quality=='Q0');up,cost=g.promote_quality(it,'G_R01_A');self.assertEqual(up.latent_affixes,it.latent_affixes);self.assertEqual(cost,10)
    def test_halved_coordinate_not_10000(self):
        it=DrawBridge(C,1,self.s).draw(1)[0]['item'];bad=replace(it,latent_affixes=(g.Affix('AF_HP',10000),*it.latent_affixes[1:]))
        with self.assertRaises(ValueError):g.validate_item(bad)
    def test_negative_count_rejected(self):
        with self.assertRaises(ValueError):DrawBridge(C,1,self.s).draw(-1)

class ActionTests(unittest.TestCase):
    def setUp(self):self.s=build_state('protect',6,'contract');self.draws=DrawBridge(C,31,self.s).draw(50);accept_draws(self.s,self.draws,'open1')
    def test_exact_received_duplicate_idempotent(self):
        h=self.s.inventory_hash();accept_draws(self.s,self.draws,'open1');self.assertEqual(h,self.s.inventory_hash())
    def test_other_receipt_collision(self):
        with self.assertRaises(ValueError):accept_draws(self.s,self.draws[:1],'open1')
    def test_duplicate_batch_unaccepted(self):
        with self.assertRaises(ValueError):accept_draws(self.s,[self.draws[0],self.draws[0]],'open2')
    def test_equip_stats_componentwise(self):
        before={a:visible_vector(self.s,a) for a in self.s.eco.roster_xp};recommend_equipment(self.s)
        for a,old in before.items():self.assertTrue(all(visible_vector(self.s,a)[k]>=v for k,v in old.items()))
    def test_equipped_single_ownership(self):
        recommend_equipment(self.s);uids=[u for us in self.s.equipped.values() for u in us];self.assertEqual(len(uids),len(set(uids)))
    def test_selector_does_not_peek_in_hidden_affixes(self):
        a=copy.deepcopy(self.s);b=copy.deepcopy(self.s)
        for uid,it in b.items.items():
            n=g.QUALITIES[it.quality]['affix_count'];b.items[uid]=replace(it,latent_affixes=tuple(v if j<n else g.Affix(v.affix_id,1000-v.roll_q) for j,v in enumerate(it.latent_affixes)))
        recommend_equipment(a);recommend_equipment(b);self.assertEqual(a.equipped,b.equipped)
    def test_equipment_selector_no_resource_change(self):
        vals=(self.s.eco.dust,dict(self.s.eco.materials),dict(self.s.eco.roster_xp),self.s.eco.credited_ms);recommend_equipment(self.s);self.assertEqual(vals,(self.s.eco.dust,self.s.eco.materials,self.s.eco.roster_xp,self.s.eco.credited_ms))
    def test_protected_not_scrapped(self):
        recommend_equipment(self.s);q=cleanup_quote(self.s,self.draws);self.assertFalse(set(q['ids'])&set(q['protected']));self.assertFalse(set(q['ids'])&actual_owned(self.s))
    def test_future_hidden_difference_not_called_safe(self):
        q=cleanup_quote(self.s,self.draws);self.assertGreater(len(q['hidden_future_difference_ids']),0);self.assertIn('not future-quality',q['scope'])
    def test_confirmation_required(self):
        q=cleanup_quote(self.s,self.draws)
        with self.assertRaises(ValueError):commit_cleanup(self.s,q,self.draws,'scrap')
    def test_quote_lock_stales(self):
        q=cleanup_quote(self.s,self.draws);u=q['ids'][0];self.s.items[u]=replace(self.s.items[u],locked=True)
        with self.assertRaises(ValueError):commit_cleanup(self.s,q,self.draws,'scrap',True)
    def test_quote_tamper_rejected(self):
        q=cleanup_quote(self.s,self.draws);q['dust']+=1
        with self.assertRaises(ValueError):commit_cleanup(self.s,q,self.draws,'scrap',True)
    def test_atomic_failure_then_retry(self):
        q=cleanup_quote(self.s,self.draws);h=self.s.inventory_hash();dust=self.s.eco.dust
        with self.assertRaises(RuntimeError):commit_cleanup(self.s,q,self.draws,'scrap',True,True)
        self.assertEqual(h,self.s.inventory_hash());commit_cleanup(self.s,q,self.draws,'scrap',True);self.assertEqual(self.s.eco.dust,dust+q['dust'])
    def test_no_double_dust(self):
        q=cleanup_quote(self.s,self.draws);commit_cleanup(self.s,q,self.draws,'scrap',True);h=self.s.inventory_hash();commit_cleanup(self.s,q,self.draws,'scrap',True);self.assertEqual(h,self.s.inventory_hash())
    def test_spend_real_formula_and_no_debt(self):
        self.s.eco.dust=29;result=spend_for_enhancement(self.s,'29');self.assertGreaterEqual(self.s.eco.dust,0);self.assertEqual(sum(x['cost'] for x in result['operations']),29-self.s.eco.dust)
        self.assertTrue(all(x['cost']==5*x['level'] for x in result['operations']))
    def test_materials_xp_dont_change_by_growth(self):
        vals=(dict(self.s.eco.materials),dict(self.s.eco.roster_xp),self.s.eco.credited_ms);spend_for_enhancement(self.s,'x');self.assertEqual(vals,(self.s.eco.materials,self.s.eco.roster_xp,self.s.eco.credited_ms))

class RuntimeTests(unittest.TestCase):
    def test_reference_preparation_6h(self):
        s=build_state('protect',6);self.assertEqual(s.eco.credited_ms,21600000);self.assertEqual(len(s.eco.gear),12);self.assertEqual(s.eco.dust,102);self.assertEqual(set(s.eco.roster_xp.values()),{1784})
    def test_natural_items_are_real_items(self):
        s=build_state('protect',6)
        for r in s.eco.gear:self.assertIn(r['uid'],s.items);g.validate_item(s.items[r['uid']])
    def test_battle_has_no_inventory_sideeffects(self):
        s=build_state('protect',6);h=s.inventory_hash();battle(s,711);self.assertEqual(h,s.inventory_hash())
    def test_battle_roundtrip_exact(self):
        s=build_state('protect',6);self.assertEqual(battle(s,711,record=True),battle(s,711,record=True))
    def test_r6_future_gear_stays_rejected(self):
        s=build_state('protect',6);p=s.loadout();p[0]=replace(p[0],items=(g.create_item('future','EQ_W_G1'),))
        with self.assertRaises(ValueError):FinalBattleR6(p,boss_variant('redistribute_pause'),11)
    def test_cat_four_types_accepted_in_slice(self):
        s=build_state('protect',6)
        for j,t in enumerate(CAT_ANALOGUES):it=g.create_item('cat'+str(j),t);s.insert(it);s.equip(it.uid,'C_FAMILIAR')
        self.assertIn(battle(s,711)['outcome'],('VICTORY','DEFEAT','TIMEOUT'))
    def test_barrier_mapping_works_in_formula(self):
        it=g.create_item('ward','EQ_W_01','Q1');it=replace(it,latent_affixes=(g.Affix('AF_WARD',1000),g.Affix('AF_HP',1),g.Affix('AF_DEF',1)))
        raw=P.actor_stats('C_WITCH',8,[replace(it,quality='Q0')]);ward=P.actor_stats('C_WITCH',8,[it]);self.assertEqual(ward['barrier_bonus_bp']-raw.get('barrier_bonus_bp',0),1000)
    def test_all_source_files_unchanged(self):
        for f in json.loads((ROOT/'data/SOURCE_FILES.json').read_text()):self.assertEqual(hashlib.sha256((ROOT/f['path']).read_bytes()).hexdigest(),f['sha256'])

if __name__=='__main__':unittest.main(verbosity=2)

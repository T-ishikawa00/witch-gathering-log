import unittest,hashlib,json,copy
from dataclasses import replace
from model import *

class RarityContracts(unittest.TestCase):
 def item(self):return b.g.create_item('unit','EQ_W_01',seed='test')
 def test_label_order(self):self.assertEqual(RARITY['ids_preserved'],['Q0','Q1','Q2','Q3','Q4'])
 def test_all_33_ids_remain(self):self.assertEqual(len(b.g.GEAR),33)
 def test_existing_rarity_flag_is_untouched(self):self.assertFalse(b.g.DATA['equipment_rules']['rarity_primary_multiplier'])
 def test_known_wand_values(self):
  rule=RarityRules(b.g,multipliers=MODELS['H1_RECOMMENDED'])
  self.assertEqual([rule.item_primary(replace(self.item(),quality='Q'+str(i)))['power'] for i in range(5)],[140000,154000,175000,203000,238000])
 def test_zero_budget_does_not_become_flat_stat(self):
  a=RarityRules(b.g,multipliers=MODELS['H1_RECOMMENDED']).item_primary(replace(self.item(),quality='Q4'))
  self.assertEqual(a,{'hp':0,'power':238000,'defense':0})
 def test_no_gear_unchanged(self):
  for aid in b.g.ACTORS:self.assertEqual(b.P.actor_stats(aid,12,[]),RarityRules(b.g,multipliers=MODELS['H1_RECOMMENDED']).actor_stats(aid,12,[]))
 def test_all_common_identical(self):
  a=self.item();self.assertEqual(b.P.actor_stats('C_WITCH',6,[a]),RarityRules(b.g,multipliers=MODELS['H1_RECOMMENDED']).actor_stats('C_WITCH',6,[a]))
 def test_not_multiply_actor_base(self):
  a=self.item();x=replace(a,quality='Q4');r=RarityRules(b.g,multipliers=MODELS['H1_RECOMMENDED']);old=b.P.actor_stats('C_WITCH',6,[x]);new=r.actor_stats('C_WITCH',6,[x]);self.assertLess(new['power'],old['power']*1.7)
 def test_secondary_stats_not_changed(self):
  a=replace(self.item(),quality='Q4');r=RarityRules(b.g,multipliers=MODELS['H1_RECOMMENDED']);old=b.P.actor_stats('C_WITCH',6,[a]);new=r.actor_stats('C_WITCH',6,[a]);self.assertEqual({k:v for k,v in old.items() if k not in ['hp','power','defense']},{k:v for k,v in new.items() if k not in ['hp','power','defense']})
 def test_quality_promotion_keeps_identity(self):
  a=self.item();z,cost=b.g.promote_quality(a,'G_R01_A');self.assertEqual(z.uid,a.uid);self.assertEqual(z.latent_affixes,a.latent_affixes);self.assertEqual(cost,10)
 def test_evolution_keeps_quality(self):
  a=replace(self.item(),quality='Q3');z,_=b.g.evolve_preview(a,'EQ_W_G1','G_R01_B',frozenset(b.g.ACTORS));self.assertEqual(z.uid,a.uid);self.assertEqual(z.quality,a.quality);self.assertEqual(z.latent_affixes,a.latent_affixes)
 def test_no_origin_based_hidden_multiplier(self):
  a=replace(self.item(),quality='Q3');alt=replace(a,uid='different',starter_grant=True,invested_dust=100,locked=True);r=RarityRules(b.g,multipliers=MODELS['H1_RECOMMENDED']);self.assertEqual(r.item_primary(a),r.item_primary(alt))
 def test_raise_on_wrong_multiplier_count(self):
  with self.assertRaises(ValueError):RarityRules(b.g,multipliers=[10000])
 def test_raise_on_ineligible_cat_weapon(self):
  with self.assertRaises(ValueError):RarityRules(b.g).actor_stats('C_FAMILIAR',6,[self.item()])
 def test_first_upgrade_still_improves(self):
  a=self.item();z,_=b.g.enhance_item(a,'G_START');r=RarityRules(b.g,multipliers=MODELS['H1_RECOMMENDED']);self.assertGreater(r.item_primary(z)['power'],r.item_primary(a)['power'])
 def test_reference_bytes_unchanged(self):
  for r in json.loads((ROOT/'data/SOURCE_MANIFEST.json').read_text()):self.assertEqual(hashlib.sha256((ROOT/r['path']).read_bytes()).hexdigest(),r['sha256'])

class ProductContracts(unittest.TestCase):
 def test_product_ids_unique(self):self.assertEqual(len(PRODUCTS),len(CATALOG['products']))
 def test_ads_only_gives_no_vouchers_or_stats(self):
  p=plan_projection([('AD_SKIP',0)],30);self.assertTrue(p['ad_skip']);self.assertEqual(p['tickets_from_products'],0);self.assertEqual(p['living_score_if_approved'],0)
 def test_ad_skip_once(self):
  with self.assertRaises(ValueError):plan_projection([('AD_SKIP',0),('AD_SKIP',1)],30)
 def test_starter_once(self):
  with self.assertRaises(ValueError):plan_projection([('STARTER',0),('STARTER',35)],90)
 def test_starter_not_recurring_in_ninety(self):self.assertEqual(plan_projection([('STARTER',0)],90)['tickets_from_products'],10)
 def test_pack_too_early(self):
  with self.assertRaises(ValueError):plan_projection([('VALUE30',0),('VALUE30',29)],90)
 def test_three_pack_periods(self):
  p=plan_projection(repeat('VALUE30',90),90);self.assertEqual((p['spend_jpy'],p['tickets_from_products']),(1440,60))
 def test_future_pack_not_granted(self):self.assertEqual(plan_projection([('VALUE30',0),('VALUE30',30)],30)['tickets_from_products'],20)
 def test_scheduled_pass_partially_grants(self):
  p=plan_projection([('DELIVERY30',0)],15);self.assertEqual((p['tickets_from_products'],p['tickets_remaining_scheduled']),(15,15))
 def test_earned_pass_does_not_expire(self):self.assertEqual(plan_projection([('DELIVERY30',0)],90)['tickets_from_products'],30)
 def test_pass_no_overlap(self):
  with self.assertRaises(ValueError):plan_projection([('DELIVERY30',0),('DELIVERY30',28)],90)
 def test_pass_does_not_auto_renew(self):self.assertEqual(plan_projection([('DELIVERY30',0)],90)['spend_jpy'],650)
 def test_three_intentional_passes(self):self.assertEqual(plan_projection(repeat('DELIVERY30',90),90)['tickets_from_products'],90)
 def test_cosmetic_not_vouchers(self):self.assertEqual(plan_projection([('OUT_C_WITCH_MOON_01',0)],30)['tickets_from_products'],0)
 def test_no_double_purchase_same_costume(self):
  with self.assertRaises(ValueError):plan_projection([('OUT_C_WITCH_MOON_01',0),('OUT_C_WITCH_MOON_01',20)],30)
 def test_outfit_stays_once_at_ninety(self):self.assertEqual(plan_projection([('OUT_C_WITCH_MOON_01',0)],90)['spend_jpy'],1480)
 def test_no_quantity_discount(self):self.assertEqual({p['price_jpy']/p['tickets'] for k,p in PRODUCTS.items() if k.startswith('TICKET')},{30.})
 def test_all_audiences_see_same_eligibility(self):self.assertEqual(offered_products_for_budget_label('FREE'),offered_products_for_budget_label('HIGH'))
 def test_no_spend_based_odds(self):self.assertTrue(all(p['odds_modifier_bp']==0 and not p['vip_requirement'] for p in PRODUCTS.values()))
 def test_all_cosmetic_total(self):
  ids=[k for k,p in PRODUCTS.items() if p.get('power_score_if_separately_approved')];s=plan_projection([(x,0) for x in ids],30);self.assertEqual(s['spend_jpy'],9100);self.assertEqual(s['living_score_if_approved'],100)
 def test_no_ticket_ads_source(self):self.assertEqual(b.e.CFG['ads']['equipment'],0);self.assertFalse(b.e.CFG['ads']['probability_boost'])
 def test_invalid_product(self):
  with self.assertRaises(ValueError):plan_projection([('missing',0)],30)
 def test_negative_date(self):
  with self.assertRaises(ValueError):plan_projection([('STARTER',-1)],30)
 def test_core_product_needs_available_art(self):self.assertTrue(all('approved' in p['requires'] for p in PRODUCTS.values() if p.get('power_score_if_separately_approved')))
 def test_optional_pass_not_mandatory_launch(self):self.assertEqual(PRODUCTS['DELIVERY30']['phase'],'later_candidate')
 def test_top_renewal_first_draw(self):self.assertAlmostEqual(top_expectation(1),.01)
 def test_top_renewal_pity_bounds(self):self.assertGreaterEqual(top_expectation(200),2)

if __name__=='__main__':unittest.main(verbosity=2)

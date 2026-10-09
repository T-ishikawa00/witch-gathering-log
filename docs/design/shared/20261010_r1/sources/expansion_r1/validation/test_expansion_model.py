import unittest
from copy import deepcopy
from fractions import Fraction
from expansion_model import *

class TransactionContract(unittest.TestCase):
    def ready(self):return Account(free_tickets=4,paid_tickets=20,natural_pity=17)
    def test_duplicate_purchase_once(self):
        a=Account();a.grant_purchase('t','ticketpack',tickets=10);a.grant_purchase('t','ticketpack',tickets=10);self.assertEqual(a.paid_tickets,10)
    def test_altered_purchase_rejected(self):
        a=Account();a.grant_purchase('t','ticketpack',tickets=10)
        with self.assertRaises(Rejected):a.grant_purchase('t','ticketpack',tickets=100)
    def test_unverified_does_not_grant(self):
        a=Account();old=a.digest()
        with self.assertRaises(Rejected):a.grant_purchase('t','pack',tickets=10,verified=False)
        self.assertEqual(a.digest(),old)
    def test_draw_retry_same_result(self):
        a=self.ready();q=a.quote('MOCK_WAND_BASE');x=a.draw('r',q,n=10);s=a.digest();y=a.draw('r',q,n=10)
        self.assertEqual(x,y);self.assertEqual(s,a.digest())
    def test_result_output_cannot_mutate_ledger(self):
        a=self.ready();q=a.quote('MOCK_WAND_BASE');x=a.draw('r',q);x['items'][0]['quality']='HACK'
        self.assertNotEqual(a.draw('r',q)['items'][0]['quality'],'HACK')
    def test_draw_payload_conflict(self):
        a=self.ready();q=a.quote('MOCK_WAND_BASE');a.draw('r',q)
        with self.assertRaises(Rejected):a.draw('r',q,n=10)
    def test_rollback_before_commit(self):
        a=self.ready();q=a.quote('MOCK_WAND_BASE');old=a.digest()
        with self.assertRaises(RuntimeError):a.draw('r',q,n=10,fail_before_commit=True)
        self.assertEqual(old,a.digest());a.draw('r',q,n=10);self.assertEqual(len(a.inventory),10)
    def test_free_then_paid(self):
        a=self.ready();x=a.draw('r',a.quote('MOCK_WAND_BASE'),n=10)
        self.assertEqual((x['free_used'],x['paid_used']),(4,6));self.assertEqual((a.free_tickets,a.paid_tickets),(0,14))
    def test_insufficient_no_state_change(self):
        a=Account(free_tickets=1);q=a.quote('MOCK_WAND_BASE');s=a.digest()
        with self.assertRaises(Rejected):a.draw('r',q,n=10)
        self.assertEqual(a.digest(),s)
    def test_no_local_paid_roll(self):
        a=self.ready();q=a.quote('MOCK_WAND_BASE')
        with self.assertRaises(Rejected):a.draw('r',q,online=False)
    def test_pending_offline_journal_prevents_purchase_quote(self):
        a=self.ready();a.pending_mutations=True
        with self.assertRaises(Rejected):a.quote('MOCK_WAND_BASE')
    def test_stale_second_device_quote(self):
        a=self.ready();q1=a.quote('MOCK_WAND_BASE');q2=a.quote('MOCK_WAND_BASE');a.draw('d1',q1)
        with self.assertRaises(Rejected):a.draw('d2',q2)
    def test_quote_version_not_silently_replaced(self):
        a=self.ready();q=a.quote('MOCK_WAND_BASE','MOCK_POOL_V2')
        with self.assertRaises(Rejected):a.draw('r',q)
    def test_one_batch_matches_ten_single_steps(self):
        a=self.ready();b=deepcopy(a);x=a.draw('batch',a.quote('MOCK_WAND_BASE'),n=10)['items'];y=[]
        for i in range(10):y+=b.draw(str(i),b.quote('MOCK_WAND_BASE'))['items']
        self.assertEqual(x,y);self.assertEqual((a.high_miss,a.target_miss),(b.high_miss,b.target_miss));self.assertEqual(a.inventory,b.inventory)
    def test_natural_pity_separate(self):
        a=self.ready();a.draw('r',a.quote('MOCK_WAND_BASE'),n=10);self.assertEqual(a.natural_pity,17)
    def test_future_gate_not_in_pool(self):self.assertNotIn('MOCK_END_WAND',self.ready().eligible())
    def test_first_evolution_required(self):
        a=self.ready();a.gate=2;self.assertNotIn('MOCK_EVOLVED_WAND',a.eligible());a.crafted.add('MOCK_EVOLVED_WAND');self.assertIn('MOCK_EVOLVED_WAND',a.eligible())
    def test_unjoined_actor_cannot_be_only_recipient(self):
        a=self.ready();a.roster=('witch','cat');self.assertNotIn('MOCK_BOOK_BASE',a.eligible());self.assertIn('MOCK_AMULET',a.eligible())
    def test_target_hard_guarantee(self):
        a=self.ready();a.target_miss=8;x=a.draw('r',a.quote('MOCK_WAND_BASE'),base_high_bp=0)['items'][0]
        self.assertEqual((x['template'],x['quality']),('MOCK_WAND_BASE','Q4'));self.assertEqual(a.target_miss,0)
    def test_high_guarantee_separate_from_target(self):
        a=self.ready();a.high_miss=4;x=a.draw('r',a.quote('MOCK_WAND_BASE'),base_high_bp=0)['items'][0];self.assertEqual(x['quality'],'Q4')
    def test_switch_target_does_not_erase_progress(self):
        a=self.ready();a.target_miss=8;q=a.quote('MOCK_HAMMER_BASE');x=a.draw('r',q,base_high_bp=0)['items'][0]
        self.assertEqual((x['template'],x['quality']),('MOCK_HAMMER_BASE','Q4'))
    def test_natural_template_and_gacha_use_same_type_identity(self):
        a=self.ready();x=a.draw('r',a.quote('MOCK_WAND_BASE'),n=10)['items'];self.assertTrue(all(i['template'] in {t.id for t in CATALOG} for i in x))
    def test_no_unpaid_refund_investment(self):
        a=self.ready();x=a.draw('r',a.quote('MOCK_WAND_BASE'),n=10)['items'];self.assertTrue(all(i['actual_investment']==0 for i in x))

class AppearanceAndBonus(unittest.TestCase):
    def prepared(self):
        a=Account();a.grant_purchase('c','dress',content=('DRESS_A',));a.grant_purchase('f','chair',content=('CHAIR_A',));return a
    def test_preview_not_ownership(self):
        a=Account()
        with self.assertRaises(Rejected):a.equip_outfit('DRESS_A')
    def test_change_outfit_not_stats(self):
        a=self.prepared();b={'DRESS_A':100,'CHAIR_A':100};before=appearance_stat(a,b);a.equip_outfit('DRESS_A');self.assertEqual(before,appearance_stat(a,b))
    def test_move_furniture_not_stats(self):
        a=self.prepared();b={'DRESS_A':100,'CHAIR_A':100};before=appearance_stat(a,b);a.furniture={'left':'CHAIR_A'};a.furniture={'right':'CHAIR_A'};self.assertEqual(before,appearance_stat(a,b))
    def test_owned_duplicates_count_once(self):
        a=self.prepared();a.grant_purchase('bundle','room_set',content=('DRESS_A','CHAIR_A'));self.assertEqual(a.active_content(),{'DRESS_A','CHAIR_A'})
    def test_revoke_one_of_two_grants_keeps_right(self):
        a=self.prepared();a.grant_purchase('bundle','set',content=('DRESS_A',));a.equip_outfit('DRESS_A');a.revoke_cosmetic('c');self.assertEqual(a.outfit,'DRESS_A')
    def test_final_revoke_fallback_does_not_touch_gear(self):
        a=self.prepared();a.equip_outfit('DRESS_A');a.inventory={'normal':{'id':'normal','quality':'Q4'}};before=deepcopy(a.inventory);a.revoke_cosmetic('c');self.assertEqual(a.outfit,'BASE');self.assertEqual(before,a.inventory)
    def test_duplicate_revoke_idempotent(self):
        a=self.prepared();a.revoke_cosmetic('c');old=a.digest();a.revoke_cosmetic('c');self.assertEqual(old,a.digest())
    def test_bonus_cap_not_unlimited_collection(self):self.assertEqual(effective_living_bonus(0,{str(i):100 for i in range(100)},cap_bp=300),300)
    def test_free_path_same_cap(self):self.assertEqual(effective_living_bonus(300,{}),effective_living_bonus(0,{'outfit':200,'furn':200}))
    def test_same_percent_group_not_multiply(self):self.assertEqual(mock_stat(100,0,1000,0,{'x':100,'y':200}),113)
    def test_cap_preview_can_be_zero(self):self.assertEqual(effective_living_bonus(300,{}),effective_living_bonus(300,{'new':100}))
    def test_battle_snapshot_immutable_on_cosmetic_purchase(self):
        a=self.prepared();snapshot={'stat':appearance_stat(a,{'DRESS_A':100,'CHAIR_A':100,'DRESS_B':100})};old=deepcopy(snapshot);a.grant_purchase('b','dressB',content=('DRESS_B',));self.assertEqual(snapshot,old)

class ProductionContracts(unittest.TestCase):
    def valid(self):return {'contexts':['home','portrait','battle'],'battle_states':STATES,'actor_id':'witch','revision':'test','editable_source':'MOCK_REFERENCE','grip_contract':'MOCK_GRIP'}
    def test_outfit_coverage_schema(self):self.assertTrue(outfit_deliverable(self.valid()))
    def test_shop_only_image_is_not_outfit_kit(self):
        m=self.valid();m['contexts']=['portrait'];self.assertFalse(outfit_deliverable(m))
    def test_missing_battle_state_blocks_contract(self):
        m=self.valid();m['battle_states']=STATES[:-1];self.assertFalse(outfit_deliverable(m))
    def test_missing_editable_source_blocks_contract(self):
        m=self.valid();m['editable_source']='';self.assertFalse(outfit_deliverable(m))
    def test_furniture_category_and_interaction(self):
        s={'category':'seat','needed_interactions':['sit'],'max_width':2};a={'category':'seat','supported_interactions':['sit'],'max_width':2,'has_back_underpaint':True,'seat_anchor_valid':True};self.assertTrue(safe_mount(s,a));a['supported_interactions']=[];self.assertFalse(safe_mount(s,a))
    def test_no_flattened_hole_accepted(self):
        s={'category':'seat','needed_interactions':['sit'],'max_width':2};a={'category':'seat','supported_interactions':['sit'],'max_width':2,'has_back_underpaint':False,'seat_anchor_valid':True};self.assertFalse(safe_mount(s,a))
    def test_furniture_too_big(self):
        s={'category':'seat','needed_interactions':['sit'],'max_width':2};a={'category':'seat','supported_interactions':['sit'],'max_width':3,'has_back_underpaint':True,'seat_anchor_valid':True};self.assertFalse(safe_mount(s,a))

class MathChecks(unittest.TestCase):
    def test_probability_mass(self):
        for p in (Fraction(1,100),Fraction(3,100),Fraction(5,100)):
            for n in (40,60,80,100):self.assertEqual(sum(high_pity_distribution(p,n)),1)
    def test_mean_closed_form(self):
        for p in (Fraction(1,100),Fraction(3,100),Fraction(5,100)):
            for n in (40,60,80,100):self.assertEqual(high_pity_mean(p,n),(1-(1-p)**n)/p)
    def test_harder_guarantee_cannot_lengthen_expected_wait(self):self.assertLess(high_pity_mean(Fraction(3,100),40),high_pity_mean(Fraction(3,100),80))
    def test_pool_expansion_dilutes_target_without_control(self):self.assertLess(Fraction(3,100)/16,Fraction(3,100)/8)

if __name__=='__main__':unittest.main(verbosity=2)

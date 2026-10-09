"""Tests of the after-draw reference only; no claims of R6 battle or device QA."""
import unittest,zipfile,hashlib,random
from after_draw_model import *

A,B,C=candidates()
def simple(uid,q=0,tid='EQ_W_01',score=6500,**kw):
    return fixture_item(uid,tid,q,score,origin='gacha',**kw)
def ledger_fixture():
    old=[fixture_item('old','EQ_W_01',0,equipped=True)]
    new=[simple('new0'),simple('new1')]
    l=ReviewLedger({x.uid:x for x in old});l.accept('draw1',new)
    p=offer_cleanup(old,new);return l,p

class SourceContract(unittest.TestCase):
    def test_all_source_copies_equal_archive(self):
        meta=json.loads((ROOT/'data/SOURCE_COVERAGE.json').read_text())
        for r in meta['source_files']:
            self.assertEqual(hashlib.sha256((ROOT/r['copy']).read_bytes()).hexdigest(),r['sha256'])
    def test_original_zip_crc_and_hash(self):
        meta=json.loads((ROOT/'data/SOURCE_COVERAGE.json').read_text());p=ROOT/'source/RESEARCH_R3_ORIGINAL.zip'
        self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),meta['research_zip_sha256'])
        with zipfile.ZipFile(p) as z:self.assertIsNone(z.testzip())
    def test_candidate_ids_unchanged(self):self.assertEqual((A.id,C.id),tuple(PLAN['primary']['candidates']))
    def test_nine_initial_types(self):self.assertEqual(len(eligible()),9)
    def test_29_source_types(self):self.assertEqual(len(GEAR),29)
    def test_source_pool_gate(self):self.assertNotIn('EQ_W_G1',eligible())
    def test_parent_gate_without_craft_not_enough(self):self.assertNotIn('EQ_W_G1',eligible(INITIAL_GATES|{'G_R01_B'}))
    def test_parent_craft_without_gate_not_enough(self):self.assertNotIn('EQ_W_G1',eligible(crafted={'EQ_W_G1'}))
    def test_parent_gate_and_craft(self):self.assertIn('EQ_W_G1',eligible(INITIAL_GATES|{'G_R01_B'},crafted={'EQ_W_G1'}))
    def test_old_daily_denominator_wrong_not_silently_inherited(self):
        self.assertEqual(PLAN['natural_context']['powder_per_hour']*24,288)
        self.assertNotEqual(PLAN['natural_context']['powder_per_hour']*24,144)

class Draws(unittest.TestCase):
    def test_replay(self):self.assertEqual(Generator(C,7).draw(50),Generator(C,7).draw(50))
    def test_batch_matches_sequential(self):
        a=Generator(C,22);b=Generator(C,22)
        self.assertEqual(a.draw(50),sum((b.draw(1) for _ in range(50)),[]));self.assertEqual(a.state,b.state)
    def test_chunks_preserve_discovery(self):
        a=Generator(C,99);b=Generator(C,99)
        self.assertEqual(a.draw(50),b.draw(5)+b.draw(10)+b.draw(35))
    def test_snapshot_known_protected(self):
        g=Generator(C,9,known={'EQ_W_01'});items=g.draw(200)
        self.assertFalse(any(i.first_discovery for i in items if i.template_id=='EQ_W_01'))
        for tid in set(i.template_id for i in items)-{'EQ_W_01'}:self.assertEqual(sum(i.first_discovery for i in items if i.template_id==tid),1)
    def test_empty_draw_does_not_mutate(self):
        g=Generator(C,1);self.assertEqual(g.draw(0),[]);self.assertEqual(g.seq,0);self.assertEqual(g.state,Counters())
    def test_negative_draw(self):
        with self.assertRaises(ValueError):Generator(C,1).draw(-1)
    def test_bad_target(self):
        with self.assertRaises(ValueError):Generator(C,1,target='EQ_W_P2')
    def test_q0_no_affixes_q1_one(self):
        items=Generator(C,1).draw(500)
        self.assertTrue(any(i.quality==0 for i in items));self.assertTrue(any(i.quality==1 for i in items))
        for i in items:self.assertEqual(len(i.affixes),(0,1,2,3,3)[i.quality])
    def test_core_guarantee_only_when_slot_exists(self):
        for i in Generator(C,5).draw(500):
            if i.quality>0:self.assertIn(GEAR[i.template_id]['core_affix'],dict(i.affixes))
    def test_legendary_default_lock(self):
        for i in Generator(C,11).draw(500):self.assertEqual(i.locked,i.quality==4)
    def test_no_installed_funding_unequal_odds(self):
        # Generator has no funding input. This is not a real purchase-path test.
        self.assertEqual(Generator(C,777).draw(30),Generator(C,777).draw(30))
    def test_affix_quantile_range(self):
        self.assertTrue(all(5000<=v<=10000 for i in Generator(C,10).draw(100) for a,v in i.affixes))

class Cleanup(unittest.TestCase):
    def test_locked_preserved(self):
        x=simple('x',locked=True);self.assertNotIn('x',offer_cleanup([simple('old')],[x])['ids'])
    def test_equipped_preserved(self):
        x=simple('x',equipped=True);self.assertNotIn('x',offer_cleanup([simple('old')],[x])['ids'])
    def test_saved_preserved(self):
        x=simple('x',saved=True);self.assertNotIn('x',offer_cleanup([simple('old')],[x])['ids'])
    def test_invested_dust_preserved(self):
        x=simple('x',invested_powder=5);self.assertNotIn('x',offer_cleanup([simple('old')],[x])['ids'])
    def test_invested_material_preserved(self):
        x=simple('x',invested_materials=1);self.assertNotIn('x',offer_cleanup([simple('old')],[x])['ids'])
    def test_native_high_rank_not_fake_investment(self):
        old=simple('old',rank=2);x=simple('x',rank=2);self.assertIn('x',offer_cleanup([old],[x])['ids'])
    def test_first_discovery_kept(self):
        x=simple('x',first_discovery=True);self.assertNotIn('x',offer_cleanup([simple('old')],[x])['ids'])
    def test_old_inventory_never_proposed(self):
        self.assertFalse(offer_cleanup(profile('established_box'),[],2)['ids'])
    def test_q2_held_primary(self):
        self.assertFalse(offer_cleanup([simple('old',2,score=9000)],[simple('new',2,score=5000)])['ids'])
    def test_q2_can_be_optional_duplicate(self):
        self.assertEqual(offer_cleanup([simple('old',2,score=9000)],[simple('new',2,score=5000)],2)['ids'],['new'])
    def test_q3_never_bulk(self):
        self.assertFalse(offer_cleanup([simple('old',3,score=9000)],[simple('new',3,score=5000)],2)['ids'])
    def test_no_cross_quality_comparison(self):self.assertFalse(comparable_ge(simple('a',2),simple('b',1)))
    def test_crossed_affixes_keep_both(self):
        a=simple('a',2);b=simple('b',2)
        names=[x[0] for x in a.affixes];a=replace(a,affixes=((names[0],9500),(names[1],5000)));b=replace(b,affixes=((names[0],5000),(names[1],9500)))
        self.assertFalse(offer_cleanup([],[a,b],2)['ids'])
    def test_shared_amulett_needs_four_copies(self):
        x=[simple(str(i),tid='EQ_AMU_01') for i in range(5)]
        self.assertEqual(len(offer_cleanup([],x)['ids']),1)
    def test_cat_not_counted_as_human_body_owner(self):
        x=[simple(str(i),tid='EQ_BODY_01') for i in range(4)]
        self.assertEqual(len(offer_cleanup([],x)['ids']),1)
    def test_witness_not_also_scrapped(self):
        for seed in range(100):
            new=Generator(C,seed,known=eligible()).draw(50);p=offer_cleanup(profile('established_box'),new,2)
            self.assertFalse(any(set(w)&set(p['ids']) for w in p['witnesses'].values()))
    def test_conservation_counts(self):
        for seed in range(100):
            r,new,p=summarize_session(C,seed,'first_box',50);self.assertEqual(r['retained']+r['offered_for_optional_scrap'],50)
    def test_duplicate_ids_rejected(self):
        with self.assertRaises(ValueError):offer_cleanup([simple('same')],[simple('same')])

class Transactions(unittest.TestCase):
    def test_zero_auto_destruction_on_accept(self):
        l,p=ledger_fixture();self.assertEqual(len(l.inventory),3);self.assertEqual(l.dust,0)
    def test_full_box_uses_inbox(self):
        l=ReviewLedger({});x=Generator(C,1).draw(50);l.accept('x',x,0);self.assertEqual(len(l.inbox),50);self.assertFalse(l.inventory)
    def test_repeat_receipt_idempotent(self):
        l=ReviewLedger({});x=Generator(C,1).draw(50);l.accept('x',x);h=digest(l.state());l.accept('x',x);self.assertEqual(h,digest(l.state()))
    def test_receipt_collision_rejected(self):
        l=ReviewLedger({});l.accept('x',[simple('1')])
        with self.assertRaises(ValueError):l.accept('x',[simple('2')])
    def test_failed_scrap_is_atomic(self):
        l,p=ledger_fixture();q=l.quote(p['ids'],[1,2,4,0,0],p['ids']);h=digest(l.state())
        with self.assertRaises(RuntimeError):l.commit_scrap('s',q,p['ids'],True)
        self.assertEqual(h,digest(l.state()));l.commit_scrap('s',q,p['ids']);self.assertEqual(l.dust,2)
    def test_repeat_scrap_is_idempotent(self):
        l,p=ledger_fixture();q=l.quote(p['ids'],[1,2,4,0,0],p['ids']);l.commit_scrap('s',q,p['ids']);h=digest(l.state());l.commit_scrap('s',q,p['ids']);self.assertEqual(h,digest(l.state()))
    def test_stale_lock_rejected(self):
        l,p=ledger_fixture();q=l.quote(p['ids'],[1,2,4,0,0],p['ids']);l.lock('new0')
        with self.assertRaises(ValueError):l.commit_scrap('s',q,p['ids'])
        self.assertEqual(l.dust,0);self.assertIn('new0',l.inventory)
    def test_tampered_amount_rejected(self):
        l,p=ledger_fixture();q=l.quote(p['ids'],[1,2,4,0,0],p['ids']);q['powder']=999
        with self.assertRaises(ValueError):l.commit_scrap('s',q,p['ids'])
    def test_empty_selection_rejected(self):
        l,p=ledger_fixture()
        with self.assertRaises(ValueError):l.quote([], [1,2,4,0,0],p['ids'])
    def test_manual_fake_allowlist_not_trusted(self):
        l=ReviewLedger({});l.accept('x',[simple('unique')])
        with self.assertRaises(ValueError):l.quote(['unique'],[1,2,4,0,0],['unique'])
    def test_witness_disappears_rejected(self):
        l,p=ledger_fixture();q=l.quote(p['ids'],[1,2,4,0,0],p['ids']);l.inventory.pop('old');l.revision+=1
        with self.assertRaises(ValueError):l.commit_scrap('s',q,p['ids'])
    def test_quote_does_not_commit(self):
        l,p=ledger_fixture();h=digest(l.state());l.quote(p['ids'],[1,2,4,0,0],p['ids']);self.assertEqual(h,digest(l.state()))
    def test_inbox_scrap_keeps_protected(self):
        l=ReviewLedger({'old':fixture_item('old','EQ_W_01',0,equipped=True)});x=[simple('a'),simple('b',locked=True)];l.accept('x',x,1)
        p=offer_cleanup([l.inventory['old']],list(l.inbox.values()));q=l.quote(p['ids'],[1,2,4,0,0],p['ids']);l.commit_scrap('s',q,p['ids'])
        self.assertIn('b',l.inbox);self.assertEqual(l.dust,1)

class Upgrade(unittest.TestCase):
    def test_zero_powder(self):self.assertEqual(enhancement_probe(0)['affordable_steps'],0)
    def test_four_no_upgrade(self):self.assertEqual(enhancement_probe(4)['affordable_steps'],0)
    def test_five_one_step(self):self.assertEqual(enhancement_probe(5)['affordable_steps'],1)
    def test_fifteen_two_steps(self):self.assertEqual(enhancement_probe(15)['affordable_steps'],2)
    def test_thirty_full_plus3(self):self.assertEqual(enhancement_probe(30)['full_plus3_items'],1)
    def test_ninety_three_full(self):self.assertEqual(enhancement_probe(90)['full_plus3_items'],3)
    def test_extra_dust_not_overspent(self):self.assertEqual(enhancement_probe(200)['left'],110)
    def test_at_cap_has_no_strength_upgrade(self):self.assertEqual(enhancement_probe(100,True)['affordable_steps'],0)
    def test_monotonic_affordable_steps(self):
        prev=0
        for d in range(150):
            r=enhancement_probe(d);self.assertGreaterEqual(r['affordable_steps'],prev);self.assertEqual(r['spent']+r['left'],d);prev=r['affordable_steps']

if __name__=='__main__':unittest.main(verbosity=2)

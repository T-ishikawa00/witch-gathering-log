"""Contract tests for math comparisons, not player-experience acceptance."""
import hashlib,json,unittest,zipfile,random
from dataclasses import replace
from collections import defaultdict
from compare_gacha import *

class ComparisonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.a,cls.b,cls.c=candidates()
    def test_probabilities_sum(self):
        for c in candidates():self.assertEqual(sum(c.probability_bp),10000)
    def test_bad_probability_rejected(self):
        with self.assertRaises(ValueError):replace(self.a,probability_bp=(0,0,0,0,9999))
    def test_negative_price_rejected(self):
        with self.assertRaises(ValueError):replace(self.a,yen_equivalent_per_pull=0)
    def test_bad_roll_rejected(self):
        with self.assertRaises(ValueError):step(self.a,Counters(),10000,0)
    def test_illegal_counter_rejected(self):
        with self.assertRaises(ValueError):step(self.a,Counters(40,0),0,0)
    def test_baseline_matches_original_json(self):
        old=json.loads((ROOT/'source/GACHA_CANDIDATE_R2_UNCHANGED.json').read_text())
        self.assertEqual(self.a.probability_bp,tuple(old['base_probability_bp'].get('Q'+str(i),0) for i in range(5)))
        self.assertEqual(self.a.top_pity,old['top_pity']);self.assertEqual(self.a.mid_pity,old['mid_pity'])
        self.assertEqual(self.a.yen_equivalent_per_pull,old['ticket_price_jpy_proposal'])
    def test_original_byte_hashes(self):
        for row in json.loads((ROOT/'source/SOURCE_HASHES.json').read_text()):
            self.assertEqual(hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest(),row['sha256'])
    def test_original_zip_crc(self):
        with zipfile.ZipFile(ROOT/'source/COMMERCE_R2_ORIGINAL.zip') as z:self.assertIsNone(z.testzip())
    def test_common_is_possible(self):self.assertEqual(step(self.c,Counters(),9999,9999)[0],0)
    def test_old_never_common(self):
        self.assertEqual(min(step(self.a,Counters(),i,0)[0] for i in range(10000)),2)
    def test_mid_pity_does_not_increase_top_odds(self):
        results=[step(self.c,Counters(25,19),i,0)[0] for i in range(10000)]
        self.assertEqual(results.count(4),100);self.assertEqual(results.count(3),9900)
    def test_top_pity_precedes_mid(self):
        q,_,s=step(self.c,Counters(99,19),9999,9999);self.assertEqual(q,4);self.assertEqual((s.top_miss,s.mid_miss),(0,0))
    def test_no_top_early_guarantee(self):self.assertNotEqual(step(self.c,Counters(98,18),9999,9999)[0],4)
    def test_non_target_enables_guarantee(self):
        q,t,s=step(self.c,Counters(),0,9999);self.assertEqual((q,t,s.force_target),(4,False,True))
    def test_guarantee_survives_low_draw(self):
        _,_,s=step(self.c,Counters(0,0,True),9999,9999);self.assertTrue(s.force_target)
    def test_guaranteed_target_clears_force(self):
        q,t,s=step(self.c,Counters(0,0,True),0,9999);self.assertEqual((q,t,s.force_target),(4,True,False))
    def test_upper_bound_bad_luck(self):
        for c in candidates():
            s=Counters();selected=None
            for n in range(1,c.top_pity*2+1):
                q,t,s=step(c,s,9999,9999)
                if q==4 and t:selected=n;break
            self.assertEqual(selected,2*c.top_pity)
    def test_batch_equal_single(self):
        rng=random.Random(90);rolls=[(rng.randrange(10000),rng.randrange(10000)) for _ in range(50)]
        def run(groups):
            s=Counters();out=[]
            for group in groups:
                for q,t in group:
                    a,b,s=step(self.c,s,q,t);out.append((a,b,s))
            return out
        self.assertEqual(run([rolls]),run([rolls[i:i+10] for i in range(0,50,10)]))
    def test_top_pmf_mass(self):
        for c in candidates():self.assertAlmostEqual(sum(first_top_pmf(c)),1,places=11)
    def test_target_pmf_mass(self):
        for c in candidates():self.assertAlmostEqual(sum(selected_top_pmf(c)),1,places=10)
    def test_target_mean_formula(self):
        for c in candidates():
            first=sum((i+1)*p for i,p in enumerate(first_top_pmf(c)))
            target=sum((i+1)*p for i,p in enumerate(selected_top_pmf(c)))
            self.assertAlmostEqual(target,(2-c.target_probability_bp/10000)*first,places=8)
    def test_convolution_matches_independent_finite_state(self):
        c=self.a;states={(0,False):1.};pmf=[]
        for _ in range(2*c.top_pity):
            nxt=defaultdict(float);hit=0.
            for (miss,force),m in states.items():
                p=1. if miss==c.top_pity-1 else c.probability_bp[4]/10000
                hit+=m*p*(1 if force else .5)
                if not force:nxt[0,True]+=m*p*.5
                if p<1:nxt[miss+1,force]+=m*(1-p)
            pmf.append(hit);states=nxt
        for x,y in zip(pmf,selected_top_pmf(c)):self.assertAlmostEqual(x,y,places=13)
    def test_zero_horizon(self):self.assertEqual(quality_horizons(self.c,[0])[0]['expected_quality_counts'],[0]*5)
    def test_horizon_total_counts(self):
        for c in candidates():
            for n,r in quality_horizons(c,[1,10,50]).items():
                self.assertAlmostEqual(sum(r['expected_quality_counts']),n,places=8);self.assertAlmostEqual(r['probability_mass'],1,places=10)
    def test_unforced_top_expectation(self):
        for c in candidates():
            x=quality_horizons(c,[10])[10]['expected_quality_counts'][4]
            self.assertAlmostEqual(x,10*c.probability_bp[4]/10000,places=10)
    def test_no_rare_probability_correct(self):
        self.assertAlmostEqual(no_rare_probability(self.c,10),.75**10)
        self.assertAlmostEqual(no_rare_probability(self.b,10),.9**10)
        self.assertEqual(no_rare_probability(self.a,10),0)
    def test_all_common_batch_impossible_after_mid_pity(self):self.assertEqual(no_rare_probability(self.c,20),0)
    def test_expected_price_not_just_pull_count(self):
        ma=sum((i+1)*p for i,p in enumerate(selected_top_pmf(self.a)))*150
        mb=sum((i+1)*p for i,p in enumerate(selected_top_pmf(self.b)))*15
        self.assertLess(abs(ma-mb)/ma,.01)
    def test_sampling_matches_cdf_in_documented_runs(self):
        r=json.loads((ROOT/'results/ANALYSIS_R3.json').read_text())
        for d in r['candidates']:self.assertLess(d['sampling_crosscheck']['max_cdf_absolute_difference'],.02)
    def test_same_nominal_daily_free_yen(self):
        self.assertEqual({c.free_pulls_per_day*c.yen_equivalent_per_pull for c in candidates()},{150})

if __name__=='__main__':unittest.main(verbosity=2)

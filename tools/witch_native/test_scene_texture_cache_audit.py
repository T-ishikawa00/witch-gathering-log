import copy
import unittest
from scene_texture_cache_audit import verify


class CacheAuditContractTests(unittest.TestCase):
    def setUp(self):
        cache = dict(entries=5, estimatedBytes=100, byteLimit=64*1024*1024,
                     entryLimit=128, hits=1, misses=6, evictions=1)
        self.raw = {}
        self.raw['rows'] = [dict(**{'pass': p}, sceneID='SCN_A_R%02d_%02d' % (r, a),
            backgroundLoaded=True, sceneMatches=True, renderedAfterConfigure=True,
            actualBackgroundID='BG', expectedBackgroundID='BG', cache=copy.deepcopy(cache))
            for p in [1, 2] for r in range(1, 6) for a in range(1, 5)]
        self.raw.update(pressureRows=[dict(id='HOME_BASE', loaded=True, cache=copy.deepcopy(cache))],
            afterClear=dict(entries=0, estimatedBytes=0), finalCache=copy.deepcopy(cache),
            heldTextureSurvivesCacheClear=True, heldTextureSurvivesRouteSweep=True,
            stateUnchanged=True, saveUnchanged=True, initialSaveSHA256='abc', finalSaveSHA256='abc', restoredTab='家')
        self.raw.update(beforePressure=dict(evictions=0), initialContext=dict(tab='家',region='R01',activeEnemy=None),
                        restoredContext=dict(tab='家',region='R01',activeEnemy=None))

    def check(self): return verify(self.raw, ['HOME_BASE'])

    def test_complete_scoped_report(self): self.assertTrue(all(self.check().values()))

    def test_duplicate_scene_cannot_replace_missing_scene(self):
        self.raw['rows'][1]['sceneID'] = self.raw['rows'][0]['sceneID']
        self.assertFalse(self.check()['twoPassesOfTwentyScenes'])

    def test_over_budget_rejected(self):
        self.raw['rows'][5]['cache']['estimatedBytes'] = 64*1024*1024+1
        self.assertFalse(self.check()['allCacheBounds'])

    def test_no_eviction_does_not_prove_pressure(self):
        for row in self.raw['rows'] + self.raw['pressureRows']: row['cache']['evictions'] = 0
        self.raw['finalCache']['evictions'] = 0
        self.assertFalse(self.check()['pressureActuallyEvicted'])

    def test_save_mismatch_rejected_even_if_boolean_true(self):
        self.raw['finalSaveSHA256'] = 'changed'
        self.assertFalse(self.check()['stateAndSaveUnchanged'])

    def test_missing_texture_is_failure(self):
        self.raw['pressureRows'][0]['loaded'] = False
        self.assertFalse(self.check()['exactPressureIDsLoaded'])

    def test_wrong_background_is_failure(self):
        self.raw['rows'][0]['actualBackgroundID'] = 'OTHER'
        self.assertFalse(self.check()['backgroundsLoadedAndRendered'])

    def test_missing_cache_metrics_is_failure(self):
        self.raw['finalCache'] = {}
        self.assertFalse(self.check()['allCacheBounds'])

    def test_old_route_evictions_do_not_prove_pressure(self):
        self.raw['beforePressure']['evictions'] = 1
        self.assertFalse(self.check()['pressureActuallyEvicted'])

    def test_wrong_restored_context_is_failure(self):
        self.raw['restoredContext']['region'] = 'R05'
        self.assertFalse(self.check()['presentationContextRestored'])


if __name__ == '__main__': unittest.main()

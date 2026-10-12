import unittest

from run_effect_projection_previews import actor_is_loaded, current_background_matches, report_events, require_pair, require_direct


class ProjectionPreviewContractTests(unittest.TestCase):
    def test_current_area_rejects_stale_base_flag_and_wrong_or_fallback_route(self):
        art = {"states": {"background_BG_R03_FIELD": True, "background_VAR_A_R03_03": True},
               "areaBackground": {"regionID": "R03", "areaID": "A_R03_03",
                                  "sceneID": "SCN_A_R03_03", "renderedBackgroundID": "VAR_A_R03_03"}}
        self.assertTrue(current_background_matches("E03_MAGNET", art, "R03"))
        for key, value in (("areaID", "A_R03_01"), ("sceneID", "SCN_A_R03_01"),
                           ("renderedBackgroundID", "BG_R03_FIELD"), ("fallbackReason", "decode_failed")):
            bad = {**art, "areaBackground": {**art["areaBackground"], key: value}}
            self.assertFalse(current_background_matches("E03_MAGNET", bad, "R03"), key)
        self.assertFalse(current_background_matches("E03_MAGNET", {**art, "states": {"background_BG_R03_FIELD": True}}, "R03"))

    def test_current_boss_area_uses_boss_background(self):
        art = {"states": {"background_BG_R02_BOSS": True},
               "areaBackground": {"regionID": "R02", "areaID": "A_R02_04",
                                  "sceneID": "SCN_A_R02_04", "renderedBackgroundID": "BG_R02_BOSS"}}
        self.assertTrue(current_background_matches("B02_MIRROR", art, "R02"))
        self.assertFalse(current_background_matches("B02_MIRROR", {**art, "areaBackground": {}}, "R02"))

    def test_legacy_receipts_keep_their_legacy_background_rule(self):
        self.assertTrue(current_background_matches("E03_MAGNET", {"states": {"background_BG_R03_FIELD": True}}, "R03"))
        self.assertFalse(current_background_matches("E03_MAGNET", {"states": {"background_BG_R03_FIELD": False}}, "R03"))

    def test_actor_load_requires_actor_state_and_finite_positive_geometry(self):
        art = {"actorIDs": ["ACT_E_R01_01"],
               "states": {"ACT_E_R01_01:battle_entry_walk": True},
               "geometry": {"ACT_E_R01_01": {"width": 42.0, "height": 30.0}}}
        self.assertTrue(actor_is_loaded(art, "E_R01_01"))
        for value in (0, -1, True, float("inf"), float("nan")):
            invalid = {**art, "geometry": {"ACT_E_R01_01": {"width": value, "height": 30.0}}}
            self.assertFalse(actor_is_loaded(invalid, "E_R01_01"), repr(value))
        self.assertFalse(actor_is_loaded({**art, "states": {"load_ACT_E_R01_01": True}}, "E_R01_01"))
        self.assertFalse(actor_is_loaded({**art, "actorIDs": []}, "E_R01_01"))

    def test_pair_requires_exact_cue_and_impact_target_set(self):
        rows = [
            {"effectID": "FX", "rootActionID": "root1", "step": "cue_placement", "targetIDs": "ERNA,AIRA"},
            {"effectID": "FX", "rootActionID": "root1", "step": "impact_placement", "targetIDs": "ERNA,AIRA"},
        ]
        self.assertTrue(require_pair(rows, "FX", "root1", {"ERNA", "AIRA"}))

    def test_pair_rejects_missing_impact(self):
        rows = [{"effectID": "FX", "rootActionID": "root1", "step": "cue_placement", "targetIDs": "ERNA"}]
        self.assertFalse(require_pair(rows, "FX", "root1", {"ERNA"}))

    def test_pair_rejects_extra_recipient(self):
        rows = [
            {"effectID": "FX", "rootActionID": "root1", "step": "cue_placement", "targetIDs": "ERNA,AIRA"},
            {"effectID": "FX", "rootActionID": "root1", "step": "impact_placement", "targetIDs": "ERNA,AIRA,ACT_BOSS"},
        ]
        self.assertFalse(require_pair(rows, "FX", "root1", {"ERNA", "AIRA"}))

    def test_direct_requires_exactly_one_row_and_exact_target(self):
        row = {"effectID": "FX", "rootActionID": "root1", "step": "direct_full:enemy_armor", "targetIDs": "ACT_BOSS"}
        self.assertTrue(require_direct([row], "FX", "root1", {"direct_full:enemy_armor", "coalesced:enemy_armor"}, {"ACT_BOSS"}))
        self.assertFalse(require_direct([row, row], "FX", "root1", {"direct_full:enemy_armor", "coalesced:enemy_armor"}, {"ACT_BOSS"}))
        self.assertFalse(require_direct([row], "FX", "root1", {"direct_full:enemy_armor"}, {"ERNA"}))

    def test_event_merge_deduplicates_identical_raw_and_relevant_entries(self):
        event = {"kind": "enemy_hit", "sourceID": "BOSS", "targetID": "C_WITCH", "amount": 44,
                 "rootActionID": "enemy:BOSS:1", "timestampMs": 1500}
        report = {"result": {"events": [event]}, "events": [event], "relevantEvents": [event]}
        self.assertEqual(report_events(report), [event])

    def test_event_merge_collapses_enriched_projection_of_same_event(self):
        base = {"kind": "enemy_light_transfer", "sourceID": "E_R05_03", "targetID": "E_R05_02",
                "amount": 1500, "rootActionID": "enemy:E_R05_03:1", "timestampMs": 2500}
        enriched = {**base, "tick": 2, "diagnostics": {"duration_ms": 5000}}
        self.assertEqual(report_events({"result": {"events": [base]}, "relevantEvents": [enriched]}), [enriched])

    def test_compact_duplicate_cannot_discard_full_hit_coefficient(self):
        compact = {"kind": "enemy_hit", "sourceID": "E_R03_04", "targetID": "C_SMITH",
                   "amount": 440, "rootActionID": "enemy:E_R03_04:1", "timestampMs": 2000}
        full = {**compact, "tick": 2, "diagnostics": {"candidateMagnetCoefficientBP": 12500}}
        for report in ({"relevantEvents": [compact], "events": [full]},
                       {"result": {"events": [compact]}, "events": [full]}):
            self.assertEqual(report_events(report), [full])
        self.assertNotIn("diagnostics", compact, "Merging must not alter the raw report")

    def test_conflicting_duplicate_diagnostics_are_rejected(self):
        base = {"kind": "enemy_hit", "sourceID": "E_R03_04", "targetID": "C_SMITH",
                "amount": 440, "rootActionID": "enemy:E_R03_04:1", "timestampMs": 2000}
        report = {"events": [{**base, "diagnostics": {"candidateMagnetCoefficientBP": 12500}}],
                  "relevantEvents": [{**base, "diagnostics": {"candidateMagnetCoefficientBP": 12499}}]}
        with self.assertRaisesRegex(ValueError, "Conflicting event projections"):
            report_events(report)


if __name__ == "__main__":
    unittest.main()

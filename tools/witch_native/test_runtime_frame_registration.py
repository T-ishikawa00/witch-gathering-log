import unittest
import sys
from pathlib import Path
import json
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_runtime_frame_registration as audit


class RuntimeFrameRegistrationTests(unittest.TestCase):
    def test_current_candidate_tables_match_real_runtime_manifest_tuples(self):
        report = audit.audit()
        current = [row for row in report["tables"] if row["actor"] != "NOIR_R001_ERRATUM"]
        self.assertEqual({row["actor"] for row in current}, {"AIRA", "ERNA", "LUNA", "NOIR"})
        self.assertTrue(all(row["status"] == "PASS" for row in current), current)
        self.assertTrue(all(not row["unreachableRows"] for row in current), current)
        self.assertTrue(all(row["status"] == "PASS" for row in report["runtimeCallsiteChecks"]))

    def test_noir_attack_04_is_execute_clip_local_index_one(self):
        actual = audit.runtime_tuples()["NOIR"]
        matching = [row for row in actual if row.asset_id == "GeneratedArt/PartyAttack/NOIR__attack_04.png"]
        self.assertEqual([(row.frame_index, row.state) for row in matching], [(1, "execute")])
        noir_rows = next(rows for actor, _, rows in audit.registration_sources() if actor == "NOIR")
        row = next(row for row in noir_rows if row["runtimeBodyAssetID"].endswith("NOIR__attack_04.png"))
        self.assertEqual(row["runtimeFrameIndex"], 1)

    def test_noir_walk_source_suffix_is_not_runtime_index(self):
        actual = audit.runtime_tuples()["NOIR"]
        walk2 = [row for row in actual if row.asset_id.endswith("NOIR__walk_2.png")]
        self.assertEqual([(row.frame_index, row.state) for row in walk2], [(1, "walk")])
        noir_rows = next(rows for actor, _, rows in audit.registration_sources() if actor == "NOIR")
        row = next(row for row in noir_rows if row["runtimeBodyAssetID"].endswith("NOIR__walk_2.png"))
        self.assertEqual(row["runtimeFrameIndex"], 1)
        self.assertEqual(row["sourceFrameIndex"], 2)

    def test_regression_detects_a_candidate_row_with_only_unreachable_index(self):
        actual = audit.runtime_tuples()["NOIR"]
        correct = next(row for row in actual if row.asset_id.endswith("NOIR__attack_04.png"))
        self.assertFalse(any(row.asset_id == correct.asset_id and row.frame_index == 4
                             and row.canvas == correct.canvas for row in actual))

    def test_historical_noir_r001_error_is_preserved_as_erratum(self):
        report = audit.audit()
        historical = next(row for row in report["tables"] if row["actor"] == "NOIR_R001_ERRATUM")
        self.assertEqual(historical["status"], "KNOWN_ERRATUM")
        self.assertEqual(len(historical["unreachableRows"]), 12)
        self.assertTrue(all("PartyRest/NOIR__rest_" in row["assetID"] or
                            "PartyAttack/NOIR__attack_" in row["assetID"]
                            for row in historical["unreachableRows"]))

    def test_latest_merged_runtime_index_has_all_candidate_tuples_once(self):
        index = Path("native/build/app_20261010T210950/WitchGathering.app/Art/runtime_index.json")
        result = audit.audit_runtime_index(audit.ROOT, index)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["expectedCandidateTupleCount"], 134)
        self.assertEqual(result["reachableCandidateTupleCount"], 134)
        self.assertEqual(result["missingExpectedCandidates"], 0)
        self.assertEqual(result["duplicateTupleCount"], 0)
        self.assertEqual(result["unreachableRows"], [])

    def test_runtime_index_probe_flags_removed_and_duplicate_rows(self):
        source = json.loads(Path("native/build/app_20261010T210950/WitchGathering.app/Art/runtime_index.json").read_text())
        rows = source["entries"]["ERNA"]["semanticFrameLandmarksCandidate"]["rows"]
        rows.pop()
        rows.append(rows[0].copy())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "runtime_index.json"
            path.write_text(json.dumps(source))
            result = audit.audit_runtime_index(audit.ROOT, path)
        self.assertEqual(result["missingExpectedCandidates"], 1)
        self.assertEqual(result["duplicateTupleCount"], 1)
        self.assertEqual(result["status"], "PARTIAL_OR_INVALID")


if __name__ == "__main__":
    unittest.main()

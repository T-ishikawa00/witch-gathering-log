from pathlib import Path
import json
import tempfile
import unittest
from unittest.mock import patch
import storage_guard as guard


class StorageGuardTests(unittest.TestCase):
    def test_thresholds_and_expected_output(self):
        self.assertEqual(guard.capacity_state(34_700_000_000, True, 2_000_000_000), "READY")
        self.assertEqual(guard.capacity_state(50_000_000_000, True), "HOLD_LARGE_OUTPUT")
        self.assertEqual(guard.capacity_state(9_999_999_999, True, 0), "HOLD_LARGE_OUTPUT")
        self.assertEqual(guard.capacity_state(10_000_000_000, True, 0), "HOLD_LARGE_OUTPUT")
        self.assertEqual(guard.capacity_state(10_000_000_000, False), "WARN_LOW_CAPACITY")
        self.assertEqual(guard.capacity_state(12_249_999_999, True, 250_000_000), "HOLD_LARGE_OUTPUT")
        self.assertEqual(guard.capacity_state(12_250_000_000, True, 250_000_000), "WARN_LOW_CAPACITY")
        self.assertEqual(guard.capacity_state(22_250_000_000, True, 250_000_000), "READY")
        self.assertEqual(guard.capacity_state(19_999_999_999, False), "WARN_LOW_CAPACITY")
        self.assertEqual(guard.capacity_state(20_000_000_000, False), "READY")
        with self.assertRaises(ValueError):
            guard.capacity_state(-1, True)
        with self.assertRaises(ValueError):
            guard.capacity_state(50_000_000_000, True, -1)

    def test_task_specific_floor_and_maximum_override_general_threshold(self):
        self.assertEqual(guard.capacity_state(34_700_000_000, True, 23_000_000_000), "HOLD_LARGE_OUTPUT")
        self.assertEqual(guard.capacity_state(34_700_000_000, True, 2_000_000_000,
                                             minimum_remaining_bytes=31_000_000_000), "HOLD_LARGE_OUTPUT")
        budget = guard.capacity_budget(34_700_000_000, True, 250_000_000)
        self.assertEqual(budget['requiredStartBytes'], 12_250_000_000)
        self.assertEqual(budget['projectedFreeAfterSafetyBytes'], 32_450_000_000)
        self.assertEqual(guard.capacity_budget(9_000_000_000, True, 0, safety_bytes=0,
                                              minimum_remaining_bytes=0)['minimumRemainingBytes'], 10_000_000_000)
        for value in [float('nan'), float('inf'), -1, True]:
            with self.assertRaises(ValueError):
                guard.capacity_state(34_700_000_000, True, value)

    def test_hold_retains_evidence_without_touching_artifact(self):
        with tempfile.TemporaryDirectory(prefix="witch-capacity-test-") as temporary:
            root = Path(temporary)
            artifact = root / "source.dat"
            artifact.write_bytes(b"protected")
            with patch.object(guard.shutil, "disk_usage") as usage:
                usage.return_value.free = 29_000_000_000
                with self.assertRaises(guard.StorageCapacityError):
                    guard.check_capacity(root, "isolated-negative", heavy=True, artifact_paths=[artifact])
            self.assertEqual(artifact.read_bytes(), b"protected")
            row = json.loads((root / "docs/production/current/storage_management_r001/CAPACITY_EVENTS_R002.jsonl").read_text())
            self.assertFalse(row["deletion"])
            self.assertEqual(row["status"], "HOLD_LARGE_OUTPUT")
            self.assertEqual(row["holdReason"], "EXPECTED_MAXIMUM_NOT_SUPPLIED")
            self.assertEqual(row["artifacts"][0]["logicalBytes"], 9)

    def test_symlinks_and_overlapping_paths_not_double_counted(self):
        with tempfile.TemporaryDirectory(prefix="witch-capacity-test-") as temporary:
            root = Path(temporary)
            (root / "a").write_bytes(b"1234")
            (root / "link").symlink_to(root)
            rows = guard.measure_artifacts([root, root / "a"])
            self.assertEqual(sum(row["logicalBytes"] for row in rows), 4)
            self.assertEqual(sum(row["symlinksSkipped"] for row in rows), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)

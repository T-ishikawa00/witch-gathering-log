"""Receipt regressions: compact phones must pass without accepting giant sprites."""
import json
import os
from pathlib import Path
import tempfile
import time
import unittest

from party_motion_audit import field_heights, validated_geometry


class MotionGeometryTests(unittest.TestCase):
    def receipt(self, folder, height, stale=False):
        launched = time.time() - 2
        state = folder / 'last_party_state.json'
        state.write_text(json.dumps({'value': 'walk'}))
        geometry = folder / 'last_party_geometry.json'
        payload = {'states': {a + ':walk': True for a in height},
                   'expectedPartyHeights': height,
                   'geometry': {a: {'height': h} for a, h in height.items()}}
        geometry.write_text(json.dumps({'value': json.dumps(payload)}))
        if stale:
            os.utime(geometry, (launched - 1, launched - 1))
        return launched

    def test_compact_and_tall_field_receipts(self):
        for width, compact, human, cat in [(375, True, 95.1492537313, 67.1641791045),
                                           (440, False, 145.5721393035, 78.8059701493)]:
            expected = field_heights(width, compact)
            self.assertAlmostEqual(expected['LUNA'], human)
            self.assertAlmostEqual(expected['NOIR'], cat)
            with tempfile.TemporaryDirectory() as temp:
                folder = Path(temp)
                start = self.receipt(folder, expected)
                self.assertTrue(validated_geometry(folder, start, .2, expected))

    def test_wrong_renderer_expectation_cannot_self_certify(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            start = self.receipt(folder, {a: 256 for a in field_heights(375, True)})
            with self.assertRaises(RuntimeError):
                validated_geometry(folder, start, .08, field_heights(375, True))

    def test_stale_geometry_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            expected = field_heights(375, True)
            start = self.receipt(folder, expected, stale=True)
            with self.assertRaises(RuntimeError):
                validated_geometry(folder, start, .08, expected)


if __name__ == '__main__':
    unittest.main()

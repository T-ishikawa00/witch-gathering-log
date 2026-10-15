import unittest

from run_r456 import elapsed_seconds


class RuntimeClockR456Tests(unittest.TestCase):
    def test_epoch_start_is_comparable_across_helper_invocations(self):
        start = 1_797_000_000_000_000_000
        later = start + 6_549_201_291
        self.assertAlmostEqual(elapsed_seconds(start, later), 6.549201291)

    def test_backward_wall_clock_fails_closed(self):
        with self.assertRaisesRegex(RuntimeError, "wall clock moved backward"):
            elapsed_seconds(2_000, 1_999)

    def test_invalid_persisted_start_fails_closed(self):
        for start in (-1, True, 1.5):
            with self.subTest(start=start):
                with self.assertRaisesRegex(RuntimeError, "invalid persisted epoch start time"):
                    elapsed_seconds(start, 2_000)


if __name__ == "__main__":
    unittest.main()

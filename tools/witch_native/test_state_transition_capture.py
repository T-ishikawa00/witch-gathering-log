import json
import hashlib
from pathlib import Path
import tempfile
import unittest

import state_transition_capture as capture


class StateTransitionCaptureContractTests(unittest.TestCase):
    def test_final_screenshot_command_is_device_scoped(self):
        destination = Path("/tmp/final.png")
        self.assertEqual(capture.final_screenshot_command("SIM-123", destination),
                         ["xcrun", "simctl", "io", "SIM-123", "screenshot", "/tmp/final.png"])

    def test_empty_or_incomplete_capture_cannot_pass(self):
        actor = "ACT_E_R05_04"
        valid_case = {"actorID": actor, "status": "CAPTURED_REQUIRES_HOST_AND_VISUAL_REVIEW"}
        valid_capture = {"recorderExitCode": 0, "videoHasFrames": True, "videoDecodePass": True,
                         "videoSHA256": "video", "finalScreenshotSHA256": "image"}
        self.assertFalse(capture.completion_checks([actor], [], {}, True)["success"])
        self.assertFalse(capture.completion_checks([actor], [valid_case], {}, True)["success"])
        self.assertFalse(capture.completion_checks([actor], [valid_case], {actor: valid_capture}, False)["success"])
        self.assertTrue(capture.completion_checks([actor], [valid_case], {actor: valid_capture}, True)["success"])
        self.assertFalse(capture.completion_checks([actor], [valid_case, valid_case], {actor: valid_capture}, True)["success"])
        self.assertFalse(capture.completion_checks([actor], [valid_case], {actor: dict(valid_capture, videoDecodePass=False)}, True)["success"])

    def test_build_source_snapshot_requires_exact_pinned_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            source = folder / "LivingScene.swift"
            source.write_bytes(b"frozen")
            digest = hashlib.sha256(b"frozen").hexdigest()
            receipt = {"source_snapshot": str(folder), "source_sha256": {"native/WitchApp/LivingScene.swift": digest}}
            self.assertEqual(capture.validate_source_snapshot(receipt), {
                "source_snapshot_present": True, "source_snapshot_hashes_match": True})
            source.write_bytes(b"changed")
            self.assertEqual(capture.validate_source_snapshot(receipt)["source_snapshot_hashes_match"], False)

    def test_sample_requires_fresh_matching_actor_and_requested_state(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "last_art_sample_idle_early.json"
            payload = {"actorIDs": ["ACT_E_R05_04"],
                       "states": {"ACT_E_R05_04:idle": True},
                       "enemyPresentation": {"ACT_E_R05_04": {"state": "idle", "frameIndex": 1}}}
            path.write_text(json.dumps({"kind": "art_sample_idle_early", "value": json.dumps(payload)}))
            self.assertIsNone(capture.parse_art_payload(path, path.stat().st_mtime + 1, "ACT_E_R05_04", "idle"))
            self.assertIsNone(capture.parse_art_payload(path, 0, "ACT_E_R05_03", "idle"))
            self.assertIsNone(capture.parse_art_payload(path, 0, "ACT_E_R05_04", "walk"))
            self.assertIsNotNone(capture.parse_art_payload(path, 0, "ACT_E_R05_04", "idle"))

    def test_late_sample_requires_exact_expected_transition_and_real_clip_path(self):
        actor = "ACT_E_R05_04"
        clips = {
            "anticipate": {"frames": ["a0.png", "a1.png", "a2.png"], "fps": 10, "loop": False},
            "execute": {"frames": ["e0.png", "e1.png", "e2.png"], "fps": 10, "loop": False},
            "recover": {"frames": ["r0.png", "r1.png", "r2.png"], "fps": 10, "loop": False},
            "idle": {"frames": ["i0.png", "i1.png", "i2.png"], "fps": 3, "loop": True},
            "walk": {"frames": ["w0.png", "w1.png"], "fps": 8, "loop": True},
            "hit": {"frames": ["h0.png", "h1.png", "h2.png"], "fps": 12, "loop": False},
            "resolve": {"frames": ["z0.png", "z1.png", "z2.png"], "fps": 8, "loop": False},
        }
        self.assertEqual(capture.expected_late_state("anticipate", clips), "idle")
        self.assertEqual(capture.expected_late_state("execute", clips), "recover")
        self.assertEqual(capture.expected_late_state("recover", clips), "idle")
        self.assertEqual(capture.expected_late_state("hit", clips), "idle")
        self.assertEqual(capture.expected_late_state("resolve", clips), "resolve")
        self.assertEqual(capture.expected_state_at("anticipate", clips, .15), "anticipate")
        self.assertEqual(capture.expected_state_at("anticipate", clips, .4), "idle")
        self.assertEqual(capture.expected_state_at("execute", clips, .4), "recover")
        self.assertEqual(capture.expected_state_at("execute", clips, .7), "idle")
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "last_art_sample_anticipate_late.json"
            payload = {"actorIDs": [actor], "states": {actor + ":anticipate": True},
                       "enemyPresentation": {actor: {"state": "idle", "frameIndex": 1,
                           "framePath": "i1.png", "isPartRig": False}}}
            path.write_text(json.dumps({"kind": "art_sample_anticipate_late", "value": json.dumps(payload)}))
            self.assertIsNotNone(capture.parse_art_payload(path, 0, actor, "idle", "anticipate"))
            self.assertTrue(capture.presentation_matches_clip(payload["enemyPresentation"][actor], "idle", clips))
            wrong_late = json.loads(json.dumps(payload))
            wrong_late["enemyPresentation"][actor]["state"] = "anticipate"
            path.write_text(json.dumps({"kind": "art_sample_anticipate_late", "value": json.dumps(wrong_late)}))
            self.assertIsNone(capture.parse_art_payload(path, 0, actor, "idle", "anticipate"))
            wrong_path = dict(payload["enemyPresentation"][actor], framePath="a0.png")
            self.assertFalse(capture.presentation_matches_clip(wrong_path, "idle", clips))
            wrong_index = dict(payload["enemyPresentation"][actor], frameIndex=0)
            self.assertFalse(capture.presentation_matches_clip(wrong_index, "idle", clips))

    def test_sprite_action_handoff_allows_only_terminal_frame_within_bounded_grace(self):
        clips = {
            "anticipate": {"frames": [f"a{i}.png" for i in range(10)], "fps": 24, "loop": False},
            "execute": {"frames": [f"e{i}.png" for i in range(8)], "fps": 24, "loop": False},
            "recover": {"frames": [f"r{i}.png" for i in range(10)], "fps": 24, "loop": False},
            "idle": {"frames": [f"i{i}.png" for i in range(12)], "fps": 24, "loop": True},
            "walk": {"frames": ["w0.png", "w1.png"], "fps": 10, "loop": True},
            "hit": {"frames": [f"h{i}.png" for i in range(8)], "fps": 24, "loop": False},
            "resolve": {"frames": ["z0.png", "z1.png", "z2.png"], "fps": 7, "loop": False},
        }
        duration = len(clips["anticipate"]["frames"]) / clips["anticipate"]["fps"]
        terminal = {"state": "anticipate", "frameIndex": 9,
                    "framePath": "a9.png", "isPartRig": False}
        next_clip = {"state": "idle", "frameIndex": 0,
                     "framePath": "i0.png", "isPartRig": False}

        # The reported production sample was about 9 ms beyond duration and
        # still exposed this exact last anticipate frame.
        self.assertTrue(capture.presentation_matches_timed_sample(
            terminal, "anticipate", clips, duration + .009))
        self.assertTrue(capture.presentation_matches_timed_sample(
            next_clip, "anticipate", clips, duration + .009))
        self.assertFalse(capture.presentation_matches_timed_sample(
            terminal, "anticipate", clips, duration + 1 / 30))
        self.assertFalse(capture.presentation_matches_timed_sample(
            dict(terminal, frameIndex=8, framePath="a8.png"),
            "anticipate", clips, duration + .009))
        self.assertFalse(capture.presentation_matches_timed_sample(
            dict(terminal, framePath="wrong.png"),
            "anticipate", clips, duration + .009))
        self.assertFalse(capture.presentation_matches_timed_sample(
            dict(terminal, state="execute", frameIndex=7, framePath="e7.png"),
            "anticipate", clips, duration + .009))
        self.assertTrue(capture.presentation_matches_timed_sample(
            {"state": "anticipate", "frameIndex": 8,
             "framePath": "a8.png", "isPartRig": False},
            "anticipate", clips, duration - 1 / 24))

    def test_settled_receipt_proves_automatic_return_after_boundary_sample(self):
        actor = "ACT_E_R02_03"
        clips = {
            "anticipate": {"frames": [f"a{i}.png" for i in range(10)], "fps": 24, "loop": False},
            "execute": {"frames": [f"e{i}.png" for i in range(8)], "fps": 24, "loop": False},
            "recover": {"frames": [f"r{i}.png" for i in range(10)], "fps": 24, "loop": False},
            "idle": {"frames": [f"i{i}.png" for i in range(12)], "fps": 24, "loop": True},
            "walk": {"frames": [f"w{i}.png" for i in range(5)], "fps": 10, "loop": True},
            "hit": {"frames": [f"h{i}.png" for i in range(8)], "fps": 24, "loop": False},
            "resolve": {"frames": ["z0.png", "z1.png", "z2.png"], "fps": 7, "loop": False},
        }
        request_id = "state-request-unique-1"
        request_uptime = 1000.0
        delay, expected_state, contract = capture.settled_expectation("anticipate", clips)
        self.assertAlmostEqual(delay, 10 / 24 + .10)
        self.assertEqual((expected_state, contract), ("idle", "nonloop_returns_to_idle"))
        base_receipt = {
            "kind": "art_sample_anticipate_settled",
            "qaStateRequestID": request_id,
            "qaRequestedState": "anticipate",
            "qaExpectedSettledState": "idle",
            "qaSettleContract": "nonloop_returns_to_idle",
            "qaSettleDelaySeconds": delay,
            "qaRequestUptime": request_uptime,
            "qaSampleUptime": request_uptime + delay + .01,
        }
        idle = {"state": "idle", "isPartRig": False,
                "frameIndex": 4, "framePath": "i4.png"}
        payload = {"actorIDs": [actor],
                   "states": {actor + ":anticipate": True},
                   "enemyPresentation": {actor: idle}}
        late_boundary = {"state": "anticipate", "frameIndex": 9, "framePath": "a9.png"}
        self.assertEqual(capture.verify_settled_observation(
            base_receipt, payload, actor, "anticipate", request_id,
            request_uptime, clips), [])

        # The exact terminal frame at duration+9ms is only pending evidence;
        # it cannot substitute for a settled idle readback.
        stuck_payload = {**payload, "enemyPresentation": {actor: late_boundary}}
        errors = capture.verify_settled_observation(
            base_receipt, stuck_payload, actor, "anticipate", request_id,
            request_uptime, clips)
        self.assertIn("settled_presentation_path_or_state_mismatch", errors)

        too_early = dict(base_receipt, qaSampleUptime=request_uptime + delay - .002)
        self.assertIn("settled_sample_too_early", capture.verify_settled_observation(
            too_early, payload, actor, "anticipate", request_id,
            request_uptime, clips))
        too_late = dict(base_receipt, qaSampleUptime=request_uptime + delay + .501)
        self.assertIn("settled_sample_too_late", capture.verify_settled_observation(
            too_late, payload, actor, "anticipate", request_id,
            request_uptime, clips))
        nonfinite_sample = dict(base_receipt, qaSampleUptime=float("nan"))
        self.assertIn("settled_sample_uptime_missing", capture.verify_settled_observation(
            nonfinite_sample, payload, actor, "anticipate", request_id,
            request_uptime, clips))
        self.assertEqual(capture.verify_settled_observation(
            base_receipt, payload, actor, "anticipate", request_id,
            float("nan"), clips), ["settled_request_uptime_invalid"])
        stale = dict(base_receipt, qaStateRequestID="old-request")
        self.assertIn("settled_request_id_mismatch", capture.verify_settled_observation(
            stale, payload, actor, "anticipate", request_id,
            request_uptime, clips))
        wrong_path = {**payload, "enemyPresentation": {actor: dict(idle, framePath="a9.png")}}
        self.assertIn("settled_presentation_path_or_state_mismatch", capture.verify_settled_observation(
            base_receipt, wrong_path, actor, "anticipate", request_id,
            request_uptime, clips))

    def test_settled_contract_covers_execute_chain_loops_and_terminal_resolve(self):
        clips = {
            "anticipate": {"frames": ["a0.png", "a1.png"], "fps": 10, "loop": False},
            "execute": {"frames": ["e0.png", "e1.png", "e2.png"], "fps": 10, "loop": False},
            "recover": {"frames": ["r0.png", "r1.png"], "fps": 10, "loop": False},
            "idle": {"frames": ["i0.png", "i1.png", "i2.png"], "fps": 3, "loop": True},
            "walk": {"frames": ["w0.png", "w1.png"], "fps": 8, "loop": True},
            "hit": {"frames": ["h0.png"], "fps": 10, "loop": False},
            "resolve": {"frames": ["z0.png", "z1.png", "z2.png"], "fps": 10, "loop": False},
        }
        delay, state, contract = capture.settled_expectation("execute", clips)
        self.assertAlmostEqual(delay, .3 + .2 + .1)
        self.assertEqual((state, contract), ("idle", "execute_then_recover_to_idle"))
        delay, state, contract = capture.settled_expectation("walk", clips)
        self.assertAlmostEqual(delay, .25 + .1)
        self.assertEqual((state, contract), ("walk", "loop_remains_active"))
        delay, state, contract = capture.settled_expectation("resolve", clips)
        self.assertAlmostEqual(delay, .3 + .1)
        self.assertEqual((state, contract), ("resolve", "terminal_resolve_holds"))

    def test_sample_receipt_requires_same_request_and_monotonic_sample(self):
        base = {"qaStateRequestID": "request-a", "qaRequestedState": "hit",
                "qaRequestUptime": 25.0, "qaSampleUptime": 25.2}
        self.assertTrue(capture.receipt_matches_state_request(base, "request-a", "hit", 25.0))
        self.assertFalse(capture.receipt_matches_state_request(base, "request-b", "hit", 25.0))
        self.assertFalse(capture.receipt_matches_state_request(base, "request-a", "recover", 25.0))
        self.assertFalse(capture.receipt_matches_state_request(
            dict(base, qaRequestUptime=24.0), "request-a", "hit", 25.0))
        self.assertFalse(capture.receipt_matches_state_request(
            dict(base, qaSampleUptime=24.9), "request-a", "hit", 25.0))
        self.assertFalse(capture.receipt_matches_state_request(
            dict(base, qaSampleUptime=True), "request-a", "hit", 25.0))
        self.assertFalse(capture.receipt_matches_state_request(
            base, "request-a", "hit", float("nan")))

    def test_final_receipt_requires_all_seven_successful_states(self):
        actor = "ACT_B_R05_B"
        complete = {"kind": "art_audit", "actorIDs": [actor],
                    "states": {actor + ":" + state: True for state in capture.STATES},
                    "enemyPresentation": {actor: {"state": "resolve"}}}
        self.assertEqual(capture.verify_final_payload(complete, complete, actor), [])
        complete["states"][actor + ":hit"] = False
        self.assertEqual(capture.verify_final_payload(complete, complete, actor), ["state_not_rendered:hit"])

    def test_fixed_receipts_restore_prior_bytes_timestamps_and_retain_new_names(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            old = folder / "last_art_state.json"
            old.write_bytes(b'{"prior":"exact"}\n')
            old_atime = 1_699_999_000_987_654_321
            old_mtime = 1_700_000_000_123_456_789
            old.touch()
            import os
            os.chmod(old, 0o640)
            os.utime(old, ns=(old_atime, old_mtime))
            snapshot = capture.snapshot_fixed_receipts(folder)
            old.write_bytes(b"overwritten")
            new = folder / "last_art_sample_walk_late.json"
            new.write_bytes(b"new run")
            restored = capture.restore_fixed_receipts(folder, snapshot)
            self.assertEqual(old.stat().st_mtime_ns, old_mtime)
            self.assertEqual(old.stat().st_atime_ns, old_atime)
            self.assertEqual(old.stat().st_mode & 0o777, 0o640)
            self.assertEqual(old.read_bytes(), b'{"prior":"exact"}\n')
            self.assertTrue(new.exists())
            self.assertEqual(new.read_bytes(), b"new run")
            self.assertEqual(restored, {"last_art_state.json": True})


if __name__ == "__main__":
    unittest.main()

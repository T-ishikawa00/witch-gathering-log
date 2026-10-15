import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).with_name("qa_process_primitives.py")
spec = importlib.util.spec_from_file_location("qa_process_primitives", MODULE)
qa = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = qa
spec.loader.exec_module(qa)


class ProcessPrimitiveTests(unittest.TestCase):
    def test_exact_process_identity_and_arguments(self):
        good = [{"pid": 73, "executable": "/Applications/Witch.app/Witch", "argv": ["--qa-isolated", "--save-key", "abc"]}]
        owned = qa.verify_owned_process(73, good, "/Applications/Witch.app/Witch", ["--qa-isolated", "--save-key", "abc"])
        self.assertEqual(owned.pid, 73)
        for rows, args, exe in [
            (good + [{"pid": 99, "executable": "/tmp/other", "argv": []}], ["--qa-isolated", "--save-key", "abc"], "/Applications/Witch.app/Witch"),
            (good, ["--qa-isolated", "--save-key", "other"], "/Applications/Witch.app/Witch"),
            (good, ["--qa-isolated", "--save-key", "abc", "--extra"], "/Applications/Witch.app/Witch"),
            (good, ["--qa-isolated", "--save-key", "abc"], "relative/Witch"),
        ]:
            with self.assertRaises(qa.PrimitiveError):
                qa.verify_owned_process(73, rows, exe, args)
        with self.assertRaises(qa.PrimitiveError):
            qa.verify_owned_process(74, good, "/Applications/Witch.app/Witch", ["--qa-isolated", "--save-key", "abc"])

    def test_create_new_evidence_never_overwrites(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "evidence.json"
            qa.create_new_evidence(path, {"revision": 1})
            original = path.read_bytes()
            with self.assertRaises(qa.PrimitiveError):
                qa.create_new_evidence(path, {"revision": 2})
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(json.loads(original), {"revision": 1})

    def test_mutable_receipt_update_is_atomic_and_requires_existing_file(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "run.json"
            with self.assertRaises(qa.PrimitiveError):
                qa.update_run_receipt(path, {"phase": "start"})
            path.write_text('{"phase":"start"}\n', encoding="utf-8")
            qa.update_run_receipt(path, {"phase": "complete", "ok": True})
            self.assertEqual(json.loads(path.read_text(encoding="utf-8")), {"ok": True, "phase": "complete"})
            self.assertEqual(sorted(p.name for p in Path(td).iterdir()), ["run.json"])

    def test_output_directory_is_reserved_once(self):
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "run-1"
            reserved = qa.reserve_output_directory(output)
            self.assertEqual(reserved, output)
            with self.assertRaises(qa.PrimitiveError):
                qa.reserve_output_directory(output)
            self.assertTrue(output.is_dir())


if __name__ == "__main__":
    unittest.main()

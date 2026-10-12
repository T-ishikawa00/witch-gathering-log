"""Focused regression tests for resource capture/freeze integrity."""
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from PIL import UnidentifiedImageError

MODULE_PATH = Path(__file__).with_name('prepare_resources.py')
spec = importlib.util.spec_from_file_location('prepare_resources_under_test', MODULE_PATH)
prepare_resources = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(prepare_resources)
ResourceCapture = prepare_resources.ResourceCapture
copy_frozen = prepare_resources.copy_frozen


class ResourceCaptureTests(unittest.TestCase):
    def test_rejects_zero_byte_png_before_copy(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            source, target = root / 'bad.png', root / 'out' / 'bad.png'
            source.write_bytes(b'')
            with self.assertRaises(UnidentifiedImageError):
                ResourceCapture().copy(source, target)
            self.assertFalse(target.exists())

    def test_finish_detects_source_mutation_during_capture(self):
        with tempfile.TemporaryDirectory() as td:
            source = Path(td) / 'asset.json'
            source.write_text('{"v":1}')
            capture = ResourceCapture()
            self.assertEqual(capture.read(source), b'{"v":1}')
            source.write_text('{"v":2}')
            with self.assertRaisesRegex(RuntimeError, 'sources changed during capture'):
                capture.finish()

    def test_copy_frozen_rejects_tampered_prepared_resource(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); frozen = root / 'prepared'; out = root / 'bundle'
            frozen.mkdir(); asset = frozen / 'Art' / 'sprite.png'; asset.parent.mkdir()
            asset.write_bytes(b'captured bytes')
            manifest = root / 'RESOURCE_SHA256.json'
            manifest.write_text(json.dumps({'Art/sprite.png': hashlib.sha256(b'captured bytes').hexdigest()}))
            asset.write_bytes(b'tampered after freeze')
            with self.assertRaisesRegex(RuntimeError, 'Frozen resource SHA manifest mismatch'):
                copy_frozen(out, frozen, manifest)
            self.assertFalse(out.exists())

    def test_copy_frozen_uses_captured_bytes_after_live_source_changes(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); live = root / 'live'; frozen = root / 'prepared'; out = root / 'bundle'
            rel = Path('Art/sprite.bin')
            live_asset = live / rel; live_asset.parent.mkdir(parents=True); live_asset.write_bytes(b'original live bytes')
            frozen_asset = frozen / rel; frozen_asset.parent.mkdir(parents=True); frozen_asset.write_bytes(live_asset.read_bytes())
            manifest = root / 'RESOURCE_SHA256.json'
            manifest.write_text(json.dumps({rel.as_posix(): hashlib.sha256(frozen_asset.read_bytes()).hexdigest()}))
            # Mutate the upstream source only after its bytes have been frozen.
            live_asset.write_bytes(b'newer live bytes')
            copy_frozen(out, frozen, manifest)
            self.assertEqual((out / rel).read_bytes(), b'original live bytes')
            self.assertEqual(live_asset.read_bytes(), b'newer live bytes')


if __name__ == '__main__':
    unittest.main(verbosity=2)

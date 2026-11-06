import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from copy_resources import copy_pack, verify


class ResourcePackTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / 'source'
        self.source.mkdir()
        (self.source / 'image.png').write_bytes(b'synthetic-test-resource')
        self.manifest = self.root / 'manifest.json'
        self.manifest.write_text(json.dumps({'image.png': hashlib.sha256(b'synthetic-test-resource').hexdigest()}))

    def test_copy_preserves_source_and_reads_back(self):
        copy_pack(self.source, self.manifest, self.root / 'output')
        self.assertEqual((self.root / 'output/image.png').read_bytes(), (self.source / 'image.png').read_bytes())

    def test_changed_or_extra_inputs_fail_before_output(self):
        (self.source / 'extra').write_text('not in manifest')
        with self.assertRaises(ValueError):
            copy_pack(self.source, self.manifest, self.root / 'output')
        self.assertFalse((self.root / 'output').exists())

    def test_traversal_and_source_overlap_rejected(self):
        with self.assertRaises(ValueError):
            copy_pack(self.source, self.manifest, self.source / 'output')
        self.manifest.write_text(json.dumps({'../escape': '0' * 64}))
        with self.assertRaises(ValueError):
            verify(self.source, self.manifest)

    def test_symlink_resource_rejected(self):
        (self.source / 'image.png').rename(self.root / 'original')
        (self.source / 'image.png').symlink_to(self.root / 'original')
        with self.assertRaises(ValueError):
            verify(self.source, self.manifest)


if __name__ == '__main__':
    unittest.main()

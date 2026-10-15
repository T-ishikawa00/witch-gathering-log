"""Small disposable regressions for R187's forced-clone resource writer."""
import errno
import hashlib
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import plistlib
from unittest import mock
from pathlib import Path

MODULE_PATH=Path(__file__).parents[2]/'tools/witch_native/prepare_resources.py'
spec=importlib.util.spec_from_file_location('prepare_resources_r187',MODULE_PATH)
module=importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)

def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

class ResourceReuseR187Tests(unittest.TestCase):
    def test_forced_clone_preserves_content_mode_xattrs_and_source(self):
        with tempfile.TemporaryDirectory(prefix='resource-r187-') as temporary:
            root=Path(temporary);source=root/'source.bin';target=root/'out'/'source.bin'
            source.write_bytes(b'validated-resource\0'*32768);source.chmod(0o640)
            try:
                if hasattr(os,'setxattr'):os.setxattr(source,'com.example.r187',b'xattr-payload',follow_symlinks=False)
                else:subprocess.run(['/usr/bin/xattr','-w','com.example.r187','xattr-payload',str(source)],check=True,capture_output=True)
            except (AttributeError,OSError,subprocess.CalledProcessError):self.skipTest('xattrs unavailable on disposable test volume')
            original=(digest(source),module._source_signature(source))
            capture=module.ResourceCapture();capture.copy(source,target);capture.finish()
            self.assertEqual(digest(target),original[0])
            self.assertEqual(stat.S_IMODE(target.stat().st_mode),0o640)
            if hasattr(os,'getxattr'):actual_xattr=os.getxattr(target,'com.example.r187',follow_symlinks=False)
            else:
                encoded=subprocess.run(['/usr/bin/xattr','-px','com.example.r187',str(target)],check=True,capture_output=True,text=True).stdout
                actual_xattr=bytes.fromhex(''.join(encoded.split()))
            self.assertEqual(actual_xattr,b'xattr-payload')
            self.assertEqual(module._source_signature(source),original[1])
            self.assertEqual(capture.copy_actions[0]['method'],'APFS_CLONE_FORCE')

    def test_identical_valid_output_is_not_rewritten(self):
        with tempfile.TemporaryDirectory(prefix='resource-r187-') as temporary:
            root=Path(temporary);source=root/'source.bin';target=root/'out.bin'
            source.write_bytes(b'unchanged');target.write_bytes(source.read_bytes())
            # Reuse requires the full supported metadata signature, not just bytes.
            shutil.copystat(source,target,follow_symlinks=False)
            self.assertEqual(module._metadata_signature(target),module._metadata_signature(source))
            before=target.stat().st_mtime_ns
            capture=module.ResourceCapture();capture.copy(source,target)
            self.assertEqual(target.stat().st_mtime_ns,before)
            self.assertEqual(capture.copy_actions[0]['method'],'SKIPPED_IDENTICAL_SHA256')

    def test_identical_bytes_with_mode_or_xattr_mismatch_are_replaced(self):
        with tempfile.TemporaryDirectory(prefix='resource-r187-') as temporary:
            root=Path(temporary);source=root/'source.bin';target=root/'target.bin'
            source.write_bytes(b'identical-content');target.write_bytes(b'identical-content')
            source.chmod(0o640);target.chmod(0o600)
            capture=module.ResourceCapture();capture.copy(source,target)
            self.assertEqual(capture.copy_actions[0]['method'],'APFS_CLONE_FORCE')
            self.assertEqual(stat.S_IMODE(target.stat().st_mode),0o640)
            setter=getattr(os,'setxattr',None)
            if setter:
                setter(source,'com.example.r187','source',follow_symlinks=False)
                setter(target,'com.example.r187','stale',follow_symlinks=False)
                capture=module.ResourceCapture();capture.copy(source,target)
                self.assertEqual(capture.copy_actions[0]['method'],'APFS_CLONE_FORCE')
                self.assertEqual(os.getxattr(target,'com.example.r187',follow_symlinks=False),b'source')

    def test_nested_symlink_parent_is_refused_before_writing_outside(self):
        with tempfile.TemporaryDirectory(prefix='resource-r187-') as temporary:
            root=Path(temporary);source=root/'source.bin';source.write_bytes(b'bytes')
            outside=root/'outside';outside.mkdir();output=root/'out';output.mkdir()
            (output/'Art').symlink_to(outside,target_is_directory=True)
            with self.assertRaisesRegex(ValueError,'output component'):
                module.ResourceCapture().copy(source,output/'Art'/'nested.bin')
            self.assertEqual(list(outside.iterdir()),[])

    def test_actool_temporary_sources_finish_before_cleanup_and_app_outputs_coexist(self):
        with tempfile.TemporaryDirectory(prefix='resource-r187-') as temporary:
            root=Path(temporary);catalog=root/'native'/'WitchAssets.xcassets';catalog.mkdir(parents=True)
            original=catalog/'Contents.json';original.write_text('{"images":[]}')
            out=root/'WitchGathering.app';out.mkdir();(out/'WitchGathering').write_bytes(b'unchanged-binary')
            (out/'Info.plist').write_bytes(b'unchanged-info')
            def fake_actool(args,**kwargs):
                compiled=Path(args[args.index('--compile')+1]);compiled.mkdir(parents=True,exist_ok=True)
                (compiled/'Assets.car').write_bytes(b'compiled-assets')
                info=Path(args[args.index('--output-partial-info-plist')+1])
                info.write_bytes(plistlib.dumps({'CFBundleIcons':{'CFBundlePrimaryIcon':{'CFBundleIconName':'AppIcon'}}}))
                return mock.Mock(returncode=0,stdout='stubbed')
            capture=module.ResourceCapture()
            with mock.patch.object(module.subprocess,'run',side_effect=fake_actool):
                module.compile_asset_catalog(root,out,capture)
            captured_paths=[str(path) for path in capture.captured]
            self.assertEqual(captured_paths,[str(original)])
            capture.finish()
            self.assertEqual((out/'Assets.car').read_bytes(),b'compiled-assets')
            self.assertEqual((out/'WitchGathering').read_bytes(),b'unchanged-binary')
            self.assertEqual((out/'Info.plist').read_bytes(),b'unchanged-info')
            self.assertTrue((out/'ASSET_COMPILE.log').exists())

    def test_darwin_xattr_fallback_branch_reads_digest_without_python_wrappers(self):
        if sys.platform!='darwin':self.skipTest('Darwin xattr fallback only')
        with tempfile.TemporaryDirectory(prefix='resource-r187-') as temporary:
            source=Path(temporary)/'source.bin';source.write_bytes(b'x')
            try:
                if hasattr(os,'setxattr'):os.setxattr(source,'com.example.r187',b'payload',follow_symlinks=False)
                else:subprocess.run(['/usr/bin/xattr','-w','com.example.r187','payload',str(source)],check=True,capture_output=True)
            except (OSError,subprocess.CalledProcessError):self.skipTest('xattr setup unavailable')
            with mock.patch.object(os,'listxattr',None,create=True),mock.patch.object(os,'getxattr',None,create=True):
                actual=module._xattr_digests(source)
            self.assertEqual(actual['com.example.r187'],hashlib.sha256(b'payload').hexdigest())

    def test_changed_output_is_atomically_replaced_and_source_is_unchanged(self):
        with tempfile.TemporaryDirectory(prefix='resource-r187-') as temporary:
            root=Path(temporary);source=root/'source.bin';target=root/'out.bin'
            source.write_bytes(b'new-validated-content');target.write_bytes(b'old-content')
            source_before=(digest(source),module._source_signature(source))
            capture=module.ResourceCapture();capture.copy(source,target);capture.finish()
            self.assertEqual(digest(target),source_before[0])
            self.assertEqual(module._source_signature(source),source_before[1])
            self.assertEqual(capture.copy_actions[0]['method'],'APFS_CLONE_FORCE')
            self.assertEqual(list(root.glob('out.bin.resource-tmp-*')),[])

    def test_missing_source_writes_nothing(self):
        with tempfile.TemporaryDirectory(prefix='resource-r187-') as temporary:
            root=Path(temporary);target=root/'out.bin'
            with self.assertRaises(FileNotFoundError):module.ResourceCapture().copy(root/'missing.bin',target)
            self.assertFalse(target.exists())

    def test_symlink_source_or_destination_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix='resource-r187-') as temporary:
            root=Path(temporary);source=root/'source.bin';source.write_bytes(b'bytes')
            source_link=root/'source-link';source_link.symlink_to(source)
            with self.assertRaisesRegex(ValueError,'regular non-symlink'):
                module.ResourceCapture().copy(source_link,root/'out')
            target=root/'target-link';target.symlink_to(source)
            with self.assertRaisesRegex(ValueError,'destination must be a regular'):
                module.ResourceCapture().copy(source,target)

    def test_clone_failure_is_atomic_and_does_not_silently_fallback(self):
        with tempfile.TemporaryDirectory(prefix='resource-r187-') as temporary:
            root=Path(temporary);source=root/'source.bin';target=root/'out.bin'
            source.write_bytes(b'new');target.write_bytes(b'old')
            def fail_after_partial(src,dst,flags):
                Path(dst).write_bytes(b'partial')
                raise OSError(errno.EIO,'injected clone I/O failure')
            capture=module.ResourceCapture(copyfile_fn=fail_after_partial)
            with self.assertRaises(OSError):capture.copy(source,target)
            self.assertEqual(target.read_bytes(),b'old')
            self.assertEqual(list(root.glob('out.bin.resource-tmp-*')),[])
            self.assertEqual(capture.full_copy_fallback_used_bytes,0)

    def test_explicit_full_copy_fallback_requires_and_records_budget(self):
        with tempfile.TemporaryDirectory(prefix='resource-r187-') as temporary:
            root=Path(temporary);source=root/'source.bin';target=root/'out.bin';source.write_bytes(b'fallback-content')
            calls=[]
            def clone_unavailable_then_copy(src,dst,flags):
                calls.append(flags)
                if flags & module.COPYFILE_CLONE_FORCE:
                    Path(dst).write_bytes(b'partial clone')
                    raise OSError(errno.ENOTSUP,'clone unsupported')
                shutil.copyfile(src,dst)
                shutil.copystat(src,dst)
            denied=module.ResourceCapture(copyfile_fn=clone_unavailable_then_copy)
            with self.assertRaisesRegex(RuntimeError,'budget is insufficient'):
                denied.copy(source,target)
            self.assertFalse(target.exists());self.assertEqual(len(calls),1)
            allowed=module.ResourceCapture(full_copy_fallback_budget_bytes=source.stat().st_size,copyfile_fn=clone_unavailable_then_copy)
            allowed.copy(source,target)
            self.assertEqual(target.read_bytes(),source.read_bytes())
            self.assertEqual(allowed.full_copy_fallback_used_bytes,source.stat().st_size)
            self.assertEqual(allowed.copy_actions[0]['method'],'FULL_COPY_EXPLICIT_BUDGET')

    def test_copy_frozen_rejects_missing_or_unexpected_inputs_and_preserves_unmanaged_outputs(self):
        with tempfile.TemporaryDirectory(prefix='resource-r212-') as temporary:
            root=Path(temporary);frozen=root/'frozen';out=root/'out';frozen.mkdir()
            (frozen/'a.bin').write_bytes(b'a');manifest=root/'hashes.json'
            manifest.write_text(json.dumps({'a.bin':digest(frozen/'a.bin')}))
            (frozen/'extra.bin').write_bytes(b'extra')
            with self.assertRaisesRegex(RuntimeError,'manifest mismatch'):module.copy_frozen(out,frozen,manifest)
            self.assertFalse(out.exists())
            (frozen/'extra.bin').unlink()
            out.mkdir();(out/'unexpected.bin').write_bytes(b'keep')
            receipt=module.copy_frozen(out,frozen,manifest)
            self.assertEqual(receipt['resource_sha256'],{'a.bin':digest(frozen/'a.bin')})
            self.assertEqual((out/'unexpected.bin').read_bytes(),b'keep')
            # Unmanaged Xcode files coexist; a symlink at a manifest-owned path is rejected.
            malicious=root/'malicious';malicious.mkdir();outside=malicious/'outside.bin';outside.write_bytes(b'keep')
            linked=malicious/'a.bin';linked.symlink_to(outside)
            with self.assertRaisesRegex(ValueError,'destination must be a regular'):
                module.copy_frozen(malicious,frozen,manifest)
            self.assertEqual(outside.read_bytes(),b'keep')
            self.assertTrue(linked.is_symlink())

    def test_copy_frozen_reuses_exact_output_and_verifies_readback(self):
        with tempfile.TemporaryDirectory(prefix='resource-r187-') as temporary:
            root=Path(temporary);frozen=root/'frozen';out=root/'out';frozen.mkdir();out.mkdir()
            (frozen/'a.bin').write_bytes(b'a');(frozen/'b.bin').write_bytes(b'b')
            expected={p.name:digest(p) for p in frozen.iterdir()}
            manifest=root/'hashes.json';manifest.write_text(json.dumps(expected))
            (out/'a.bin').write_bytes(b'a')
            shutil.copystat(frozen/'a.bin',out/'a.bin',follow_symlinks=False)
            self.assertEqual(module._metadata_signature(out/'a.bin'),module._metadata_signature(frozen/'a.bin'))
            # Exact bytes and metadata skip; only the absent managed output clones.
            receipt=module.copy_frozen(out,frozen,manifest)
            self.assertEqual(receipt['resource_sha256'],expected)
            methods={Path(row['destination']).name:row['method'] for row in receipt['copy_actions']}
            self.assertEqual(methods,{'a.bin':'SKIPPED_IDENTICAL_SHA256','b.bin':'APFS_CLONE_FORCE'})

    def test_copy_frozen_preserves_unmanaged_app_files(self):
        with tempfile.TemporaryDirectory(prefix='resource-r187-') as temporary:
            root=Path(temporary);source=root/'frozen';out=root/'WitchGathering.app';source.mkdir();out.mkdir()
            (source/'Art').mkdir();(source/'Art'/'a.bin').write_bytes(b'owned-resource')
            (out/'Info.plist').write_bytes(b'plist');(out/'WitchGathering').write_bytes(b'executable')
            manifest=root/'hashes.json';manifest.write_text(json.dumps({'Art/a.bin':digest(source/'Art'/'a.bin')}))
            receipt=module.copy_frozen(out,source,manifest)
            self.assertEqual(receipt['resource_sha256'],{'Art/a.bin':digest(source/'Art'/'a.bin')})
            self.assertTrue(receipt['unmanaged_output_files_preserved'])
            self.assertEqual((out/'Info.plist').read_bytes(),b'plist')
            self.assertEqual((out/'WitchGathering').read_bytes(),b'executable')

if __name__=='__main__':unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Exercise failed builds in disposable project roots; never alter the real app."""
from pathlib import Path
import json,shutil,subprocess,sys,tempfile,unittest
SOURCE=Path(__file__).resolve().parent
class BuildReceiptTests(unittest.TestCase):
    def run_failure(self,broken_png):
        with tempfile.TemporaryDirectory(prefix='witch-build-receipt-') as directory:
            root=Path(directory);scripts=root/'tools/witch_native';scripts.mkdir(parents=True)
            for name in ['build.py','prepare_resources.py']:shutil.copy2(SOURCE/name,scripts/name)
            for path in ['native/WitchApp','native/StoreKitLocalQA','native/Art','native/build']:(root/path).mkdir(parents=True,exist_ok=True)
            (root/'native/WitchApp/Broken.swift').write_text('#error("Intentional isolated compiler failure")\n')
            (root/'native/StoreKitLocalQA/ReusableBridge.swift').write_text('// isolated fixture\n')
            entries={'BROKEN':{'selectedPNG':'broken.png'}} if broken_png else {}
            (root/'native/Art/runtime_index.json').write_text(json.dumps({'entries':entries}))
            if broken_png:(root/'native/Art/broken.png').write_bytes(b'')
            receipt=root/'native/build/BUILD_RECEIPT.json'
            receipt.write_text(json.dumps({'status':'SIMULATOR_BUILD_PASS','bundle':'old-success'}))
            process=subprocess.run([sys.executable,str(scripts/'build.py')],cwd=root,text=True,capture_output=True,timeout=90)
            self.assertNotEqual(process.returncode,0)
            current=json.loads(receipt.read_text())
            self.assertEqual(current['status'],'FAILED_RESOURCE_CAPTURE' if broken_png else 'FAILED_COMPILE')
            self.assertNotEqual(current['bundle'],'old-success')
            self.assertFalse(current['signing']);self.assertFalse(current['upload'])
            self.assertEqual(json.loads((Path(current['bundle']).parent/'BUILD_RECEIPT.json').read_text()),current)
            if not broken_png:self.assertIn('Intentional isolated compiler failure',Path(current['build_log']).read_text())
    def test_failed_resource_capture_replaces_old_success_receipt(self):self.run_failure(True)
    def test_failed_compile_replaces_old_success_receipt(self):self.run_failure(False)
if __name__=='__main__':unittest.main(verbosity=2)

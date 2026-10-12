import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).parent))
from prepare_resources import ResourceCapture, merge_runtime_index

SCRIPT=Path(__file__).with_name('prepare_resources.py')

def write_json(path,value):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')

class RuntimeIndexOverlayTests(unittest.TestCase):
    def fixture(self,root):
        art=root/'native/Art';art.mkdir(parents=True)
        write_json(art/'runtime_index.json',{'entries':{'E1':{'name':'base','sequenceFrames':{'idle':['base-idle'],'walk':['base-walk']},'clips':{'attack':{'fps':5,'frames':['old']},'idle':{'fps':2}},'layers':['base-layer'],'other':'base'}}})
        write_json(art/'generated_runtime_overlay.json',{'status':'CANDIDATE','entries':{'E1':{'name':'first','sequenceFrames':{'idle':['overlay-idle'],'hit':['hit']},'clips':{'attack':{'frames':['first'],'fps':8},'recover':{'frames':['recover']}},'layers':['first-layer'],'other':'first'}}})
        write_json(art/'generated_motion_metadata_overlay_r001.json',{'status':'CANDIDATE','entries':{'E1':{'sequenceFrames':{'walk':['motion-walk']},'clips':{'attack':{'frames':['motion'],'fps':9}}}}})
        write_json(art/'runtime_overlay_999_rejected.json',{'status':'REJECTED_BY_REVIEW','entries':{'E1':{'name':'must-not-apply','sequenceFrames':{'idle':['bad']}}}})
        write_json(art/'runtime_overlay_001_later.json',{'status':'CANDIDATE','entries':{'E1':{'name':'last','sequenceFrames':{'hit':['last-hit']},'clips':{'idle':{'fps':7}}}}})
        return art

    def test_order_field_replace_state_shallow_merge_and_rejected_exclusion(self):
        with tempfile.TemporaryDirectory() as d:
            art=self.fixture(Path(d));index,overlays=merge_runtime_index(art)
            e=index['entries']['E1']
            self.assertEqual(e['name'],'last')
            self.assertEqual(e['layers'],['first-layer'])
            self.assertEqual(e['other'],'first')
            self.assertEqual(e['sequenceFrames'],{'idle':['overlay-idle'],'walk':['motion-walk'],'hit':['last-hit']})
            self.assertEqual(e['clips'],{'attack':{'frames':['motion'],'fps':9},'idle':{'fps':7},'recover':{'frames':['recover']}})
            assembly=index['resourceAssembly']
            self.assertEqual([x['path'] for x in assembly['appliedOverlays']],['generated_runtime_overlay.json','generated_motion_metadata_overlay_r001.json','runtime_overlay_001_later.json'])
            rejected=assembly['excludedRejectedOverlays']
            self.assertEqual([x['path'] for x in rejected],['runtime_overlay_999_rejected.json'])
            for record in assembly['appliedOverlays']+rejected:
                self.assertEqual(record['sha256'],hashlib.sha256((art/record['path']).read_bytes()).hexdigest())
            self.assertFalse(assembly['humanApproval'])

    def test_index_only_cli_writes_only_requested_json_and_matches_function(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);art=self.fixture(root);out=root/'merged.json'
            proc=subprocess.run([sys.executable,str(SCRIPT),'--index-only',str(out),'--root',str(root)],capture_output=True,text=True)
            self.assertEqual(proc.returncode,0,proc.stderr)
            self.assertEqual(proc.stdout,'')
            self.assertEqual({p.name for p in root.iterdir()},{'native','merged.json'})
            got=json.loads(out.read_text());expected,_=merge_runtime_index(art)
            self.assertEqual(got,expected)

    def test_help_has_no_filesystem_side_effect(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            proc=subprocess.run([sys.executable,str(SCRIPT),'--help'],cwd=root,capture_output=True,text=True)
            self.assertEqual(proc.returncode,0,proc.stderr)
            self.assertIn('--index-only OUTPUT',proc.stdout)
            self.assertEqual(list(root.iterdir()),[])

    def test_index_only_capture_rejects_overlay_mutated_during_merge(self):
        class MutatingCapture(ResourceCapture):
            def read(self,path):
                data=super().read(path)
                path=Path(path)
                if path.name=='generated_runtime_overlay.json':path.write_text('{}')
                return data
        with tempfile.TemporaryDirectory() as d:
            art=self.fixture(Path(d));capture=MutatingCapture()
            merge_runtime_index(art,capture)
            with self.assertRaisesRegex(RuntimeError,'changed during capture'):
                capture.finish()

    def test_explicit_priority_overrides_late_legacy_name_and_rejected_stays_excluded(self):
        with tempfile.TemporaryDirectory() as d:
            art=self.fixture(Path(d))
            write_json(art/'runtime_overlay_zzzz_legacy.json',{'entries':{'E1':{'name':'late-legacy'}}})
            write_json(art/'runtime_overlay_actor_repair.json',{'mergePriority':100,'entries':{'E1':{'name':'explicit-repair'}}})
            write_json(art/'runtime_overlay_rejected_repair.json',{'mergePriority':101,'status':'REJECTED','entries':{'E1':{'name':'must-not-win'}}})
            index,_=merge_runtime_index(art)
            self.assertEqual(index['entries']['E1']['name'],'explicit-repair')
            self.assertEqual(index['resourceAssembly']['appliedOverlays'][-1]['mergePriority'],100)

    def test_invalid_priority_is_rejected_before_merge(self):
        for bad in [True,'100',-1,100001]:
            with self.subTest(priority=bad),tempfile.TemporaryDirectory() as d:
                art=self.fixture(Path(d))
                write_json(art/'runtime_overlay_repair.json',{'mergePriority':bad,'entries':{}})
                with self.assertRaisesRegex(ValueError,'mergePriority'):
                    merge_runtime_index(art)

if __name__=='__main__':unittest.main()

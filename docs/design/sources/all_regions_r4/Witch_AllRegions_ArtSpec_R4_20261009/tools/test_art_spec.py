"""Negative tests: deliberately corrupt a copy; original sources remain intact."""
import copy
import json
import unittest
from validate_art_spec import ROOT, validate

class DesignValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw=(ROOT/'source_snapshot/world_catalog_R1.json').read_bytes()
        cls.world=json.loads(cls.raw)
        cls.art=json.loads((ROOT/'data/art_catalog_R4.json').read_text())
    def fails(self,change,check):
        d=copy.deepcopy(self.art);change(d)
        result={r['check']:r['pass'] for r in validate(d,self.world,self.raw)}
        self.assertFalse(result[check],check)
    def test_00_valid_baseline(self): self.assertTrue(all(x['pass'] for x in validate(self.art,self.world,self.raw)))
    def test_01_duplicate_id(self):self.fails(lambda d:d['enemies'][1].update(id=d['enemies'][0]['id']),'IDS_UNIQUE')
    def test_02_drop_mismatch(self):self.fails(lambda d:d['enemies'][0].update(material_id='M_R02_E1'),'ENEMY_DROP_UNCHANGED')
    def test_03_source_mutation(self):self.fails(lambda d:d['materials'][0]['source_record'].update(name='New Material'),'SOURCE_RECORDS_UNCHANGED')
    def test_04_invented_number(self):self.fails(lambda d:d['gear'][0]['recipe_source']['ingredients'][0].update(quantity=0),'NO_NUMERIC_INVENTION')
    def test_05_background_has_boss(self):self.fails(lambda d:d['scenes'][0]['background_must_exclude'].remove('enemy_bodies'),'SCENE_ACTORS_EXCLUDED_FROM_BACKGROUND')
    def test_06_missing_family(self):self.fails(lambda d:d['scenes'][0].update(base_family_id='BG_FAKE'),'SCENE_FAMILY_AND_VARIANT_REFERENCES')
    def test_07_fake_ios_pass(self):self.fails(lambda d:d['enemies'][0]['approvals'].update(ios='PASS'),'NO_UNVERIFIED_RUNTIME_SUCCESS')
    def test_08_invented_output(self):self.fails(lambda d:d['jobs'][0].update(export_paths=['fake.png']),'NO_FABRICATED_FILES')
    def test_09_invented_authorization(self):self.fails(lambda d:d['jobs'][0].update(production_permission='GRANTED'),'NO_NEW_PRODUCTION_AUTHORIZATION')
    def test_10_broken_recipe_trace(self):self.fails(lambda d:d['material_gear_traces'].pop(),'MATERIAL_GEAR_EDGES_EXACT')
    def test_11_dependency_cycle(self):self.fails(lambda d:d['jobs'][0].update(depends_on=[d['jobs'][0]['asset_id']]),'DEPENDENCY_GRAPH_ACYCLIC')
    def test_12_missing_anchor(self):self.fails(lambda d:d['enemies'][0]['required_anchors'].remove('ground'),'CLIPS_AND_ANCHORS_PRESENT')
    def test_13_silent_smith_fix(self):self.fails(lambda d:next(g for g in d['gear'] if g['id']=='EQ_S_01').update(presentation_mode_proposal='FULLY_APPROVED'),'SMITH_ATTACHMENT_STILL_BLOCKED')
    def test_14_false_mac_save(self):self.fails(lambda d:d['meta'].update(mac_saved_by_chat=True),'NO_MAC_SAVE_CLAIM')
if __name__=='__main__':unittest.main()

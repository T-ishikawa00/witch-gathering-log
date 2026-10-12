import unittest
from pathlib import Path
from party_frame_audit import expected_details,unique_save_key,detail_ids_match
from frame_source_proof import expected_frame,verify_frame_source
import hashlib,json,struct,tempfile

class FrameAuditFidelityTests(unittest.TestCase):
    def test_erna_layered_motion_proof_uses_exact_costume_state_index_and_receipt_sha(self):
        with tempfile.TemporaryDirectory() as td:
            app=Path(td)/'WitchGathering.app';resource='GeneratedArt/LayeredMotion/travel__cast_4.png'
            path=app/resource;path.parent.mkdir(parents=True)
            png=b'\x89PNG\r\n\x1a\n'+b'\0'*8+struct.pack('>II',256,256)+b'candidate'
            path.write_bytes(png);digest=hashlib.sha256(png).hexdigest()
            manifest={'travel':{'canvas':[256,256],'execute':{'frames':[{'path':'travel__cast_3.png','sha256':'0'*64},{'path':'travel__cast_4.png','sha256':digest}]}}}
            (path.parent/'MANIFEST.json').write_text(json.dumps(manifest))
            receipt={'resource_sha256':{resource:digest}}
            (app.parent/'BUILD_RECEIPT.json').write_text(json.dumps(receipt))
            geom={'bodyAssetID':resource,'bodyFrameIndex':1,'bodyCanvasWidth':256,'bodyCanvasHeight':256}
            self.assertEqual(expected_frame(app,'ERNA','execute',1,'appearance-travel-branch'),(resource,[256,256]))
            proof=verify_frame_source(app,'ERNA','execute',1,'appearance-travel-branch',geom)
            self.assertEqual(proof['bundlePath'],resource)
            self.assertEqual(proof['sha256'],digest)
            with self.assertRaises(ValueError):verify_frame_source(app,'ERNA','execute',0,'appearance-travel-branch',geom)
            with self.assertRaises(ValueError):expected_frame(app,'ERNA','execute',1,'unknown-fixture')

    def test_same_basename_different_run_or_actor_cannot_reuse_save(self):
        keys={unique_save_key(path,actor,fixture,'resolve',2) for path,actor,fixture in [
            ('/qa/noir-r3/tier01','NOIR','details-C_FAMILIAR-01'),
            ('/qa/noir-r4/tier01','NOIR','details-C_FAMILIAR-01'),
            ('/qa/noir-r3/tier01','LUNA','details-C_APPRENTICE-01'),
            ('/qa/noir-r3/tier01','NOIR','details-C_FAMILIAR-02')]}
        self.assertEqual(len(keys),4)

    def test_wrong_actor_or_unsupported_costume_rejected(self):
        for actor,fixture in [('NOIR','details-C_APPRENTICE-01'),('ERNA','details-C_WITCH-04'),('AIRA','details-C_SMITH-03-travel')]:
            with self.assertRaises(ValueError):expected_details(actor,fixture)

    def test_equipped_other_actor_or_missing_detail_cannot_pass(self):
        expected=expected_details('NOIR','details-C_FAMILIAR-03')
        self.assertFalse(detail_ids_match({'equipmentRegistration':{}},expected))
        self.assertFalse(detail_ids_match({'equipmentRegistration':{'EQ_AMU_03':{}}},expected))
        self.assertFalse(detail_ids_match({'equipmentRegistration':{k:{} for k in expected|{'EQ_BODY_03'}}},expected))
        self.assertFalse(detail_ids_match({'equipmentRegistration':{k:{} for k in expected}},expected))
        valid={k:{'status':'registered','visible':True} for k in expected}
        self.assertTrue(detail_ids_match({'equipmentRegistration':valid},expected,'execute'))
        valid['EQ_AMU_03']['status']='missing_detail_image'
        self.assertFalse(detail_ids_match({'equipmentRegistration':valid},expected,'execute'))

    def test_invisible_attack_only_effect_is_expected_but_missing_charm_is_not(self):
        expected=expected_details('NOIR','details-C_FAMILIAR-03')
        registrations={'EQ_AMU_03':{'status':'registered','visible':True},'EQ_F_03':{'status':'registered','visible':False}}
        self.assertTrue(detail_ids_match({'equipmentRegistration':registrations},expected,'idle'))
        self.assertFalse(detail_ids_match({'equipmentRegistration':registrations},expected,'execute'))
        registrations['EQ_AMU_03']['visible']=False
        self.assertFalse(detail_ids_match({'equipmentRegistration':registrations},expected,'idle'))

    def test_formal_consumer_scope_excludes_unapproved_cat_slots(self):
        self.assertEqual(expected_details('NOIR','details-C_FAMILIAR-01'),{'EQ_AMU_01','EQ_F_01'})
        self.assertEqual(expected_details('NOIR','detail-item-C_FAMILIAR-EQ_AMU_01'),{'EQ_AMU_01','EQ_F_01'})
        self.assertEqual(expected_details('NOIR','detail-item-C_FAMILIAR-EQ_AMU_02'),{'EQ_AMU_02','EQ_F_01'})
        self.assertEqual(expected_details('NOIR','detail-item-C_FAMILIAR-EQ_F_02'),{'EQ_F_02'})
        self.assertEqual(len(expected_details('ERNA','details-C_WITCH-03-travel')),5)
        self.assertEqual(len(expected_details('AIRA','details-C_SMITH-03')),6)

    def test_occluded_fingers_do_not_hide_visible_glove_or_certify_unknown_point(self):
        from unittest.mock import patch
        from frame_source_proof import expected_detail_visibility
        for actor,palm,hand in [('ERNA','freePalm','freeHand'),('LUNA','freePalm','freeHand'),('AIRA','workingPalm','workingHand')]:
            row={'bodyAssetID':'body.png','frameIndex':0,'landmarkVisibility':{palm:'occluded',hand:'visible'}}
            data={'entries':{actor:{'semanticFrameLandmarksCandidate':{'rows':[row]}}}}
            with patch('frame_source_proof.expected_frame',return_value=('body.png',[256,256])),patch('frame_source_proof.document',return_value=data):
                visible=expected_detail_visibility('/frozen',actor,'idle',0,'fixture',{'EQ_HAND_03','EQ_RING_03'})
                self.assertEqual(visible,{'EQ_HAND_03':True,'EQ_RING_03':False})
                row['landmarkVisibility'][palm]='unknown'
                visible=expected_detail_visibility('/frozen',actor,'idle',0,'fixture',{'EQ_RING_03'})
                self.assertTrue(visible['EQ_RING_03'])
                self.assertFalse(detail_ids_match({'equipmentRegistration':{'EQ_RING_03':{'status':'no_registration','visible':False}}},{'EQ_RING_03'},'idle',visible))

    def test_forearm_occluded_chest_hides_amulet_without_hiding_other_details(self):
        from unittest.mock import patch
        from frame_source_proof import expected_detail_visibility
        row={'bodyAssetID':'attack04.png','frameIndex':1,'landmarkVisibility':{'chest':'occluded','workingPalm':'occluded','workingHand':'visible','visibleRightAnkle':'visible'}}
        data={'entries':{'AIRA':{'semanticFrameLandmarksCandidate':{'rows':[row]}}}}
        gears={'EQ_AMU_03','EQ_RING_03','EQ_HAND_03','EQ_FEET_03','EQ_BODY_03','EQ_S_03'}
        with patch('frame_source_proof.expected_frame',return_value=('attack04.png',[320,256])),patch('frame_source_proof.document',return_value=data):
            visible=expected_detail_visibility('/frozen','AIRA','execute',1,'fixture',gears)
        self.assertEqual({gear for gear in gears if not visible[gear]},{'EQ_AMU_03','EQ_RING_03'})
        registrations={gear:{'status':'registered','visible':visible[gear]} for gear in gears}
        self.assertTrue(detail_ids_match({'equipmentRegistration':registrations},gears,'execute',visible))
        registrations['EQ_AMU_03']['visible']=True
        self.assertFalse(detail_ids_match({'equipmentRegistration':registrations},gears,'execute',visible))

if __name__=='__main__':unittest.main()

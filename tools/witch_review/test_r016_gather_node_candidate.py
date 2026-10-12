#!/usr/bin/env python3
"""Offline R016 source/catalog contract checks; not simulator or visual acceptance."""
from __future__ import annotations
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INDEX = json.loads((ROOT / "native/Art/runtime_index.json").read_text())
ROUTES = (ROOT / "native/WitchApp/AreaSceneRouting.swift").read_text()
PRESENTATION = (ROOT / "native/WitchApp/R016GatherNodePresentation.swift").read_text()
SCENE = (ROOT / "native/WitchApp/LivingScene.swift").read_text()
APP = (ROOT / "native/WitchApp/App.swift").read_text()


class GatherNodeSourceContracts(unittest.TestCase):
    def test_all_twenty_r4_materials_have_both_runtime_states(self):
        blocks = re.findall(r'gatherableMaterialIDs:\s*\[([^\]]*)\]', ROUTES)
        ids = [item for block in blocks for item in re.findall(r'"(M_R\d\d_G\d)"', block)]
        expected = {f"M_R{region:02}_G{slot}" for region in range(1, 6) for slot in range(1, 5)}
        self.assertEqual(set(ids), expected)
        self.assertEqual(len(ids), 20)
        for material in expected:
            node_id = "NODE_" + material
            entry = INDEX["entries"][node_id]
            self.assertEqual(entry["kind"], "gather_prop")
            for state in ("present", "collected"):
                path = ROOT / "native/Art" / entry["selectedPNG"][state]
                self.assertTrue(path.is_file(), f"missing {node_id}:{state}")
                self.assertGreater(path.stat().st_size, 0)

    def test_projection_and_renderer_use_exact_material_identity(self):
        self.assertIn('return "NODE_" + materialID', PRESENTATION)
        self.assertIn('resolution.selectionBasis == .selectedGatherMaterial', PRESENTATION)
        self.assertIn('resolution.route.gatherableMaterialIDs.contains(materialID)', PRESENTATION)
        self.assertIn('entry["kind"] as? String == "gather_prop"', PRESENTATION)
        self.assertIn('node.name="gather_node:"+projection.materialID', SCENE)
        self.assertIn('texture(R016GatherNodePresentation.imageID(for:projection))', SCENE)
        self.assertIn('gatherNodeAudit=["materialID":materialID,"nodeID":nodeID,"regionID":regionID', SCENE)

    def test_scene_rebuild_clears_previous_node_and_audit(self):
        self.assertIn('gatherNode=nil;gatherNodeMaterialID=nil;gatherNodeAudit=[:]', SCENE)
        self.assertIn('key.hasPrefix("gather_node_")', SCENE)
        self.assertIn('let gatherChanged = self.selectedGatherMaterialID != selectedGatherMaterialID', SCENE)

    def test_only_positive_real_claim_result_queues_animation_after_sheet_dismissal(self):
        collect = APP.split('func collect()', 1)[1].split('func presentPendingGatherVisualAfterResultDismissal', 1)[0]
        self.assertIn('claimOffline(now:Date()', collect)
        self.assertIn('collectionSummary?.materials.contains(where:{$0.0==materialID && $0.1>0}) == true', collect)
        self.assertIn('pendingGatherVisualMaterialID=materialID', collect)
        self.assertLess(collect.index('pendingGatherVisualMaterialID=nil'), collect.index('engine.claimOffline'))
        self.assertIn('onDismiss:{model.presentPendingGatherVisualAfterResultDismissal()}', APP)
        self.assertIn('func closeSheet(){ sheet=nil }', APP)
        self.assertIn('fighting ? nil:state.gatherTargetMaterialID', APP)

    def test_transition_is_explicitly_visual_only(self):
        transition = PRESENTATION.split('static func successfulClaimActions', 1)[1]
        ordered = [".setTexture(collected)", "wait(forDuration: collectedHold)",
                   ".fadeOut(withDuration: 0.12)", "wait(forDuration: visualRespawnPause)",
                   ".setTexture(present)", ".fadeIn(withDuration: 0.18)"]
        cursor = -1
        for item in ordered:
            cursor = transition.find(item, cursor + 1)
            self.assertGreaterEqual(cursor, 0, f"missing/reordered visual step {item}")
        self.assertIn("presentation-only", PRESENTATION)
        self.assertIn("No timer or", PRESENTATION)
        self.assertNotIn("claimOffline", PRESENTATION)


if __name__ == "__main__":
    unittest.main(verbosity=2)

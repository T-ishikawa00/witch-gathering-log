#!/usr/bin/env python3
"""Execute the candidate's Swift nodeID(for:) for all R4 material IDs."""
from __future__ import annotations
import hashlib
import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DRAFT = ROOT / "docs/production/current/qa_drafts/r016_gather_nodes"
INDEX = json.loads((ROOT / "native/Art/runtime_index.json").read_text())
ROUTES = (ROOT / "native/WitchApp/AreaSceneRouting.swift").read_text()
HARNESS = r'''import Foundation
import SpriteKit
struct R015AreaSceneRoute { let regionID: String; let gatherableMaterialIDs: [String] }
struct R015AreaSceneResolution {
    enum SelectionBasis { case selectedGatherMaterial }
    let selectionBasis: SelectionBasis
    let route: R015AreaSceneRoute
}
@MainActor enum ArtLibrary { static var index: [String:[String:Any]] = [:] }
@main struct CandidateNodeIDCheck {
    @MainActor static func main() {
        for region in 1...5 { for slot in 1...4 {
            let material="M_R\(String(format:"%02d",region))_G\(slot)"
            guard let node=R016GatherNodePresentation.nodeID(for:material) else { fputs("nil\n",stderr); exit(1) }
            print(material + "=" + node)
        }}
    }
}
'''

class SwiftNodeIDTests(unittest.TestCase):
    def test_candidate_swift_function_returns_exact_20_catalog_node_ids(self):
        route_blocks = re.findall(r'gatherableMaterialIDs:\s*\[([^\]]*)\]', ROUTES)
        material_ids = sorted(set(re.findall(r'"(M_R\d\d_G\d)"', "\n".join(route_blocks))))
        self.assertEqual(len(material_ids), 20)
        with tempfile.TemporaryDirectory(prefix="r016-node-id-") as temp:
            temp_path = Path(temp)
            helper = temp_path / "R016GatherNodePresentation.swift"
            helper.write_text((DRAFT / "GatherNodePresentation.swift.candidate").read_text())
            harness = temp_path / "Harness.swift"
            harness.write_text(HARNESS)
            exe = temp_path / "candidate-node-id-check"
            build = subprocess.run(["swiftc", "-parse-as-library", "-framework", "SpriteKit", str(helper), str(harness), "-o", str(exe)],
                                  capture_output=True, text=True)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(exe)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            actual = {}
            for line in run.stdout.splitlines():
                material, node = line.split("=", 1)
                self.assertNotIn(material, actual)
                actual[material] = node
            self.assertEqual(set(actual), set(material_ids))
            expected = {material: "NODE_" + material for material in material_ids}
            self.assertEqual(actual, expected)
            for material, node in actual.items():
                self.assertEqual(INDEX["entries"][node]["kind"], "gather_prop")
                self.assertEqual(set(INDEX["entries"][node]["selectedPNG"]), {"present", "collected"})
            (DRAFT / "SWIFT_NODE_ID_R001.json").write_text(json.dumps({
                "status": "PASS", "method": "Compiled and executed candidate Swift implementation; compared outputs to current R4 route IDs and runtime index",
                "count": len(actual), "mapping": actual,
                "helperSHA256": hashlib.sha256(helper.read_bytes()).hexdigest(),
                "runtimeIndexSHA256": hashlib.sha256((ROOT / "native/Art/runtime_index.json").read_bytes()).hexdigest(),
                "routeSourceSHA256": hashlib.sha256((ROOT / "native/WitchApp/AreaSceneRouting.swift").read_bytes()).hexdigest()
            }, ensure_ascii=False, indent=2) + "\n")

if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Read back immutable R016 per-ID runtime evidence without inferring art approval."""
import hashlib
import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CURRENT = ROOT / 'docs/production/current'
RUN = CURRENT / 'qa_drafts/r016_gather_nodes/runtime_app034944/RUN_R001.json'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    run = json.loads(RUN.read_text())
    app = ROOT / run['app']
    assert sha(app / 'WitchGathering') == run['executableSHA256']
    assert sha(app.parent / 'BUILD_RECEIPT.json') == run['buildReceiptSHA256']
    transition_path = ROOT / run['all20TransitionReceipt']['path']
    transitions = json.loads(transition_path.read_text())
    assert transitions['status'] == 'RUNTIME_NODES_PASS'
    assert all(transitions['nodeSweepInvariants'].values())
    by_id = {row['materialID']: row for row in transitions['rows']}
    expected = {f'M_R{r:02}_G{g}' for r in range(1, 6) for g in range(1, 5)}
    assert set(by_id) == expected
    rows = []
    for record in run['heldScreenRecords']:
        mid = record['materialID']
        receipt = ROOT / record['auditJSON']
        screen = ROOT / record['screenshot']
        assert sha(receipt) == record['auditSHA256']
        assert sha(screen) == record['screenshotSHA256']
        held = json.loads(receipt.read_text())
        assert held['status'] == 'RUNTIME_NODES_PASS'
        assert held['nodeCount'] == 1 and held['requestedMaterialID'] == mid
        row = held['rows'][0]
        assert row['materialID'] == mid and row['nodeID'] == 'NODE_' + mid
        assert all(row['assertions'].values())
        assert all(held['nodeSweepInvariants'].values())
        assert sha(app / 'Art' / row['sourcePNG']) == row['sourcePNG_SHA256']
        assert row['runtimeTexturePixelSHA256'] == row['sourceImagePixelSHA256']
        transition = by_id[mid]
        assert transition['presentationTransitionPassed']
        assert transition['presentTexturePixelSHA256AfterRespawn'] == row['runtimeTexturePixelSHA256']
        assert transition['collectedAudit']['textureID'] == 'NODE_' + mid + '__collected'
        rows.append({
            'id': 'NODE_' + mid, 'materialID': mid, 'regionID': row['regionID'],
            'sceneID': row['sceneID'], 'sourcePNG': row['sourcePNG'],
            'sourcePNG_SHA256': row['sourcePNG_SHA256'], 'heldReceipt': record['auditJSON'],
            'heldReceiptSHA256': record['auditSHA256'], 'screenshot': record['screenshot'],
            'screenshotSHA256': record['screenshotSHA256'],
            'runtimeNodeAndTexture': 'PASS', 'collectedThenPresentPixels': 'PASS',
            'stateRevisionSaveInvariant': 'PASS', 'readiness': 'PARTIAL',
            'humanApproval': False,
            'limits': ['Held screen uses an isolated renderer projection, not player target selection.',
                       'Runtime pixel identity does not establish visual state readability or final art acceptance.']
        })
    assert {r['materialID'] for r in rows} == expected and len(rows) == 20
    result = {'schema': 'R016_GATHER_PER_ID_EVIDENCE_R001',
              'at': datetime.now().astimezone().isoformat(), 'status': '20_RUNTIME_RECORDS_HASH_VERIFIED',
              'app': run['app'], 'executableSHA256': run['executableSHA256'],
              'buildReceiptSHA256': run['buildReceiptSHA256'],
              'run': str(RUN.relative_to(ROOT)), 'runSHA256': sha(RUN),
              'transitionReceipt': str(transition_path.relative_to(ROOT)),
              'transitionReceiptSHA256': sha(transition_path),
              'scope': 'Exact app034944 only; no promotion to later builds or Human adoption.',
              'claims': {'positive': run['positiveClaim'], 'noGain': run['noGainClaim'],
                         'error': run['errorClaim'], 'readback': run['postRestartReadbacks']},
              'rows': rows}
    out = CURRENT / 'GATHER_NODE_EVIDENCE_R016_APP034944.json'
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'path': str(out), 'status': result['status'], 'rowCount': len(rows)}))


if __name__ == '__main__':
    main()

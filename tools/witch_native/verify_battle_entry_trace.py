#!/usr/bin/env python3
"""Validate saved battle-entry model/getter evidence; never infer visual quality."""
import argparse
import datetime
import hashlib
import json
import math
from pathlib import Path

ACTOR = 'ACT_B_R04_B'

def verify(folder):
    if not __debug__:
        raise RuntimeError('Validation requires Python assertions; refuse optimized interpreter')
    capture = json.loads((folder / 'CAPTURE.json').read_text())
    trace = json.loads((folder / 'entry_trace.json').read_text())
    assert capture['status'] == 'CAPTURED_REQUIRES_HOST_AND_VISUAL_VALIDATION'
    build = json.loads((folder / 'BUILD_RECEIPT.json').read_text())
    assert build['status'] == 'SIMULATOR_BUILD_PASS'
    assert build['executable_sha256'] == capture['executableSHA256']
    assert build['bundle'] == capture['app']
    for name, expected in capture['filesSHA256'].items():
        assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == expected, 'Input drift: ' + name
    flags = capture['launchArguments']
    assert '--qa-isolated' in flags and '--qa-battle-entry-trace' in flags
    assert '--qa-save-key=' + capture['saveKey'] in flags
    assert '--qa-encounter=B_R04_B' in flags
    assert ('--qa-dragon-mesh-r004' in flags) == capture['meshRequested'] == trace['requestedMeshCandidate']
    assert ('--qa-dragon-grounded-entry-r005' in flags) == trace.get('groundedEntryR005Requested', False)
    assert trace['saveKey'] == capture['saveKey']
    start = datetime.datetime.fromisoformat(trace['startedAt'].replace('Z', '+00:00')).timestamp()
    assert capture['launchStartedUnix'] <= start <= capture['traceCopiedUnix']
    assert trace['entryDurationSeconds'] == .6
    def finite(value):
        if isinstance(value, dict): return all(finite(v) for v in value.values())
        if isinstance(value, list): return all(finite(v) for v in value)
        if isinstance(value, (int, float)): return math.isfinite(value)
        return True
    assert finite(trace), 'Nonfinite number in trace'
    rows = trace['rows']
    assert 30 <= len(rows) <= 300
    assert rows[0]['phase'] == 'arrivalScheduled'
    for i, row in enumerate(rows):
        assert row['sample'] == i and ACTOR in row['actors']
        if i:
            assert row['elapsedSeconds'] > rows[i - 1]['elapsedSeconds']
        assert all(math.isfinite(v) for v in row['actors'][ACTOR]['root'])
        assert not row['scenePaused'] and row['sceneSpeed'] == 1
    rendered = [r for r in rows if r['phase'] == 'didFinishUpdate']
    assert len(rendered) >= 30 and rendered[-1]['elapsedSeconds'] >= 1.5
    assert all(a['sceneFrame'] < b['sceneFrame'] for a, b in zip(rendered, rendered[1:]))
    walk = [r for r in rows if r['actors'][ACTOR]['presentation']['state'] == 'walk']
    rest = [r for r in rows if r['actors'][ACTOR]['presentation']['state'] != 'walk']
    walk_rendered = [r for r in walk if r['phase'] == 'didFinishUpdate']
    assert len(walk_rendered) >= 12 and rest
    assert walk_rendered[-1]['elapsedSeconds'] - walk_rendered[0]['elapsedSeconds'] >= .4
    measured_walk_span = walk_rendered[-1]['sceneTime'] - walk_rendered[0]['sceneTime']
    measured_rest_start = rest[0]['sceneTime'] - walk_rendered[0]['sceneTime']
    assert .54 <= measured_walk_span <= .67
    assert .575 <= measured_rest_start <= .72
    mesh = trace['requestedMeshCandidate']
    grounded = trace.get('groundedEntryR005Requested', False)
    assert trace['meshPeriodSeconds'] == (.6 if grounded else 1.2)
    for r in walk:
        actor = r['actors'][ACTOR]; rig = actor['presentation']['rig']
        assert actor['arrivalAction'] and rig['meshActive'] == mesh
        assert rig['groundedEntryActive'] == grounded
        if mesh:
            assert rig['meshPresent'] and rig['meshVertexCount'] == 429 and rig['meshActionRunning']
            assert not rig['bodyHidden'] and not rig['rigHidden'] and not rig['overlayActive']
    for r in rest:
        actor = r['actors'][ACTOR]; rig = actor['presentation']['rig']
        assert not actor['arrivalAction'] and not rig['meshActive'] and not rig['meshPresent']
        assert not rig['groundedEntryActive'] and rig['subdivisionLevels'] == 2
        assert not rig['meshActionRunning'] and not rig['overlayActive'] and not rig['bodyHidden']
        if actor['presentation']['state'] == 'idle':
            assert not rig['rigHidden']
        assert max(abs(a - b) for a, b in zip(actor['root'], actor['home'])) < .001
    points = [r['actors'][ACTOR]['presentation']['rig']['points'][0]['scenePoint'] for r in walk]
    spread = [max(p[i] for p in points) - min(p[i] for p in points) for i in range(2)]
    roots = [r['actors'][ACTOR]['root'] for r in walk]
    root_spread = max(p[0] for p in roots) - min(p[0] for p in roots)
    if mesh:
        variants = {json.dumps(r['actors'][ACTOR]['presentation']['rig']['points'], sort_keys=True) for r in walk_rendered}
        warp_variants = {tuple(v for p in r['actors'][ACTOR]['presentation']['rig']['points'] for v in p['destinationNormalized']) for r in walk_rendered}
        assert len(variants) >= 8 and len(warp_variants) >= 8
    if grounded:
        residuals = []
        for row in walk:
            actor = row['actors'][ACTOR]; p = actor['presentation']['rig']['points'][0]
            assert p['index'] == 34 and p['sourceArtworkPixels'] == [16, 140]
            for axis in range(2):
                residual = actor['root'][axis] - actor['home'][axis] + p['scenePoint'][axis] - p['unwarpedScenePoint'][axis]
                assert math.isfinite(residual) and abs(residual) < .001
                residuals.append(abs(residual))
        assert mesh and max(spread) < .001, 'Reference point not fixed in scene getter'
        assert .5 < root_spread < 5, 'Entry movement outside candidate envelope'
    elif mesh:
        assert 15 < root_spread < 23
    key = capture['saveKey']
    save = json.loads((folder / ('qa-' + key + '-save.json')).read_text())['snapshot']
    resolution = json.loads(json.loads((folder / 'last_battle_resolution.json').read_text())['value'])
    assert save['lastEncounterID'] == 'B_R04_B' and save['lastCombatResult']['won']
    assert resolution['saveFile'] == 'qa-' + key + '-save.json' and not resolution['cancelled']
    assert resolution['enemyID'] == save['lastEncounterID'] and resolution['won'] == save['lastCombatResult']['won']
    battle = json.loads((folder / 'last_battle.json').read_text())
    assert battle['revision'] == save['revision'] and battle['value'].startswith('VICTORY: B_R04_B, rewards committed atomically;')
    assert json.loads(json.loads((folder / 'last_presentation_hp.json').read_text())['value']) == {}
    return {'status': 'GETTER_AND_GAMEPLAY_CHECKS_PASS', 'saveKey': key, 'rows': len(rows),
            'walkRows': len(walk), 'walkRenderedRows': len(walk_rendered), 'renderedRows': len(rendered), 'firstRestElapsed': rest[0]['elapsedSeconds'],
            'meshRequested': mesh, 'groundedEntryRequested': grounded,
            'measuredWalkSpanSeconds': measured_walk_span, 'measuredRestStartSeconds': measured_rest_start,
            'referencePointRangeScenePoints': spread, 'rootTravelScenePoints': root_spread,
            'visibleVideoMarkerVerified': False, 'visualGroundContactAccepted': False,
            'artComplete': False, 'humanAdopted': False,
            'inputsSHA256': {n: hashlib.sha256((folder / n).read_bytes()).hexdigest()
                            for n in ['CAPTURE.json', 'entry_trace.json', 'BUILD_RECEIPT.json',
                                      'last_battle_resolution.json', 'last_presentation_hp.json',
                                      'qa-' + key + '-save.json']}}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = verify(args.folder)
    with args.output.open('x') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps({k: report[k] for k in ['status', 'walkRows', 'rootTravelScenePoints', 'referencePointRangeScenePoints']}))

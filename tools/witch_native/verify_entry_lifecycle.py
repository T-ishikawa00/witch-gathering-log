#!/usr/bin/env python3
"""Verify actual paused/resumed battle-entry getter data, separately from UI pass."""
import argparse
import datetime
import hashlib
import json
import math
from pathlib import Path

ACTOR = 'ACT_B_R04_B'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def epoch(value):
    return datetime.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()


def verify(folder):
    def load(name):
        return json.loads((folder / name).read_text())
    capture = load('CAPTURE.json')
    trace = load('entry_trace.json')
    test = load('TEST_SUMMARY.json')
    key = (folder / 'TEST_SAVE_KEY.txt').read_text().strip()
    require(capture['status'] == 'CAPTURED_REQUIRES_HOST_VALIDATION', 'Capture incomplete')
    require(capture['saveKey'] == key == trace['saveKey'], 'Run identity mismatch')
    required = {'entry_trace.json', 'TEST_SUMMARY.json', 'TEST_SAVE_KEY.txt', 'SOURCE_SHA256.json',
                'RESOURCE_SHA256.json', 'UI.log', 'attachments/manifest.json', 'last_battle.json',
                'last_battle_resolution.json', 'last_presentation_hp.json', 'qa-' + key + '-save.json'}
    require(required <= capture['filesSHA256'].keys(), 'Input hash manifest incomplete')
    for name, value in capture['filesSHA256'].items():
        require(sha(folder / name) == value, 'Input drift: ' + name)
    require(not capture['sourceDrift'] and not capture['resourceDrift'], 'Build input drift')
    require(capture['installedExecutableSHA256'] == capture['executableSHA256'], 'Installed build mismatch')
    require(test['passedTests'] == 1 and test['failedTests'] == 0 and test['result'] == 'Passed', 'UI driver failed')
    require(test['startTime'] <= epoch(trace['startedAt']) <= test['finishTime'], 'Stale trace')
    require(trace['requestedMeshCandidate'] is True and trace['groundedEntryR005Requested'] is True
            and trace['lifecycleRequested'] is True, 'Missing required QA mode')
    require(trace['entryDurationSeconds'] == .6 and trace['meshPeriodSeconds'] == .6
            and trace['captureWindowSeconds'] == 8, 'Entry timing contract changed')
    rows = trace['rows']
    require(60 <= len(rows) <= 900 and rows[0]['phase'] == 'arrivalScheduled', 'Trace coverage invalid')
    observed_span = rows[-1]['elapsedSeconds'] - rows[0]['elapsedSeconds']
    require(observed_span >= 7.5, 'Trace ended before the requested observation window')
    def actor(row):
        return row['actors'][ACTOR]
    def rig(row):
        return actor(row)['presentation']['rig']
    def finite_numbers(values):
        return all(type(v) in (int, float) and math.isfinite(v) for v in values)
    for index, row in enumerate(rows):
        require(row['sample'] == index, 'Sample order mismatch')
        require(type(row['scenePaused']) is bool and type(row['sceneSpeed']) in (int, float)
                and row['sceneSpeed'] == 1, 'Invalid scene pause/speed')
        require(finite_numbers(actor(row)['root'] + actor(row)['home'] + actor(row)['scale']), 'Invalid transform')
        require(finite_numbers([row['elapsedSeconds'], row['sceneTime'], row['sceneClock']]), 'Invalid time')
        if index:
            require(row['elapsedSeconds'] > rows[index - 1]['elapsedSeconds'], 'Elapsed time not increasing')
    inactive = [r for r in rows if r['phase'].startswith('lifecycle_') and r['scenePaused']]
    require(len(inactive) >= 3, 'ENTRY_TIMING_INCONCLUSIVE: no complete inactive/background transition')
    first, last = inactive[0], inactive[-1]
    active = next((r for r in rows if r['sample'] > last['sample'] and r['phase'] == 'lifecycle_active'), None)
    require(active is not None and not active['scenePaused'], 'No foreground transition')
    pause_seconds = active['elapsedSeconds'] - first['elapsedSeconds']
    require(pause_seconds >= 3, 'Inactive interval shorter than 3 seconds')
    paused = [r for r in rows if first['sample'] <= r['sample'] <= active['sample']]
    background = next((r for r in paused if r['phase'] == 'lifecycle_background'), None)
    require(background is not None, 'No actual background event')
    background_seconds = active['elapsedSeconds'] - background['elapsedSeconds']
    require(background_seconds >= 2.5, 'Background interval too short for staged3secHome cycle')
    for row in paused:
        require(actor(row)['presentation']['state'] == 'walk' and rig(row)['groundedEntryActive'] is True,
                'ENTRY_TIMING_INCONCLUSIVE: transition occurred outside grounded walk')
        require(row['sceneFrame'] == first['sceneFrame'] and row['sceneClock'] == first['sceneClock'],
                'Frame or presentation clock changed while inactive')
    def geometry(row):
        a, g = actor(row), rig(row)
        return {'root': a['root'], 'home': a['home'], 'scale': a['scale'],
                'points': [{k: p[k] for k in ('index', 'sourceArtworkPixels', 'destinationNormalized', 'scenePoint')}
                           for p in g['points']]}
    require(all(geometry(r) == geometry(first) for r in paused), 'Sampled geometry changed while inactive')
    walk = [r for r in rows if actor(r)['presentation']['state'] == 'walk']
    before = [r for r in walk if r['phase'] == 'didFinishUpdate' and r['sample'] < first['sample']]
    resumed = [r for r in walk if r['phase'] == 'didFinishUpdate' and r['sample'] > active['sample']]
    require(len(before) >= 2 and len(resumed) >= 2, 'Missing rendered walk before/after pause')
    def warp(row):
        return tuple(v for p in rig(row)['points'] for v in p['destinationNormalized'])
    require(len({warp(r) for r in resumed}) >= 2, 'Mesh did not resume movement')
    max_residual = 0
    endpoint_handoffs = []
    for row in walk:
        a, g = actor(row), rig(row)
        require(a['arrivalAction'] and g['meshActive'] and g['meshPresent']
                and g['groundedEntryActive'] and g['meshVertexCount'] == 429, 'Actual mesh not active')
        require(not g['overlayActive'] and not g['bodyHidden'] and not g['rigHidden'], 'Wrong visible body path')
        require(len(g['points']) == 4, 'Sampled vertex contract changed')
        for p in g['points']:
            require(finite_numbers(p['destinationNormalized'] + p['scenePoint']), 'Invalid sampled vertex')
        if not g['meshActionRunning']:
            # SpriteKit can complete the body warp one rendered frame before
            # the root's wait+run sequence requests idle. Admit only the final
            # identity frame, never a stalled middle-of-stride action.
            require(row is walk[-1] and row['phase'] == 'didFinishUpdate' and not row['scenePaused']
                    and row['sample'] > active['sample'], 'Nonterminal warp action stopped')
            require(max(abs(x - y) for x, y in zip(a['root'], a['home'])) < .001, 'Endpoint root not home')
            require(all(p['scenePoint'] == p['unwarpedScenePoint'] for p in g['points']), 'Endpoint not identity')
            following = next((r for r in rows if r['sample'] > row['sample'] and r['phase'] == 'didFinishUpdate'), None)
            require(following is not None and following['sceneFrame'] == row['sceneFrame'] + 1
                    and actor(following)['presentation']['state'] == 'idle'
                    and not rig(following)['meshActive'] and not rig(following)['groundedEntryActive']
                    and rig(following)['subdivisionLevels'] == 2, 'Endpoint did not hand off on next frame')
            endpoint_handoffs.append(row['sample'])
        p = g['points'][0]
        require(p['index'] == 34 and p['sourceArtworkPixels'] == [16, 140], 'Reference vertex mismatch')
        for axis in range(2):
            residual = abs(a['root'][axis] - a['home'][axis] + p['scenePoint'][axis] - p['unwarpedScenePoint'][axis])
            max_residual = max(max_residual, residual)
            require(residual < .001, 'Grounded root compensation mismatch')
    rest = [r for r in rows if r['sample'] > active['sample'] and actor(r)['presentation']['state'] != 'walk']
    require(rest and any(actor(r)['presentation']['state'] == 'idle' for r in rest), 'No idle restore')
    for row in rest:
        a, g = actor(row), rig(row)
        require(not a['arrivalAction'] and not g['meshActive'] and not g['meshPresent']
                and not g['meshActionRunning'] and not g['groundedEntryActive']
                and g['subdivisionLevels'] == 2, 'Entry mesh did not clean up')
        require(max(abs(x - y) for x, y in zip(a['root'], a['home'])) < .001, 'Root did not restore')
    save = load('qa-' + key + '-save.json')['snapshot']
    resolution_raw = load('last_battle_resolution.json')
    resolution = json.loads(resolution_raw['value'])
    battle = load('last_battle.json')
    require(resolution['saveFile'] == 'qa-' + key + '-save.json' and not resolution['cancelled'], 'Wrong battle/save')
    require(resolution['enemyID'] == save['lastEncounterID'] == 'B_R04_B', 'Wrong actual enemy')
    require(resolution['won'] == save['lastCombatResult']['won'], 'Save/outcome mismatch')
    require(battle['revision'] == resolution_raw['revision'] == save['revision'], 'Revision mismatch')
    prefix = 'VICTORY' if resolution['won'] else 'DEFEAT'
    require(battle['value'].startswith(prefix + ': B_R04_B'), 'Battle outcome mismatch')
    require(json.loads(load('last_presentation_hp.json')['value']) == {}, 'Terminal HP mismatch')
    require(test['startTime'] <= epoch(battle['date']) <= test['finishTime'], 'Stale battle receipt')
    return {'status': 'ACTUAL_ENTRY_LIFECYCLE_GETTER_AND_SAVE_PASS', 'saveKey': key, 'rows': len(rows),
            'inactiveToActiveSeconds': pause_seconds, 'pausedTransitionRows': len(paused),
            'backgroundToActiveSeconds': background_seconds, 'observedTraceSpanSeconds': observed_span,
            'activeEdgeComparison': 'Synchronous scenePhase callback unpauses then samples before next SpriteKit update',
            'pausedFrame': first['sceneFrame'], 'renderedWalkBefore': len(before),
            'renderedWalkAfter': len(resumed), 'resumedWarpVariants': len({warp(r) for r in resumed}),
            'sampledVertices': 4, 'maxCompensationResidualScenePoints': max_residual,
            'singleIdentityEndpointHandoffSamples': endpoint_handoffs,
            'sceneFrameAndSampledGeometryStable': True, 'idleRestore': True,
            'outcome': prefix, 'finalRevision': save['revision'],
            'UIStaging': '3sec test-only preparation; actual entry action remains0.6sec',
            'physicalDeviceExecuted': False, 'naturalWalkAccepted': False, 'humanAdopted': False,
            'CAPTURESha256': sha(folder / 'CAPTURE.json'), 'verifierSHA256': sha(Path(__file__))}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = verify(args.folder)
    with args.output.open('x') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps(report))

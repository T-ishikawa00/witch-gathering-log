#!/usr/bin/env python3
"""Run isolated scene/cache QA. Cost bounds are not a device-memory benchmark."""
import argparse
import base64
import datetime as dt
import fcntl
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
import uuid

from state_transition_capture import validate_normal_build, snapshot_fixed_receipts, restore_fixed_receipts

DEVICE = '1D034CC3-9259-4AEE-A21D-E6E88D242ACF'
BUNDLE = 'local.witch.autonomous.r1'

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def write(p, value):
    p.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

def command(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=45).strip()

def support_folder():
    return Path(command('xcrun', 'simctl', 'get_app_container', DEVICE, BUNDLE, 'data')) / 'Library/Application Support/Witch03to05R1'

def verify(raw, expected_ids):
    expected_scenes = {'SCN_A_R%02d_%02d' % (r, a) for r in range(1, 6) for a in range(1, 5)}
    rows = raw.get('rows', [])
    pressure = raw.get('pressureRows', [])
    snapshots = [r.get('cache', {}) for r in rows + pressure] + [raw.get('finalCache', {})]
    bounds = all(c.get('byteLimit') == 64 * 1024 * 1024 and c.get('entryLimit') == 128
                 and 0 <= c.get('estimatedBytes', -1) <= c['byteLimit']
                 and 0 <= c.get('entries', -1) <= c['entryLimit'] for c in snapshots)
    clear = raw.get('afterClear', {})
    return {
        'twoPassesOfTwentyScenes': len(rows) == 40 and all(
            {r.get('sceneID') for r in rows if r.get('pass') == p} == expected_scenes for p in [1, 2]),
        'backgroundsLoadedAndRendered': bool(rows) and all(r.get('backgroundLoaded') is True
            and r.get('sceneMatches') is True and r.get('renderedAfterConfigure') is True
            and r.get('actualBackgroundID') == r.get('expectedBackgroundID') for r in rows),
        'exactPressureIDsLoaded': [r.get('id') for r in pressure] == expected_ids
            and all(r.get('loaded') is True for r in pressure),
        'allCacheBounds': bounds,
        'pressureActuallyEvicted': bool(pressure)
            and raw.get('beforePressure', {}).get('evictions', -1) >= 0
            and pressure[-1].get('cache', {}).get('evictions', -1) > raw['beforePressure']['evictions'],
        'clearReleasedAllCacheEntries': clear.get('entries') == 0 and clear.get('estimatedBytes') == 0,
        'heldNodeRetainedTexture': raw.get('heldTextureSurvivesCacheClear') is True
            and raw.get('heldTextureSurvivesRouteSweep') is True,
        'stateAndSaveUnchanged': raw.get('stateUnchanged') is True and raw.get('saveUnchanged') is True
            and raw.get('initialSaveSHA256') == raw.get('finalSaveSHA256')
            and raw.get('initialSaveSHA256') not in [None, 'MISSING'],
        'homeRestored': raw.get('restoredTab') == '家',
        'presentationContextRestored': isinstance(raw.get('initialContext'), dict)
            and set(raw['initialContext']) == {'tab', 'region', 'activeEnemy'}
            and raw['initialContext'] == raw.get('restoredContext'),
    }

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--app', type=Path, required=True)
    ap.add_argument('--ids', type=Path, required=True, help='JSON list derived from the pinned preflight inventory')
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--execute', action='store_true')
    args = ap.parse_args()
    app, output = args.app.resolve(), args.output.resolve()
    build = validate_normal_build(app, app.parent / 'BUILD_RECEIPT.json')
    if build['status'] != 'SIMULATOR_BUILD_PASS' or not all(build['checks'].values()):
        raise ValueError('Frozen build preflight failed')
    ids = json.loads(args.ids.read_text())
    if not isinstance(ids, list) or not ids or len(ids) != len(set(ids)):
        raise ValueError('A nonempty unique ID list is required')
    if not args.execute:
        print(json.dumps({'status': 'PREFLIGHT_ONLY', 'idCount': len(ids)})); return 0
    lock = Path('/tmp/witch-loop-qa-' + DEVICE + '.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    output.mkdir(parents=True, exist_ok=False)
    report = {'status': 'RUNNING', 'startedAt': dt.datetime.now().astimezone().isoformat(),
              'device': DEVICE, 'app': str(app), 'executableSHA256': sha(app / 'WitchGathering'),
              'scope': 'PRESENTATION_ROUTE_AND_CACHE_PRESSURE_ONLY_NOT_DEVICE_MEMORY_OR_GAMEPLAY'}
    write(output / 'RUN.json', report)
    support = None
    before = {}
    identity_verified = False
    launched = False
    key = 'cache-' + uuid.uuid4().hex
    try:
        initial_support = support_folder()
        report['initialSupportPath'] = str(initial_support)
        before = snapshot_fixed_receipts(initial_support)
        backup = output / 'prior_fixed_receipts'; backup.mkdir()
        for name, record in before.items():
            (backup / name).write_bytes(record['bytes'])
        write(output / 'PRIOR_FIXED_METADATA.json', {name: {k: v for k, v in row.items() if k != 'bytes'}
                                                  for name, row in before.items()})
        shutil.copy2(app.parent / 'BUILD_RECEIPT.json', output / 'BUILD_RECEIPT.json')
        shutil.copy2(args.ids, output / 'PRESSURE_IDS.json')
        command('xcrun', 'simctl', 'install', DEVICE, str(app))
        support = support_folder()
        report['postInstallSupportPath'] = str(support)
        report['containerPathChanged'] = support != initial_support
        # simctl can move the existing data container to a new UUID. Verify
        # actual prior data identity before launching or selecting a restore
        # destination, rather than assuming path stability or copying blindly.
        report['postInstallPriorBytesMatch'] = {name: (support / name).is_file()
            and (support / name).read_bytes() == row['bytes'] for name, row in before.items()}
        identity_verified = all(report['postInstallPriorBytesMatch'].values())
        if not identity_verified: raise ValueError('Post-install prior data identity mismatch; no QA launched')
        save = support / ('qa-' + key + '-save.json')
        if save.exists(): raise ValueError('QA save key already exists')
        launch = ['--qa-isolated', '--qa-save-key=' + key, '--qa-scene-texture-cache',
                  '--qa-scene-cache-ids-b64=' + base64.b64encode(json.dumps(ids).encode()).decode()]
        report['saveKey'] = key; report['launchArguments'] = launch
        start = time.time()
        launched = True  # Also stop a launch whose CLI result times out.
        report['launchResult'] = command('xcrun', 'simctl', 'launch', '--terminate-running-process', DEVICE, BUNDLE, *launch)
        result = support / ('scene_texture_cache_' + key + '.json')
        screenshots = set()
        deadline = time.monotonic() + 150
        while time.monotonic() < deadline:
            for region in ['R01', 'R03', 'R05']:
                name = 'scene_texture_cache_' + key + '_p1_A_' + region + '_01.json'
                if region not in screenshots and (support / name).exists():
                    # The screenshot is observational; the per-route receipt is
                    # the exact scene identity because the sweep keeps running.
                    command('xcrun', 'simctl', 'io', DEVICE, 'screenshot', str(output / (region + '_observational.png')))
                    screenshots.add(region)
            if result.exists() and result.stat().st_mtime >= start: break
            time.sleep(.08)
        if not result.exists(): raise TimeoutError('Matching cache report not produced')
        raw = json.loads(result.read_text())
        if raw.get('saveKey') != key: raise ValueError('Wrong QA run ID')
        for source in support.glob('scene_texture_cache_' + key + '*.json'):
            shutil.copy2(source, output / source.name)
        shutil.copy2(save, output / save.name)
        command('xcrun', 'simctl', 'io', DEVICE, 'screenshot', str(output / 'home_restored.png'))
        report['checks'] = verify(raw, ids)
        report['rawReport'] = result.name
        report['status'] = 'PASS_TECHNICAL_REQUIRES_VISUAL_REVIEW' if all(report['checks'].values()) else 'FAIL'
    except Exception as error:
        report['status'] = 'FAIL'; report['error'] = repr(error)
    finally:
        cleanup_errors = []
        if launched:
            try:
                stopped = subprocess.run(['xcrun', 'simctl', 'terminate', DEVICE, BUNDLE], capture_output=True, timeout=30)
                report['terminateExitCode'] = stopped.returncode
                if stopped.returncode: cleanup_errors.append('QA app termination returned ' + str(stopped.returncode))
            except Exception as error: cleanup_errors.append('terminate: ' + repr(error))
        # Preserve fresh fixed receipts before restoring the pre-install bytes.
        try:
            fresh = output / 'fresh_fixed_receipts'; fresh.mkdir()
            if support is not None:
                for source in support.glob('*.json'):
                    if source.name.startswith('last_') or source.name in ('runtime_metrics.json', 'battle_before.json'):
                        try: shutil.copy2(source, fresh / source.name)
                        except Exception as error: cleanup_errors.append('fresh ' + source.name + ': ' + repr(error))
        except Exception as error: cleanup_errors.append('fresh directory: ' + repr(error))
        # Restoration must still run if fresh-copy or recorder/termination fails.
        if support is not None and identity_verified:
            restored = {}
            for name, row in before.items():
                try: restored.update(restore_fixed_receipts(support, {name: row}))
                except Exception as error:
                    restored[name] = False
                    cleanup_errors.append('restore ' + name + ': ' + repr(error))
            report['priorFixedReceiptRestoration'] = restored
            if not all(restored.values()): report['status'] = 'FAIL'
        elif before:
            report['restorationSkipped'] = 'No verified post-install data destination; prior bytes retained in backup'
            report['status'] = 'FAIL'
        report['cleanupErrors'] = cleanup_errors
        if cleanup_errors: report['status'] = 'FAIL'
        report['finishedAt'] = dt.datetime.now().astimezone().isoformat()
        report['filesSHA256'] = {}
        for p in output.rglob('*'):
            if p.is_file() and p.name != 'RUN.json':
                try: report['filesSHA256'][str(p.relative_to(output))] = sha(p)
                except Exception as error:
                    report['status'] = 'FAIL'; cleanup_errors.append('hash ' + str(p) + ': ' + repr(error))
        write(output / 'RUN.json', report)
    print(json.dumps({k: report.get(k) for k in ['status', 'error', 'checks']}))
    return 0 if report['status'] == 'PASS_TECHNICAL_REQUIRES_VISUAL_REVIEW' else 1

if __name__ == '__main__':
    raise SystemExit(main())

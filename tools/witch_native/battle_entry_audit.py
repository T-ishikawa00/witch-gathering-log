#!/usr/bin/env python3
"""Capture the real battle entry with per-render marker/geometry evidence.

Uses only the dedicated root QA Simulator and a fresh isolated challenge save.
Preserves raw output in a new directory. Capture is not visual acceptance.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import signal
import subprocess
import time
import uuid

DEVICE = '1D034CC3-9259-4AEE-A21D-E6E88D242ACF'
BUNDLE = 'local.witch.autonomous.r1'

def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    if not __debug__: raise RuntimeError('QA capture refuses optimized interpreter')
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--app', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--mesh', action='store_true')
    ap.add_argument('--grounded-entry', action='store_true')
    a = ap.parse_args()
    if a.grounded_entry and not a.mesh: ap.error('--grounded-entry requires --mesh')
    app, out = a.app.resolve(), a.output.resolve()
    receipt = json.loads((app.parent / 'BUILD_RECEIPT.json').read_text())
    assert receipt['status'] == 'SIMULATOR_BUILD_PASS'
    assert sha(app / 'WitchGathering') == receipt['executable_sha256']
    out.mkdir(parents=True, exist_ok=False)
    shutil.copy2(app.parent / 'BUILD_RECEIPT.json', out / 'BUILD_RECEIPT.json')
    key = 'battle-entry-' + str(uuid.uuid4())
    report = {'status': 'RUNNING', 'saveKey': key, 'meshRequested': a.mesh,
              'app': str(app), 'executableSHA256': sha(app / 'WitchGathering'),
              'device': DEVICE, 'fixture': 'challenge, not earned progression',
              'startedAt': datetime.datetime.now().astimezone().isoformat()}
    run('xcrun', 'simctl', 'install', DEVICE, str(app))
    folder = Path(run('xcrun', 'simctl', 'get_app_container', DEVICE, BUNDLE, 'data')) / 'Library/Application Support/Witch03to05R1'
    log = (out / 'video.log').open('w')
    video = out / 'battle.mp4'
    recorder = subprocess.Popen(['xcrun', 'simctl', 'io', DEVICE, 'recordVideo', '--codec=h264', str(video)], stdout=log, stderr=subprocess.STDOUT)
    report['recorderStartedUnix'] = time.time()
    try:
        time.sleep(.4)
        launched = time.time()
        report['launchStartedUnix'] = launched
        args = ['--qa-isolated', '--qa-save-key=' + key, '--qa-fixture=challenge',
                '--qa-persist-fixture', '--qa-encounter=B_R04_B', '--qa-battle-entry-trace']
        if a.mesh:
            args.append('--qa-dragon-mesh-r004')
        if a.grounded_entry:
            args.append('--qa-dragon-grounded-entry-r005')
        report['launchArguments'] = args
        report['launchResult'] = run('xcrun', 'simctl', 'launch', '--terminate-running-process', DEVICE, BUNDLE, *args)
        deadline = time.monotonic() + 100
        trace = None
        complete = None
        while time.monotonic() < deadline:
            matches = list(folder.glob('battle_entry_' + key + '_*.json'))
            if trace is None and matches:
                assert len(matches) == 1, 'Unexpected duplicate entry trace'
                trace = matches[0]
                assert trace.stat().st_mtime >= launched
                payload = json.loads(trace.read_text())
                assert payload['saveKey'] == key and payload['requestedMeshCandidate'] == a.mesh
                shutil.copy2(trace, out / 'entry_trace.json')
                report['traceCopiedUnix'] = time.time()
                run('xcrun', 'simctl', 'io', DEVICE, 'screenshot', str(out / 'after_entry.png'))
            battle = folder / 'last_battle.json'
            if battle.exists() and battle.stat().st_mtime >= launched:
                value = json.loads(battle.read_text())
                if value.get('value', '').startswith('VICTORY: B_R04_B, rewards committed atomically;'):
                    complete = value
                    break
            time.sleep(.1)
        assert trace is not None, 'Entry trace missing'
        assert complete is not None, 'Fresh matching battle completion missing'
        for name in ['last_battle.json', 'last_battle_art.json', 'last_battle_resolution.json',
                     'last_presentation_hp.json', 'runtime_metrics.json', 'battle_before.json',
                     'qa-' + key + '-save.json']:
            p = folder / name
            assert p.exists() and p.stat().st_mtime >= launched, 'Missing/stale ' + name
            shutil.copy2(p, out / name)
        saved = json.loads((out / ('qa-' + key + '-save.json')).read_text())['snapshot']
        resolution = json.loads(json.loads((out / 'last_battle_resolution.json').read_text())['value'])
        assert saved['lastEncounterID'] == 'B_R04_B' and saved['lastCombatResult']['won']
        assert resolution['saveFile'] == 'qa-' + key + '-save.json' and not resolution['cancelled']
        assert resolution['enemyID'] == 'B_R04_B' and resolution['won']
        report['status'] = 'CAPTURED_REQUIRES_HOST_AND_VISUAL_VALIDATION'
        run('xcrun', 'simctl', 'io', DEVICE, 'screenshot', str(out / 'result.png'))
    except Exception as error:
        report['status'] = 'CAPTURE_FAILED'
        report['error'] = repr(error)
        raise
    finally:
        recorder.send_signal(signal.SIGINT)
        recorder.wait(timeout=20)
        log.close()
        report['finishedAt'] = datetime.datetime.now().astimezone().isoformat()
        report['filesSHA256'] = {p.name: sha(p) for p in out.iterdir() if p.is_file()}
        (out / 'CAPTURE.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        print(json.dumps({k: report.get(k) for k in ['status', 'saveKey', 'error']}, ensure_ascii=False))

if __name__ == '__main__':
    main()

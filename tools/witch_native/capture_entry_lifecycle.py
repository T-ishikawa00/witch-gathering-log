#!/usr/bin/env python3
"""Copy a completed entry-lifecycle UI run into a new evidence directory."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('xcresult', 'freeze', 'app', 'ui-log', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    summary = json.loads(subprocess.check_output([
        'xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
        '--path', str(args.xcresult), '--compact'], text=True))
    (out / 'TEST_SUMMARY.json').write_text(json.dumps(summary, indent=2) + '\n')
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments',
                    '--path', str(args.xcresult), '--output-path', str(out / 'attachments')],
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    manifest = json.loads((out / 'attachments/manifest.json').read_text())
    identities = [a for t in manifest for a in t['attachments']
                  if a['suggestedHumanReadableName'].startswith('dragon_grounded_entry_lifecycle_save_key_')]
    if len(identities) != 1 or identities[0]['deviceId'] != args.device:
        raise ValueError('Expected exactly one save-key attachment from the requested device')
    key = (out / 'attachments' / identities[0]['exportedFileName']).read_text().strip()
    if not key.startswith('dragon-entry-lifecycle-') or not all(c.isalnum() or c == '-' for c in key):
        raise ValueError('Unexpected isolated save key')
    (out / 'TEST_SAVE_KEY.txt').write_text(key + '\n')
    container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.device,
        'local.witch.autonomous.r1', 'data'], text=True).strip()) / 'Library/Application Support/Witch03to05R1'
    traces = list(container.glob('battle_entry_' + key + '_*.json'))
    if len(traces) != 1:
        raise ValueError('Exactly one trace required for this fresh UUID run')
    shutil.copy2(traces[0], out / 'entry_trace.json')
    required = ['last_battle.json', 'last_battle_resolution.json', 'last_presentation_hp.json',
                'qa-' + key + '-save.json']
    for name in required:
        shutil.copy2(container / name, out / name)
    for name in ['last_art.json', 'last_battle_before.json', 'runtime_metrics.json']:
        if (container / name).exists():
            shutil.copy2(container / name, out / name)
    shutil.copy2(args.ui_log, out / 'UI.log')
    shutil.copy2(args.freeze / 'SOURCE_SHA256.json', out / 'SOURCE_SHA256.json')
    shutil.copy2(args.freeze / 'RESOURCE_SHA256.json', out / 'RESOURCE_SHA256.json')
    source = json.loads((args.freeze / 'SOURCE_SHA256.json').read_text())
    drift = [name for name, value in source.items() if sha(args.freeze / name) != value]
    resources = json.loads((args.freeze / 'RESOURCE_SHA256.json').read_text())
    resource_drift = [name for name, value in resources.items() if sha(args.app / name) != value]
    installed = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.device,
        'local.witch.autonomous.r1', 'app'], text=True).strip())
    report = {'status': 'CAPTURED_REQUIRES_HOST_VALIDATION', 'saveKey': key, 'device': args.device,
              'capturedAt': datetime.datetime.now().astimezone().isoformat(),
              'xcresult': str(args.xcresult.resolve()), 'app': str(args.app.resolve()),
              'executableSHA256': sha(args.app / 'WitchGathering'),
              'installedExecutableSHA256': sha(installed / 'WitchGathering'),
              'sourceFreeze': str(args.freeze.resolve()), 'sourceDrift': drift,
              'resourceDrift': resource_drift, 'resourceCount': len(resources),
              'traceOriginalFilename': traces[0].name,
              'filesSHA256': {str(p.relative_to(out)): sha(p) for p in out.rglob('*') if p.is_file()},
              'candidateAdopted': False, 'physicalDeviceExecuted': False}
    (out / 'CAPTURE.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'status': report['status'], 'saveKey': key,
                      'sourceDrift': drift, 'resourceDrift': resource_drift}))


if __name__ == '__main__':
    main()

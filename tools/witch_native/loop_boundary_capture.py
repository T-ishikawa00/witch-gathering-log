#!/usr/bin/env python3
"""Capture real SpriteKit idle/walk loops on reserved, isolated QA simulators.

Each attempt has an exclusive folder/save UUID and preserves failed raw evidence.
This viewer capture does not establish battle progression or art approval.
"""
import argparse
import datetime
import fcntl
import hashlib
import json
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time
import uuid

BUNDLE = 'local.witch.autonomous.r1'
DEVICES = ['1D034CC3-9259-4AEE-A21D-E6E88D242ACF',
           '9A067715-7CF3-40D3-9064-38423223959B']

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write_json_atomic(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + '.tmp-' + str(uuid.uuid4()))
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)

def resource_manifest(bundle):
    bundle = Path(bundle)
    return {str(p.relative_to(bundle)): sha(p) for p in sorted(bundle.rglob('*'))
            if p.is_file() and p.name != 'WitchGathering'}

def inspect_build_receipt(app, receipt_path, allow_resource_preview=False):
    """Validate either a normal build or an explicitly authorized local resource preview."""
    app = Path(app).resolve()
    receipt_path = Path(receipt_path).resolve()
    receipt = json.loads(receipt_path.read_text())
    checks = {}
    if receipt.get('status') == 'SIMULATOR_BUILD_PASS':
        checks['normal_build_status'] = True
        checks['bundle_executable_sha'] = sha(app / 'WitchGathering') == receipt.get('executable_sha256')
        checks['bundle_resource_map'] = resource_manifest(app) == receipt.get('resource_sha256')
        return {'receipt': receipt, 'receiptPath': receipt_path, 'receiptSHA256': sha(receipt_path),
                'status': receipt['status'], 'checks': checks, 'resourcePreview': False}
    if not allow_resource_preview:
        raise RuntimeError('Nonstandard build receipt requires --allow-resource-preview')
    if receipt.get('status') != 'QA_RESOURCE_PREVIEW_FROM_VERIFIED_BUILD' or receipt.get('resourcePreview') is not True:
        raise RuntimeError('Invalid resource-preview receipt status/flag')
    base_path = Path(receipt.get('baseBuildReceiptPath', '')).resolve()
    base_receipt = json.loads(base_path.read_text())
    base_bundle = Path(base_receipt['bundle']).resolve()
    base_resources = base_receipt.get('resource_sha256')
    candidate_resources = receipt.get('resource_sha256')
    source_hashes = receipt.get('source_sha256')
    overrides = receipt.get('resourceOverrides')
    checks['base_receipt_sha'] = sha(base_path) == receipt.get('baseBuildReceiptSHA256')
    checks['base_build_pass'] = base_receipt.get('status') == 'SIMULATOR_BUILD_PASS'
    checks['base_executable_sha'] = sha(base_bundle / 'WitchGathering') == base_receipt.get('executable_sha256')
    checks['base_resource_map'] = resource_manifest(base_bundle) == base_resources
    checks['candidate_executable_unchanged'] = receipt.get('executable_sha256') == base_receipt.get('executable_sha256') == sha(app / 'WitchGathering')
    checks['source_map_unchanged'] = source_hashes == base_receipt.get('source_sha256')
    checks['candidate_resource_map_exact'] = isinstance(candidate_resources, dict) and resource_manifest(app) == candidate_resources
    override_rows = overrides if isinstance(overrides, list) else []
    override_paths = [x.get('path') for x in override_rows if isinstance(x, dict)]
    checks['override_rows_well_formed'] = isinstance(overrides, list) and len(override_paths) == len(override_rows) and all(
        isinstance(x.get('path'), str) and (x.get('beforeSHA256') is None or isinstance(x.get('beforeSHA256'), str)) and
        isinstance(x.get('afterSHA256'), str) for x in override_rows if isinstance(x, dict))
    checks['override_paths_unique'] = len(override_paths) == len(set(override_paths)) and bool(override_paths)
    safe_paths = all(isinstance(p, str) and p and not Path(p).is_absolute() and '..' not in Path(p).parts for p in override_paths)
    checks['override_paths_safe'] = safe_paths
    changed_paths = sorted(k for k in set(base_resources or {}) | set(candidate_resources or {})
                           if (base_resources or {}).get(k) != (candidate_resources or {}).get(k))
    checks['override_list_is_complete'] = sorted(override_paths) == changed_paths
    checks['override_hashes_match_maps'] = safe_paths and all(
        x.get('beforeSHA256') == (base_resources or {}).get(x['path']) and
        x.get('afterSHA256') == (candidate_resources or {}).get(x['path']) and
        (app / x['path']).is_file() and sha(app / x['path']) == x.get('afterSHA256')
        for x in override_rows if isinstance(x, dict))
    return {'receipt': receipt, 'receiptPath': receipt_path, 'receiptSHA256': sha(receipt_path),
            'status': receipt['status'], 'checks': checks, 'resourcePreview': True,
            'baseReceiptPath': base_path, 'baseReceiptSHA256': sha(base_path)}

def run(*command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT).strip()

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--app', required=True, type=Path)
    ap.add_argument('--output', required=True, type=Path)
    ap.add_argument('--device', required=True, choices=DEVICES)
    ap.add_argument('--dragon-mesh-r004', action='store_true')
    ap.add_argument('--allow-resource-preview', action='store_true')
    ap.add_argument('--resource-preview-receipt', type=Path)
    ap.add_argument('actors', nargs='+')
    a = ap.parse_args()
    if any(not re.fullmatch(r'ACT_[EB]_R0[1-5]_[0-9AB]{1,2}', x) for x in a.actors):
        ap.error('Use explicit enemy actor IDs')
    if len(a.actors) != len(set(a.actors)):
        ap.error('Duplicate actor IDs')
    app, out = a.app.resolve(), a.output.resolve()
    if a.resource_preview_receipt and not a.allow_resource_preview:
        ap.error('--resource-preview-receipt requires --allow-resource-preview')
    build_path = (a.resource_preview_receipt.resolve() if a.resource_preview_receipt else
                  app.parent / ('RESOURCE_PREVIEW_RECEIPT.json' if a.allow_resource_preview else 'BUILD_RECEIPT.json'))
    build_info = inspect_build_receipt(app, build_path, a.allow_resource_preview)
    failed_build_checks = [k for k, v in build_info['checks'].items() if not v]
    if failed_build_checks:
        raise RuntimeError('Build receipt validation failed: ' + ', '.join(failed_build_checks))
    build = build_info['receipt']
    lock = open('/tmp/witch-loop-qa-' + a.device + '.lock', 'a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    out.mkdir(parents=True, exist_ok=False)
    shutil.copy2(build_path, out / 'BUILD_RECEIPT.json')
    install = ['xcrun', 'simctl', 'install', a.device, str(app)]
    run(*install)
    container = Path(run('xcrun', 'simctl', 'get_app_container', a.device, BUNDLE, 'data'))
    installed = Path(run('xcrun', 'simctl', 'get_app_container', a.device, BUNDLE, 'app'))
    installed_sha = sha(installed / 'WitchGathering')
    if installed_sha != build['executable_sha256']:
        raise RuntimeError('Installed executable mismatch')
    folder = container / 'Library/Application Support/Witch03to05R1'
    batch = {'status': 'RUNNING', 'app': str(app), 'device': a.device,
             'executableSHA256': installed_sha, 'buildReceiptStatus': build_info['status'],
             'buildReceiptSHA256': build_info['receiptSHA256'], 'resourcePreview': build_info['resourcePreview'],
             'baseBuildReceiptSHA256': build_info.get('baseReceiptSHA256'), 'installCommand': install,
             'installedBundle': str(installed), 'dataContainer': str(container), 'cases': []}
    for actor in a.actors:
        case = out / actor
        case.mkdir(exist_ok=False)
        key = 'loop-' + str(uuid.uuid4())
        report = {'actorID': actor, 'saveKey': key, 'app': str(app),
                  'device': a.device, 'dataContainer': str(container),
                  'installedBundle': str(installed), 'executableSHA256': installed_sha,
                  'buildReceiptStatus': build_info['status'], 'buildReceiptSHA256': build_info['receiptSHA256'],
                  'resourcePreview': build_info['resourcePreview'],
                  'resourcePreviewOverrides': build.get('resourceOverrides', []),
                  'baseBuildReceiptSHA256': build_info.get('baseReceiptSHA256'),
                  'startedAt': datetime.datetime.now().astimezone().isoformat(),
                  'scope': 'isolated native art viewer, not battle/earned progression',
                  'artComplete': False, 'candidateAdopted': False, 'status': 'RUNNING'}
        video = case / 'loops.mp4'
        record_command = ['xcrun', 'simctl', 'io', a.device, 'recordVideo', '--codec=h264', str(video)]
        log = (case / 'video.log').open('w')
        recorder = subprocess.Popen(record_command, stdout=log, stderr=subprocess.STDOUT)
        report.update(recordCommand=record_command, recorderPID=recorder.pid, recorderStartedUnix=time.time())
        failure = None
        try:
            time.sleep(.5)
            extra = ['--qa-dragon-mesh-r004'] if a.dragon_mesh_r004 else []
            launch = ['xcrun', 'simctl', 'launch', '--terminate-running-process', a.device,
                      BUNDLE, '--qa-isolated', '--qa-save-key=' + key,
                      '--art-audit=' + actor, '--qa-loop-boundary-trace', *extra]
            report['launchCommand'] = launch
            report['launchStartedUnix'] = time.time()
            report['launchResult'] = run(*launch)
            deadline = time.monotonic() + 150
            trace = None
            while time.monotonic() < deadline:
                found = list(folder.glob('loop_boundary_' + key + '_*.json'))
                if len(found) > 1:
                    raise RuntimeError('Ambiguous duplicate trace')
                if found:
                    trace = found[0]
                    if trace.stat().st_mtime < report['launchStartedUnix']:
                        raise RuntimeError('Stale trace')
                    raw = json.loads(trace.read_text())
                    if raw.get('saveKey') != key or raw.get('actorID') != actor:
                        raise RuntimeError('Wrong trace identity')
                    shutil.copy2(trace, case / 'trace.json')
                    report['traceContainerPath'] = str(trace)
                    report['traceCopiedUnix'] = time.time()
                    break
                time.sleep(.1)
            if trace is None:
                raise RuntimeError('No matching loop trace within 150 seconds')
            run('xcrun', 'simctl', 'io', a.device, 'screenshot', str(case / 'after.png'))
            report['status'] = 'CAPTURED_REQUIRES_HOST_AND_VISUAL_VALIDATION'
        except Exception as error:
            failure = repr(error)
            report.update(status='CAPTURE_FAILED', error=failure)
        finally:
            if recorder.poll() is None:
                recorder.send_signal(signal.SIGINT)
            try:
                report['recorderExitCode'] = recorder.wait(timeout=25)
            except subprocess.TimeoutExpired:
                report['recorderStop'] = 'TIMEOUT_LEFT_RUNNING_REQUIRES_OPERATOR'
                report['status'] = 'CAPTURE_FAILED'
                failure = failure or 'Recorder did not stop within 25 seconds after SIGINT'
                # Stop the child before hashing a partial video. Preserve the
                # timeout as a failed attempt instead of losing its receipt.
                try:
                    recorder.kill()
                    report['recorderStop'] = 'TIMEOUT_KILLED_AFTER_GRACE_PERIOD'
                    report['recorderExitCode'] = recorder.wait(timeout=5)
                except Exception as stop_error:
                    report['recorderStopError'] = repr(stop_error)
            log.close()
            try:
                probe_command = ['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(video)]
                probe_raw = run(*probe_command)
                (case / 'video_probe.json').write_text(probe_raw + '\n')
                probe = json.loads(probe_raw)
                streams = [s for s in probe.get('streams', []) if s.get('codec_type') == 'video']
                if report.get('recorderExitCode') != 0 or video.stat().st_size == 0 or not streams or float(probe.get('format', {}).get('duration', 0)) <= 0:
                    raise RuntimeError('Recording did not finalize as a nonempty playable video')
                report['videoProbeCommand'] = probe_command
            except Exception as error:
                failure = failure or repr(error)
                report.update(status='CAPTURE_FAILED', error=failure, videoValidationError=repr(error))
            for name in ['last_art_audit.json', 'last_art_state.json', 'runtime_metrics.json',
                         'qa-' + key + '-save.json']:
                p = folder / name
                if p.exists() and p.stat().st_mtime >= report.get('launchStartedUnix', float('inf')):
                    shutil.copy2(p, case / name)
            report['finishedAt'] = datetime.datetime.now().astimezone().isoformat()
            report['filesSHA256'] = {p.name: sha(p) for p in sorted(case.iterdir()) if p.is_file()}
            write_json_atomic(case / 'CAPTURE.json', report)
            batch['cases'].append({'actorID': actor, 'status': report['status'], 'error': failure,
                                   'captureSHA256': sha(case / 'CAPTURE.json')})
            write_json_atomic(out / 'RUN.json', batch)
            print(actor + ' ' + report['status'], flush=True)
    batch['status'] = 'CAPTURE_FAILED' if any(c['error'] for c in batch['cases']) else 'CAPTURED_REQUIRES_HOST_AND_VISUAL_VALIDATION'
    write_json_atomic(out / 'RUN.json', batch)
    if batch['status'] == 'CAPTURE_FAILED':
        raise SystemExit(1)

if __name__ == '__main__':
    main()

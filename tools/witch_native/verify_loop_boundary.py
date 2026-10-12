#!/usr/bin/env python3
"""Read-only contract validation of captured native loops, independently of UI status.

Passing this contract proves observed sequence coverage, not visual naturalness.
"""
import argparse
import datetime
import hashlib
import json
import math
from pathlib import Path
from loop_boundary_capture import inspect_build_receipt

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def validate(base):
    capture = json.loads((base / 'CAPTURE.json').read_text())
    trace = json.loads((base / 'trace.json').read_text())
    build_path = base.parent / 'BUILD_RECEIPT.json'
    build = json.loads(build_path.read_text())
    # Legacy captures predate explicit mode fields. Derive ordinary mode only
    # from the verified SIMULATOR_BUILD_PASS receipt; previews must opt in.
    receipt_hint = json.loads(build_path.read_text())
    preview_requested = capture.get('resourcePreview') is True or receipt_hint.get('status') == 'QA_RESOURCE_PREVIEW_FROM_VERIFIED_BUILD'
    build_info = inspect_build_receipt(capture.get('app', ''), build_path, preview_requested)
    run_path = base.parent / 'RUN.json'
    run = json.loads(run_path.read_text()) if run_path.is_file() else {}
    capture_sha = sha(base / 'CAPTURE.json')
    checks = []
    def check(name, value, detail=None):
        checks.append({'name': name, 'passed': bool(value), 'detail': detail})
    check('capture_complete', capture['status'] == 'CAPTURED_REQUIRES_HOST_AND_VISUAL_VALIDATION')
    legacy_normal = not preview_requested and 'buildReceiptStatus' not in capture and 'resourcePreview' not in capture
    check('capture_build_status_matches', legacy_normal or capture.get('buildReceiptStatus') == build_info['status'])
    check('capture_preview_flag_matches', legacy_normal or capture.get('resourcePreview') is build_info['resourcePreview'])
    check('capture_base_build_sha_matches', (legacy_normal and 'baseBuildReceiptSHA256' not in capture) or
          capture.get('baseBuildReceiptSHA256') == build_info.get('baseReceiptSHA256'))
    for name, passed in build_info['checks'].items():
        check('build_receipt_' + name, passed)
    matching_cases = [c for c in run.get('cases', []) if c.get('actorID') == capture.get('actorID')]
    check('parent_run_present', bool(run))
    check('parent_run_single_case', len(matching_cases) == 1)
    check('capture_bound_to_parent_run', len(matching_cases) == 1 and matching_cases[0].get('captureSHA256') == capture_sha)
    check('parent_run_identity_matches_capture', run.get('app') == capture.get('app') and run.get('device') == capture.get('device') and run.get('executableSHA256') == capture.get('executableSHA256'))
    run_receipt_sha = run.get('buildReceiptSHA256')
    check('parent_run_receipt_pin_matches_capture', run_receipt_sha in (None, capture.get('buildReceiptSHA256')) and
          (not preview_requested or run_receipt_sha == capture.get('buildReceiptSHA256')))
    if preview_requested:
        check('parent_run_preview_metadata_matches_capture', run.get('resourcePreview') is True and
              run.get('buildReceiptStatus') == build_info['status'] and
              run.get('baseBuildReceiptSHA256') == build_info.get('baseReceiptSHA256'))
    check('capture_build_pin', sha(build_path) == capture['buildReceiptSHA256'])
    app = Path(capture['app'])
    check('executable_matches_build', capture['executableSHA256'] == build['executable_sha256'] == sha(app / 'WitchGathering'))
    mandatory = {'trace.json', 'loops.mp4', 'video.log', 'video_probe.json', 'after.png'}
    check('required_raw_hashes_present', mandatory.issubset(capture['filesSHA256']))
    check('all_recorded_raw_hashes_unchanged', all((base / k).is_file() and sha(base / k) == v for k, v in capture['filesSHA256'].items()))
    check('recorder_finalized', type(capture.get('recorderExitCode')) is int and capture['recorderExitCode'] == 0 and (base / 'loops.mp4').stat().st_size > 0)
    video_probe = json.loads((base / 'video_probe.json').read_text())
    check('video_probe_has_video', any(s.get('codec_type') == 'video' and s.get('width', 0) > 0 and s.get('height', 0) > 0 for s in video_probe.get('streams', [])) and float(video_probe.get('format', {}).get('duration', 0)) > 0)
    check('trace_identity', trace['saveKey'] == capture['saveKey'] and trace['actorID'] == capture['actorID'] and bool(trace.get('runID')))
    check('capture_and_trace_identity', capture.get('actorID') == trace.get('actorID') and capture.get('saveKey') == trace.get('saveKey') and capture.get('app') == run.get('app') and capture.get('device') == run.get('device'))
    started = datetime.datetime.fromisoformat(trace['startedAt'].replace('Z', '+00:00')).timestamp()
    check('trace_belongs_to_launch_window', capture['launchStartedUnix'] <= started <= capture['traceCopiedUnix'])
    check('isolated_flags', all(x in capture['launchCommand'] for x in ['--qa-isolated', '--qa-save-key=' + trace['saveKey'], '--art-audit=' + trace['actorID'], '--qa-loop-boundary-trace']))
    index_path = app / 'Art/runtime_index.json'
    check('runtime_index_matches_build', sha(index_path) == build['resource_sha256'].get('Art/runtime_index.json'))
    index_data = json.loads(index_path.read_text())
    entry = index_data.get('entries', {}).get(trace.get('actorID'))
    rows = trace.get('rows', [])
    check('actor_present_in_runtime_index', isinstance(entry, dict))
    if not isinstance(entry, dict) or trace.get('actorID') != capture.get('actorID') or not isinstance(rows, list):
        return {'status': 'FAIL_OBSERVED_LOOP_CONTRACT', 'actorID': trace.get('actorID'),
                'saveKey': trace.get('saveKey'), 'checks': checks, 'states': [],
                'inputSHA256': {p.name: sha(p) for p in [base / 'CAPTURE.json', base / 'trace.json', build_path]},
                'validatorSHA256': sha(Path(__file__)), 'artComplete': False,
                'naturalnessAccepted': False,
                'scope': 'Identity/catalog failure rejected before loop analysis'}
    check('trace_complete', trace['status'] == 'CAPTURED_REQUIRES_HOST_VALIDATION')
    check('observed_rows', len(rows) > 10)
    check('integer_fields_are_not_booleans', all(type(r['sequence']) is int and type(r['sceneFrame']) is int and type(r['presentation']['frameIndex']) is int for r in rows))
    check('finite_numeric_times', all(type(r['elapsedSeconds']) in (int, float) and math.isfinite(r['elapsedSeconds']) and r['elapsedSeconds'] >= 0 for r in rows))
    check('unique_ordered_sequences', [r['sequence'] for r in rows] == list(range(len(rows))))
    check('all_actual_render_markers', all(r['phase'] == 'didFinishUpdate' and r['videoMarker'] == 'LOOP %04d' % r['sequence'] for r in rows))
    check('ordered_time_and_scene_frames', all(b['elapsedSeconds'] >= a['elapsedSeconds'] and b['sceneFrame'] > a['sceneFrame'] for a, b in zip(rows, rows[1:])))
    results = []
    windows = trace['modes']
    check('two_expected_modes', [m['state'] for m in windows] == ['idle', 'walk'])
    check('mode_windows_recorded', all(m.get('status') == 'OBSERVED_TWO_LOOP_BOUNDARIES' and type(m.get('windowStartRow')) is int and type(m.get('windowEndRow')) is int for m in windows))
    if any(type(m.get('windowStartRow')) is not int or type(m.get('windowEndRow')) is not int for m in windows):
        windows = []
    check('continuous_mode_windows', bool(windows) and windows[0]['windowStartRow'] == 0 and all(b['windowStartRow'] == a['windowEndRow'] + 1 for a, b in zip(windows, windows[1:])) and 1 <= len(rows) - windows[-1]['windowEndRow'] <= 2)
    for state in ['idle', 'walk']:
        mode = next((m for m in windows if m['state'] == state), None)
        samples = [] if mode is None else [r for r in rows if mode['windowStartRow'] <= r['sequence'] <= mode['windowEndRow']]
        check(state + '_observed', bool(samples))
        if not samples:
            continue
        check(state + '_window_identity', all(r['activeMode'] == state for r in samples))
        check(state + '_integer_metadata', type(mode['frameCount']) is int and type(mode['wrapCount']) is int)
        check(state + '_presentation_matches', all(r['presentation']['state'] == state for r in samples))
        result = {'state': state, 'samples': len(samples), 'elapsedSeconds': samples[-1]['elapsedSeconds'] - samples[0]['elapsedSeconds']}
        if not samples[0]['presentation']['isPartRig']:
            clip = entry['clips'][state]
            paths = clip['frames']; fps = float(clip['fps'])
            check(state + '_reported_metadata_matches_bundle', mode['framePaths'] == paths and mode['expectedFPS'] == fps and mode['frameCount'] == len(paths))
            check(state + '_declared_loop', clip.get('loop') is True and fps > 0)
            check(state + '_observed_two_periods_in_real_time', result['elapsedSeconds'] >= 2 * len(paths) / fps)
            check(state + '_frame_resources_match_build', all(sha(app / 'Art' / p) == build['resource_sha256'].get('Art/' + p) for p in set(paths)))
            indices = [r['presentation']['frameIndex'] for r in samples]
            check(state + '_frame_paths_match_actual_texture_index', all(0 <= i < len(paths) and r['presentation']['framePath'] == paths[i] for i, r in zip(indices, samples)))
            check(state + '_all_frames_observed', set(indices) == set(range(len(paths))))
            wraps = [{'before': a['sequence'], 'after': b['sequence']} for a, b in zip(samples, samples[1:]) if a['presentation']['frameIndex'] == len(paths) - 1 and b['presentation']['frameIndex'] == 0]
            skips = [(a, b) for a, b in zip(indices, indices[1:]) if b not in (a, (a + 1) % len(paths))]
            check(state + '_at_least_two_observed_wraps', len(wraps) >= 2)
            check(state + '_no_skipped_texture_frames', not skips, skips)
            result.update(kind='sprite_frame_sequence', frameCount=len(paths), fps=fps, wraps=wraps, skippedTransitions=skips)
        else:
            rig = [r['presentation']['partRig'] for r in samples]
            check(state + '_rig_action_running', all(r.get('actionRunning') for r in rig))
            check(state + '_rig_not_mesh_candidate', all(not r.get('walkMeshActive') for r in rig))
            wraps = [{'before': a['sequence'], 'after': b['sequence']} for a, b in zip(samples, samples[1:]) if a['presentation']['partRig'].get('normalizedProgress', 0) > .7 and b['presentation']['partRig'].get('normalizedProgress', 1) < .3]
            result.update(kind='rig_transform_phase', wraps=wraps, spriteFrameIdentityClaimed=False)
            if state == 'idle':
                check(state + '_at_least_two_rig_transform_wraps', len(wraps) >= 2)
            else:
                check('walk_leg_overlay_active', all(r.get('walkLegOverlayActive') for r in rig))
                indices = [r.get('walkLegOverlayFrameIndex') for r in rig]
                paths = entry['clips']['walk']['frame_paths']
                count = len(paths)
                check('walk_overlay_resources_match_build', all(sha(app / 'Art' / p) == build['resource_sha256'].get('Art/' + p) for p in paths))
                check('walk_overlay_frame_paths', all(type(i) is int and 0 <= i < count and r['walkLegOverlayFramePath'] == paths[i] for i, r in zip(indices, rig)))
                check('walk_overlay_metadata_matches_bundle', mode['framePaths'] == paths and mode['frameCount'] == count and mode['expectedFPS'] == entry['clips']['walk']['fps'])
                # The trace's actual observed two-frame overlay remains distinct
                # from transform phase; do not infer mesh gait phase from it.
                overlay_wraps = [{'before': a['sequence'], 'after': b['sequence']} for a, b in zip(samples, samples[1:]) if a['presentation']['partRig'].get('walkLegOverlayFrameIndex', -1) > 0 and b['presentation']['partRig'].get('walkLegOverlayFrameIndex') == 0]
                check('walk_overlay_all_frames', set(indices) == set(range(count)))
                check('walk_overlay_at_least_two_wraps', len(overlay_wraps) >= 2)
                result.update(overlayFrameIndices=sorted(set(indices)), overlayWraps=overlay_wraps, gaitMeshPhaseClaimed=False)
        results.append(result)
    return {'status': 'PASS_OBSERVED_LOOP_CONTRACT' if all(c['passed'] for c in checks) else 'FAIL_OBSERVED_LOOP_CONTRACT',
            'actorID': trace['actorID'], 'saveKey': trace['saveKey'], 'checks': checks, 'states': results,
            'inputSHA256': {p.name: sha(p) for p in [base / 'CAPTURE.json', base / 'trace.json', build_path]},
            'validatorSHA256': sha(Path(__file__)), 'artComplete': False, 'naturalnessAccepted': False,
            'buildReceiptStatus': build_info['status'], 'resourcePreview': build_info['resourcePreview'],
            'baseBuildReceiptSHA256': build_info.get('baseReceiptSHA256'),
            'scope': 'Actual per-render getters and two loop wraps; encoded pixels and visual continuity require separate review'}

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('capture', type=Path)
    ap.add_argument('--output', required=True, type=Path)
    a = ap.parse_args()
    if a.output.exists():
        raise RuntimeError('Refuse to replace existing verification')
    report = validate(a.capture.resolve())
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'actorID': report['actorID'], 'status': report['status'], 'failed': [c['name'] for c in report['checks'] if not c['passed']]}))
    if report['status'].startswith('FAIL'):
        raise SystemExit(1)

if __name__ == '__main__':
    main()

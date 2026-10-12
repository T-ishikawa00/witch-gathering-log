#!/usr/bin/env python3
"""Correlate loop seam observations with visible per-render video markers.

All crops/contact sheets are derived QA evidence, not edited game artwork.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
from PIL import Image, ImageDraw

def refuse(message):
    raise SystemExit('REFUSED: ' + message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('capture', type=Path)
    ap.add_argument('--ocr', type=Path, required=True)
    ap.add_argument('--host-verification', type=Path,
                    help='Current verifier receipt; defaults to CAPTURE/HOST_VERIFICATION_R001.json')
    ap.add_argument('--output', type=Path, required=True)
    a = ap.parse_args()
    base, out = a.capture.resolve(), a.output.resolve()
    capture = json.loads((base / 'CAPTURE.json').read_text())
    trace = json.loads((base / 'trace.json').read_text())
    build_path = base.parent / 'BUILD_RECEIPT.json'
    run_path = base.parent / 'RUN.json'
    host_path = (a.host_verification.resolve() if a.host_verification else base / 'HOST_VERIFICATION_R001.json')
    if not build_path.is_file() or not run_path.is_file() or not host_path.is_file():
        raise RuntimeError('Missing build, parent run, or host verification receipt')
    build = json.loads(build_path.read_text())
    run = json.loads(run_path.read_text())
    host = json.loads(host_path.read_text())
    capture_sha = sha(base / 'CAPTURE.json')
    trace_sha = sha(base / 'trace.json')
    build_sha = sha(build_path)
    matching_cases = [c for c in run.get('cases', []) if c.get('actorID') == capture.get('actorID')]
    if capture.get('status') != 'CAPTURED_REQUIRES_HOST_AND_VISUAL_VALIDATION':
        refuse('Capture is not complete')
    if len(matching_cases) != 1 or matching_cases[0].get('captureSHA256') != capture_sha:
        refuse('Capture is not bound to exactly one parent RUN case')
    if capture.get('app') != run.get('app') or capture.get('device') != run.get('device') or capture.get('executableSHA256') != run.get('executableSHA256'):
        refuse('Capture app/device/executable identity differs from parent RUN')
    if run.get('buildReceiptSHA256') not in (None, capture.get('buildReceiptSHA256')):
        refuse('Parent RUN build receipt pin differs from capture')
    if capture.get('buildReceiptSHA256') != build_sha or capture.get('executableSHA256') != build.get('executable_sha256'):
        refuse('Capture build pin does not match BUILD_RECEIPT')
    is_preview = build.get('status') == 'QA_RESOURCE_PREVIEW_FROM_VERIFIED_BUILD'
    legacy_normal = not is_preview and 'buildReceiptStatus' not in capture and 'resourcePreview' not in capture
    if not (legacy_normal or (capture.get('buildReceiptStatus') == build.get('status') and capture.get('resourcePreview') is is_preview)):
        refuse('Capture build mode does not match its receipt')
    if is_preview and capture.get('baseBuildReceiptSHA256') != build.get('baseBuildReceiptSHA256'):
        # The copied preview receipt pins the base receipt by its actual content.
        base_receipt_path = Path(build.get('baseBuildReceiptPath', '')).resolve()
        if not base_receipt_path.is_file() or capture.get('baseBuildReceiptSHA256') != sha(base_receipt_path):
            refuse('Capture does not match preview base-build receipt pin')
    if is_preview and (run.get('resourcePreview') is not True or
            run.get('buildReceiptStatus') != build.get('status') or
            run.get('baseBuildReceiptSHA256') != capture.get('baseBuildReceiptSHA256')):
        refuse('Parent RUN preview metadata differs from capture')
    if host.get('status') != 'PASS_OBSERVED_LOOP_CONTRACT' or host.get('actorID') != capture.get('actorID') or host.get('saveKey') != capture.get('saveKey'):
        refuse('Host verification is missing, failed, or belongs to a different capture')
    host_checks = host.get('checks')
    if not isinstance(host_checks, list) or not host_checks or any(c.get('passed') is not True for c in host_checks if isinstance(c, dict)) or any(not isinstance(c, dict) for c in host_checks):
        refuse('Host verification does not contain an all-passing check list')
    if host.get('inputSHA256') != {'CAPTURE.json': capture_sha, 'trace.json': trace_sha, 'BUILD_RECEIPT.json': build_sha}:
        refuse('Host verification input pins do not match current capture inputs')
    verifier_path = Path(__file__).with_name('verify_loop_boundary.py').resolve()
    if host.get('validatorSHA256') != sha(verifier_path):
        refuse('Host verification was produced by a different verifier revision')
    capture_files = capture.get('filesSHA256', {})
    if not isinstance(capture_files, dict) or any(not (base / name).is_file() or sha(base / name) != expected for name, expected in capture_files.items()):
        refuse('Capture raw-file hashes do not match')
    if out.exists():
        refuse('Refuse to replace existing video-alignment output')
    rows = trace['rows']
    if trace_sha != capture_files.get('trace.json'):
        refuse('Trace changed since capture')
    if sha(base / 'loops.mp4') != capture_files.get('loops.mp4'):
        refuse('Video changed since capture')
    out.mkdir(parents=True, exist_ok=False)
    start = datetime.datetime.fromisoformat(trace['startedAt'].replace('Z', '+00:00')).timestamp()
    seams = []
    for previous, row in zip(rows, rows[1:]):
        if row['activeMode'] != previous['activeMode']:
            continue
        left, right = previous['presentation'], row['presentation']
        if not right.get('isPartRig'):
            wrap = left.get('frameIndex', -1) > 0 and right.get('frameIndex') == 0
        else:
            lp, rp = left.get('partRig', {}), right.get('partRig', {})
            if lp.get('walkLegOverlayActive') and rp.get('walkLegOverlayActive'):
                wrap = lp.get('walkLegOverlayFrameIndex', -1) > 0 and rp.get('walkLegOverlayFrameIndex') == 0
            else:
                wrap = lp.get('normalizedProgress', 0) > .7 and rp.get('normalizedProgress', 1) < .3
        if wrap:
            seams.append({'state': row['activeMode'], 'beforeSequence': previous['sequence'],
                          'afterSequence': row['sequence'], 'elapsedSeconds': row['elapsedSeconds'],
                          'isPartRig': right.get('isPartRig', False)})
    # Extract all observed seams, so a single skipped encoded video frame cannot
    # be silently replaced by a different timing claim.
    commands, images, contexts = [], [], {}
    for i, seam in enumerate(seams):
        target = start - capture['recorderStartedUnix'] + seam['elapsedSeconds']
        begin = max(0, target - .65)
        frames, crops = out / ('seam_%02d' % i), out / ('markers_%02d' % i)
        frames.mkdir(); crops.mkdir()
        cmd = ['ffmpeg', '-v', 'error', '-ss', str(begin), '-i', str(base / 'loops.mp4'),
               '-t', '1.3', '-vf', 'fps=60', '-q:v', '2', str(frames / 'frame_%04d.jpg')]
        subprocess.run(cmd, check=True)
        commands.append(cmd)
        r = next(r for r in rows if r['sequence'] == seam['afterSequence'])
        scale, origin = r['viewContentScale'], r['viewWindowOrigin']
        left, top = int((origin[0] + 2) * scale), int((origin[1] + 80) * scale)
        box = (left, top, left + int(175 * scale), top + int(42 * scale))
        for f in sorted(frames.glob('*.jpg')):
            crop = crops / (f.stem + '.png')
            with Image.open(f) as im:
                im.crop(box).save(crop)
            images.append(crop)
            contexts[str(crop)] = {'videoFrame': str(f.relative_to(out)), 'seamIndex': i,
                                   'encodedFrameAt60FPS': int(f.stem.split('_')[-1])}
    proc = subprocess.run([str(a.ocr.resolve()), *map(str, images)], capture_output=True, text=True, check=True)
    (out / 'OCR_RAW.json').write_text(proc.stdout)
    by_sequence = {r['sequence']: r for r in rows}
    matches = []
    for item in json.loads(proc.stdout):
        m = re.fullmatch(r'LOOP\s+(\d{4})', item.get('text', '').strip())
        if not m:
            continue
        n = int(m.group(1)); row = by_sequence.get(n)
        if not row or row['phase'] != 'didFinishUpdate' or row['videoMarker'] != 'LOOP %04d' % n:
            continue
        matches.append({**contexts[item['path']], 'sequence': n, 'state': row['activeMode'],
                        'frameIndex': row['presentation'].get('frameIndex'),
                        'elapsedSeconds': row['elapsedSeconds']})
    pairs = []
    for i, seam in enumerate(seams):
        own = [m for m in matches if m['seamIndex'] == i]
        candidates = [(left, right) for left in own for right in own
                      if left['sequence'] == seam['beforeSequence'] and right['sequence'] == seam['afterSequence']
                      and 1 <= right['encodedFrameAt60FPS'] - left['encodedFrameAt60FPS'] <= 3]
        chosen = min(candidates, key=lambda p: p[1]['encodedFrameAt60FPS'] - p[0]['encodedFrameAt60FPS']) if candidates else None
        left, right = chosen if chosen else (None, None)
        pairs.append({**seam, 'exactAdjacentTraceRowsMatched': bool(chosen),
                      'videoFrameGapAt60FPS': None if not chosen else right['encodedFrameAt60FPS'] - left['encodedFrameAt60FPS'],
                      'before': left, 'after': right})
    accepted = [p for p in pairs if p['exactAdjacentTraceRowsMatched']]
    if accepted:
        sheet = Image.new('RGB', (760, 500 * len(accepted)), '#17212a')
        draw = ImageDraw.Draw(sheet)
        for i, pair in enumerate(accepted):
            for x, edge in [(0, 'before'), (380, 'after')]:
                match = pair[edge]
                with Image.open(out / match['videoFrame']) as im:
                    im.thumbnail((375, 465)); sheet.paste(im, (x, 500 * i + 30))
                draw.text((x + 4, 500 * i + 8), '%s %s LOOP %04d' % (pair['state'], edge, match['sequence']), fill='white')
        sheet.save(out / 'SEAMS.jpg', quality=95)
    report = {'status': 'EXACT_ADJACENT_MARKER_PAIRS_FOUND' if accepted else 'EXACT_PAIRS_NOT_PROVEN',
              'actorID': capture['actorID'], 'saveKey': capture['saveKey'],
              'captureSHA256': capture_sha, 'traceSHA256': trace_sha,
              'buildReceiptSHA256': build_sha, 'hostVerificationPath': str(host_path),
              'hostVerificationSHA256': sha(host_path), 'hostVerifierSourceSHA256': sha(verifier_path),
              'resourcePreview': capture.get('resourcePreview', False),
              'baseBuildReceiptSHA256': capture.get('baseBuildReceiptSHA256'),
              'videoSHA256': sha(base / 'loops.mp4'), 'ocrExecutableSHA256': sha(a.ocr.resolve()),
              'extractCommands': commands, 'matches': matches, 'seamPairs': pairs,
              'exactPairCount': len(accepted),
              'exactPairStates': sorted({p['state'] for p in accepted}),
              'scope': 'Adjacent trace row labels OCR-matched in video time order within 3 extracted 60fps frames; inspect OCR and actor pixels separately',
              'naturalnessAccepted': False, 'artComplete': False}
    (out / 'ALIGNMENT.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['actorID', 'status', 'exactPairCount', 'exactPairStates']}))

if __name__ == '__main__':
    main()

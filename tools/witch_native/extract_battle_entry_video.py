#!/usr/bin/env python3
"""Read-only video-to-trace correlation through visible ENTRY frame numbers.

Derived JPEG/crops are QA evidence, never replacement game artwork.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
from PIL import Image, ImageDraw

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('capture', type=Path)
    ap.add_argument('--ocr', type=Path, required=True)
    a = ap.parse_args(); base = a.capture.resolve()
    out = base / 'video_alignment'; out.mkdir(exist_ok=False)
    frames = out / 'frames'; frames.mkdir()
    crops = out / 'markers'; crops.mkdir()
    capture = json.loads((base / 'CAPTURE.json').read_text())
    trace = json.loads((base / 'entry_trace.json').read_text())
    start = datetime.datetime.fromisoformat(trace['startedAt'].replace('Z', '+00:00')).timestamp()
    extract = max(0, start - capture['recorderStartedUnix'] - .5)
    command = ['ffmpeg', '-v', 'error', '-ss', str(extract), '-i', str(base / 'battle.mp4'),
               '-t', '3', '-vf', 'fps=30', '-q:v', '2', str(frames / 'frame_%04d.jpg')]
    subprocess.run(command, check=True)
    row = trace['rows'][1]; scale = row['viewContentScale']; origin = row['viewWindowOrigin']
    # Label's top-left: scene(8, height-90) -> view(8,90). Include font ascenders.
    left, top = int((origin[0] + 2) * scale), int((origin[1] + 80) * scale)
    marker_box = (left, top, left + int(165 * scale), top + int(42 * scale))
    for f in sorted(frames.glob('*.jpg')):
        with Image.open(f) as im: im.crop(marker_box).save(crops / (f.stem + '.png'))
    proc = subprocess.run([str(a.ocr.resolve()), *map(str, sorted(crops.glob('*.png')))],
                          capture_output=True, text=True, check=True)
    (out / 'OCR_RAW.json').write_text(proc.stdout)
    matches = []
    for item in json.loads(proc.stdout):
        match = re.fullmatch(r'ENTRY\s+(\d{3})', item.get('text', '').strip())
        if not match: continue
        index = int(match.group(1))
        if index >= len(trace['rows']): continue
        r = trace['rows'][index]
        if r['phase'] != 'didFinishUpdate' or r['videoMarker'] != 'ENTRY %03d' % index: continue
        name = Path(item['path']).stem
        matches.append({'videoFrame': name + '.jpg', 'sample': index,
                        'elapsedSeconds': r['elapsedSeconds'], 'sceneFrame': r['sceneFrame'],
                        'state': r['actors']['ACT_B_R04_B']['presentation']['state']})
    selected = []
    for target in [.08, .2, .35, .5, .62, .85]:
        if matches:
            picked = min(matches, key=lambda r: abs(r['elapsedSeconds'] - target))
            if picked not in selected: selected.append(picked)
    # A montage preserves the visible paws and the independently OCR-matched marker.
    contact = Image.new('RGB', (1005, 340 * len(selected)), '#17212a')
    d = ImageDraw.Draw(contact)
    for i, m in enumerate(selected):
        with Image.open(frames / m['videoFrame']) as im:
            crop = im.crop((650, 970, 1320, 1530)).resize((670, 560))
            crop.thumbnail((600, 300)); contact.paste(crop, (350, i * 340 + 30))
        marker = Image.open(crops / (Path(m['videoFrame']).stem + '.png')).convert('RGB')
        marker.thumbnail((330, 120)); contact.paste(marker, (10, i * 340 + 55))
        d.text((12, i * 340 + 15), 'trace %03d | %.4f s | %s' % (m['sample'], m['elapsedSeconds'], m['state']), fill='white')
    if selected: contact.save(out / 'CONTACT.jpg', quality=95)
    report = {'status': 'VISIBLE_MARKER_MATCHES_FOUND' if matches else 'NO_MARKER_MATCHES',
              'exactMeaning': 'OCR frame number links encoded video image to scene getter sample; manually inspect selected marker crops',
              'videoSHA256': hashlib.sha256((base / 'battle.mp4').read_bytes()).hexdigest(),
              'traceSHA256': hashlib.sha256((base / 'entry_trace.json').read_bytes()).hexdigest(),
              'extractCommand': command, 'markerCrop': marker_box, 'matches': matches, 'selected': selected,
              'visualGroundContactAccepted': False, 'artComplete': False}
    (out / 'ALIGNMENT.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'status': report['status'], 'matches': len(matches), 'selected': len(selected)}))

if __name__ == '__main__':
    main()

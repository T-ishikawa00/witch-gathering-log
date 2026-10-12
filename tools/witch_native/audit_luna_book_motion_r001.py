#!/usr/bin/env python3
"""Read-only alpha/canvas and atlas-cell audit for LUNA motion candidates."""
from pathlib import Path
from PIL import Image
import hashlib, json
import numpy as np
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
mp = ROOT / 'native/GeneratedArt/luna_book_motion_candidates_r001/LUNA_BOOK_MOTION_CANDIDATES_R001.json'
m = json.loads(mp.read_text())
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
results, issues = [], []
for atlas in m['sourceAtlases']:
    path = ROOT / atlas['atlasPath']
    im = Image.open(path).convert('RGBA')
    alpha = np.asarray(im.getchannel('A'))
    labels, _ = ndimage.label(alpha >= 16)
    comps = []
    for i, sl in enumerate(ndimage.find_objects(labels), 1):
        if sl is not None and int((labels[sl] == i).sum()) > 100:
            comps.append((i, (sl[1].start, sl[0].start, sl[1].stop, sl[0].stop)))
    comps.sort(key=lambda x: (x[1][1], x[1][0]))
    if len(comps) != 9:
        issues.append(f'{atlas["atlasPath"]}: expected 9 major components, got {len(comps)}')
        continue
    centers = [((b[0] + b[2]) / 2, (b[1] + b[3]) / 2) for _, b in comps]
    xs, ys = sorted(x for x, _ in centers), sorted(y for _, y in centers)
    xgroups = [sum(xs[i:i+3]) / 3 for i in (0, 3, 6)]
    ygroups = [sum(ys[i*3:(i+1)*3]) / 3 for i in range(3)]
    xb = [0, (xgroups[0] + xgroups[1]) / 2, (xgroups[1] + xgroups[2]) / 2, im.width]
    yb = [0, (ygroups[0] + ygroups[1]) / 2, (ygroups[1] + ygroups[2]) / 2, im.height]
    for cell, (label, bbox) in enumerate(comps):
        if bbox[0] == 0 or bbox[1] == 0 or bbox[2] == im.width or bbox[3] == im.height:
            issues.append(f'{atlas["atlasPath"]} component {cell} touches atlas edge {bbox}')
        frame = next(f for f in m['frames'] if f['sourceAtlasPath'] == atlas['atlasPath'] and f['sourceComponentIndex'] == cell)
        crop = frame['cropBoxPx']
        roi = labels[crop[1]:crop[3], crop[0]:crop[2]]
        detached = int(np.count_nonzero((roi > 0) & (roi != label)))
        row, col = divmod(cell, 3)
        crosses = crop[0] < xb[col] or crop[2] > xb[col+1] or crop[1] < yb[row] or crop[3] > yb[row+1]
        major_other = sum(int(np.count_nonzero(roi == other)) for other, other_box in comps
                          if other != label and (other_box[2]-other_box[0]) * (other_box[3]-other_box[1]) > 100)
        if major_other:
            issues.append(f'{frame["assetID"]}: crop includes {major_other} pixels from another major silhouette')
        out = Image.open(ROOT / frame['packedPath']).convert('RGBA')
        ob = out.getchannel('A').point(lambda x: 255 if x >= 16 else 0).getbbox()
        if out.size != (256, 256) or ob is None:
            issues.append(f'{frame["assetID"]}: invalid canvas/alpha')
        if ob and ob[3] != 244:
            issues.append(f'{frame["assetID"]}: foot baseline {ob[3]} != 244')
        results.append({'assetID': frame['assetID'], 'state': frame['state'], 'frameIndex': frame['frameIndex'],
                        'sourceComponentIndex': cell, 'sourceBBoxAlpha16Px': list(bbox),
                        'inferredCellBoundsPx': [round(xb[col]), round(yb[row]), round(xb[col+1]), round(yb[row+1])],
                        'cropBoxPx': crop, 'detachedAlphaAccentPixelsWithinCellCrop': detached,
                        'crossesInferredCellGutter': crosses, 'majorNeighborPixelsInCrop': major_other,
                        'packedCanvasPx': list(out.size), 'packedAlpha16BBoxPx': list(ob) if ob else None,
                        'packedSHA256': sha(ROOT / frame['packedPath'])})
state_counts = {}
for f in m['frames']:
    state_counts[f['state']] = state_counts.get(f['state'], 0) + 1
report = {'schema': 'luna_book_motion_atlas_qa_r002', 'status': 'PASS' if not issues else 'FAIL',
          'manifest': str(mp.relative_to(ROOT)), 'manifestSHA256': sha(mp), 'atlasAudits': m['sourceAtlases'],
          'frameCount': len(results), 'frameCountsByState': state_counts,
          'detachedAlphaAccentPixelsWithinFrameCrops': sum(x['detachedAlphaAccentPixelsWithinCellCrop'] for x in results),
          'majorNeighborPixelsInCrops': sum(x['majorNeighborPixelsInCrop'] for x in results),
          'crossGutterFrames': sum(x['crossesInferredCellGutter'] for x in results), 'cropPaddingPx': 0,
          'frames': results, 'issues': issues,
          'scope': 'Mechanical alpha/crop/canvas/baseline and inferred-cell boundary QA only; detached within-cell accents are reported separately. No naturalness, runtime rendering, or Human acceptance.'}
out = ROOT / 'docs/production/current/core/LUNA_BOOK_MOTION_ATLAS_QA_R002.json'
tmp = out.with_suffix('.json.tmp')
tmp.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n'); tmp.replace(out)
md = ROOT / 'docs/production/current/core/LUNA_BOOK_MOTION_ATLAS_QA_R002.md'
lines = ['# LUNA motion candidate atlas QA R002', '',
         f'**{report["status"]}** — {report["frameCount"]} frames; detached alpha accents inside inferred cell crops: {report["detachedAlphaAccentPixelsWithinFrameCrops"]}; pixels from another major silhouette: {report["majorNeighborPixelsInCrops"]}; crops crossing inferred cell gutters: {report["crossGutterFrames"]}.',
         '', 'R001 treated every disconnected alpha pixel as neighboring-frame contamination. This revision separates tiny detached accents inside the same inferred 3×3 cell from actual gutter crossing and pixels belonging to another major silhouette. It is still mechanical QA only; natural motion, grip, SpriteKit rendering, and Human art acceptance remain unverified. Per-frame source bounds and output hashes are in the JSON companion.']
if issues:
    lines += ['', 'Issues:'] + ['- ' + x for x in issues]
tmp = md.with_suffix('.md.tmp'); tmp.write_text('\n'.join(lines) + '\n'); tmp.replace(md)
print(json.dumps({'status': report['status'], 'frameCount': len(results),
                  'detachedAlphaAccentPixelsWithinFrameCrops': report['detachedAlphaAccentPixelsWithinFrameCrops'],
                  'majorNeighborPixelsInCrops': report['majorNeighborPixelsInCrops'],
                  'crossGutterFrames': report['crossGutterFrames'], 'issues': issues, 'report': str(md)}, ensure_ascii=False, indent=2))

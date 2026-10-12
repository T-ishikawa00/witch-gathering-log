#!/usr/bin/env python3
"""Verify AIRA R010 source identity and candidate landmark integrity."""
from __future__ import annotations
import hashlib, json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OVERLAY = ROOT / 'native/Art/runtime_overlay_aira_landmarks_r010.json'
REJECTED_R009 = next(ROOT.glob('native/Art/*aira_palm_cuff_r009.json'))
doc = json.loads(OVERLAY.read_text())
assert doc['status'] == 'UNAPPROVED_CANDIDATE_ONLY'
assert doc['mergePriority'] == 100
assert set(doc['entries']) == {'AIRA'}
rows = doc['entries']['AIRA']['semanticFrameLandmarksCandidate']['rows']
assert len(rows) == 27
seen = set()
for row in rows:
    src = ROOT / row['source_path']
    raw = src.read_bytes()
    im = Image.open(src).convert('RGBA')
    key = (row['bodyAssetID'], row['frameIndex'])
    assert key not in seen, key
    seen.add(key)
    assert list(im.size) == row['canvas_px'], (src, im.size, row['canvas_px'])
    assert hashlib.sha256(raw).hexdigest() == row['sourceSHA256'], src
    lm = row['landmarks_px_top_left']
    x, y = lm['visibleRightAnkle']
    assert lm['screenRightBootCuff'] == [x, y]
    assert 0 <= x < im.width and 0 <= y < im.height
    assert im.getpixel((x, y))[3] >= 16, (src, x, y)
    assert lm['workingPalm'] is None
    assert row['landmarkVisibility']['workingPalm'] == 'occluded'
    if src.stem in {'AIRA__attack_04', 'AIRA__attack_05'}:
        assert lm['chest'] is None and row['landmarkVisibility']['chest'] == 'occluded'
assert len(seen) == 27
r9 = json.loads(REJECTED_R009.read_text())
assert r9['status'].startswith('REJECTED_SUPERSEDED')
print(json.dumps({
    'status': 'PASS_SOURCE_CANVAS_HASH_POINT_ALPHA_STRUCTURE_ONLY',
    'overlay': str(OVERLAY.relative_to(ROOT)),
    'overlaySHA256': hashlib.sha256(OVERLAY.read_bytes()).hexdigest(),
    'rows': len(rows),
    'mergePriority': doc['mergePriority'],
    'chestOccluded': ['attack_04', 'attack_05'],
    'visualFit': 'PENDING_PARENT_HELD_FRAME_REVIEW',
}, ensure_ascii=False, indent=2))

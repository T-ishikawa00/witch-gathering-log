#!/usr/bin/env python3
"""Integrity validator for off-glob AIRA R011 candidate; does not validate anatomy."""
from __future__ import annotations
import hashlib, json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CANDIDATE = ROOT / 'native/Art/GeneratedCandidates/EquipmentDetails/aira_equipment_landmarks_r011_candidate.json'
doc = json.loads(CANDIDATE.read_text())
assert doc['status'] == 'UNAPPROVED_CANDIDATE_ONLY'
assert doc['humanApproval'] is False
assert doc['mergePriority'] == 100
assert set(doc['entries']) == {'AIRA'}
rows = doc['entries']['AIRA']['semanticFrameLandmarksCandidate']['rows']
assert len(rows) == 27
seen = set(); alpha_checked = 0; hidden = []
for row in rows:
    source = ROOT / row['source_path']
    raw = source.read_bytes()
    image = Image.open(source).convert('RGBA')
    key = (row['bodyAssetID'], row['frameIndex'])
    assert key not in seen, key
    seen.add(key)
    assert list(image.size) == row['canvas_px'], (source, image.size, row['canvas_px'])
    assert hashlib.sha256(raw).hexdigest() == row['sourceSHA256'], source
    lm = row['landmarks_px_top_left']
    cuff = lm['screenRightBootCuff']
    ankle = lm['visibleRightAnkle']
    assert cuff == ankle, (source, cuff, ankle)
    if cuff is None:
        assert row['landmarkVisibility']['screenRightBootCuff'] in {'occluded', 'unknown'}
        assert row['landmarkVisibility']['visibleRightAnkle'] in {'occluded', 'unknown'}
        hidden.append(source.stem)
    else:
        x, y = cuff
        assert 0 <= x < image.width and 0 <= y < image.height, (source, cuff)
        assert image.getpixel((x, y))[3] >= 16, (source, cuff)
        alpha_checked += 1
    assert lm['workingPalm'] is None
    assert row['landmarkVisibility']['workingPalm'] == 'occluded'
    if source.stem in {'AIRA__attack_04', 'AIRA__attack_05'}:
        assert lm['chest'] is None and row['landmarkVisibility']['chest'] == 'occluded'
assert len(seen) == 27
# Publication is a candidate overlay only; require byte-identical provenance.
overlay = ROOT / 'native/Art/runtime_overlay_aira_landmarks_r011.json'
assert overlay.exists() and overlay.read_bytes() == CANDIDATE.read_bytes()
print(json.dumps({
    'status': 'PASS_SOURCE_HASH_CANVAS_ROW_KEYS_AND_NULL_VISIBILITY_ONLY',
    'candidate': str(CANDIDATE.relative_to(ROOT)),
    'candidate_sha256': hashlib.sha256(CANDIDATE.read_bytes()).hexdigest(),
    'rows': len(rows), 'point_alpha_integrity_checks': alpha_checked,
    'explicitly_hidden_cuff_rows': hidden,
    'runtime_overlay': str(overlay.relative_to(ROOT)),
    'runtime_overlay_sha256': hashlib.sha256(overlay.read_bytes()).hexdigest(),
    'runtime_publish': 'UNAPPROVED_CANDIDATE_OVERLAY_ONLY_NO_BUILD',
    'anatomical_fit': 'PENDING_INDEPENDENT_VISUAL_REVIEW',
    'note': 'Hash/canvas/alpha/coordinate checks do not establish that a non-null point is on the gold boot cuff.'
}, ensure_ascii=False, indent=2))

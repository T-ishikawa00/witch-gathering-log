#!/usr/bin/env python3
"""Verify source identity and structure of AIRA R009 landmark candidate rows."""
from __future__ import annotations
import glob, hashlib, json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
source=Path(glob.glob(str(ROOT/'native/Art/*equipment_landmarks_aira_r008.json'))[0])
semantic=json.loads(source.read_text())['entries']['AIRA']['semanticFrameLandmarksCandidate']['rows']
overlay_paths=glob.glob(str(ROOT/'native/Art/*aira_palm_cuff_r009.json'))
assert len(overlay_paths)==1, overlay_paths
overlay=Path(overlay_paths[0]); doc=json.loads(overlay.read_text())
rows=doc['entries']['AIRA']['semanticFrameLandmarksCandidate']['rows']
assert len(rows)==len(semantic)==27
source_by_key={(r['bodyAssetID'],r['frameIndex']):r for r in semantic}
seen=set()
for row in rows:
 key=(row['bodyAssetID'],row['frameIndex']); assert key not in seen; seen.add(key)
 src=source_by_key[key]
 assert row['actorID']=='AIRA' and row['canvas_px']==src['canvas_px']
 assert row['sourceSHA256']==src['sourceSHA256']
 assert row['source_path']==src['source_path']
 lm=row['landmarks_px_top_left']; assert lm['workingPalm'] is None
 assert row['landmarkVisibility']['workingPalm']=='occluded'
 assert row['landmarkVisibility']['screenRightBootCuff']=='visible'
 assert lm['visibleRightAnkle']==lm['screenRightBootCuff']
 x,y=lm['screenRightBootCuff']; assert 0<=x<row['canvas_px'][0] and 0<=y<row['canvas_px'][1]
 assert row['measurementStatus']=='INDIVIDUAL_SOURCE_GRID_REMEASURED_CANDIDATE_R009'
print(json.dumps({'status':'PASS_27_SOURCE_BOUND_CANDIDATE_ROWS','path':str(overlay.relative_to(ROOT)),'sha256':hashlib.sha256(overlay.read_bytes()).hexdigest(),'rows':len(rows),'workingPalm':{'occluded':sum(r['landmarkVisibility']['workingPalm']=='occluded' for r in rows),'unknown':sum(r['landmarkVisibility']['workingPalm']=='unknown' for r in rows)},'bootCuffVisible':sum(r['landmarkVisibility']['screenRightBootCuff']=='visible' for r in rows),'sourceRowsMatched':len(seen),'visualFit':'NOT_TESTED_BY_THIS_CHECK'},indent=2))

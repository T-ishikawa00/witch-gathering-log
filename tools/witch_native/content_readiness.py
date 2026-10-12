#!/usr/bin/env python3
"""Re-audit CONTENT_READINESS_R002 asset paths against a frozen app bundle.

Read-only. This checks path presence and SHA-256 against the build receipt; it does
not certify visual quality, runtime use, approval, or gameplay integration.
"""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = ROOT / 'docs/production/current/CONTENT_READINESS_R002.json'
DEFAULT_RECEIPT = ROOT / 'docs/production/current/native/BUILD_RECEIPT_R029.json'
DEFAULT_OUT = ROOT / 'docs/production/current/CONTENT_READINESS_R003_R029.json'

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def iter_assets(value, prefix=''):
    if isinstance(value, dict):
        if isinstance(value.get('path'), str):
            yield (prefix, value)
        for k, v in value.items():
            yield from iter_assets(v, f'{prefix}.{k}' if prefix else k)
    elif isinstance(value, list):
        for i, v in enumerate(value):
            yield from iter_assets(v, f'{prefix}[{i}]')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--source', type=Path, default=DEFAULT_SOURCE)
    ap.add_argument('--receipt', type=Path, default=DEFAULT_RECEIPT)
    ap.add_argument('--out', type=Path, default=DEFAULT_OUT)
    a = ap.parse_args()
    source, receipt = json.loads(a.source.read_text()), json.loads(a.receipt.read_text())
    bundle = Path(receipt['bundle'])
    if not bundle.is_dir(): raise SystemExit(f'bundle missing: {bundle}')
    declared = receipt.get('resource_sha256', {})
    actual_bundle = sha(bundle / 'WitchGathering')
    if actual_bundle != receipt.get('executable_sha256'):
        raise SystemExit('executable SHA mismatch against receipt')
    rows_out, missing_paths, path_count = [], [], 0
    by_hash = {}
    for rel, digest in declared.items(): by_hash.setdefault(digest, []).append(rel)
    png_decode = {}
    try:
        from PIL import Image
        for rel in declared:
            if rel.lower().endswith('.png'):
                try:
                    with Image.open(bundle / rel) as im: im.verify()
                    png_decode[rel] = 'PASS'
                except Exception as exc:
                    png_decode[rel] = f'FAIL:{type(exc).__name__}:{exc}'
    except ImportError:
        png_decode = {rel:'UNKNOWN_PIL_UNAVAILABLE' for rel in declared if rel.lower().endswith('.png')}
    for row in source['rows']:
        checks=[]
        for field, obj in iter_assets(row.get('runtimePaths', {})):
            rel=obj['path']; path_count += 1
            candidates=[rel, rel[4:] if rel.startswith('Art/') else None]
            resolved=next((x for x in candidates if x and (bundle/x).is_file()), rel)
            file=bundle / resolved
            present=file.is_file(); actual=sha(file) if present else None
            receipt_sha=declared.get(resolved)
            source_sha=obj.get('sha256')
            same_source_sha_paths=by_hash.get(source_sha, []) if source_sha else []
            matches=bool(present and actual == receipt_sha and actual == source_sha)
            c={'field':field,'path':rel,'resolvedBundlePath':resolved if present else None,'present':present,'actualSHA256':actual,
               'receiptSHA256':receipt_sha,'sourceSHA256':source_sha,'matchesR029Receipt':matches,
               'sourceSHAExistsAtAnyR029Path':bool(same_source_sha_paths),'sameSHAPaths':same_source_sha_paths,
               'pngDecode':png_decode.get(resolved,'NOT_PNG_OR_UNCHECKED')}
            checks.append(c)
            if not present: missing_paths.append({'stableID':row['stableID'],**c})
        rows_out.append({'category':row['category'],'stableID':row['stableID'],
                         'priorR002Status':row.get('status'),'pathChecks':checks,
                         'allReferencedPathsMatchR029':all(c['matchesR029Receipt'] for c in checks) if checks else None})
    summary={'rowCount':len(rows_out),'pathReferenceCount':path_count,
             'exactPathAndHashMatchCount':sum(1 for row in rows_out for c in row['pathChecks'] if c['matchesR029Receipt']),
             'oldPathAbsentCount':len(missing_paths),'absentPathsWithSameSourceHashElsewhere':sum(1 for c in missing_paths if c['sourceSHAExistsAtAnyR029Path']),
             'absentPathsByStableID':{},'oldPathAbsentExamples':missing_paths[:80],
             'pngResourceCount':sum(1 for p in declared if p.lower().endswith('.png')),
             'pngDecodeFailures':{p:v for p,v in png_decode.items() if v.startswith('FAIL:')},
             'pngDecodeUnknownCount':sum(1 for v in png_decode.values() if v.startswith('UNKNOWN')),
             'scopeNote':'Path/hash integrity only; does not assert visual acceptance, runtime integration, formal adoption, or gameplay completeness.'}
    summary['absentPathsByStableID']={k:v for k,v in __import__('collections').Counter(x['stableID'] for x in missing_paths).items()}
    out={'schema':'content_readiness_r003_r029_delta','auditMode':'READ_ONLY_BUNDLE_PATH_AND_HASH_DELTA',
         'targetBuild':{'label':'R029','bundle':str(bundle),'receipt':str(a.receipt),
                        'executableSHA256':actual_bundle,'receiptStatus':receipt.get('status')},
         'sourceLedger':str(a.source),'summary':summary,'rows':rows_out}
    a.out.parent.mkdir(parents=True,exist_ok=True)
    a.out.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'out':str(a.out),'summary':summary},ensure_ascii=False,indent=2))
if __name__=='__main__': main()

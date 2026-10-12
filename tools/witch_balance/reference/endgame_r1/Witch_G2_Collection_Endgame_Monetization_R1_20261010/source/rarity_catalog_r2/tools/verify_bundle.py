"""Verify delivered bytes; never rewrites source or results."""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parents[1]
def main():
    rows=json.loads((ROOT/'PACKAGE_MANIFEST.json').read_text())['files']
    for r in rows:
        p=(ROOT/r['path']).resolve()
        if not p.is_relative_to(ROOT) or not p.is_file():raise RuntimeError('Missing/unsafe '+r['path'])
        if p.stat().st_size!=r['bytes'] or hashlib.sha256(p.read_bytes()).hexdigest()!=r['sha256']:raise RuntimeError('Changed '+r['path'])
    for r in json.loads((ROOT/'data/SOURCE_MANIFEST.json').read_text()):
        if hashlib.sha256((ROOT/r['path']).read_bytes()).hexdigest()!=r['sha256']:raise RuntimeError('Changed source '+r['path'])
    print('PASS',len(rows),'package files; 26 retained originals. No production acceptance.')
if __name__=='__main__':
    try:main()
    except (OSError,ValueError,RuntimeError) as exc:print('FAIL',exc,file=sys.stderr);sys.exit(1)

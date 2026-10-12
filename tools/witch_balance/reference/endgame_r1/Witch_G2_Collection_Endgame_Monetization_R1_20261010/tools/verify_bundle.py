"""Read-only file integrity verification for this delivered research bundle.

Run from any directory. Does not install dependencies, use the network, run the
research models, or modify project files. This is integrity, not authenticity,
statistical validity, product acceptance, or a security certification.
"""
from __future__ import annotations
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def main() -> int:
    manifest = json.loads((ROOT / 'PACKAGE_MANIFEST.json').read_text(encoding='utf-8'))
    rows = manifest['files']
    names = set()
    for row in rows:
        relative = row['path']
        path = (ROOT / relative).resolve()
        if relative in names or not path.is_relative_to(ROOT):
            raise ValueError('Duplicate/unsafe path: ' + relative)
        names.add(relative)
        if not path.is_file() or path.stat().st_size != row['size_bytes'] or sha(path) != row['sha256']:
            raise ValueError('Integrity mismatch: ' + relative)
    source_rows = json.loads((ROOT / 'data/SOURCE_LOCK.json').read_text(encoding='utf-8'))['files']
    for row in source_rows:
        p = (ROOT / row['path']).resolve()
        if not p.is_relative_to(ROOT) or sha(p) != row['sha256']:
            raise ValueError('Source mismatch: ' + row['path'])
    print(f'PASS: {len(rows)} delivered file hashes and {len(source_rows)} preserved source hashes.')
    print('No gameplay, store purchase, or physical-device checks were performed by this command.')
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, KeyError, ValueError) as exc:
        print('FAIL:', exc, file=sys.stderr)
        sys.exit(1)

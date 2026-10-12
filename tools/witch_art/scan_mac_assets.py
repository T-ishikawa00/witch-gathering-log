#!/usr/bin/env python3
"""Read-only inventory for Witch-related named files and the G2 asset tree."""
from __future__ import annotations

import csv
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEARCH_ROOTS = [Path('/Users/PUBLIC_USER/Downloads'), Path('/Users/PUBLIC_USER/Documents'),
                Path('/Users/PUBLIC_USER/Desktop'), Path('/Users/PUBLIC_USER/Projects')]
TERMS = ('witch', '魔女', '採集帳', 'R001')
G2 = Path('/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2')
CORE = Path('/Users/PUBLIC_USER/Downloads/R4_CORE_INCREMENTAL_r003')
R008 = Path('/Users/PUBLIC_USER/Projects/idle-loot-rpg/assets/g2/production/'
            'codex_refinement_20261010T013601JST_49a31ab7/game/native_r008/'
            'WitchG2Refinement.app/Assets')
OUT = ROOT / 'docs/production/current/art'


def summarize_tree(path: Path) -> dict:
    files = [p for p in path.rglob('*') if p.is_file()]
    return {'path': str(path), 'file_count': len(files),
            'bytes': sum(p.stat().st_size for p in files),
            'extensions': dict(Counter(p.suffix.lower() for p in files)),
            'png_count': sum(p.suffix.lower() == '.png' for p in files)}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    records = []
    roots = {}
    for base in SEARCH_ROOTS:
        found = []
        for path in base.rglob('*'):
            if path.is_file() and any(term.casefold() in path.name.casefold() for term in TERMS):
                try:
                    size = path.stat().st_size
                except OSError:
                    size = 'UNKNOWN'
                found.append({'root': str(base), 'path': str(path), 'basename': path.name,
                              'extension': path.suffix.lower(), 'bytes': size})
        found.sort(key=lambda item: item['path'].casefold())
        roots[str(base)] = {'name_matches': len(found),
            'bytes_known': sum(row['bytes'] for row in found if isinstance(row['bytes'], int))}
        records.extend(found)
    with (OUT / 'mac_related_file_names_r001.csv').open('w', newline='', encoding='utf-8-sig') as f:
        writer = csv.DictWriter(f, fieldnames=['root','path','basename','extension','bytes'])
        writer.writeheader()
        writer.writerows(records)
    result = {'matched_terms': list(TERMS), 'named_file_matches': len(records),
        'searched_roots': roots, 'asset_trees': [summarize_tree(G2), summarize_tree(CORE),
        summarize_tree(R008)],
        'interpretation': 'Name search is an index, not a completeness claim. Full project G2 tree stats are measured separately.'}
    (OUT / 'mac_related_file_names_summary_r001.json').write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

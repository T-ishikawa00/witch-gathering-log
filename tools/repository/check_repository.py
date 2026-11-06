#!/usr/bin/env python3
"""Check current documentation links, selected source hashes and Git save coverage."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[2]


def main():
    errors = []
    snapshot = json.loads((ROOT / 'docs/project/evidence/SOURCE_SNAPSHOT.json').read_text())
    for entry in snapshot['files']:
        path = ROOT / entry['path']
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
            errors.append('Source snapshot mismatch: ' + entry['path'])
    working = json.loads((ROOT / 'native/ResourceManifests/W008_WORKING_SOURCE_SHA256.json').read_text())
    for relative, sha in working.items():
        path = ROOT / 'native' / relative
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            errors.append('W008 working input mismatch: ' + relative)
    documents = [ROOT / 'README.md', *sorted((ROOT / 'docs/project').rglob('*.md'))]
    links = 0
    for document in documents:
        for target in re.findall(r'\]\(([^)]+)\)', document.read_text()):
            target = target.split('#', 1)[0].strip('<>')
            if not target or re.match(r'[A-Za-z]+:', target):
                continue
            path = (document.parent / unquote(target)).resolve()
            links += 1
            if not path.is_relative_to(ROOT) or not path.exists():
                errors.append('Broken local link: ' + str(document.relative_to(ROOT)) + ' -> ' + target)
    candidates = {entry['path'] for entry in snapshot['files']}
    candidates.update(str(path.relative_to(ROOT)) for folder in ['tools/repository', 'native/WitchReproduction.xcodeproj', 'docs/project']
                      for path in (ROOT / folder).rglob('*')
                      if path.is_file() and '__pycache__' not in path.parts)
    for relative in sorted(candidates):
        result = subprocess.run(['git', '-c', 'core.precomposeunicode=false', 'check-ignore', '--no-index', '-q', '--', relative], cwd=ROOT)
        if result.returncode == 0:
            errors.append('Important file is ignored: ' + relative)
        elif result.returncode != 1:
            errors.append('Ignore check failed: ' + relative)
    for relative, ignored in [
        ('native/WitchApp/FutureSource.swift', False),
        ('native/WitchGameCore/Sources/WitchGameCore/credentials.json', True),
        ('docs/project/service-account-example.json', True),
        ('native/WitchGameCore/save.json', True),
        ('native/WitchApp/SigningKey.p8', True),
    ]:
        result = subprocess.run(['git', 'check-ignore', '--no-index', '-q', '--', relative], cwd=ROOT)
        if result.returncode not in (0, 1) or (result.returncode == 0) != ignored:
            errors.append('Save-policy probe mismatch: ' + relative)
    print(json.dumps({'source_snapshot_files': len(snapshot['files']), 'w008_working_inputs': len(working),
                      'current_document_links': links, 'save_coverage_paths': len(candidates), 'errors': errors}, indent=2))
    raise SystemExit(1 if errors else 0)


if __name__ == '__main__':
    main()

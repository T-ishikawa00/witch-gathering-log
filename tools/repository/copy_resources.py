#!/usr/bin/env python3
"""Copy a hash-locked, owner-supplied W008 resource pack into a build product."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def verify(source, manifest):
    source = Path(source).resolve(strict=True)
    expected = json.loads(Path(manifest).read_text())
    if not isinstance(expected, dict) or not expected:
        raise ValueError('Resource manifest must be a nonempty object')
    for relative, sha in expected.items():
        path = Path(relative)
        if path.is_absolute() or '..' in path.parts or not path.parts:
            raise ValueError('Unsafe manifest path')
        target = source / path
        if any(part.is_symlink() for part in (target, *target.parents) if part != source.parent):
            raise ValueError('Resource symlinks are forbidden')
        if not target.is_file() or digest(target) != sha:
            raise ValueError('Missing or changed resource: ' + relative)
    actual = {str(path.relative_to(source)) for path in source.rglob('*') if path.is_file()}
    if actual != set(expected):
        raise ValueError('Resource pack file set differs from manifest')
    return source, expected


def copy_pack(source, manifest, destination):
    source, expected = verify(source, manifest)
    destination = Path(destination).absolute()
    if any(path.is_symlink() for path in (destination, *destination.parents)):
        raise ValueError('Build destination must not contain symlinks')
    destination = destination.resolve()
    if source == destination or source in destination.parents or destination in source.parents:
        raise ValueError('Build destination must be separate from source')
    destination.mkdir(parents=True, exist_ok=True)
    for relative, sha in expected.items():
        target = destination / relative
        if any(part.is_symlink() for part in (target, *target.parents)):
            raise ValueError('Build output contains a symlink')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / relative, target)
        if digest(target) != sha or digest(source / relative) != sha:
            raise ValueError('Resource changed during copy: ' + relative)
    print(json.dumps({'verified_resource_files': len(expected), 'copy_readback': 'PASS'}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--destination')
    args = parser.parse_args()
    if args.destination:
        copy_pack(args.source, args.manifest, args.destination)
    else:
        _, entries = verify(args.source, args.manifest)
        print(json.dumps({'verified_resource_files': len(entries)}))

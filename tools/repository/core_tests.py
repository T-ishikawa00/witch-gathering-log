#!/usr/bin/env python3
"""Run W008 Core tests with private, fresh output roots and pinned QA fixtures."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
from reproduce import FLAGS, ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    output = args.output.absolute()
    if any(path.is_symlink() for path in (output, *output.parents)):
        parser.error('Use a real absolute output directory without symlinks')
    output = output.resolve()
    if output == ROOT or ROOT in output.parents or output in ROOT.parents:
        parser.error('Output must be outside the checkout')
    fixture = ROOT / 'native/WitchGameCore/Tests/WitchGameCoreTests/Fixtures/R179_LEGACY_BASELINE.json'
    if hashlib.sha256(fixture.read_bytes()).hexdigest() != '412568c60ce01030e4ab4fc348269c6014f692f1711326b30639229c3da93363':
        parser.error('R179 fixture hash mismatch')
    output.mkdir(parents=True, exist_ok=False)
    for name in ['tmp', 'r170', 'r179', 'r181', 'r169', 'r342']:
        (output / name).mkdir()
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('WITCH_', 'R129_'))}
    env.update({
        'TMPDIR': str(output / 'tmp'),
        'CLANG_MODULE_CACHE_PATH': str(output / 'ModuleCache'),
        'WITCH_R179_CASE_ID': 'R179-first-RC_EQ_F_01-cost-v1',
        'WITCH_R179_EVIDENCE_ROOT': str(output / 'r179'),
        'WITCH_R179_LEGACY_FIXTURE': str(fixture),
        'WITCH_R181_EVIDENCE_ROOT': str(output / 'r181'),
        'WITCH_R170_CASE_ID': 'R170-development-wardrobe-v1',
        'WITCH_R170_EVIDENCE_ROOT': str(output / 'r170'),
        'WITCH_R169_CASE_ID': 'R169-previous-generation-existing-target-v1',
        'WITCH_R169_EVIDENCE_ROOT': str(output / 'r169'),
        'WITCH_R342_TEST_OUTPUT': str(output / 'r342'),
        'WITCH_CLOCK_PROBE_OUTPUT': str(output / 'clock-boundary.json'),
        'R129_TEST_OUTPUT_DIR': str(output / 'r129'),
    })
    command = ['swift', 'test', '--package-path', str(ROOT / 'native/WitchGameCore'),
               '--scratch-path', str(output / 'SwiftBuild')]
    for flag in FLAGS.split():
        command += ['-Xswiftc', '-D' + flag]
    with (output / 'core-test.log').open('w') as log:
        result = subprocess.run(command, cwd=output, env=env, stdout=log, stderr=subprocess.STDOUT)
    print('Core test exit code:', result.returncode)
    print('Log:', output / 'core-test.log')
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()

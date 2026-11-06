#!/usr/bin/env python3
"""Build the portable W008 source snapshot without editing the owner's projects."""
import argparse
import os
from pathlib import Path
import subprocess
from copy_resources import verify

ROOT = Path(__file__).resolve().parents[2]
FLAGS = 'STANDARD_PLAY_R169 FIRST_CRAFT_AID_R179 EQUIPMENT_LOADOUTS_R342 NATURAL_GEAR_R350 NATURAL_GEAR_REFINEMENT_R352 GEAR_DISMANTLE_REFUND_R353'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resources', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--sdk', choices=['iphonesimulator', 'iphoneos'], default='iphonesimulator')
    args = parser.parse_args()
    resources, _ = verify(args.resources, ROOT / 'native/ResourceManifests/W008_RESOURCE_SHA256.json')
    output = args.output.absolute()
    if any(path.is_symlink() for path in (output, *output.parents)):
        parser.error('Output must not contain symlinks; use a real absolute directory')
    output = output.resolve()
    if output == ROOT or ROOT in output.parents or output in ROOT.parents:
        parser.error('Output must be separate from the checkout')
    output.mkdir(parents=True, exist_ok=False)
    device = 'generic/platform=iOS Simulator' if args.sdk == 'iphonesimulator' else 'generic/platform=iOS'
    action = 'build-for-testing' if args.sdk == 'iphonesimulator' else 'build'
    command = ['xcodebuild', '-project', str(ROOT / 'native/WitchReproduction.xcodeproj'),
               '-scheme', 'WitchGathering', '-configuration', 'Release', '-sdk', args.sdk,
               '-destination', device, '-derivedDataPath', str(output / 'DerivedData'),
               'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=',
               'WITCH_RESOURCE_ROOT=' + str(resources),
               'SWIFT_ACTIVE_COMPILATION_CONDITIONS=' + FLAGS, action]
    with (output / 'build.log').open('w') as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                env={**os.environ, 'CLANG_MODULE_CACHE_PATH': str(output / 'ModuleCache')})
    print('Build exit code:', result.returncode)
    print('Log:', output / 'build.log')
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()

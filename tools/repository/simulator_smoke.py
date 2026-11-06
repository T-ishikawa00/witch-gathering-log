#!/usr/bin/env python3
"""Run bounded UI48 smoke tests on a newly created Simulator; keep existing devices intact."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
from reproduce import ROOT

TESTS = [
    'UI48AcceptanceTests/testFiveEntrancesNestedBackAndClose',
    'UI48AcceptanceTests/testTrackingRecipeDoesNotConsumeAndPersistsAfterColdRelaunch',
    'UI48AcceptanceTests/testAudioSettingSurvivesColdRelaunchInIsolatedApp',
    'UI48GameplayAcceptanceTests/testCraftCancelRapidConfirmationProcessingAndColdResult',
    'UI48GameplayAcceptanceTests/testSavedLoadoutApplyAndDismantleProtectionSurviveRelaunch',
    'UI48ExtendedAcceptanceTests/testResearchConsumesItsLiveMaterialsAndPersists',
    'UI48ExtendedAcceptanceTests/testShopProductDetailAndPurchaseStateRemainDisconnected',
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-root', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--runtime', required=True, help='Installed com.apple.CoreSimulator.SimRuntime.* identifier')
    args = parser.parse_args()
    products = args.build_root.resolve() / 'DerivedData/Build/Products'
    runs = list(products.glob('*.xctestrun'))
    if len(runs) != 1:
        parser.error('Expected one Simulator xctestrun from reproduce.py')
    app = products / 'Release-iphonesimulator/WitchGathering.app'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'local.witch.repository.reproduction':
        parser.error('Refusing a build with the owner candidate bundle identifier')
    output = args.output.absolute()
    if any(path.is_symlink() for path in (output, *output.parents)):
        parser.error('Output must contain no symlinks')
    output = output.resolve()
    if output == ROOT or ROOT in output.parents or output in ROOT.parents:
        parser.error('Output must be outside the checkout')
    output.mkdir(parents=True, exist_ok=False)
    device = subprocess.check_output(['xcrun', 'simctl', 'create', 'Witch Repository Smoke',
                                     'com.apple.CoreSimulator.SimDeviceType.iPhone-17e', args.runtime], text=True).strip()
    (output / 'simulator.json').write_text(json.dumps({'new_device': device, 'runtime': args.runtime,
                                                      'tests': TESTS}, indent=2))
    with (output / 'ui-smoke.log').open('w') as log:
        try:
            subprocess.run(['xcrun', 'simctl', 'boot', device], check=True, stdout=log, stderr=subprocess.STDOUT)
            subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True, stdout=log, stderr=subprocess.STDOUT)
            command = ['xcodebuild', 'test-without-building', '-xctestrun', str(runs[0]),
                       '-destination', 'id=' + device, '-parallel-testing-enabled', 'NO',
                       '-resultBundlePath', str(output / 'ui-smoke.xcresult')]
            command += ['-only-testing:WitchUITests/' + test for test in TESTS]
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        finally:
            subprocess.run(['xcrun', 'simctl', 'shutdown', device], stdout=log, stderr=subprocess.STDOUT)
    print('UI smoke exit code:', result.returncode)
    print('Created Simulator retained:', device)
    print('Log:', output / 'ui-smoke.log')
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()

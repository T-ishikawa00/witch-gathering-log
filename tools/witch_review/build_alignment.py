#!/usr/bin/env python3
"""Read-only source/resource comparison for a manual build and frozen Xcode builds."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manual-app', type=Path, required=True)
    parser.add_argument('--frozen', type=Path, required=True)
    parser.add_argument('--xcode-simulator', type=Path, required=True)
    parser.add_argument('--xcode-device', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    receipt_path = args.manual_app.parent / 'BUILD_RECEIPT.json'
    receipt = json.loads(receipt_path.read_text())
    frozen_source = json.loads((args.frozen / 'SOURCE_SHA256.json').read_text())
    frozen_resources = json.loads((args.frozen / 'RESOURCE_SHA256.json').read_text())
    source_mismatches = []
    for relative, expected in receipt['source_sha256'].items():
        relative = relative.removeprefix('native/')
        if frozen_source.get(relative) != expected or digest(args.frozen / relative) != expected:
            source_mismatches.append(relative)
    manual_source_set = {p.removeprefix('native/') for p in receipt['source_sha256']}
    frozen_app_sources = {p for p in frozen_source if p.endswith('.swift') and not p.startswith('WitchUITests/')}
    source_set_difference = sorted(manual_source_set.symmetric_difference(frozen_app_sources))

    def game_resource(path):
        return path.startswith(('Art/', 'GeneratedArt/', 'Music/')) or path in {'catalog_overlay.json', 'PrivacyInfo.xcprivacy'}

    resources = {p: h for p, h in receipt['resource_sha256'].items() if game_resource(p)}
    frozen_resource_difference = sorted(set(resources).symmetric_difference(p for p in frozen_resources if game_resource(p)))
    resource_mismatches = {}
    for name, bundle in [('manual', args.manual_app), ('frozen', args.frozen / 'PreparedResources'),
                         ('xcodeSimulator', args.xcode_simulator), ('unsignedIPhoneOS', args.xcode_device)]:
        resource_mismatches[name] = [p for p, h in resources.items() if digest(bundle / p) != h]
    frozen_manifest_mismatches = [p for p, h in resources.items() if frozen_resources.get(p) != h]
    executable_matches = digest(args.manual_app / 'WitchGathering') == receipt['executable_sha256']
    passed = (receipt.get('status') == 'SIMULATOR_BUILD_PASS' and executable_matches and
              not source_mismatches and not source_set_difference and not frozen_resource_difference and
              not frozen_manifest_mismatches and not any(resource_mismatches.values()))
    result = {
        'at': datetime.datetime.now().astimezone().isoformat(), 'status': 'PASS' if passed else 'FAIL',
        'manualApp': str(args.manual_app.resolve()), 'manualBuildReceiptSHA256': digest(receipt_path),
        'frozenSource': str(args.frozen.resolve()), 'xcodeSimulator': str(args.xcode_simulator.resolve()),
        'unsignedIPhoneOS': str(args.xcode_device.resolve()), 'sourceCount': len(manual_source_set),
        'sourceMismatches': source_mismatches, 'sourceSetDifference': source_set_difference,
        'gameResourceCount': len(resources), 'resourceSetDifference': frozen_resource_difference,
        'frozenManifestMismatches': frozen_manifest_mismatches, 'resourceMismatches': resource_mismatches,
        'manualExecutableMatchesReceipt': executable_matches,
        'limits': 'Source and owned game-resource equality only. Xcode compile success is recorded in separate logs. '
                  'Does not compare architecture-specific executables, Assets.car, or generated Info.plist; '
                  'does not establish signing, physical-device execution, visual quality, or Human adoption.'
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'status': result['status'], 'sources': len(manual_source_set), 'gameResources': len(resources)}))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())

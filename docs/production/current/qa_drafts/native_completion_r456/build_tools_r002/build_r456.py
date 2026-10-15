#!/usr/bin/env python3
"""R456 dual-SDK Release build driver. Prepared only; requires a Root-sealed contract."""
from __future__ import annotations
import argparse
import datetime
import fcntl
import hashlib
import json
import os
import plistlib
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
BASE = Path(__file__).resolve().parent
INPUTS = BASE / 'INPUT_MANIFEST_R001.json'
SEAL = BASE / 'ROOT_SEAL_R001.json'
STATE = BASE / 'RUN_STATE_R001.json'
LOGS = BASE / 'logs'
OWNED_INFO = BASE / 'prepared_inputs' / 'Info_R456.plist'
WORKSPACE_ROOT = ROOT / 'native/build/ActiveIntegrationR456'
MAX_ALLOC = 2_000_000_000
SAFETY = 2_000_000_000
FLOOR = 20_000_000_000
START_FREE = 22_000_000_000
TOTAL_SECONDS = 600
PER_TARGET_SECONDS = 600
BUNDLE = 'local.witch.autonomous.r1.completion.r456'
FLAGS = ('STANDARD_PLAY_R169 FIRST_CRAFT_AID_R179 EQUIPMENT_LOADOUTS_R342 '
         'NATURAL_GEAR_R350 NATURAL_GEAR_REFINEMENT_R352 GEAR_DISMANTLE_REFUND_R353')


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def atomic_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.writing')
    with tmp.open('x', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, sort_keys=True, indent=2)
        f.write('\n'); f.flush(); os.fsync(f.fileno())
    os.replace(tmp, path)


def rooted(raw: str) -> Path:
    p = Path(raw)
    if not p.is_absolute():
        raise RuntimeError('all sealed paths must be absolute')
    resolved = Path(os.path.abspath(p))
    if not resolved.is_relative_to(ROOT):
        raise RuntimeError('sealed path outside fixed worktree')
    cur = ROOT
    for part in resolved.relative_to(ROOT).parts:
        cur = cur / part
        if cur.is_symlink():
            raise RuntimeError('symlink in sealed path')
    return resolved


def exact_file(raw: str, expected: str) -> Path:
    p = rooted(raw)
    if not p.is_file() or sha(p) != expected:
        raise RuntimeError('pinned regular file missing or changed: ' + str(p))
    return p


def live_compiler_processes() -> list[str]:
    rows = subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines()
    own = {str(os.getpid()), str(os.getppid())}
    return [row.strip() for row in rows if len(row.strip().split(None, 1)) == 2
            and row.strip().split(None, 1)[0] not in own
            and Path(row.strip().split(None, 1)[1]).name.lower() in
            {'xcodebuild', 'swift', 'swiftc', 'swift-driver', 'swift-frontend', 'actool', 'ibtoold'}]


def compiler_processes_outside(owned_root_pid: int) -> list[str]:
    rows = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,comm='], text=True).splitlines()
    parsed = []
    for row in rows:
        bits = row.strip().split(None, 2)
        if len(bits) == 3:
            try: parsed.append((int(bits[0]), int(bits[1]), bits[2]))
            except ValueError: pass
    owned = {owned_root_pid}
    changed = True
    while changed:
        changed = False
        for pid, ppid, _ in parsed:
            if ppid in owned and pid not in owned:
                owned.add(pid); changed = True
    return [f'{pid} {comm}' for pid, _, comm in parsed
            if pid not in owned and Path(comm).name.lower() in
            {'xcodebuild', 'swift', 'swiftc', 'swift-driver', 'swift-frontend', 'actool', 'ibtoold'}]


def allocated_bytes(root: Path) -> int:
    total, seen, todo = 0, set(), [root]
    while todo:
        p = todo.pop()
        try:
            if p.is_symlink():
                raise RuntimeError('output tree contains symlink')
            st = p.lstat()
            if p.is_dir():
                todo.extend(p.iterdir())
            elif p.is_file():
                key = (st.st_dev, st.st_ino)
                if key not in seen:
                    total += st.st_blocks * 512; seen.add(key)
        except FileNotFoundError:
            continue
    return total


def allocated_outputs(output: Path) -> int:
    return allocated_bytes(output) + allocated_bytes(LOGS) + allocated_bytes(OWNED_INFO)


def validate(seal_sha: str) -> tuple[dict, dict, Path, Path, Path, Path]:
    if str(ROOT) != '/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg':
        raise RuntimeError('wrong fixed worktree')
    if sha(SEAL) != seal_sha:
        raise RuntimeError('Root seal hash mismatch')
    seal = json.loads(SEAL.read_text())
    if seal.get('schema') != 'native-completion-r456-root-seal-v1' or seal.get('status') != 'ROOT_SEALED_READY_TO_BUILD':
        raise RuntimeError('R456 is not Root-sealed')
    inputs_path = exact_file(seal['inputManifestPath'], seal['inputManifestSHA256'])
    inputs = json.loads(inputs_path.read_text())
    if inputs.get('schema') != 'native-completion-r456-input-v1' or inputs.get('status') != 'ROOT_SEALED_READY_TO_BUILD':
        raise RuntimeError('input manifest is not Root-sealed')
    if inputs_path != INPUTS or inputs.get('worktree') != str(ROOT):
        raise RuntimeError('input manifest is not the fixed R456 manifest/worktree')
    if (seal.get('worktree') != str(ROOT) or seal.get('driverSHA256') != sha(Path(__file__))
            or inputs.get('driverSHA256') != sha(Path(__file__))):
        raise RuntimeError('Root seal is for another driver/worktree')
    if seal.get('protectedLivePBXSHA256') != inputs.get('protectedLivePBXSHA256'):
        raise RuntimeError('protected live PBX pin mismatch')
    expected_limits = {'attempts': 1, 'aggregateSeconds': TOTAL_SECONDS,
                       'perTargetSeconds': PER_TARGET_SECONDS, 'maxAllocatedOutputBytes': MAX_ALLOC,
                       'safetyReserveBytes': SAFETY, 'minimumFreeBytes': FLOOR,
                       'requiredStartFreeBytes': START_FREE, 'install': False,
                       'launch': False, 'freeze': False, 'resourceCopy': False}
    if seal.get('limits') != expected_limits or inputs.get('limits') != expected_limits:
        raise RuntimeError('limits differ from reviewed R456 bounds')
    if (inputs.get('bundleIdentifier') != BUNDLE or inputs.get('flags') != FLAGS.split()
            or seal.get('bundleIdentifier') != BUNDLE or seal.get('flags') != FLAGS.split()):
        raise RuntimeError('bundle/normal Release conditions mismatch')
    source_map_path = exact_file(inputs['sourceMapPath'], inputs['sourceMapSHA256'])
    frozen_map_path = exact_file(inputs['frozenSourceMapPath'], inputs['frozenSourceMapSHA256'])
    source_map, frozen_map = json.loads(source_map_path.read_text()), json.loads(frozen_map_path.read_text())
    if source_map != frozen_map or len(source_map) != 238:
        raise RuntimeError('R454 frozen 238-source map mismatch')
    for rel, digest in source_map.items():
        p = rooted(inputs['frozenSourceRoot']) / rel
        if not p.is_file() or sha(p) != digest:
            raise RuntimeError('frozen source differs: ' + rel)
    project = rooted(inputs['projectPath'])
    project_pbx = exact_file(str(project / 'project.pbxproj'), inputs['projectPBXSHA256'])
    if project_pbx != rooted(inputs['projectPBXPath']):
        raise RuntimeError('project PBX location mismatch')
    live_pbx = exact_file(inputs['protectedLivePBXPath'], inputs['protectedLivePBXSHA256'])
    if seal.get('protectedLivePBXSHA256') != sha(live_pbx):
        raise RuntimeError('live project file changed')
    resource_map = json.loads(exact_file(inputs['resourceMapPath'], inputs['resourceMapSHA256']).read_text())
    if len(resource_map) != 1922 or inputs.get('resourceCount') != 1922:
        raise RuntimeError('R454 resource map is not the pinned 1,922-file set')
    donor_map = json.loads(exact_file(inputs['donorResourceMapPath'], inputs['donorResourceMapSHA256']).read_text())
    if resource_map != donor_map:
        raise RuntimeError('R454 resources differ from the R373 pinned donor')
    info_src = exact_file(inputs['infoPlistTemplatePath'], inputs['infoPlistTemplateSHA256'])
    if not inputs.get('protectedPriorProducts'):
        raise RuntimeError('prior build products must be sealed for preservation')
    for row in inputs['protectedPriorProducts']:
        exact_file(row['path'], row['sha256'])
    state_dir = rooted(inputs['outputPath'])
    if not state_dir.is_relative_to(WORKSPACE_ROOT):
        raise RuntimeError('output must stay inside the dedicated R456 build root')
    if state_dir.exists() or state_dir.is_symlink():
        raise RuntimeError('R456 output directory already exists; do not overwrite')
    if STATE.exists() or (BASE / 'BUILD_RESULT_R001.json').exists():
        raise RuntimeError('R456 already has a prior attempt/result; preserve and stop')
    if live_compiler_processes():
        raise RuntimeError('competing compiler process is active')
    free = shutil.disk_usage(ROOT).free
    if free < START_FREE:
        raise RuntimeError('insufficient free space at start')
    return seal, inputs, source_map_path, project, info_src, state_dir


def prepare_info(source: Path) -> None:
    if OWNED_INFO.exists() or OWNED_INFO.is_symlink():
        raise RuntimeError('R456-owned Info.plist already exists; preserve and stop')
    OWNED_INFO.parent.mkdir(parents=True, exist_ok=False)
    data = plistlib.loads(source.read_bytes())
    data['CFBundleIdentifier'] = BUNDLE
    data.pop('SKIncludeConsumableInAppPurchaseHistory', None)
    with OWNED_INFO.open('xb') as f:
        f.write(plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=True))
        f.flush(); os.fsync(f.fileno())
    check = plistlib.loads(OWNED_INFO.read_bytes())
    if (check.get('CFBundleIdentifier') != BUNDLE
            or 'SKIncludeConsumableInAppPurchaseHistory' in check):
        raise RuntimeError('R456 Info.plist transformation mismatch')


def build_one(command: list[str], log_path: Path, proc_timeout: float,
              started: float, output: Path) -> dict:
    if time.monotonic() - started >= TOTAL_SECONDS:
        raise RuntimeError('aggregate build time cap reached before target')
    with log_path.open('xb') as log:
        proc = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        begin = time.monotonic()
        try:
            while proc.poll() is None:
                elapsed = time.monotonic() - started
                if elapsed > TOTAL_SECONDS or time.monotonic() - begin > proc_timeout:
                    raise RuntimeError('R456 build time cap reached')
                if allocated_outputs(output) > MAX_ALLOC or shutil.disk_usage(ROOT).free < FLOOR:
                    raise RuntimeError('R456 output/free-space bound reached')
                competing = compiler_processes_outside(proc.pid)
                if competing:
                    raise RuntimeError('unowned compiler process detected: ' + '; '.join(competing[:8]))
                time.sleep(1)
        except BaseException:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=5)
            except BaseException:
                try: os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError: pass
                proc.wait()
            raise
    if proc.returncode != 0:
        raise RuntimeError('xcodebuild failed; preserve logs and output')
    return {'returnCode': proc.returncode, 'elapsedSeconds': time.monotonic() - begin,
            'logSHA256': sha(log_path), 'command': command}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--verify-only', action='store_true')
    ap.add_argument('--seal-sha256', required=True)
    args = ap.parse_args()
    try:
        seal, inputs, source_map_path, project, info_src, output = validate(args.seal_sha256)
        if args.verify_only:
            print(json.dumps({'status': 'PINS_READY_NO_BUILD', 'sourceCount': 238,
                              'resourceCount': 1922, 'project': str(project),
                              'bundleIdentifier': BUNDLE}, sort_keys=True))
            return 0
        lock_path = BASE / 'BUILD.lock'
        with lock_path.open('a+') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            started = time.monotonic()
            output.mkdir(parents=True, exist_ok=False)
            LOGS.mkdir(exist_ok=False)
            prepare_info(info_src)
            derived = output / 'DerivedData'
            commands = [
                ['xcodebuild', 'build', '-project', str(project), '-scheme', 'WitchGathering',
                 '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', str(derived),
                 '-configuration', 'Release', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=' + FLAGS,
                 'INFOPLIST_FILE=' + str(OWNED_INFO), 'PRODUCT_BUNDLE_IDENTIFIER=' + BUNDLE,
                 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'ONLY_ACTIVE_ARCH=YES', '-jobs', '2'],
                ['xcodebuild', 'build', '-project', str(project), '-scheme', 'WitchGathering',
                 '-destination', 'generic/platform=iOS', '-sdk', 'iphoneos', '-derivedDataPath', str(derived),
                 '-configuration', 'Release', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=' + FLAGS,
                 'INFOPLIST_FILE=' + str(OWNED_INFO), 'PRODUCT_BUNDLE_IDENTIFIER=' + BUNDLE,
                 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'ONLY_ACTIVE_ARCH=YES', '-jobs', '2']]
            rows = []
            for name, command in zip(('simulator-release', 'iphoneos-unsigned-release'), commands):
                rows.append(build_one(command, LOGS / (name + '.log'), PER_TARGET_SECONDS, started, output))
            products = {
                'simulator': derived / 'Build/Products/Release-iphonesimulator/WitchGathering.app',
                'iphoneos': derived / 'Build/Products/Release-iphoneos/WitchGathering.app'}
            product_rows = {}
            for target, app in products.items():
                if not app.is_dir() or app.is_symlink():
                    raise RuntimeError(target + ' product missing or unsafe')
                plist_path = app / 'Info.plist'
                if not plist_path.is_file() or plist_path.is_symlink():
                    raise RuntimeError(target + ' Info.plist missing or unsafe')
                built_info = plistlib.loads(plist_path.read_bytes())
                executable = built_info.get('CFBundleExecutable')
                if (built_info.get('CFBundleIdentifier') != BUNDLE
                        or 'SKIncludeConsumableInAppPurchaseHistory' in built_info
                        or not isinstance(executable, str) or '/' in executable):
                    raise RuntimeError(target + ' product identity/StoreKit QA plist check failed')
                exe_path = app / executable
                if not exe_path.is_file() or exe_path.is_symlink():
                    raise RuntimeError(target + ' executable missing or unsafe')
                product_rows[target] = {'app': str(app), 'executable': str(exe_path),
                                        'executableSHA256': sha(exe_path),
                                        'bundleIdentifier': BUNDLE}
            live_map = json.loads(source_map_path.read_text())
            frozen_map = json.loads(rooted(inputs['frozenSourceMapPath']).read_text())
            if live_map != frozen_map:
                raise RuntimeError('frozen source map changed during build')
            for row in inputs['protectedPriorProducts']:
                exact_file(row['path'], row['sha256'])
            result = {'schema': 'native-completion-r456-build-result-v1', 'status': 'BUILD_COMMANDS_PASS',
                      'sealSHA256': args.seal_sha256, 'sourceMapSHA256': inputs['sourceMapSHA256'],
                      'projectPBXSHA256': inputs['projectPBXSHA256'], 'resourceMapSHA256': inputs['resourceMapSHA256'],
                      'bundleIdentifier': BUNDLE, 'configuration': 'Release', 'flags': FLAGS.split(),
                      'install': False, 'launch': False, 'attempt': 1, 'aggregateSeconds': time.monotonic()-started,
                      'allocatedOutputBytes': allocated_outputs(output), 'targets': rows,
                      'products': product_rows, 'infoPlistSHA256': sha(OWNED_INFO), 'outputPath': str(output)}
            atomic_json(BASE / 'BUILD_RESULT_R001.json', result)
        return 0
    except BaseException as exc:
        # Failure receipts belong in the R456-owned directory; never alter pinned input manifests.
        err = {'schema': 'native-completion-r456-build-result-v1', 'status': 'HOLD_OR_FAIL',
               'errorType': type(exc).__name__, 'message': str(exc),
               'at': datetime.datetime.now().astimezone().isoformat()}
        if not args.verify_only:
            try: atomic_json(BASE / 'BUILD_RESULT_R001.json', err)
            except BaseException: pass
        print(err['status'] + ': ' + err['errorType'] + ': ' + err['message'], file=sys.stderr)
        return 2

if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""R462 dual-SDK Release build driver. Prepared only; requires a Root-sealed contract."""
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
OWNED_INFO = BASE / 'prepared_inputs' / 'Info_R462.plist'
WORKSPACE_ROOT = ROOT / 'native/build/ActiveIntegrationR462'
MAX_ALLOC = 2_000_000_000
SAFETY = 2_000_000_000
FLOOR = 20_000_000_000
START_FREE = 22_000_000_000
TOTAL_SECONDS = 600
PER_TARGET_SECONDS = 600
BUNDLE = 'local.witch.autonomous.r1.completion.r462'
FLAGS = ('STANDARD_PLAY_R169 FIRST_CRAFT_AID_R179 EQUIPMENT_LOADOUTS_R342 '
         'NATURAL_GEAR_R350 NATURAL_GEAR_REFINEMENT_R352 GEAR_DISMANTLE_REFUND_R353')


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def strict_json(path: Path):
    def unique(pairs):
        obj = {}
        for key, value in pairs:
            if key in obj:
                raise RuntimeError('duplicate JSON key: ' + key)
            obj[key] = value
        return obj
    return json.loads(path.read_text(), object_pairs_hook=unique)


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


def process_rows() -> list[tuple[int, int, str]]:
    rows = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,lstart=,comm='], text=True).splitlines()
    out = []
    for row in rows:
        bits = row.strip().split(None, 7)
        if len(bits) < 7:
            continue
        try: pid, ppid = int(bits[0]), int(bits[1])
        except ValueError: continue
        start = ' '.join(bits[2:7])
        out.append((pid, ppid, start))
    return out


def descendants(rows: list[tuple[int, int, str]], root_pid: int) -> set[int]:
    parents = {}
    for pid, ppid, _ in rows:
        parents.setdefault(ppid, []).append(pid)
    found, stack = set(), [root_pid]
    while stack:
        parent = stack.pop()
        for child in parents.get(parent, []):
            if child not in found:
                found.add(child); stack.append(child)
    return found


def owned_cleanup(proc: subprocess.Popen, observed: dict[int, str], log,
                  natural_exit: bool = False) -> dict:
    cleanup_started = time.monotonic()
    rows = process_rows()
    owned_ids = descendants(rows, proc.pid)
    current = {pid: start for pid, _, start in rows}
    for pid in owned_ids:
        if pid in current:
            observed[pid] = current[pid]
    if proc.pid in current:
        observed[proc.pid] = current[proc.pid]
    target_ids = dict(observed)
    if natural_exit:
        target_ids.pop(proc.pid, None)

    def matching() -> list[int]:
        now = {pid: start for pid, _, start in process_rows()}
        return [pid for pid, start in target_ids.items() if now.get(pid) == start]

    alive = matching()
    for pid in alive:
        try: os.kill(pid, signal.SIGTERM)
        except ProcessLookupError: pass
    if proc.poll() is None:
        try: proc.wait(timeout=5)
        except subprocess.TimeoutExpired: pass
    end = time.monotonic() + 3.0
    while matching() and time.monotonic() < end:
        time.sleep(0.1)
    still = matching()
    for pid in still:
        try: os.kill(pid, signal.SIGKILL)
        except ProcessLookupError: pass
    if proc.poll() is None:
        try: proc.wait(timeout=2)
        except subprocess.TimeoutExpired: pass
    end = time.monotonic() + 2.0
    while matching() and time.monotonic() < end:
        time.sleep(0.1)
    remaining = matching()
    return {'trackedProcessCount': len(target_ids), 'termSentCount': len(alive),
            'killSentCount': len(still), 'remainingOwnedIdentities': remaining,
            'verified': not remaining and proc.poll() is not None,
            'trackedOwnedIdentities': [{'pid': pid, 'startIdentity': start}
                                       for pid, start in sorted(target_ids.items())],
            'leaderReturnCode': proc.returncode,
            'cleanupElapsedSeconds': time.monotonic() - cleanup_started}


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
    return (allocated_bytes(output) + allocated_bytes(LOGS) + allocated_bytes(OWNED_INFO)
            + allocated_bytes(BASE / 'BUILD_RESULT_R001.json') + allocated_bytes(BASE / 'BUILD.lock'))


def tree_map(root: Path) -> dict[str, str]:
    out = {}
    for parent, dirs, files in os.walk(root, topdown=True, followlinks=False):
        parent = Path(parent)
        for name in list(dirs):
            if (parent / name).is_symlink():
                raise RuntimeError('symlink in pinned tree')
        for name in files:
            p = parent / name
            if p.is_symlink() or not p.is_file():
                raise RuntimeError('non-regular file in pinned tree')
            out[p.relative_to(root).as_posix()] = sha(p)
    return out


def app_resource_map(app: Path, executable: str) -> dict[str, str]:
    out = {}
    for parent, dirs, files in os.walk(app, topdown=True, followlinks=False):
        parent = Path(parent)
        for name in list(dirs):
            if (parent / name).is_symlink():
                raise RuntimeError('symlink directory in app product')
        for name in files:
            p = parent / name
            if p.is_symlink() or not p.is_file():
                raise RuntimeError('non-regular file in app product')
            rel = p.relative_to(app).as_posix()
            if rel in {'Info.plist', 'PkgInfo', executable}:
                continue
            out[rel] = sha(p)
    return out


def verify_frozen_inputs(inputs: dict, source_map_path: Path, source_map: dict,
                         frozen_map_path: Path, frozen_map: dict, project: Path,
                         project_before: dict, project_pbx: Path, resource_map: dict,
                         info_src: Path) -> None:
    if strict_json(source_map_path) != source_map or strict_json(frozen_map_path) != frozen_map:
        raise RuntimeError('sealed source map contents changed')
    if sha(source_map_path) != inputs['sourceMapSHA256'] or sha(frozen_map_path) != inputs['frozenSourceMapSHA256']:
        raise RuntimeError('sealed source map hash changed')
    if source_map != frozen_map or len(source_map) != 240:
        raise RuntimeError('source maps no longer match the sealed 240-file set')
    source_root = rooted(inputs['frozenSourceRoot'])
    for rel, digest in source_map.items():
        path = source_root / rel
        if path.is_symlink() or not path.is_file() or sha(path) != digest:
            raise RuntimeError('frozen source changed: ' + rel)
    if tree_map(project) != project_before:
        raise RuntimeError('generated Xcode project changed during build')
    if sha(project_pbx) != inputs['projectPBXSHA256']:
        raise RuntimeError('generated project PBX hash changed')
    if sha(rooted(inputs['protectedLivePBXPath'])) != inputs['protectedLivePBXSHA256']:
        raise RuntimeError('protected live PBX changed')
    resource_path = exact_file(inputs['resourceMapPath'], inputs['resourceMapSHA256'])
    donor_path = exact_file(inputs['donorResourceMapPath'], inputs['donorResourceMapSHA256'])
    current_resource_map = strict_json(resource_path)
    if current_resource_map != resource_map or current_resource_map != strict_json(donor_path):
        raise RuntimeError('sealed resource map or donor map changed')
    actual_resources = tree_map(source_root / 'PreparedResources')
    if actual_resources != resource_map or len(actual_resources) != 1922:
        raise RuntimeError('frozen PreparedResources differ from exact 1,922-file map')
    if sha(info_src) != inputs['infoPlistTemplateSHA256']:
        raise RuntimeError('pinned Info.plist template changed')
    for row in inputs['protectedPriorProducts']:
        exact_file(row['path'], row['sha256'])


def final_bounds(started: float, output: Path) -> dict:
    elapsed = time.monotonic() - started
    allocated = allocated_outputs(output)
    free = shutil.disk_usage(ROOT).free
    if elapsed >= TOTAL_SECONDS:
        raise RuntimeError('aggregate time cap exceeded during final validation')
    if allocated > MAX_ALLOC:
        raise RuntimeError('allocated output cap exceeded during final validation')
    if free < FLOOR:
        raise RuntimeError('free-space floor breached during final validation')
    return {'aggregateSeconds': elapsed, 'allocatedOutputBytes': allocated,
            'freeBytesAtFinalCheck': free}


def validate(seal_sha: str) -> tuple:
    if str(ROOT) != '/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg':
        raise RuntimeError('wrong fixed worktree')
    if sha(SEAL) != seal_sha:
        raise RuntimeError('Root seal hash mismatch')
    seal = strict_json(SEAL)
    if seal.get('schema') != 'native-completion-r462-root-seal-v1' or seal.get('status') != 'ROOT_SEALED_READY_TO_BUILD':
        raise RuntimeError('R462 is not Root-sealed')
    inputs_path = exact_file(seal['inputManifestPath'], seal['inputManifestSHA256'])
    inputs = strict_json(inputs_path)
    if inputs.get('schema') != 'native-completion-r462-input-v1' or inputs.get('status') != 'ROOT_SEALED_READY_TO_BUILD':
        raise RuntimeError('input manifest is not Root-sealed')
    if inputs_path != INPUTS or inputs.get('worktree') != str(ROOT):
        raise RuntimeError('input manifest is not the fixed R462 manifest/worktree')
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
        raise RuntimeError('limits differ from reviewed R462 bounds')
    if (inputs.get('bundleIdentifier') != BUNDLE or inputs.get('flags') != FLAGS.split()
            or seal.get('bundleIdentifier') != BUNDLE or seal.get('flags') != FLAGS.split()):
        raise RuntimeError('bundle/normal Release conditions mismatch')
    source_map_path = exact_file(inputs['sourceMapPath'], inputs['sourceMapSHA256'])
    frozen_map_path = exact_file(inputs['frozenSourceMapPath'], inputs['frozenSourceMapSHA256'])
    source_map, frozen_map = strict_json(source_map_path), strict_json(frozen_map_path)
    if source_map != frozen_map or len(source_map) != 240:
        raise RuntimeError('R454 frozen 240-source map mismatch')
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
    resource_map = strict_json(exact_file(inputs['resourceMapPath'], inputs['resourceMapSHA256']))
    if len(resource_map) != 1922 or inputs.get('resourceCount') != 1922:
        raise RuntimeError('R454 resource map is not the pinned 1,922-file set')
    donor_map = strict_json(exact_file(inputs['donorResourceMapPath'], inputs['donorResourceMapSHA256']))
    if resource_map != donor_map:
        raise RuntimeError('R454 resources differ from the R373 pinned donor')
    info_src = exact_file(inputs['infoPlistTemplatePath'], inputs['infoPlistTemplateSHA256'])
    if not inputs.get('protectedPriorProducts'):
        raise RuntimeError('prior build products must be sealed for preservation')
    for row in inputs['protectedPriorProducts']:
        exact_file(row['path'], row['sha256'])
    state_dir = rooted(inputs['outputPath'])
    if not state_dir.is_relative_to(WORKSPACE_ROOT):
        raise RuntimeError('output must stay inside the dedicated R462 build root')
    if state_dir.exists() or state_dir.is_symlink():
        raise RuntimeError('R462 output directory already exists; do not overwrite')
    if STATE.exists() or (BASE / 'BUILD_RESULT_R001.json').exists():
        raise RuntimeError('R462 already has a prior attempt/result; preserve and stop')
    if live_compiler_processes():
        raise RuntimeError('competing compiler process is active')
    free = shutil.disk_usage(ROOT).free
    if free < START_FREE:
        raise RuntimeError('insufficient free space at start')
    project_before = tree_map(project)
    return seal, inputs, source_map_path, source_map, frozen_map_path, frozen_map, project, project_before, project_pbx, info_src, state_dir, resource_map


def prepare_info(source: Path) -> None:
    if OWNED_INFO.exists() or OWNED_INFO.is_symlink():
        raise RuntimeError('R462-owned Info.plist already exists; preserve and stop')
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
        raise RuntimeError('R462 Info.plist transformation mismatch')


def build_one(command: list[str], log_path: Path, proc_timeout: float,
              started: float, output: Path) -> dict:
    if time.monotonic() - started >= TOTAL_SECONDS:
        raise RuntimeError('aggregate build time cap reached before target')
    with log_path.open('xb') as log:
        proc = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        begin = time.monotonic()
        observed = {}
        try:
            while proc.poll() is None:
                elapsed = time.monotonic() - started
                if elapsed > TOTAL_SECONDS or time.monotonic() - begin > proc_timeout:
                    raise RuntimeError('R462 build time cap reached')
                if allocated_outputs(output) > MAX_ALLOC or shutil.disk_usage(ROOT).free < FLOOR:
                    raise RuntimeError('R462 output/free-space bound reached')
                current_rows = process_rows()
                child_ids = descendants(current_rows, proc.pid)
                for pid, _ppid, identity in current_rows:
                    if pid == proc.pid or pid in child_ids:
                        observed[pid] = identity
                competing = compiler_processes_outside(proc.pid)
                if competing:
                    raise RuntimeError('unowned compiler process detected: ' + '; '.join(competing[:8]))
                time.sleep(0.25)
        except BaseException:
            owned_cleanup(proc, observed, log)
            raise
        if time.monotonic() - begin > proc_timeout or time.monotonic() - started > TOTAL_SECONDS:
            owned_cleanup(proc, observed, log)
            raise RuntimeError('R462 build completed after time cap')
        cleanup = owned_cleanup(proc, observed, log, natural_exit=True)
        if not cleanup['verified']:
            raise RuntimeError('owned build process cleanup could not be verified')
        remaining_compilers = live_compiler_processes()
        if remaining_compilers:
            raise RuntimeError('compiler process remains after xcodebuild exit: ' + '; '.join(remaining_compilers[:8]))
    if proc.returncode != 0:
        raise RuntimeError('xcodebuild failed; preserve logs and output')
    return {'returnCode': proc.returncode, 'elapsedSeconds': time.monotonic() - begin,
            'ownedProcessCleanup': cleanup, 'logSHA256': sha(log_path), 'command': command}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--verify-only', action='store_true')
    ap.add_argument('--seal-sha256', required=True)
    args = ap.parse_args()
    try:
        (seal, inputs, source_map_path, source_map, frozen_map_path, frozen_map,
         project, project_before, project_pbx, info_src, output, resource_map) = validate(args.seal_sha256)
        if args.verify_only:
            print(json.dumps({'status': 'PINS_READY_NO_BUILD', 'sourceCount': 240,
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
                 'SYMROOT=' + str(derived / 'Build'), 'BUILD_DIR=' + str(derived / 'Build'),
                 'OBJROOT=' + str(derived / 'Build/Intermediates.noindex'),
                 'CONFIGURATION_BUILD_DIR=' + str(derived / 'Build/Products/Release-iphonesimulator'),
                 'INFOPLIST_FILE=' + str(OWNED_INFO), 'PRODUCT_BUNDLE_IDENTIFIER=' + BUNDLE,
                 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'ONLY_ACTIVE_ARCH=YES', '-jobs', '2'],
                ['xcodebuild', 'build', '-project', str(project), '-scheme', 'WitchGathering',
                 '-destination', 'generic/platform=iOS', '-sdk', 'iphoneos', '-derivedDataPath', str(derived),
                 '-configuration', 'Release', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=' + FLAGS,
                 'SYMROOT=' + str(derived / 'Build'), 'BUILD_DIR=' + str(derived / 'Build'),
                 'OBJROOT=' + str(derived / 'Build/Intermediates.noindex'),
                 'CONFIGURATION_BUILD_DIR=' + str(derived / 'Build/Products/Release-iphoneos'),
                 'INFOPLIST_FILE=' + str(OWNED_INFO), 'PRODUCT_BUNDLE_IDENTIFIER=' + BUNDLE,
                 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'ONLY_ACTIVE_ARCH=YES', '-jobs', '2']]
            rows = []
            for name, command in zip(('simulator-release', 'iphoneos-unsigned-release'), commands):
                rows.append(build_one(command, LOGS / (name + '.log'), PER_TARGET_SECONDS, started, output))
            products = {
                'simulator': derived / 'Build/Products/Release-iphonesimulator/WitchGathering.app',
                'iphoneos': derived / 'Build/Products/Release-iphoneos/WitchGathering.app'}
            product_rows = {}
            packaged_resource_maps = {}
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
                packaged_resource_maps[target] = app_resource_map(app, executable)
            sim_resources = packaged_resource_maps['simulator']
            device_resources = packaged_resource_maps['iphoneos']
            if sim_resources != resource_map or device_resources != resource_map:
                raise RuntimeError('either SDK product is missing/diverging from the exact pinned 1,922-resource map')
            verify_frozen_inputs(inputs, source_map_path, source_map, frozen_map_path,
                                 frozen_map, project, project_before, project_pbx,
                                 resource_map, info_src)
            bounds = final_bounds(started, output)
            if bounds['aggregateSeconds'] >= TOTAL_SECONDS - 2.0:
                raise RuntimeError('insufficient time margin for durable success receipt')
            if bounds['allocatedOutputBytes'] >= MAX_ALLOC - 1_000_000:
                raise RuntimeError('insufficient output margin for durable success receipt')
            result = {'schema': 'native-completion-r462-build-result-v1', 'status': 'BUILD_COMMANDS_PASS',
                      'sealSHA256': args.seal_sha256, 'sourceMapSHA256': inputs['sourceMapSHA256'],
                      'projectPBXSHA256': inputs['projectPBXSHA256'], 'resourceMapSHA256': inputs['resourceMapSHA256'],
                      'bundleIdentifier': BUNDLE, 'configuration': 'Release', 'flags': FLAGS.split(),
                      'install': False, 'launch': False, 'attempt': 1,
                      'aggregateSeconds': bounds['aggregateSeconds'],
                      'allocatedOutputBytes': bounds['allocatedOutputBytes'],
                      'freeBytesAtFinalCheck': bounds['freeBytesAtFinalCheck'], 'targets': rows,
                      'products': product_rows,
                      'packagedResourceMapSHA256': hashlib.sha256(json.dumps(
                          sim_resources, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
                      'packagedResourceCount': len(sim_resources),
                      'packagedResourceMaps': packaged_resource_maps,
                      'resourceSDKParity': True, 'resourceMapExact': True,
                      'infoPlistSHA256': sha(OWNED_INFO), 'outputPath': str(output)}
            atomic_json(BASE / 'BUILD_RESULT_R001.json', result)
            post = final_bounds(started, output)
            if live_compiler_processes():
                result['status'] = 'HOLD_OWNED_PROCESS_REMAINS'
                result['postReceiptBounds'] = post
                atomic_json(BASE / 'BUILD_RESULT_R001.json', result)
                raise RuntimeError('compiler process remains after both xcodebuild commands')
            if post['aggregateSeconds'] >= TOTAL_SECONDS or post['allocatedOutputBytes'] > MAX_ALLOC:
                result['status'] = 'HOLD_POST_RECEIPT_BOUNDARY'
                result['postReceiptBounds'] = post
                atomic_json(BASE / 'BUILD_RESULT_R001.json', result)
                raise RuntimeError('R462 final cap exceeded while writing receipt')
        return 0
    except BaseException as exc:
        # Failure receipts belong in the R462-owned directory; never alter pinned input manifests.
        err = {'schema': 'native-completion-r462-build-result-v1', 'status': 'HOLD_OR_FAIL',
               'errorType': type(exc).__name__, 'message': str(exc),
               'at': datetime.datetime.now().astimezone().isoformat()}
        if not args.verify_only:
            try: atomic_json(BASE / 'BUILD_RESULT_R001.json', err)
            except BaseException: pass
        print(err['status'] + ': ' + err['errorType'] + ': ' + err['message'], file=sys.stderr)
        return 2

if __name__ == '__main__':
    raise SystemExit(main())

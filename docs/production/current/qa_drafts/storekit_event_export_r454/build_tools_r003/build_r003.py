"""R454 isolated normal Debug-only native builder candidate. Preparation only; never install or launch."""
from pathlib import Path
import argparse, datetime, fcntl, hashlib, json, os, plistlib, shutil, signal, subprocess, sys, time, xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[6]
NATIVE = ROOT / "native"
BASE = Path(__file__).resolve().parent
MAP_PATH = BASE / "NATIVE_SOURCE_MAP_R003.json"
INPUTS_PATH = BASE / "INPUT_MANIFEST_R003.json"
CONTRACT_PATH = BASE / "ROOT_SEALED_CONTRACT_R003.json"
STATE_PATH = BASE / "BUILD_STATE_R003.json"
WORKSPACE_ROOT = NATIVE / "build/ActiveIntegrationR454/native_r003"
PBX = NATIVE / "WitchGathering.xcodeproj/project.pbxproj"
MAX_OUTPUT = 2_000_000_000
SAFETY = 2_000_000_000
FLOOR = 20_000_000_000
REQUIRED_START = 20_000_000_000
AGGREGATE_SECONDS = 600
PHASE_SECONDS = 600
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "tools/witch_native"))
from resource_inventory import capture_resource_inventory, require_reusable_inventory
from storage_guard import check_capacity


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical_sha(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def atomic_json(path, value):
    path = Path(path)
    temp = path.with_name(path.name + ".writing")
    with temp.open("x", encoding="utf-8") as out:
        json.dump(value, out, ensure_ascii=False, sort_keys=True, indent=2)
        out.write("\n"); out.flush(); os.fsync(out.fileno())
    os.replace(temp, path)


def safe_root_file(path, expected):
    path = Path(path)
    lexical = Path(os.path.abspath(path))
    if not lexical.is_absolute() or not lexical.is_relative_to(ROOT):
        raise RuntimeError("Pinned input escaped the fixed worktree")
    cursor = ROOT
    for part in lexical.relative_to(ROOT).parts:
        cursor = cursor / part
        if cursor.is_symlink():
            raise RuntimeError("Symlink in pinned input path: " + str(cursor))
    if not path.is_file() or sha(path) != expected:
        raise RuntimeError("Pinned input hash mismatch: " + str(path))
    return path


def live_source_map():
    files = (list((NATIVE / "WitchApp").glob("*.swift"))
        + list((NATIVE / "WitchGameCore/Sources/WitchGameCore").glob("*.swift"))
        + list((NATIVE / "WitchGameCore/Sources/WitchGameCore/Resources").glob("*.json"))
        + list((NATIVE / "WitchUITests").glob("*.swift"))
        + [NATIVE / "StoreKitLocalQA/ReusableBridge.swift"])
    result = {}
    for p in sorted(files):
        if p.is_symlink() or not p.is_file():
            raise RuntimeError("Source inputs must be regular non-symlink files: " + str(p))
        result[p.relative_to(NATIVE).as_posix()] = sha(p)
    return result


def resource_map(root, executable):
    root = Path(root)
    result = {}
    for base, dirs, files in os.walk(root, topdown=True, followlinks=False):
        base = Path(base)
        kept = []
        for name in dirs:
            p = base / name
            if p.is_symlink():
                raise RuntimeError("Symlink directory in built app: " + str(p))
            kept.append(name)
        dirs[:] = kept
        for name in files:
            p = base / name
            if p.is_symlink() or not p.is_file():
                raise RuntimeError("Non-regular file in built app: " + str(p))
            rel = p.relative_to(root).as_posix()
            if rel in {"Info.plist", "PkgInfo", executable}:
                continue
            result[rel] = sha(p)
    return result


def verify_environment_is_idle():
    output = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True)
    active = []
    for line in output.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) != 2 or fields[0] == str(os.getpid()):
            continue
        name = Path(fields[1]).name.lower()
        if name in {"xcodebuild", "swift", "swiftc",
                    "swift-driver", "swift-frontend", "actool", "ibtoold"}:
            active.append(line.strip())
    if active:
        raise RuntimeError("Concurrent compiler/build process detected: " + "; ".join(active[:8]))



def expected_launch_arguments(contract):
    token = contract.get("testToken")
    profile = contract.get("profileFingerprint")
    if token != "45400000-0000-4000-8000-000000000001" or profile != "62ce1ce493d34a7864cd7c7c1a5ee17aebdc8891b2b7b8dcb4eb7e6534c06e99":
        raise RuntimeError("R454 test token or root-pinned profile fingerprint mismatch")
    return ["--qa-isolated", "--qa-save-key=storekit-authority-r454", "--xcode-local-storekit-qa",
        "--screen=購入検証", "--r454-local-authority-qa", "--r454-test-token", token,
        "--r454-profile-fingerprint", profile]


def configure_storekit_scheme(scheme_path, contract, inputs):
    pinned = inputs["storeKitConfiguration"]
    safe_root_file(pinned["path"], pinned["sha256"])
    if pinned.get("relativeIdentifier") != "../../StoreKitLocalQA/iOSRunner/AppProbe/Products.storekit":
        raise RuntimeError("R454 StoreKit configuration must use the reviewed relative identifier")
    tree = ET.parse(scheme_path)
    root = tree.getroot()
    launch = root.find("LaunchAction")
    if launch is None:
        raise RuntimeError("Generated scheme has no LaunchAction")
    for old in list(launch.findall("CommandLineArguments")):
        launch.remove(old)
    args = ET.SubElement(launch, "CommandLineArguments")
    for value in expected_launch_arguments(contract):
        ET.SubElement(args, "CommandLineArgument", {"argument": value, "isEnabled": "YES"})
    for old in list(launch.findall("StoreKitConfigurationFileReference")):
        launch.remove(old)
    ET.SubElement(launch, "StoreKitConfigurationFileReference", {"identifier": pinned["relativeIdentifier"]})
    tree.write(scheme_path, encoding="utf-8", xml_declaration=True)
    check = ET.parse(scheme_path).getroot().find("LaunchAction")
    observed = [row.get("argument") for row in check.findall("./CommandLineArguments/CommandLineArgument") if row.get("isEnabled") == "YES"]
    configs = check.findall("StoreKitConfigurationFileReference")
    if observed != expected_launch_arguments(contract) or len(configs) != 1 or configs[0].get("identifier") != pinned["relativeIdentifier"]:
        raise RuntimeError("Generated StoreKit LaunchAction did not preserve the exact sealed profile/arguments")


def verify_external_trees(inputs):
    """Read-only exact tree inventory; external trees may be pinned directly or via a sealed R445 receipt."""
    checked = 0
    for pin in inputs.get("protectedExternalTrees", []):
        expected_files = pin.get("files")
        if "receiptPath" in pin:
            receipt_path = safe_root_file(pin["receiptPath"], pin["receiptSHA256"])
            receipt = json.loads(receipt_path.read_text())
            expected_files = receipt.get("protectedTrees", {}).get(pin.get("path"))
            if not isinstance(expected_files, dict):
                raise RuntimeError("R445 receipt does not contain the referenced protected tree")
        if not isinstance(expected_files, dict):
            raise RuntimeError("Protected external tree has no exact file map")
        root = Path(pin["path"])
        simulator = Path.home() / "Library/Developer/CoreSimulator/Devices/9A067715-7CF3-40D3-9064-38423223959B/data/Containers"
        allowed = [ROOT / "docs/production/current/qa_drafts/native_completion_r445",
            simulator / "Bundle/Application", simulator / "Data/Application"]
        lexical = Path(os.path.abspath(root))
        if (not lexical.is_absolute() or not any(lexical.is_relative_to(prefix) for prefix in allowed)
                or root.is_symlink() or not root.is_dir() or root.resolve() != lexical):
            raise RuntimeError("Protected tree is outside approved R445 evidence or 9A container roots: " + str(root))
        cursor = Path(lexical.anchor)
        for part in lexical.parts[1:]:
            cursor = cursor / part
            if cursor.is_symlink(): raise RuntimeError("Symlink in protected external path: " + str(cursor))
        raw = {}
        for base, dirs, files in os.walk(root, topdown=True, followlinks=False):
            base = Path(base); kept = []
            for name in dirs:
                child = base / name
                if child.is_symlink(): raise RuntimeError("Symlink in protected external tree: " + str(child))
                kept.append(name)
            dirs[:] = kept
            for name in files:
                child = base / name
                if child.is_symlink() or not child.is_file(): raise RuntimeError("Non-regular protected external file: " + str(child))
                raw[child.relative_to(root).as_posix()] = sha(child)
                checked += 1
                if checked > 30000: raise RuntimeError("Protected external pin set exceeds 30,000 files")
        if raw != expected_files:
            raise RuntimeError("Protected external tree drift: " + str(root))
    if not inputs.get("protectedExternalTrees") or checked == 0:
        raise RuntimeError("R454 requires nonempty R445 installed-app, save, and evidence protection trees")
    return checked


def validate_inputs(args):
    if str(ROOT) != "/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg":
        raise RuntimeError("R454 is bound to the reviewed worktree only")
    inputs = json.loads(safe_root_file(INPUTS_PATH, args.input_manifest_sha256).read_text())
    contract = json.loads(safe_root_file(CONTRACT_PATH, args.root_contract_sha256).read_text())
    if inputs.get("schema") != "storekit-event-export-r454-input-manifest-r003-v1":
        raise RuntimeError("Unknown R454 input manifest")
    if contract.get("schema") != "storekit-event-export-r454-build-contract-r003-v1" or contract.get("status") != "ROOT_SEALED_READY_TO_BUILD":
        raise RuntimeError("R454 requires a root-sealed contract")
    if contract.get("worktree") != str(ROOT) or contract.get("inputManifestSHA256") != args.input_manifest_sha256:
        raise RuntimeError("R454 contract/worktree/input manifest mismatch")
    if contract.get("driverSHA256") != sha(Path(__file__)):
        raise RuntimeError("R454 driver differs from sealed contract")
    if inputs.get("driverSHA256") != sha(Path(__file__)):
        raise RuntimeError("R454 input manifest does not bind this driver")
    if contract.get("sourceMapSHA256") != inputs["sourceMapSHA256"] or contract.get("sourceCount") != inputs.get("sourceCount") or inputs.get("sourceCount") != 238:
        raise RuntimeError("R454 source map contract mismatch")
    source_path = safe_root_file(inputs["sourceMapPath"], inputs["sourceMapSHA256"])
    source_map = json.loads(source_path.read_text())
    if len(source_map) != inputs["sourceCount"] or source_map != live_source_map():
        raise RuntimeError("R454 live source map is not the sealed 238-file map")
    if sha(PBX) != inputs["protectedProject"]["sha256"] or contract.get("protectedPBXSHA256") != sha(PBX):
        raise RuntimeError("Protected project file changed")
    for name, expected in inputs["tools"].items():
        if sha(ROOT / "tools/witch_native" / name) != expected:
            raise RuntimeError("Build tool input changed: " + name)
    verify_preserved_products(inputs)
    verify_external_trees(inputs)
    donor = inputs["resourceDonor"]
    receipt_path = safe_root_file(donor["receiptPath"], donor["receiptSHA256"])
    receipt = json.loads(receipt_path.read_text())
    frozen = Path(donor["frozenPath"])
    capture_path = safe_root_file(frozen / "RESOURCE_CAPTURE.json", donor["resourceCaptureSHA256"])
    map_path = safe_root_file(donor["resourceMapPath"], donor["resourceMapSHA256"])
    donor_source_path = safe_root_file(donor["sourceMapPath"], donor["sourceMapSHA256"])
    donor_capture = json.loads(capture_path.read_text())
    current_inventory = capture_resource_inventory(NATIVE)
    require_reusable_inventory(donor_capture, current_inventory)
    resources = json.loads(map_path.read_text())
    donor_map_value = json.loads(donor_source_path.read_text())
    if (len(resources) != 1922 or receipt.get("resourceCount") != 1922
            or receipt.get("sourceCount") != len(donor_map_value)
            or Path(receipt.get("frozen", "")).resolve() != frozen.resolve()
            or receipt.get("bundleIdentifier") != "local.witch.autonomous.r1.completion.r445"):
        raise RuntimeError("R445 donor is not the pinned 1,922-file resource set")
    if receipt.get("phase") != "BUILD_PASS" or receipt.get("install") is not False or receipt.get("launch") is not False:
        raise RuntimeError("R445 resource donor receipt is not a closed build-only PASS")
    if json.loads(donor_source_path.read_text()) != json.loads((frozen / "SOURCE_SHA256.json").read_text()):
        raise RuntimeError("R445 donor source map differs from its frozen map")
    if sha(ROOT / "tools/witch_native/prepare_resources.py") != sha(frozen / "prepare_resources.py"):
        raise RuntimeError("Resource assembler differs from R445 donor capture")
    for key, variant in inputs["variants"].items():
        if contract.get("variants", {}).get(key) != variant:
            raise RuntimeError("Sealed variant configuration differs: " + key)
    if contract.get("resourceCount") != 1922 or contract.get("limits") != inputs["limits"]:
        raise RuntimeError("R454 resource/budget contract mismatch")
    expected_limits = {"freezeAndDebugAggregateSeconds": 600, "debugBuildSeconds": 600,
        "maxAllocatedBytes": 2000000000, "safetyBytes": 2000000000, "minimumFreeBytes": 20000000000,
        "requiredStartFreeBytes": 20000000000, "install": False, "launch": False, "attempts": 1}
    if inputs.get("limits") != expected_limits:
        raise RuntimeError("R454 limits differ from the reviewed single-Debug fixed budget")
    profile = inputs["profile"]
    safe_root_file(profile["path"], profile["sha256"])
    if profile.get("fingerprint") != contract.get("profileFingerprint"):
        raise RuntimeError("R454 profile fingerprint is not the root-sealed host profile")
    if contract.get("launchArguments") != expected_launch_arguments(contract):
        raise RuntimeError("R454 root-sealed launch arguments differ from exact allowlist")
    expected_flags = {"debug": ["DEBUG"]}
    if {k: v["flags"] for k, v in inputs["variants"].items()} != expected_flags:
        raise RuntimeError("R454 must build only the isolated DEBUG StoreKit QA variant")
    return inputs, contract, source_map, frozen, resources


def verify_preserved_products(inputs):
    """Read-only integrity fence for R398, R406/R407 and prior R409/R418/R420/R437/R445 products."""
    checked = 0
    pin = inputs["protectedR398BuildState"]
    state = json.loads(safe_root_file(pin["path"], pin["sha256"]).read_text())
    if state.get("phase") != "PASS_BOTH_VARIANTS" or set(state.get("variants", {})) != {"release", "qa-debug"}:
        raise RuntimeError("R398 protected build is not a closed two-variant PASS")
    for variant in state["variants"].values():
        if variant.get("phase") != "PASS": raise RuntimeError("R398 protected variant is not PASS")
        for path, digest in variant.get("productFiles", {}).items():
            safe_root_file(path, digest); checked += 1

    pin = inputs["protectedR407DebugState"]
    state = json.loads(safe_root_file(pin["path"], pin["sha256"]).read_text())
    if state.get("phase") != "PASS_DEBUG_ONLY" or set(state.get("variants", {})) != {"qa-debug"}:
        raise RuntimeError("R407 protected Debug build is not a closed single-variant PASS")
    row = state["variants"]["qa-debug"]
    if row.get("phase") != "PASS" or row.get("bundleIdentifier") != "local.witch.autonomous.r1.enemyart.r407":
        raise RuntimeError("R407 protected Debug identity/status mismatch")
    for path, digest in row.get("productFiles", {}).items(): safe_root_file(path, digest); checked += 1

    pin = inputs["protectedR406ReleaseState"]
    state = json.loads(safe_root_file(pin["path"], pin["sha256"]).read_text())
    if state.get("phase") != "PARTIAL_PASS" or set(state.get("variants", {})) != {"release"}:
        raise RuntimeError("R406 protected Release state mismatch")
    row = state["variants"]["release"]
    if row.get("phase") != "PASS" or row.get("bundleIdentifier") != "local.witch.autonomous.r1.completion.r406":
        raise RuntimeError("R406 protected Release identity/status mismatch")
    for path, digest in row.get("productFiles", {}).items(): safe_root_file(path, digest); checked += 1

    for pin in inputs["additionalProtectedStates"]:
        state = json.loads(safe_root_file(pin["path"], pin["sha256"]).read_text())
        if state.get("phase") not in {"PASS_RELEASE_ONLY", "PASS_BOTH_VARIANTS"}:
            raise RuntimeError("Additional protected build is not closed PASS")
        for variant in state["variants"].values():
            if variant.get("phase") != "PASS": raise RuntimeError("Additional protected variant not PASS")
            for path, digest in variant.get("productFiles", {}).items(): safe_root_file(path, digest); checked += 1
    if checked == 0: raise RuntimeError("Protected product readback set is empty")
    return {"r398StateSHA256": inputs["protectedR398BuildState"]["sha256"],
        "r406ReleaseStateSHA256": inputs["protectedR406ReleaseState"]["sha256"],
        "r445ReleaseStateSHA256": next((x["sha256"] for x in inputs["additionalProtectedStates"] if "native_completion_r445" in x["path"]), None),
        "checkedFiles": checked}


def allocated_bytes(paths):
    total, seen = 0, set()
    for raw in paths:
        p = Path(raw)
        if not p.exists():
            continue
        todo = [p]
        while todo:
            cur = todo.pop()
            try:
                if cur.is_symlink():
                    continue
                st = cur.lstat()
                if cur.is_dir():
                    todo.extend(cur.iterdir())
                elif cur.is_file():
                    key = (st.st_dev, st.st_ino)
                    if key not in seen:
                        total += st.st_blocks * 512; seen.add(key)
            except FileNotFoundError:
                continue
    return total


def owned_elapsed(state, current=0.0):
    return sum(float(row.get("elapsedSeconds", 0.0)) for row in state.get("commands", [])) + current


def owned_run(command, log_path, phase_deadline, state, artifacts):
    start = time.monotonic()
    with Path(log_path).open("xb") as log:
        proc = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        state["ownedProcess"] = {"pid": proc.pid, "pgid": proc.pid, "command": command}
        try:
            atomic_json(STATE_PATH, state)
            while proc.poll() is None:
                free = shutil.disk_usage(ROOT).free
                dynamic = list(artifacts)
                baseline = state.get("nativeBaseline")
                if baseline:
                    dynamic.extend(set(NATIVE.glob("qa_source_*")) - set(map(Path, baseline["frozen"])))
                    dynamic.extend(set(NATIVE.glob("WitchGatheringQA_*.xcodeproj")) - set(map(Path, baseline["projects"])))
                size = allocated_bytes(dynamic)
                aggregate = owned_elapsed(state, time.monotonic() - start)
                if time.monotonic() - start > phase_deadline or aggregate > AGGREGATE_SECONDS or size > MAX_OUTPUT or free < FLOOR:
                    state["forcedStop"] = {"phaseTimeout": time.monotonic()-start > phase_deadline,
                        "aggregateTimeout": aggregate > AGGREGATE_SECONDS,
                        "allocatedBytes": size, "freeBytes": free}
                    raise RuntimeError("R454 process exceeded a monitored limit")
                if live_source_map() != state["sourceMap"] or sha(PBX) != state["protectedPBXSHA256"]:
                    raise RuntimeError("Live source or protected PBX drift during build")
                time.sleep(2)
        except BaseException:
            try: os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            try: proc.wait(timeout=5)
            except subprocess.TimeoutExpired: pass
            try: os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            proc.wait()
            raise
        finally:
            state["ownedProcess"] = None
            state.setdefault("commands", []).append({"command": command, "returnCode": proc.returncode,
                "elapsedSeconds": time.monotonic()-start, "finishedAt": datetime.datetime.now().astimezone().isoformat()})
            atomic_json(STATE_PATH, state)
    if proc.returncode != 0:
        raise RuntimeError("R454 command failed; retain outputs and logs")


def toolchain_fingerprint():
    return {"developerDirectory": subprocess.check_output(["xcode-select", "-p"], text=True).strip(),
        "swiftc": subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip(),
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
        "sdk": subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True).strip()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-manifest-sha256", required=True)
    parser.add_argument("--root-contract-sha256", required=True)
    parser.add_argument("command", choices=["freeze", "build"])
    parser.add_argument("--variant", choices=["debug"])
    args = parser.parse_args()
    inputs, contract, source_map, donor, resources = validate_inputs(args)
    if args.command == "build" and not args.variant:
        parser.error("build requires --variant debug")
    if args.command == "freeze" and args.variant:
        parser.error("--variant is valid only for the build command")
    verify_environment_is_idle()
    tools = ROOT / "tools/witch_native"
    fingerprint = {"sourceMapSHA256": inputs["sourceMapSHA256"], "inputManifestSHA256": args.input_manifest_sha256,
        "donorResourceMapSHA256": inputs["resourceDonor"]["resourceMapSHA256"],
        "protectedPBXSHA256": inputs["protectedProject"]["sha256"], "tools": inputs["tools"],
        "variants": inputs["variants"], "toolchain": toolchain_fingerprint()}
    key = canonical_sha(fingerprint)
    output_root = WORKSPACE_ROOT / key[:16]
    lock_path = BASE / "BUILD_R003.lock"
    with lock_path.open("a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        before = check_capacity(ROOT, "r454-" + args.command + ("-" + (args.variant or "") ), heavy=True,
            expected_bytes=MAX_OUTPUT, safety_bytes=SAFETY, minimum_remaining_bytes=FLOOR)
        if before["freeBytes"] < REQUIRED_START:
            raise RuntimeError("R454 requires at least 20 GB free before creating outputs")
        if args.command == "freeze":
            if STATE_PATH.exists() or output_root.exists():
                raise RuntimeError("R454 freeze slot already exists; preserve it and stop")
            initial_frozen = set(NATIVE.glob("qa_source_*"))
            initial_projects = set(NATIVE.glob("WitchGatheringQA_*.xcodeproj"))
            state = {"schema":"r454-native-build-state-r003-v1", "phase":"FREEZING", "inputKey":key,
                "fingerprint":fingerprint, "sourceMap":source_map, "sourceMapSHA256":inputs["sourceMapSHA256"],
                "protectedPBXSHA256":inputs["protectedProject"]["sha256"], "startedEpoch":time.time(),
                "beforeCapacity":before, "variants":{}, "commands":[], "install":False, "launch":False,
                "nativeBaseline":{"frozen":[str(p) for p in initial_frozen],"projects":[str(p) for p in initial_projects]}}
            atomic_json(STATE_PATH,state)
            WORKSPACE_ROOT.mkdir(parents=True, exist_ok=True)
            output_root.mkdir(parents=True)
            artifacts=(BASE,output_root)
            try:
                owned_run([sys.executable,str(tools/"make_xcode_project.py"),"--freeze","--reuse-resources-from",str(donor)],
                    BASE/"freeze_r003.log",PHASE_SECONDS,state,artifacts)
                new_frozen=set(NATIVE.glob("qa_source_*"))-initial_frozen
                new_projects=set(NATIVE.glob("WitchGatheringQA_*.xcodeproj"))-initial_projects
                if len(new_frozen)!=1 or len(new_projects)!=1:
                    raise RuntimeError("Freeze must create exactly one frozen source and one generated project")
                frozen=next(iter(new_frozen)); project=next(iter(new_projects))
                verify_preserved_products(inputs)
                if json.loads((frozen/"SOURCE_SHA256.json").read_text())!=source_map:
                    raise RuntimeError("Frozen source map mismatch")
                if json.loads((frozen/"RESOURCE_SHA256.json").read_text())!=resources:
                    raise RuntimeError("Frozen resource map differs from R445 donor")
                if sha(frozen/"RESOURCE_SHA256.json")!=inputs["resourceDonor"]["resourceMapSHA256"]:
                    raise RuntimeError("Frozen resource map byte hash differs from donor")
                scheme = project/"xcshareddata/xcschemes/WitchGathering.xcscheme"
                configure_storekit_scheme(scheme, contract, inputs)
                state.update(phase="FROZEN",frozen=str(frozen),project=str(project),workspace=str(output_root),
                    projectPlistSHA256=sha(project/"GameInfo.plist"),
                    generatedProjectPBXSHA256=sha(project/"project.pbxproj"),
                    generatedSchemeSHA256=sha(scheme),
                    elapsedSeconds=time.time()-state["startedEpoch"])
                if state["elapsedSeconds"] > PHASE_SECONDS or allocated_bytes((BASE, output_root, frozen, project)) > MAX_OUTPUT:
                    raise RuntimeError("Freeze phase exceeded its time or allocated-output limit")
                try:
                    state["afterFreezeCapacity"]=check_capacity(ROOT,"r454-freeze-after",
                        artifact_paths=(BASE,output_root,frozen,project),heavy=True,expected_bytes=0,
                        safety_bytes=SAFETY,minimum_remaining_bytes=FLOOR)
                except BaseException as capacity_error:
                    state.update(phase="FAILED_RETAINED",afterFreezeCapacityError=repr(capacity_error))
                    atomic_json(STATE_PATH,state)
                    raise
                atomic_json(STATE_PATH,state)
            except BaseException as error:
                state.update(phase="FAILED_RETAINED",error=repr(error),elapsedSeconds=time.time()-state["startedEpoch"])
                atomic_json(STATE_PATH,state); raise
            print(json.dumps({"phase":state["phase"],"frozen":state["frozen"],"project":state["project"],"workspace":state["workspace"]}))
            return
        if not STATE_PATH.is_file():
            raise RuntimeError("R454 requires the single prior freeze invocation")
        state=json.loads(STATE_PATH.read_text())
        if (state.get("schema") != "r454-native-build-state-r003-v1" or state.get("phase") not in {"FROZEN"} or state.get("inputKey")!=key
                or state.get("fingerprint")!=fingerprint or state.get("sourceMap")!=source_map
                or state.get("protectedPBXSHA256")!=inputs["protectedProject"]["sha256"]):
            raise RuntimeError("R454 frozen state is failed, incomplete, or bound to other inputs")
        if args.variant in state.get("variants",{}):
            raise RuntimeError("This R454 Debug variant already has a retained attempt; do not retry")
        if owned_elapsed(state) >= AGGREGATE_SECONDS:
            raise RuntimeError("R454 aggregate 10-minute budget expired")
        project=Path(state["project"]); frozen=Path(state["frozen"]); workspace=Path(state["workspace"])
        baseline=state.get("nativeBaseline",{})
        expected_frozen=set(NATIVE.glob("qa_source_*"))-set(map(Path,baseline.get("frozen",[])))
        expected_projects=set(NATIVE.glob("WitchGatheringQA_*.xcodeproj"))-set(map(Path,baseline.get("projects",[])))
        if (workspace!=output_root or len(expected_frozen)!=1 or len(expected_projects)!=1
                or frozen not in expected_frozen or project not in expected_projects
                or frozen.is_symlink() or project.is_symlink()
                or json.loads((frozen/"SOURCE_SHA256.json").read_text())!=source_map):
            raise RuntimeError("R454 freeze outputs differ from sealed source/workspace")
        project_pbx=project/"project.pbxproj"
        scheme=project/"xcshareddata/xcschemes/WitchGathering.xcscheme"
        if (sha(project_pbx)!=state.get("generatedProjectPBXSHA256")
                or sha(scheme)!=state.get("generatedSchemeSHA256")):
            raise RuntimeError("Generated project or shared scheme changed after freeze")
        plist_path=project/"GameInfo.plist"
        if sha(plist_path)!=state["projectPlistSHA256"]:
            raise RuntimeError("Generated Info plist was changed outside the runner")
        verify_preserved_products(inputs)
        variant=inputs["variants"][args.variant]
        info=plistlib.loads(plist_path.read_bytes())
        allowed_project_ids={"local.witch.autonomous.r1"}
        allowed_project_ids.update(row.get("bundleIdentifier") for row in state.get("variants",{}).values() if row.get("phase")=="PASS")
        if info.get("CFBundleIdentifier") not in allowed_project_ids:
            raise RuntimeError("Generated project Bundle ID is outside the prior sealed variant history")
        original_plist_sha=sha(plist_path)
        info["CFBundleIdentifier"]=variant["bundleIdentifier"]
        plist_path.write_bytes(plistlib.dumps(info,sort_keys=True))
        state["projectPlistSHA256"]=sha(plist_path); state["phase"]="BUILDING_"+args.variant.upper()
        atomic_json(STATE_PATH,state)
        artifacts=(BASE,workspace,frozen,project)
        command=["xcodebuild","build","-project",str(project),"-scheme","WitchGathering",
            "-destination","generic/platform=iOS Simulator","-derivedDataPath",str(workspace),
            "-configuration",variant["configuration"],"SWIFT_ACTIVE_COMPILATION_CONDITIONS="+" ".join(variant["flags"]),
            "PRODUCT_BUNDLE_IDENTIFIER="+variant["bundleIdentifier"],"CODE_SIGNING_ALLOWED=NO","ONLY_ACTIVE_ARCH=YES","-jobs","2"]
        variant_started = time.monotonic()
        try:
            owned_run(command,BASE/(args.variant+"_build.log"),PHASE_SECONDS,state,artifacts)
            app=workspace/"Build/Products"/(variant["configuration"]+"-iphonesimulator")/"WitchGathering.app"
            if not app.is_dir(): raise RuntimeError("R454 app product is missing")
            built=plistlib.loads((app/"Info.plist").read_bytes())
            if built.get("CFBundleIdentifier")!=variant["bundleIdentifier"]:
                raise RuntimeError("R454 built Bundle ID mismatch")
            exe=built.get("CFBundleExecutable")
            if not isinstance(exe,str) or not exe or "/" in exe: raise RuntimeError("Invalid CFBundleExecutable")
            actual_resources=resource_map(app,exe)
            if actual_resources!=resources or len(actual_resources)!=1922:
                raise RuntimeError("R454 built app resource path/hash map differs from donor")
            verify_preserved_products(inputs)
            verify_external_trees(inputs)
            if live_source_map()!=source_map or sha(PBX)!=inputs["protectedProject"]["sha256"]:
                raise RuntimeError("Source or protected PBX changed during build")
            variant_elapsed = time.monotonic() - variant_started
            if variant_elapsed > PHASE_SECONDS:
                raise RuntimeError("Variant build plus product verification exceeded 600 seconds")
            for previous in state["variants"].values():
                if previous.get("phase") == "PASS":
                    for path, digest in previous["productFiles"].items():
                        if sha(Path(path)) != digest:
                            raise RuntimeError("Prior successful variant product changed: " + path)
            products={str(p):sha(p) for p in sorted((workspace/"Build/Products").rglob("*")) if p.is_file() and not p.is_symlink()}
            state["variants"][args.variant]={"phase":"PASS","app":str(app),"bundleIdentifier":built["CFBundleIdentifier"],
                "executableSHA256":sha(app/exe),"infoPlistSHA256":sha(app/"Info.plist"),
                "resourceCount":len(actual_resources),"resourceMapSHA256":canonical_sha(actual_resources),
                "productFiles":products,"projectPlistBeforeSHA256":original_plist_sha,
                "projectPlistAfterSHA256":sha(plist_path),"install":False,"launch":False,
                "variantElapsedSeconds":variant_elapsed}
            state["phase"]="PASS_DEBUG_ONLY"
            state["finishedAt"]=datetime.datetime.now().astimezone().isoformat()
        except BaseException as error:
            state["variants"][args.variant]={"phase":"FAILED_RETAINED","error":repr(error)}
            state["phase"]="FAILED_RETAINED"; raise
        finally:
            state["elapsedSeconds"]=time.time()-state["startedEpoch"]
            state["ownedProcessSeconds"]=owned_elapsed(state)
            state["allocatedBytes"]=allocated_bytes(artifacts)
            try:
                state["afterCapacity"]=check_capacity(ROOT,"r454-build-after-"+args.variant,artifact_paths=artifacts,
                    heavy=True,expected_bytes=0,safety_bytes=SAFETY,minimum_remaining_bytes=FLOOR)
            except BaseException as capacity_error:
                state["afterCapacityError"]=repr(capacity_error)
                state["phase"]="FAILED_RETAINED"
            if state["allocatedBytes"]>MAX_OUTPUT or state["ownedProcessSeconds"]>AGGREGATE_SECONDS:
                state["phase"]="FAILED_RETAINED"; state["finalLimitError"]="Aggregate byte or time cap exceeded"
            atomic_json(STATE_PATH,state)
        if state["phase"] == "FAILED_RETAINED":
            raise RuntimeError("R454 final capacity/time closure failed; all outputs retained")
        print(json.dumps({"phase":state["phase"],"variant":args.variant,"elapsedSeconds":state["elapsedSeconds"],
            "allocatedBytes":state["allocatedBytes"],"resourceCount":state["variants"][args.variant]["resourceCount"]}))

if __name__=="__main__":
    main()

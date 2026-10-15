"""Bounded Root-owned R454 identity and Core save integration runner. No app install."""
import hashlib, json, os, re, shutil, signal, subprocess, time
from pathlib import Path

ROOT = Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
HERE = Path(__file__).absolute().parent
OUT = ROOT / 'native/build/ActiveIntegrationR454/core_r001'
MAX_BUILD = 700_000_000
MIN_FREE = 20_000_000_000
TESTS = ['LocalPurchaseDeliveryQAImporterR453Tests.swift', 'SaveRepositoryRecoveryR001Tests.swift', 'LocalPurchaseTransactionIdentityR454Tests.swift']

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def allocated(p): return sum(f.stat().st_blocks * 512 for f in p.rglob('*') if f.is_file() and not f.is_symlink())
def write(p, value):
    with p.open('x') as f: json.dump(value, f, indent=2); f.write('\n')

def main():
    assert not OUT.exists(), 'owned run directory already exists; preserve it'
    assert shutil.disk_usage(ROOT).free > MIN_FREE + MAX_BUILD
    fixture_root = ROOT / 'docs/production/current/qa_drafts/gacha_local_integration_r453/root_execution_r001/authority_fixture'
    fixture = fixture_root / 'delivery.json'
    fixture_manifest = json.loads((fixture_root / 'RESULT.json').read_text())
    assert sha(fixture) == fixture_manifest['deliverySHA256']
    source_root = ROOT / 'native/WitchGameCore'
    files = sorted(p for p in (source_root/'Sources').rglob('*') if p.is_file())
    files += [source_root/'Tests/WitchGameCoreTests'/name for name in TESTS]
    assert all(not p.is_symlink() and p.exists() for p in files)
    rows = [{'path':str(p.relative_to(ROOT)), 'sha256':sha(p), 'bytes':p.stat().st_size} for p in files]
    assert sum(row['bytes'] for row in rows) < 15_000_000
    package = OUT/'package'; scratch = OUT/'scratch'
    package.mkdir(parents=True); scratch.mkdir()
    for p in files:
        dest=package/p.relative_to(source_root); dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(p,dest)
    (package/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "WitchGameCore", platforms: [.macOS(.v14)], targets: [
    .target(name: "WitchGameCore", resources: [.process("Resources")]),
    .testTarget(name: "WitchGameCoreTests", dependencies: ["WitchGameCore"])
])
''')
    for name in ['cache','config','security','tmp','build']: (scratch/name).mkdir()
    env = dict(os.environ)
    env.update(TMPDIR=str(scratch/'tmp'), WITCH_R453_DELIVERY_FIXTURE=str(fixture),
               WITCH_R453_DELIVERY_FIXTURE_SHA256=sha(fixture))
    command=['swift','test','--package-path',str(package),'--scratch-path',str(scratch/'build'),
             '--cache-path',str(scratch/'cache'),'--config-path',str(scratch/'config'),
             '--security-path',str(scratch/'security'),'--jobs','2',
             '--filter','LocalPurchaseDeliveryQAImporterR453Tests|SaveRepositoryRecoveryR001Tests|LocalPurchaseTransactionIdentityR454Tests']
    start=time.monotonic(); log=HERE/'swift_test.log'
    preflight={'status':'SEALED_BEFORE_EXECUTION','inputs':rows,'fixtureSHA256':sha(fixture),
               'freeBytesBefore':shutil.disk_usage(ROOT).free,'command':command,
               'maxSeconds':300,'maxBuildBytes':MAX_BUILD,'minimumFreeBytes':MIN_FREE,
               'runnerSHA256':sha(Path(__file__))}
    write(HERE/'SWIFT_INPUTS.json',preflight)
    hold=None
    with log.open('xb') as out:
        process=subprocess.Popen(command,cwd=ROOT,env=env,stdout=out,stderr=subprocess.STDOUT,start_new_session=True)
        while process.poll() is None:
            if time.monotonic()-start>300: hold='time limit'
            if shutil.disk_usage(ROOT).free<MIN_FREE: hold='free space reserve'
            if allocated(OUT)>MAX_BUILD: hold='allocated build limit'
            if log.stat().st_size>10_000_000: hold='log size limit'
            if hold:
                os.killpg(process.pid,signal.SIGTERM)
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=5)
                break
            time.sleep(1)
    output=log.read_text(errors='replace')
    cases=re.findall(r"Test Case '-\[WitchGameCoreTests\.([^ ]+) ([^\]]+)\]' (passed|failed|skipped)",output)
    unchanged=all(sha(ROOT/r['path'])==r['sha256'] for r in rows)
    result={'status':'PASS' if process.returncode==0 and cases and all(c[2]=='passed' for c in cases) and unchanged and not hold else 'FAIL_OR_INCOMPLETE',
            'exitCode':process.returncode,'hold':hold,'elapsedSeconds':time.monotonic()-start,
            'testCases':[{'suite':s,'test':t,'result':v} for s,t,v in cases],
            'inputFilesUnchanged':unchanged,'allocatedBuildBytes':allocated(OUT),
            'freeBytesAfter':shutil.disk_usage(ROOT).free,'logSHA256':sha(log),
            'scope':'isolated Core fixture-to-save boundary and save regressions; not StoreKit runtime or Apple authorization'}
    write(HERE/'SWIFT_RESULT.json',result)
    print(json.dumps(result,indent=2))
    return 0 if result['status']=='PASS' else 1

if __name__=='__main__': raise SystemExit(main())

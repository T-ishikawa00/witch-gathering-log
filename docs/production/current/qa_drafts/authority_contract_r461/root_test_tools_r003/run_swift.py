"""Root-owned bounded R461 candidate and existing purchase/save regression run."""
import hashlib, json, os, re, shutil, signal, subprocess, time
from pathlib import Path

ROOT = Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
BASE = ROOT / 'docs/production/current/qa_drafts/authority_contract_r461'
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'native/build/ActiveIntegrationR461/core_r002'
MAX_BUILD, MIN_FREE, SECONDS = 700_000_000, 20_000_000_000, 300
TESTS = ['LocalPurchaseDeliveryQAImporterR453Tests.swift', 'SaveRepositoryRecoveryR001Tests.swift',
         'LocalPurchaseTransactionIdentityR454Tests.swift']

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def allocated(p): return sum(f.stat().st_blocks * 512 for f in p.rglob('*') if f.is_file() and not f.is_symlink())
def write(p, value):
    with p.open('x') as f: json.dump(value, f, indent=2); f.write('\n')

def main():
    assert not OUT.exists(), 'preserve prior run'
    assert shutil.disk_usage(ROOT).free > MIN_FREE + MAX_BUILD
    fixture = Path(os.environ['WITCH_R461_EXCHANGE_FIXTURE_PATH']).resolve(strict=True)
    fixture_sha = os.environ['WITCH_R461_EXCHANGE_FIXTURE_SHA256']
    assert fixture.is_relative_to(BASE) and not fixture.is_symlink() and sha(fixture) == fixture_sha
    legacy = ROOT / 'docs/production/current/qa_drafts/gacha_local_integration_r453/root_execution_r001/authority_fixture/delivery.json'
    legacy_receipt = json.loads((legacy.parent/'RESULT.json').read_text())
    assert sha(legacy) == legacy_receipt['deliverySHA256']
    source_root = ROOT / 'native/WitchGameCore'
    candidate = BASE / 'swift_candidate_r002'
    sources = [(p, p.relative_to(source_root)) for p in sorted((source_root/'Sources').rglob('*')) if p.is_file()]
    sources += [(source_root/'Tests/WitchGameCoreTests'/name, Path('Tests/WitchGameCoreTests')/name) for name in TESTS]
    sources += [(candidate/'AuthorityClientContractR461.swift', Path('Sources/WitchGameCore/AuthorityClientContractR461.swift')),
                (BASE/'root_candidate_r005/swift/AuthorityClientContractR461Tests.swift', Path('Tests/WitchGameCoreTests/AuthorityClientContractR461Tests.swift'))]
    assert len({str(dst) for _, dst in sources}) == len(sources)
    assert all(p.is_file() and not p.is_symlink() for p, _ in sources)
    rows = [{'path': str(p.relative_to(ROOT)), 'destination': str(dst), 'sha256': sha(p), 'bytes': p.stat().st_size} for p, dst in sources]
    assert sum(r['bytes'] for r in rows) < 15_000_000
    package, scratch = OUT/'package', OUT/'scratch'
    package.mkdir(parents=True); scratch.mkdir()
    for p, dst in sources:
        target=package/dst; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(p,target)
    (package/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "WitchGameCore", platforms: [.macOS(.v14)], targets: [
    .target(name: "WitchGameCore", resources: [.process("Resources")]),
    .testTarget(name: "WitchGameCoreTests", dependencies: ["WitchGameCore"])
])
''')
    for name in ['cache','config','security','tmp','build']: (scratch/name).mkdir()
    env=dict(os.environ)
    env.update(TMPDIR=str(scratch/'tmp'), WITCH_R453_DELIVERY_FIXTURE=str(legacy),
               WITCH_R453_DELIVERY_FIXTURE_SHA256=sha(legacy),
               WITCH_R461_CROSS_LANGUAGE_FIXTURE_REQUIRED='1',
               WITCH_R461_EXCHANGE_FIXTURE_PATH=str(fixture), WITCH_R461_EXCHANGE_FIXTURE_SHA256=fixture_sha)
    command=['swift','test','--package-path',str(package),'--scratch-path',str(scratch/'build'),
             '--cache-path',str(scratch/'cache'),'--config-path',str(scratch/'config'),
             '--security-path',str(scratch/'security'),'--jobs','2',
             '--filter','LocalPurchaseDeliveryQAImporterR453Tests|SaveRepositoryRecoveryR001Tests|LocalPurchaseTransactionIdentityR454Tests|AuthorityClientContractR461Tests']
    log=HERE/'swift_test.log'
    write(HERE/'INPUTS.json', {'status':'SEALED_BEFORE_EXECUTION','inputs':rows,'runnerSHA256':sha(Path(__file__)),
        'legacyFixtureSHA256':sha(legacy),'crossLanguageFixtureSHA256':fixture_sha,
        'crossLanguageFixturePath':str(fixture),'command':command,'freeBytesBefore':shutil.disk_usage(ROOT).free,
        'maxSeconds':SECONDS,'maxBuildBytes':MAX_BUILD,'minimumFreeBytes':MIN_FREE})
    start=time.monotonic(); hold=None
    with log.open('xb') as output:
        process=subprocess.Popen(command,cwd=ROOT,env=env,stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
        while process.poll() is None:
            if time.monotonic()-start>SECONDS: hold='time limit'
            if shutil.disk_usage(ROOT).free<MIN_FREE: hold='free space reserve'
            if allocated(OUT)>MAX_BUILD: hold='allocated build limit'
            if log.stat().st_size>10_000_000: hold='log limit'
            if hold:
                os.killpg(process.pid,signal.SIGTERM)
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=5)
                break
            time.sleep(1)
    cases=re.findall(r"Test Case '-\[WitchGameCoreTests\.([^ ]+) ([^\]]+)\]' (passed|failed|skipped)",log.read_text(errors='replace'))
    unchanged=all(sha(ROOT/r['path'])==r['sha256'] for r in rows) and sha(fixture)==fixture_sha
    result={'status':'PASS' if process.returncode==0 and cases and all(c[2]=='passed' for c in cases) and unchanged and not hold else 'FAIL_OR_INCOMPLETE',
        'exitCode':process.returncode,'hold':hold,'elapsedSeconds':time.monotonic()-start,
        'testCases':[{'suite':s,'test':t,'result':v} for s,t,v in cases], 'inputFilesUnchanged':unchanged,
        'allocatedBuildBytes':allocated(OUT),'freeBytesAfter':shutil.disk_usage(ROOT).free,'logSHA256':sha(log),
        'scope':'Candidate protocol plus existing isolated purchase/save regressions; synthetic cross-language fixture; no app, network, Apple authorization or production grant'}
    write(HERE/'RESULT.json',result)
    print(json.dumps({k:v for k,v in result.items() if k!='testCases'},indent=2)); print('testCases',len(cases))
    return 0 if result['status']=='PASS' else 1

if __name__=='__main__': raise SystemExit(main())

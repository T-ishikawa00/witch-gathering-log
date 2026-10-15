"""Bounded candidate-overlay Python regression and synthetic signed fixture run."""
from pathlib import Path
import hashlib,json,os,re,shutil,signal,subprocess,time
ROOT=Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
HERE=Path(__file__).resolve().parent
CANDIDATE=HERE.parent/'root_candidate_r004/python'
OUT=ROOT/'native/build/ActiveIntegrationR461/python_r002'
PYTHON=ROOT/'tools/witch_purchase_authority/.venv_signed_audit_r001/bin/python'

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,a):
    with p.open('x') as f:json.dump(a,f,indent=2);f.write('\n')
def allocated_bytes():
    total=0
    for parent,_,files in os.walk(OUT):
        for name in files:
            p=Path(parent)/name
            try:
                if not p.is_symlink():total+=p.stat().st_blocks*512
            except FileNotFoundError:pass
    return total
def bounded(command,cwd,env,log,seconds):
    started=time.monotonic()
    with log.open('xb') as f:
        process=subprocess.Popen(command,cwd=cwd,env=env,stdout=f,stderr=subprocess.STDOUT,start_new_session=True)
        while process.poll() is None:
            allocated=allocated_bytes()
            if (time.monotonic()-started>seconds or allocated>100_000_000 or
                shutil.disk_usage(ROOT).free<20_000_000_000 or log.stat().st_size>10_000_000):
                os.killpg(process.pid,signal.SIGTERM)
                try:process.wait(timeout=5)
                except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=5)
                return -1
            time.sleep(.2)
    return process.returncode
def main():
    assert not OUT.exists() and shutil.disk_usage(ROOT).free>20_100_000_000
    live=ROOT/'tools/witch_purchase_authority'
    files={str(p.relative_to(live)):p for p in live.glob('*.py')}
    files.update({str(p.relative_to(live)):p for p in (live/'tests').glob('*.py')})
    files['local_service_r461.py']=CANDIDATE/'local_service_r461.py'
    files['tests/test_local_service_r461.py']=CANDIDATE/'tests/test_local_service_r461.py'
    rows=[{'path':str(p.relative_to(ROOT)),'destination':r,'sha256':sha(p),'bytes':p.stat().st_size} for r,p in sorted(files.items())]
    assert sum(r['bytes'] for r in rows)<10_000_000
    stage=OUT/'package'; package=stage/'tools/witch_purchase_authority'; package.mkdir(parents=True)
    (stage/'tools/__init__.py').write_text('')
    for r,p in files.items():
        dest=package/r;dest.parent.mkdir(exist_ok=True);shutil.copy2(p,dest)
    (OUT/'tmp').mkdir()
    env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',TMPDIR=str(OUT/'tmp'),
             PYTHONPATH=os.pathsep.join(map(str,[stage,package,package/'tests'])))
    command=[str(PYTHON),'-B','-m','unittest','discover','-s',str(package/'tests'),'-p','test_local_service_r461.py','-v']
    write(HERE/'PYTHON_INPUTS.json',{'status':'SEALED_BEFORE_EXECUTION','inputs':rows,
        'runnerSHA256':sha(Path(__file__)),'exporterSHA256':sha(HERE/'export_signed_exchange.py'),
        'command':command,'maxSeconds':180,'maximumAllocatedBytes':100_000_000,
        'freeBytesBefore':shutil.disk_usage(ROOT).free})
    start=time.monotonic();log=HERE/'python_test.log'
    exit_code=bounded(command,stage,env,log,180)
    output=log.read_text(errors='replace'); count=re.search(r'Ran (\d+) tests?',output)
    unchanged=all(sha(ROOT/r['path'])==r['sha256'] for r in rows)
    result={'status':'PASS' if exit_code==0 and count and unchanged else 'FAIL_OR_INCOMPLETE',
        'exitCode':exit_code,'testMethodExecutions':int(count.group(1)) if count else None,
        'elapsedSeconds':time.monotonic()-start,'inputsUnchanged':unchanged,'logSHA256':sha(log),
        'warningLines':sum('Warning:' in line for line in output.splitlines()),
        'freeBytesAfter':shutil.disk_usage(ROOT).free,'scope':'candidate-overlay service and existing ledger/crypto tests'}
    write(HERE/'PYTHON_RESULT.json',result);print(json.dumps(result))
    if result['status']!='PASS':return 1
    exchange=bounded([str(PYTHON),'-B',str(HERE/'export_signed_exchange.py')],stage,env,HERE/'signed_exchange.log',60)
    print(json.dumps({'signedExchangeExitCode':exchange}))
    return exchange

if __name__=='__main__':raise SystemExit(main())

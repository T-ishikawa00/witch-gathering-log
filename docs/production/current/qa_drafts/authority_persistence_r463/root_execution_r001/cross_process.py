from pathlib import Path
import datetime,hashlib,json,os,shutil,subprocess,time
ROOT=Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
HERE=Path(__file__).resolve().parent
OUT=ROOT/'native/build/ActiveIntegrationR463/process_rehearsal_r001'
BINARY=ROOT/'native/build/ActiveIntegrationR463/core_r001/scratch/build/debug/AuthorityStoreProbeR463'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    assert not OUT.exists() and BINARY.is_file()
    assert json.loads((HERE/'RESULT.json').read_text())['status']=='PASS'
    assert shutil.disk_usage(ROOT).free>20_050_000_000
    OUT.mkdir(parents=True,mode=0o700)
    rehearsal=OUT/'r459-sandbox-rehearsal';rehearsal.mkdir(mode=0o700)
    marker=rehearsal/'R459_LOCAL_REHEARSAL_ONLY'
    with marker.open('x') as f:f.write('NOT_AUTHORIZED_FOR_PRODUCTION\n')
    marker.chmod(0o600)
    start=time.monotonic();rows=[];checks={};children=[]
    def read_result(p,args):
        stdout,stderr=p.communicate(timeout=15)
        row={'arguments':args,'pid':p.pid,'exitCode':p.returncode,'stdout':stdout,'stderr':stderr}
        rows.append(row);assert p.returncode==0,row
        return json.loads(stdout)
    def invoke(*args):
        cmd=[str(BINARY),str(rehearsal),*args]
        p=subprocess.Popen(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE);children.append(p)
        return read_result(p,list(args))
    try:
        written=invoke('write');checks['firstSave']=written['saved'] is True
        cold=invoke('read');checks['newProcessColdRead']=cold['pendingEqual'] and cold['revision']==5 and cold['pid']!=written['pid']
        barrier=str(time.time()+2)
        racers=[]
        for rev in ('6','7'):
            args=['race',rev,barrier]
            p=subprocess.Popen([str(BINARY),str(rehearsal),*args],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE);children.append(p);racers.append((p,args))
        race_results=[read_result(p,args) for p,args in racers]
        checks['exactlyOneProcessCASWinner']=sum(r['saved'] for r in race_results)==1 and len({r['pid'] for r in race_results})==2
        winner=next(r['proposedRevision'] for r in race_results if r['saved'])
        after=invoke('read');checks['winningRevisionDurable']=after['revision']==winner and after['pendingEqual']
        refund=invoke('refund');checks['refundSaved']=refund['saved']
        stale=invoke('stale');checks['staleSuccessRejectedAfterProcessRestart']=stale['acceptedStale'] is False and stale['revision']==10 and stale['debt']==2
        checks['withinTimeAndSpace']=time.monotonic()-start<60 and sum(p.stat().st_size for p in OUT.rglob('*') if p.is_file())<50_000_000
        result={'status':'PASS' if all(checks.values()) else 'FAIL','checks':checks,'binarySHA256':sha(BINARY),'sourceSHA256':sha(HERE/'Probe.swift'),'rows':rows,'elapsedSeconds':time.monotonic()-start,'scope':'Synthetic isolated local persistence across independent executable processes and competing writers; no game save, actualpayment or powerloss test','output':str(OUT),'freeBytesAfter':shutil.disk_usage(ROOT).free}
    except BaseException as e:
        result={'status':'FAIL','errorType':type(e).__name__,'message':str(e),'rows':rows,'checks':checks}
    finally:
        for p in children:
            if p.poll() is None:
                p.terminate()
                try:p.wait(timeout=3)
                except subprocess.TimeoutExpired:p.kill();p.wait(timeout=3)
    with (HERE/'PROCESS_RESULT.json').open('x') as f:json.dump(result,f,indent=2);f.write('\n')
    print(json.dumps({k:v for k,v in result.items() if k!='rows'},indent=2))
    return 0 if result['status']=='PASS' else 1
if __name__=='__main__':raise SystemExit(main())

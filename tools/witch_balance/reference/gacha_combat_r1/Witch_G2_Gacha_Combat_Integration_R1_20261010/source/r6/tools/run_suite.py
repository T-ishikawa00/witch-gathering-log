from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import subprocess,sys,json
from run_validation import jobs,ROOT

def execute(j):
    if j['id']=='legacy_replay_protect6':return
    log=ROOT/'results'/('run_'+j['id']+'.txt')
    with log.open('w') as f:
        p=subprocess.run([sys.executable,str(ROOT/'tools/run_validation.py'),'--job',j['id']],stdout=f,stderr=subprocess.STDOUT)
    if p.returncode:raise RuntimeError(j['id']+': '+str(p.returncode))
    print('DONE',j['id'],flush=True)

if __name__=='__main__':
    with ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(execute,jobs()))
    print('ALL_COMPARISON_JOBS_FINISHED',flush=True)

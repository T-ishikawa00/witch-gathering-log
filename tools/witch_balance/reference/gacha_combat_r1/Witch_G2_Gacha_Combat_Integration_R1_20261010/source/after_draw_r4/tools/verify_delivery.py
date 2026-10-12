"""Verify delivered bytes, copied inputs, prior/new tests and recorded aggregates.
Read-only; no network, install, Mac project access, or regeneration of evidence.
"""
from pathlib import Path
from hashlib import sha256
import subprocess,sys,os,json,collections
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
def main():
    manifest=json.loads((ROOT/'MANIFEST.json').read_text())
    for row in manifest['files']:
        p=(ROOT/row['path']).resolve()
        if not p.is_relative_to(ROOT) or not p.is_file():raise RuntimeError('missing/unsafe file:'+row['path'])
        b=p.read_bytes()
        if len(b)!=row['bytes'] or sha256(b).hexdigest()!=row['sha256']:raise RuntimeError('changed:'+row['path'])
    print('Package hashes:',len(manifest['files']),'PASS',flush=True)
    env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1')
    for rel in ['source/research_r3/tools/test_compare.py','source/commerce_r2/tools/test_commerce.py','tools/test_after_draw.py']:
        r=subprocess.run([sys.executable,'-B',str(ROOT/rel)],cwd=ROOT,env=env,check=False)
        if r.returncode:raise RuntimeError('tests failed:'+rel)
    from run_study import aggregate
    grouped=collections.defaultdict(list)
    for line in (ROOT/'results/study/SESSION_ROWS.jsonl').read_text().splitlines():
        d=json.loads(line);grouped[f'{d["scenario"]}|{d["profile"]}|{d["candidate"][0]}'].append(d)
    expected=json.loads((ROOT/'results/study/ANALYSIS_R4.json').read_text())['primary_summaries']
    for k,v in grouped.items():
        if aggregate(v)!=expected[k]:raise RuntimeError('aggregate mismatch:'+k)
    print('Primary session rows re-aggregate:',len(grouped),'cells PASS',flush=True)
    summary=json.loads((ROOT/'results/VALIDATION_SUMMARY_R4.json').read_text())
    for rel,d in summary['implementation_sha256'].items():
        if sha256((ROOT/rel).read_bytes()).hexdigest()!=d:raise RuntimeError('implementation binding mismatch:'+rel)
    print('PASS. These checks do not certify gameplay balance, real users or real devices.')
if __name__=='__main__':
    try:main()
    except (RuntimeError,OSError,ValueError) as e:print('FAIL:',e,file=sys.stderr);sys.exit(1)

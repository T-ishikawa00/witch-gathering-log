"""Read-only hash and frozen golden replay checks; no network or game writes."""
from pathlib import Path
import hashlib,json,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
def main():
    manifest=json.loads((ROOT/'PACKAGE_MANIFEST.json').read_text())
    for r in manifest['files']:
        p=(ROOT/r['path']).resolve()
        if not p.is_relative_to(ROOT) or not p.is_file():raise RuntimeError('missing/unsafe: '+r['path'])
        b=p.read_bytes()
        if len(b)!=r['bytes'] or hashlib.sha256(b).hexdigest()!=r['sha256']:raise RuntimeError('mismatch: '+r['path'])
    source=json.loads((ROOT/'data/SOURCE_FILES.json').read_text())
    for r in source:
        if hashlib.sha256((ROOT/r['path']).read_bytes()).hexdigest()!=r['sha256']:raise RuntimeError('source changed: '+r['path'])
    study=json.loads((ROOT/'results/main/EXPERIMENT_RESULTS.json').read_text())
    for name in ('bridge.py','run_experiments.py'):
        if hashlib.sha256((ROOT/'tools'/name).read_bytes()).hexdigest()!=study['code_sha256'][name]:raise RuntimeError('calculation source differs: '+name)
    from bridge import g,boss_variant,FinalBattleR6
    from fixtures_r6 import make_state,upgrade
    for seed in (100049,100069):
        for side,state in [('before',make_state()),('after',upgrade(make_state()))]:
            actual=FinalBattleR6(state.loadout(),boss_variant('redistribute_pause'),seed,record=True,decision_trace=True).run()
            expected=json.loads((ROOT/f'source/r6/results/R6B_KNOWN_{seed}_{side}.json').read_text())
            if actual['log_sha256']!=expected['log_sha256'] or actual['input_fingerprint']!=expected['input_fingerprint']:raise RuntimeError('golden mismatch')
    print(json.dumps({'bundle_files_hashed':len(manifest['files']),'source_files_hashed':len(source),'old_R6_golden_pairs':4,'main_calculation_code_unchanged':True,'status':'PASS'},ensure_ascii=False))
if __name__=='__main__':main()

"""Recompute saved residual/known pairs in a fresh output directory."""
from bootstrap import *
from fixtures_r6 import *
from selected_final import FinalBattleR6
import argparse,json,hashlib,copy

def main(output):
    output.mkdir(parents=True,exist_ok=False)
    checks=[]
    for seed in [100049,100069]:
        s=make_state();t=upgrade(s)
        for side,state in [('before',s),('after',t)]:
            got=FinalBattleR6(state.loadout(),boss_variant('redistribute_pause'),seed,record=True,decision_trace=True).run()
            expected=json.loads((ROOT/'results'/f'R6B_KNOWN_{seed}_{side}.json').read_text())
            okay=got['log_sha256']==expected['log_sha256'] and got['input_fingerprint']==expected['input_fingerprint']
            checks.append({'seed':seed,'side':side,'log_and_input_match':okay,'outcome':got['outcome']})
            if not okay:raise AssertionError(checks[-1])
    lock=json.loads((ROOT/'data/SOURCE_LOCK_R6.json').read_text());bad=[]
    for f in lock['vendor_files']:
        if hashlib.sha256((ROOT/f['path']).read_bytes()).hexdigest()!=f['sha256']:bad.append(f['path'])
    if bad:raise AssertionError(bad)
    result={'known_case_rechecks':checks,'vendor_hash_checked':len(lock['vendor_files']),'vendor_mismatch':bad,'status':'PASS'}
    (output/'SMOKE_REPRODUCTION.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print(json.dumps(result,ensure_ascii=False))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',required=True,type=Path);args=p.parse_args();main(args.output)

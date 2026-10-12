"""Read-only integrity check of the delivered package (not gameplay validation)."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1]

def main():
    meta=json.loads((ROOT/'PACKAGE_MANIFEST.json').read_text())
    bad=[]
    for f in meta['files']:
        p=ROOT/f['path']
        if not p.is_file():bad.append({'path':f['path'],'issue':'missing'});continue
        data=p.read_bytes()
        if len(data)!=f['bytes'] or hashlib.sha256(data).hexdigest()!=f['sha256']:
            bad.append({'path':f['path'],'issue':'size_or_hash_mismatch'})
    print(json.dumps({'checked':len(meta['files']),'mismatches':bad,'status':'PASS' if not bad else 'FAIL'},ensure_ascii=False))
    if bad:raise SystemExit(1)
if __name__=='__main__':main()

"""Verify immutable delivered files without network or third-party packages."""
from pathlib import Path
import hashlib,json,sys,zipfile
ROOT=Path(__file__).resolve().parents[1]
def main():
    manifest=json.loads((ROOT/'PACKAGE_MANIFEST.json').read_text())
    failures=[]
    for row in manifest['files']:
        p=ROOT/row['path']
        if not p.is_file(): failures.append({'path':row['path'],'error':'missing'});continue
        data=p.read_bytes()
        if len(data)!=row['bytes'] or hashlib.sha256(data).hexdigest()!=row['sha256']:
            failures.append({'path':row['path'],'error':'byte/hash mismatch'})
        if p.suffix=='.zip':
            with zipfile.ZipFile(p) as z:
                bad=z.testzip()
                if bad:failures.append({'path':row['path'],'error':'ZIP CRC '+bad})
    out={'files_checked':len(manifest['files']),'failures':failures,'result':'PASS' if not failures else 'FAIL','scope':'byte integrity only; not gameplay acceptance'}
    print(json.dumps(out,ensure_ascii=False,indent=2))
    return bool(failures)
if __name__=='__main__':sys.exit(main())

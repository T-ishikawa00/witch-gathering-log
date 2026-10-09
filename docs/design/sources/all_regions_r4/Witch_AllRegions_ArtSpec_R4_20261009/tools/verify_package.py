"""Read-only integrity check after extracting this package."""
from pathlib import Path
from hashlib import sha256
import json
import sys
root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'PACKAGE_SHA256.json').read_text())
errors=[]
for item in manifest['files']:
    p=(root/item['path']).resolve()
    if not p.is_relative_to(root.resolve()):
        errors.append(item['path']+': unsafe path');continue
    if not p.is_file():
        errors.append(item['path']+': missing');continue
    if p.stat().st_size!=item['bytes'] or sha256(p.read_bytes()).hexdigest()!=item['sha256']:
        errors.append(item['path']+': checksum mismatch')
print(json.dumps({'checked':len(manifest['files']),'errors':errors},ensure_ascii=False,indent=2))
sys.exit(bool(errors))

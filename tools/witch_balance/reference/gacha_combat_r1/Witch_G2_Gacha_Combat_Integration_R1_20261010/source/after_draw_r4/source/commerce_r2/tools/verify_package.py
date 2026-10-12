"""Read-only byte verification; not a security signature or gameplay acceptance."""
from pathlib import Path
from hashlib import sha256
import json,sys
P=Path(__file__).resolve().parents[1]
def verify():
 m=json.loads((P/'MANIFEST.json').read_text())
 for r in m['files']:
  f=(P/r['path']).resolve()
  if not f.is_relative_to(P):raise ValueError('unsafe path')
  b=f.read_bytes()
  if len(b)!=r['bytes'] or sha256(b).hexdigest()!=r['sha256']:raise ValueError('mismatch '+r['path'])
 print('Package file hashes PASS:',len(m['files']))
 s=json.loads((P/'data/SOURCE_COVERAGE.json').read_text())
 for r in s['originals']:
  if sha256((P/r['path']).read_bytes()).hexdigest()!=r['sha256']:raise ValueError('source mismatch')
 print('Preserved original files PASS:',len(s['originals']))
 print('R1-R6 originals absent; live payments/combat/device/art are not validated here.')
if __name__=='__main__':
 try:verify()
 except (OSError,ValueError,KeyError) as e:print('FAIL',e,file=sys.stderr);sys.exit(1)

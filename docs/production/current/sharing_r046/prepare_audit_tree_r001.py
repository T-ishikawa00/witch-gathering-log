"""Build a reviewed audit tree with a separate index. Does not create refs or push."""
from pathlib import Path
import os, subprocess, json, hashlib, datetime, re, posixpath

R=Path(__file__).resolve().parents[4]
D=Path(__file__).resolve().parent
BASE='497549e9339431b5680eaa398fef16ff1b81f117'
assert R.parent.name=='witch-03to05-r1'
def git(*args,env=None,data=None):
    return subprocess.check_output(['git',*args],cwd=R,env=env,input=data)
sha=lambda b:hashlib.sha256(b).hexdigest()
head=git('rev-parse','HEAD').decode().strip()
assert head!='a63ab3a56ba66183f0fa6722ef6eab635c6454b7','save local R046 checkpoint first'
assert not git('diff','--cached','--name-only').strip(),'real index must be empty'
original_status=git('status','--porcelain=v1')
selection=json.loads((D/'SELECTION_DRAFT_R001.json').read_text())
assert selection['sourceCheckpoint']==head and not selection['secretScanFindings']
index=D/'AUDIT_R046.index'
manifest_path=D/'SHARED_PAYLOAD_MANIFEST_R002.json'
receipt_path=D/'AUDIT_TREE_R001.json'
assert not any(p.exists() for p in [index,manifest_path,receipt_path])
env={**os.environ,'GIT_INDEX_FILE':str(index)}
git('read-tree',BASE,env=env)
rows=[]
for row in selection['files']:
    source=row['path']; target='README.md' if source.endswith('/sharing_r046/AUDIT_README_R001.md') else source
    data=(R/source).read_bytes()
    assert len(data)==row['size'] and sha(data)==row['sha256'],source
    mode='100644'
    old=git('ls-tree','HEAD','--',source).decode().split()
    if old:mode=old[0]
    assert mode in ['100644','100755']
    oid=git('hash-object','-w','--stdin',data=data).decode().strip()
    git('update-index','--add','--cacheinfo',mode+','+oid+','+target,env=env)
    rows.append({**row,'sourcePath':source,'path':target,'gitBlob':oid,'mode':mode})
assert len(rows)==len({r['path'] for r in rows})
manifest={'schema':'r046-shared-payload-v2','at':datetime.datetime.now().astimezone().isoformat(),
 'localDevelopmentCheckpoint':head,'remoteBaseMain':BASE,'intendedBranch':'codex/audit-03to05-20261012-r046',
 'fileCountExcludingThisManifest':len(rows),'bytesExcludingThisManifest':sum(r['size'] for r in rows),
 'files':rows,'excludes':'large generated art/audio/video, builds, caches, full development history, raw transaction logs',
 'selfReference':'This manifest is excluded from its own hash list; its blob/hash is pinned in the local audit-tree receipt.',
 'sourceMapping':'README.md comes from AUDIT_README_R001.md; remaining selected paths keep their repo-relative path.',
 'authority':'User-authorized single private audit/checkpoint push only. No force push, main rewrite, privacy changes, release or real charges.',
 'secretPatternFindings':selection['secretScanFindings'],'formalCompletion':False}
manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
mp=manifest_path.relative_to(R).as_posix();mb=manifest_path.read_bytes();mo=git('hash-object','-w','--stdin',data=mb).decode().strip()
git('update-index','--add','--cacheinfo','100644,'+mo+','+mp,env=env)
tree=git('write-tree',env=env).decode().strip()
root_readme=git('show',tree+':README.md').decode()
links=[]
for link in re.findall(r'\]\(([^)]+)\)',root_readme):
    if '://' in link or link.startswith('#'):continue
    target=posixpath.normpath(link.split('#')[0])
    assert not target.startswith('../') and not target.startswith('/')
    git('cat-file','-e',tree+':'+target)
    links.append(target)
for row in rows:
    data=git('show',tree+':'+row['path'])
    assert sha(data)==row['sha256'] and len(data)==row['size'],row['path']
changes=git('diff-tree','-r','--no-commit-id','--name-status',BASE,tree).decode().splitlines()
assert all(not x.startswith('D\t') for x in changes),'snapshot must not delete inherited files'
assert git('rev-parse','HEAD').decode().strip()==head and git('status','--porcelain=v1')==original_status
receipt={'status':'TREE_PREPARED_NOT_COMMITTED_NOT_PUSHED','at':datetime.datetime.now().astimezone().isoformat(),
 'tree':tree,'parent':BASE,'developmentHEAD':head,'isolatedIndex':str(index),'manifest':mp,'manifestSHA256':sha(mb),
 'manifestBlob':mo,'selectedFilesIncludingManifest':len(rows)+1,'selectedBytesIncludingManifest':sum(r['size'] for r in rows)+len(mb),
 'rootReadmeLinkCount':len(links),'rootReadmeLinksAllResolve':True,'changedPaths':changes,
 'realIndexUnchanged':True,'developmentHEADUnchanged':True,'workingStatusUnchanged':True,'remoteWrite':False}
receipt_path.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:receipt[k] for k in ['tree','selectedFilesIncludingManifest','selectedBytesIncludingManifest','rootReadmeLinkCount','status']}))

"""Build exact allowlisted audit tree via a separate index. Never push or change HEAD."""
from pathlib import Path
import os,subprocess,json,hashlib,re,posixpath,datetime,stat
R=Path(__file__).resolve().parents[4];D=Path(__file__).resolve().parent
S=json.loads((D/'local_only/SELECTION_REVIEWED_R004.json').read_text());HEAD=S['sourceCheckpoint'];BASE=S['parent']
def git(*a,data=None,env=None):return subprocess.check_output(['git',*a],cwd=R,input=data,env=env)
sha=lambda b:hashlib.sha256(b).hexdigest()
assert git('rev-parse','HEAD').decode().strip()==HEAD
assert not git('diff','--cached','--name-only').strip()
state=git('status','--porcelain=v1','--untracked-files=no');index0=sha((Path(git('rev-parse','--git-path','index').decode().strip())).read_bytes())
rows={r['path']:dict(r) for r in S['files']}
# New audit artifacts only. No local-only snapshots, temporary indexes, or receipt inventories.
for name in ['INDEX.md','AUDIT_README_R001.md','GALLERY.md','GALLERY_MANIFEST_R001.json','LOCAL_ONLY_EVIDENCE_R001.json','OMITTED_REPRO_COPIES_R001.json','REPRODUCTION.md','REVIEW_HOLD_R001.json','PREPARATION_NOTES_R001.json','prepare_selection_r001.py','prepare_supplements_r001.py','write_audit_index_r001.py','prepare_audit_tree_r001.py']:
 p=D/name;b=p.read_bytes();target='README.md' if name=='AUDIT_README_R001.md' else str(p.relative_to(R));rows[target]={'path':target,'localSource':str(p),'sourcePath':str(p.relative_to(R)),'originCommit':'NEW_AUDIT_PACKAGING_ONLY','mode':'100644','sha256':sha(b),'size':len(b)}
# Removed source paths are not expected in the active code scopes; no stale duplicate source left inherited.
assert not git('diff','--diff-filter=D','--name-only',BASE,HEAD,'--','native/WitchApp','native/WitchGameCore','tools/witch_purchase_authority').strip()
patterns={'private_key':rb'-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----','github_token':rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})','openai_key':rb'\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{35,}','aws_key':rb'\bAKIA[A-Z0-9]{16}\b','slack_token':rb'\bxox[baprs]-[A-Za-z0-9-]{20,}','credential_url':rb'https?://[^\s/\"\']+:[^\s/@\"\']+@'}
findings=[];email_paths=[];textcount=0;imagecount=0;contents={}
for p,r in sorted(rows.items()):
 assert r['mode'] in ['100644','100755']
 if r['originCommit']==HEAD:b=git('cat-file','blob',r['gitBlob'])
 else:
  f=Path(r['localSource']);assert f.is_file() and not f.is_symlink();b=f.read_bytes()
 assert len(b)==r['size'] and sha(b)==r['sha256'],p
 assert r['size']<5_000_000,p
 if Path(p).suffix.lower()=='.png':
  assert b.startswith(b'\x89PNG\r\n\x1a\n');imagecount+=1
 else:
  b.decode('utf-8');textcount+=1
  for kind,pat in patterns.items():
   if re.search(pat,b):findings.append({'path':p,'kind':kind})
  mails=re.findall(rb'(?<![\w.+-])([\w.+-]+)@([A-Za-z0-9-]+\.[A-Za-z0-9.-]+)',b)
  def known_filename(local,domain):
   return (local==b'python' and domain==b'3.13') or (domain==b'2x.png' and re.fullmatch(rb'AppIcon[0-9]+x[0-9]+',local)) or (domain==b'3x.ktx' and re.fullmatch(rb'[A-F0-9]{8}(?:-[A-F0-9]{4}){3}-[A-F0-9]{12}',local))
  unexpected=sorted(set(domain.decode() for local,domain in mails if domain.decode().lower() not in ['example.com','example.test','example.invalid','localhost.localdomain'] and not known_filename(local,domain)))
  if unexpected:email_paths.append({'path':p,'domains':unexpected})
 if any(x in Path(p).parts for x in ['.git','.codex','.ssh','DerivedData','Simulator','xcuserdata','local_only']) or Path(p).suffix.lower() in ['.p8','.p12','.mobileprovision','.key','.pem','.cer'] or Path(p).name.startswith('.env'):findings.append({'path':p,'kind':'forbidden_path'})
 contents[p]=b
scan={'at':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).isoformat(),'textFiles':textcount,'pngFiles':imagecount,'files':len(rows),'bytes':sum(len(b) for b in contents.values()),'credentialPatternFindings':findings,'emailDomainReview':email_paths,'allowedPrivateLocalPaths':'/Users/PUBLIC_USER paths retained only as requested audit/reproduction evidence','scope':'Exact new/updated payload bytes. Regex checks, allowlist, UTF8/type validation and visual sample. Inherited R046 content separately identifiable. Unknown encoded secrets not exhaustively detectable.','signingCertificatesOrProfilesIncluded':False,'privateKeysIncluded':False,'realPurchaseCredentialsIncluded':False}
(D/'local_only/SECURITY_SCAN_DRAFT_R001.json').write_text(json.dumps(scan,ensure_ascii=False,indent=2)+'\n')
assert not findings,findings
print('Security scan',len(rows),'files',imagecount,'PNG, email-domain review paths',len(email_paths))
if email_paths:
 print(json.dumps(email_paths,ensure_ascii=False));raise SystemExit('Review email-domain candidates before building tree')
scan['status']='SCOPED_SCAN_PASS';scan['reviewedEmailFalsePositives']='AppIcon size suffix @2x.png, UUID texture @3x.ktx, Homebrew python@3.13 paths; exact filename patterns only.';sp=D/'SECURITY_SCAN_R001.json';sp.write_text(json.dumps(scan,ensure_ascii=False,indent=2)+'\n');rel=str(sp.relative_to(R));contents[rel]=sp.read_bytes();rows[rel]={'path':rel,'sourcePath':rel,'originCommit':'NEW_AUDIT_PACKAGING_ONLY','mode':'100644','sha256':sha(contents[rel]),'size':len(contents[rel])}
idx=D/'local_only/AUDIT_R088.index';assert not idx.exists();env={**os.environ,'GIT_INDEX_FILE':str(idx)};git('read-tree',BASE,env=env)
entries=[]
for p,r in sorted(rows.items()):
 oid=git('hash-object','-w','--stdin',data=contents[p]).decode().strip();r['gitBlob']=oid;entries.append((r['mode']+' '+oid+'\t'+p).encode()+b'\0')
git('update-index','-z','--index-info',data=b''.join(entries),env=env)
manifest={'schema':'r088-private-audit-payload-v1','sourceCheckpoint':HEAD,'auditedImplementation':S['auditedImplementation'],'parentR046':BASE,'branch':S['branch'],'files':list(sorted(rows.values(),key=lambda x:x['path'])),'fileCountExcludingThisManifest':len(rows),'bytesExcludingThisManifest':sum(r['size'] for r in rows.values()),'native240InputHashesMatchR465':True,'selfHash':'This manifest excluded from itself; its SHA and gitBlob pinned in local tree/readback receipts.','sharedCommitIsNotDevelopmentCommit':True,'inheritedParentFiles':'R046 files retained. Entries not listed here are inherited historical content, not claimed as newest evidence.','sourceVersionRule':'originCommit fixed R088, retained local prior evidence, or new packaging. No gameplay source edits in sharing.','releaseComplete':False}
mp=D/'SHARED_PAYLOAD_MANIFEST_R001.json';mp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');mb=mp.read_bytes();mo=git('hash-object','-w','--stdin',data=mb).decode().strip();git('update-index','--add','--cacheinfo','100644,'+mo+','+str(mp.relative_to(R)),env=env)
tree=git('write-tree',env=env).decode().strip()
# Validate the complete audit tree and only same-or-additive changes relative to R046.
files={}
for x in git('ls-tree','-rlz',tree).split(b'\0'):
 if x:
  a,p=x.split(b'\t');m,k,o,n=a.decode().split();files[p.decode()]={'mode':m,'blob':o,'size':int(n)}
for p,r in rows.items():assert files[p]=={'mode':r['mode'],'blob':r['gitBlob'],'size':r['size']},p
changes=git('diff-tree','-r','--no-commit-id','--name-status',BASE,tree).decode().splitlines();assert not any(x.startswith('D\t') for x in changes)
links=[]
for p in ['README.md',str((D/'INDEX.md').relative_to(R)),str((D/'GALLERY.md').relative_to(R))]:
 b=git('show',tree+':'+p).decode()
 for link in re.findall(r'\]\(([^)]+)\)',b):
  if '://' in link or link.startswith('#'):continue
  target=posixpath.normpath(posixpath.join(posixpath.dirname(p),link.split('#')[0]));assert target in files or any(f.startswith(target+'/') for f in files),(p,target);links.append(target)
assert git('rev-parse','HEAD').decode().strip()==HEAD and git('status','--porcelain=v1','--untracked-files=no')==state
assert index0==sha(Path(git('rev-parse','--git-path','index').decode().strip()).read_bytes())
inherited=[{'path':p,**v} for p,v in sorted(files.items()) if p not in rows and p!=str(mp.relative_to(R))]
receipt={'status':'TREE_PREPARED_NO_REF_NO_PUSH','tree':tree,'parent':BASE,'developmentHEAD':HEAD,'branch':S['branch'],'totalTreeFiles':len(files),'totalTreeBytes':sum(x['size'] for x in files.values()),'payloadFilesIncludingManifest':len(rows)+1,'payloadBytesIncludingManifest':sum(r['size'] for r in rows.values())+len(mb),'manifestSHA256':sha(mb),'manifestGitBlob':mo,'manifestPath':str(mp.relative_to(R)),'linksChecked':len(links),'changedPaths':changes,'inheritedFileCount':len(inherited),'preservedRealIndex':True,'preservedDevelopmentHEAD':True,'preservedTrackedDirtyStatus':True,'deletions':0,'newRemoteWrite':False}
(D/'local_only/INHERITED_R046_FILES_R001.json').write_text(json.dumps(inherited,ensure_ascii=False,indent=2)+'\n');(D/'local_only/AUDIT_TREE_R001.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in receipt.items() if k!='changedPaths'}))

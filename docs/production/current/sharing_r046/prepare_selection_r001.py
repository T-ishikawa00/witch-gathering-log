from pathlib import Path
import json,hashlib,subprocess,re,datetime
R=Path(__file__).resolve().parents[4];D=Path(__file__).resolve().parent;P=R/'docs/production/current'
assert R.name=='idle-loot-rpg' and R.parent.name=='witch-03to05-r1'
selected={};omitted=[]
def add(p,reason):
 p=Path(p);p=p if p.is_absolute() else R/p
 if not p.is_file() or p.is_symlink():return
 rel=p.relative_to(R).as_posix();size=p.stat().st_size
 if size>2_000_000 and not (rel.endswith('sharing_r046/gallery/home_r052.png') and size<4_000_000):omitted.append({'path':rel,'size':size,'reason':'per-file 2MB audit cap'});return
 if p.suffix.lower() in {'.mp4','.mov','.wav','.aiff','.zip','.p12','.pem','.key','.mobileprovision'}:raise RuntimeError('disallowed '+rel)
 selected[rel]={'path':rel,'size':size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'reason':reason}
# Runtime files are pinned to the actual current app; no build directory is shared.
build=json.loads((R/'native/build/app_R093_compile_r002/BUILD_RECEIPT.json').read_text())
for rel,h in build['source_sha256'].items():
 assert hashlib.sha256((R/rel).read_bytes()).hexdigest()==h,rel
 add(rel,'R093 exact app runtime source')
for folder in ['native/WitchGameCore/Sources/WitchGameCore/Resources','native/WitchGameCore/Tests','native/WitchUITests']:
 for p in (R/folder).rglob('*'):
  if p.suffix in {'.swift','.json','.csv','.md'}:add(p,'core resources and regression tests')
add('native/WitchGameCore/Package.swift','standalone core test package')
for p in (R/'native/StoreKitLocalQA').glob('*'):
 if p.suffix in {'.swift','.storekit','.md','.json'}:add(p,'local StoreKit regression implementation')
# Small source and schemas only; output data and old frozen copies stay local.
tracked=subprocess.check_output(['git','ls-tree','-r','--name-only','HEAD','tools'],cwd=R,text=True).splitlines()
for rel in tracked:
 if Path(rel).suffix in {'.py','.swift','.js','.mjs','.ts','.sh'}:add(rel,'validation or production source')
 if Path(rel).suffix in {'.json','.md','.csv'} and not any(x in Path(rel).parts for x in ['reference','results','output','outputs','study','reports','reruns']):add(rel,'tool documentation or schema')
for p in (R/'docs/design').glob('*'):
 if p.suffix in {'.md','.json'}:add(p,'current design authority and conflicts')
mission=R/'docs/production/mission_20261010_r1/Witch_Codex_Autonomous_03to05_20261010'
for p in mission.glob('*'):
 if p.suffix in {'.md','.json'}:add(p,'user-delegated mission and acceptance')
for name in ['CURRENT_STATUS.md','NEXT_ACTIONS.md','ACTIVE_WORK_R026.json','DECISION_LOG.md','VALIDATION_LOG.md','CONTENT_SCOPE_AND_GATES_R1.md','CONTENT_MATRIX_R059_APP020805.json','CONTENT_MATRIX_R059_APP020805.md','CONTENT_PROGRESS_SUPPLEMENT_R071.json','CHECKPOINT_R045_CANDIDATE_FILES_R001.json','CHECKPOINT_R045_RECEIPT.json','LOCAL_QA_MEDIA_DELTA_R045_R001.json','CHECKPOINT_R046_RECEIPT.json','CHECKPOINT_R046_CANDIDATE_FILES_R001.json','LOCAL_QA_MEDIA_DELTA_R046_R001.json']:
 add(P/name,'current progress, individual readiness and checkpoint evidence')
for p in (P/'purchases').glob('*.md'):add(p,'purchase status; raw transaction material excluded')
for folder in ['audio','independent_review/checkpoint_r045','independent_review/equipment_r093_native_r001','independent_review/notice_r092_native_r001','independent_review/luna_r093_r088_native_r001','independent_review/integration_r093','independent_review/earned_build_comparison_r025']:
 for p in (P/folder).glob('*'):
  if p.suffix in {'.md','.json'}:add(p,'selected independent audit conclusions and checks')
integ=P/'recovery_r022/integration_r093_notice_luna_grounding_r001'
for name in ['BUILD_RECEIPT_R002.json','CORE_FULL_R006.json','CORE_FULL_R006.log','INTEGRATION_R002.json','INTEGRATION_R004.json','LUNA_TIMING_CORRECTION_R003.json','UNSIGNED_BUILD_RECEIPT_R004.json','UNSIGNED_COMMAND_R004.json','UNSIGNED_FINAL_VERIFICATION_R004.json','UNSIGNED_R003_LINKER_WARNING_ADDENDUM.json','build_r002.py','build_unsigned_r004.py']:
 add(integ/name,'current compiled build and test receipts')
for folder in ['qa_drafts/progress_checkpoint_r046','sharing_r046']:
 for p in (P/folder).glob('*'):
  if p.suffix in {'.md','.json','.py'} and p.name not in ['SELECTION_DRAFT_R001.json','SHARED_PAYLOAD_MANIFEST_R002.json','AUDIT_TREE_R001.json','PUSH_RECEIPT_R001.json','FINAL_TREE_REVIEW_R001.json']:add(p,'audit checkpoint handoff')
for folder in ['qa_drafts/luna_native_continuity_r010','recovery_r022/local_work_backlog']:
 for p in (P/folder).glob('*'):
  if p.suffix in {'.md','.json'} and ('MATRIX' in p.name or 'REMAINING' in p.name):add(p,'coverage and remaining-work summary')
for p in (D/'gallery').glob('*'):
 if p.suffix in {'.png','.jpg','.json'}:add(p,'actual native screen evidence with explicit build scope')
# Superseded progress drafts are retained locally but not used as the current audit report.
for rel in list(selected):
 if '/progress_checkpoint_r046/' in rel and Path(rel).name in ['STAGE_IV_R001.md','STAGE_IV_R001.json','STAGE_III_V_R001.md','STAGE_III_V_R001.json']:
  selected.pop(rel)
rows=[selected[k] for k in sorted(selected)]
# Report paths and rule only; never log matched secret contents.
patterns={'private_key':rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----','openai_key':rb'\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}\b','github_token':rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b','aws_access_key':rb'\bAKIA[0-9A-Z]{16}\b','credential_url':rb'https?://[^\s/@:]+:[^\s/@]+@'}
findings=[]
for row in rows:
 data=(R/row['path']).read_bytes()
 for name,pat in patterns.items():
  if re.search(pat,data):findings.append({'path':row['path'],'rule':name})
result={'schema':'audit-selection-draft-r046','at':datetime.datetime.now().astimezone().isoformat(),'sourceCheckpoint':subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip(),'status':'DRAFT_PENDING_FINAL_TREE_REVIEW','fileCount':len(rows),'bytes':sum(x['size'] for x in rows),'files':rows,'omitted':omitted,'secretScanFindings':findings,'scanScope':'selected payload only; regex triage not exhaustive security assurance','doesNotInclude':'large generated art/audio/video/build caches/full local history/raw personal transaction logs','remoteWrite':False}
(D/'SELECTION_DRAFT_R001.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:result[k] for k in ['fileCount','bytes','secretScanFindings']}))

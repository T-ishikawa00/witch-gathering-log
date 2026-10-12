from pathlib import Path
import subprocess,json,hashlib,datetime
R=Path(__file__).resolve().parents[4];P=R/'docs/production/current';D=Path(__file__).resolve().parent
assert R.parent.name=='witch-03to05-r1'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip()=='a63ab3a56ba66183f0fa6722ef6eab635c6454b7'
assert not subprocess.check_output(['git','diff','--cached','--name-only'],cwd=R,text=True).strip()
required=[P/'qa_drafts/progress_checkpoint_r046/PROGRESS_REPORT_R046.md',P/'qa_drafts/progress_checkpoint_r046/ALL159_CURRENT_MAPPING_R001.json']
assert all(p.is_file() for p in required),'current progress/all159 map not ready'
selected={};media={};omitted=[]
def add(p):
 if not p.is_file() or p.is_symlink():return
 rel=p.relative_to(R).as_posix();parts=p.parts
 if any(x in parts for x in ['__pycache__','.build','.git','pretest_json','posttest_json','pre_json','post_json','attachments','exported','diagnostic_export_r002']):return
 if any(x.endswith('.xcresult') or x.endswith('.app') for x in parts):return
 if p.name in ['SELECTION_DRAFT_R001.json','CHECKPOINT_R046_RECEIPT.json'] or 'PATHSPEC' in p.name or p.suffix in ['.index','.pack','.bundle']:return
 if p.suffix in ['.png','.jpg','.jpeg','.mp4','.mov','.wav'] and 'sharing_r046/gallery' not in rel:
  media[rel]={'path':rel,'size':p.stat().st_size,'sha256':sha(p)};return
 if p.suffix not in ['.py','.swift','.md','.json','.log','.xctestrun','.tsv','.txt','.png','.jpg','.jpeg']:return
 if p.stat().st_size>4_000_000:omitted.append({'path':rel,'size':p.stat().st_size,'reason':'large evidence retained locally'});return
 selected[rel]={'path':rel,'size':p.stat().st_size,'sha256':sha(p)}
for rel in ['CURRENT_STATUS.md','NEXT_ACTIONS.md','ACTIVE_WORK_R026.json','CHECKPOINT_R045_RECEIPT.json']:
 add(P/rel)
folders=['sharing_r046','qa_drafts/progress_checkpoint_r046','independent_review/github_share_r046','independent_review/checkpoint_r045','independent_review/luna_r093_r088_native_r001','qa_drafts/luna_grip_r096','qa_drafts/pursuit_notice_r092/layout_candidate_r095_r001','qa_drafts/pursuit_notice_r092/layout_candidate_r095_r002']
for rel in folders:
 for p in (P/rel).rglob('*'):add(p)
ward=P/'qa_drafts/wardrobe_home_r094'
for child in ward.iterdir():
 if child.is_dir() and child.name in ['runner_candidate_r005','runner_candidate_r006','runner_candidate_r007','runner_candidate_r008','runner_candidate_r009','native_candidate_r001','native_candidate_r002','native_candidate_r003','native_candidate_r004','independent_failure_diagnosis_r001','native_run_r005_F843_large_erna_travel','native_run_r007_F843_large_erna_travel','native_run_r009_F843_large_erna_travel']:
  for p in child.rglob('*'):add(p)
integ=P/'recovery_r022/integration_r093_notice_luna_grounding_r001'
for p in integ.glob('*'):
 if p.name.startswith('UNSIGNED') or p.name.startswith('build_unsigned'):add(p)
add(P/'qa_drafts/luna_native_continuity_r010/R093_ALL3_BOOK_NATIVE_MATRIX_R001.json')
for folder in list((P/'status_archives').glob('r10[89]_*'))+list((P/'status_archives').glob('r110_*')):
 for p in folder.glob('*'):add(p)
# Exact selection is a local preservation checkpoint. Audit push has its own stricter manifest.
rows=[selected[k] for k in sorted(selected)];mr=[media[k] for k in sorted(media)]
manifest=P/'CHECKPOINT_R046_CANDIDATE_FILES_R001.json';media_path=P/'LOCAL_QA_MEDIA_DELTA_R046_R001.json';assert not manifest.exists() and not media_path.exists()
media_path.write_text(json.dumps({'schema':'local-media-delta-r046','count':len(mr),'bytes':sum(x['size'] for x in mr),'files':mr,'remoteUpload':False},indent=2)+'\n');add(media_path);rows=[selected[k] for k in sorted(selected)]
manifest.write_text(json.dumps({'schema':'local-checkpoint-r046','at':datetime.datetime.now().astimezone().isoformat(),'parent':'a63ab3a56ba66183f0fa6722ef6eab635c6454b7','fileCount':len(rows),'bytes':sum(x['size'] for x in rows),'files':rows,'omittedLargeLocalEvidence':omitted,'activeR010Excluded':True,'unrelatedProjectPBXExcluded':True},indent=2)+'\n')
paths=[x['path'] for x in rows]+[manifest.relative_to(R).as_posix()];(P/'CHECKPOINT_R046_PATHSPEC_R001.txt').write_text('\n'.join(paths)+'\n');print(json.dumps({'payloadFiles':len(rows),'payloadBytes':sum(x['size'] for x in rows),'localMedia':len(mr),'mediaBytes':sum(x['size'] for x in mr),'manifestSHA256':sha(manifest)}))

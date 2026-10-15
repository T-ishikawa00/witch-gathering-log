"""Read retained audit evidence, create small manifests; no game/build changes."""
from pathlib import Path
import json,hashlib,subprocess,plistlib,datetime
R=Path(__file__).resolve().parents[4];D=Path(__file__).resolve().parent;Q=R/'docs/production/current/qa_drafts';S=json.loads((D/'local_only/SELECTION_DRAFT_R001.json').read_text());rows={x['path']:x for x in S['files']}
sha=lambda b:hashlib.sha256(b).hexdigest()
def add(p,target=None):
 p=Path(p);p=p if p.is_absolute() else R/p;b=p.read_bytes();rel=str(p.relative_to(R));target=target or rel
 if target in rows:assert rows[target]['sha256']==sha(b),target;return
 oid=subprocess.run(['git','rev-parse',S['sourceCheckpoint']+':'+rel],cwd=R,capture_output=True,text=True)
 origin=S['sourceCheckpoint'] if oid.returncode==0 and subprocess.check_output(['git','cat-file','blob',oid.stdout.strip()],cwd=R)==b else 'RETAINED_LOCAL_EVIDENCE_NOT_IN_R088'
 rows[target]={'path':target,'sourcePath':rel,'localSource':str(p),'mode':'100644','size':len(b),'sha256':sha(b),'originCommit':origin,'gitBlob':oid.stdout.strip() if origin==S['sourceCheckpoint'] else None}
# Missing bounded primary ledgers, errata, raw evidence and checkpoint receipt.
for p in [Q/'asset_readiness_r308/ASSET_READINESS_R001.json',R/'docs/production/current/CHECKPOINT_R088_RECEIPT_R001.json',Q/'wardrobe_furniture_runtime_r433/execution_r001/START.json',Q/'normal_progression_continuation_r443/candidate_r002/execution_r001/START.json']:
 add(p)
for folder in ['art_completion_acceptance_r450','zero_summon_first_craft_r448','zero_summon_seed_robustness_r452','normal_progression_continuation_r443','native_challenge_completion_r449']:
 for p in (Q/folder).rglob('*'):
  if p.is_file() and p.suffix in ['.json','.md','.swift','.py','.txt','.log'] and p.stat().st_size<2_000_000 and not any(x in p.parts for x in ['.build','__pycache__','node_modules']):add(p)
# Exact actual R465 generated project and active resource identities, separate from dirty PBX.
B=json.loads((Q/'native_completion_r465/build_tools_r001/INPUT_MANIFEST_R001.json').read_text())
for key in ['projectPBXPath','infoPlistTemplatePath','frozenSourceMapPath','resourceMapPath']:
 p=Path(B[key]);target=str((D/'build_identity'/p.name).relative_to(R));add(p,target)
add(R/'native/qa_source_20261015T080035/prepare_resources.py',str((D/'build_identity/prepare_resources.py').relative_to(R)))
media=[]
def gallery(run_dir, labels, release, caption):
 run=run_dir/'RUN.json';d=json.loads(run.read_text());app=Path(d.get('app',''))
 info=None
 # Pinned root build result is authoritative for app identity.
 bp=Q/('native_completion_'+release)/'ROOT_BUILD_RESULT_R001.json'
 build=json.loads(bp.read_text());products=build.get('products',{})
 product=products.get('simulator',{})
 if 'app' in product:app=Path(product['app'])
 elif release=='r456':app=R/'native/build/ActiveIntegrationR456/r456-r001/DerivedData/Build/Products/Release-iphonesimulator/WitchGathering.app'
 if (app/'Info.plist').exists():info=plistlib.loads((app/'Info.plist').read_bytes())
 for c in d['checkpoints']:
  if c['label'] not in labels or not c.get('screenshot'):continue
  p=Path(c['screenshot']);assert sha(p.read_bytes())==c['screenshotSHA256'];add(p)
  media.append({'path':str(p.relative_to(R)),'localPath':str(p),'sha256':sha(p.read_bytes()),'bytes':p.stat().st_size,'captureRelease':release.upper(),'caption':caption+' / '+c['label'],'stateRevision':c.get('revision'),'capturedAtJST':datetime.datetime.fromtimestamp(c['capturedAt'],datetime.timezone(datetime.timedelta(hours=9))).isoformat(),'sourceRun':str(run.relative_to(R)),'sourceRunSHA256':sha(run.read_bytes()),'buildReceipt':str(bp.relative_to(R)),'buildReceiptSHA256':sha(bp.read_bytes()),'bundleID':d.get('bundleID'),'CFBundleVersion':info.get('CFBundleVersion') if info else 'see retained app Info.plist; not freshly read','executableSHA256':product.get('executableSHA256') or build.get('simulatorExecutableSHA256'),'latestR465':release=='r465','qualityAccepted':False})
gallery(Q/'native_completion_r465/runtime_tools_r001/runs/f3fdf3c8-7ba7-4c69-ae3f-f58253bbadce',['home','empty_search','filters_cleared','cold'],'r465','最新通常ビルド。ホーム／検索解除と冷起動。')
gallery(Q/'native_completion_r456/runtime_tools_r002/runs/1605ec80-407f-4736-a077-1be866dac17a',['battle','gear'],'r456','過去版の補助画面。R05最終ボス戦／装備比較。R465の撮影ではない。')
# Preserve the failed screenshot, not only the corrected one.
p=Q/'native_completion_r462/runtime_tools_r003/runs/799b47c3-09fb-4461-a16b-2f754a5278be/checkpoints/filters_cleared/screen.png';add(p)
media.append({'path':str(p.relative_to(R)),'localPath':str(p),'sha256':sha(p.read_bytes()),'bytes':p.stat().st_size,'captureRelease':'R462','caption':'失敗証拠：解除後もIME文字が残存。R465で修正。','sourceRun':str(p.parents[2].relative_to(R))+'/RUN.json','latestR465':False,'qualityAccepted':False})
# A few distinct ordinary-play UI contexts, fully labelled historical.
for folder,labels,release in [('wardrobe_furniture_runtime_r433/execution_r001',['erna_companion','luna_preview','desk_placed_preview'],'R420 (capture R433)'),('normal_progression_continuation_r443/candidate_r002/execution_r001',['all_five_regions_cleared','earned_book_evolved'],'R420 lineage (capture R443)')]:
 b=Q/folder;start=json.loads((b/'START.json').read_text());ap=Path(start.get('app') or start['r420App']);info=plistlib.loads((ap/'Info.plist').read_bytes());exe=ap/info.get('CFBundleExecutable','WitchGathering');eh=sha(exe.read_bytes());pin=start.get('appInventory',{}).get('WitchGathering') or start.get('r420ExecutableSHA256');assert not pin or eh==pin
 for label in labels:
  cp=b/'checkpoints'/label/'CHECKPOINT.json';d=json.loads(cp.read_text());p=cp.parent/'screen.png';add(p);add(cp)
  sm=d.get('screenshot',{});assert not sm.get('sha256') or sm['sha256']==sha(p.read_bytes())
  media.append({'path':str(p.relative_to(R)),'localPath':str(p),'sha256':sha(p.read_bytes()),'bytes':p.stat().st_size,'captureRelease':release,'caption':'過去の通常操作記録 / '+label+'。最新版全画面合格の代用ではない。','stateRevision':d.get('revision'),'sourceCheckpoint':str(cp.relative_to(R)),'checkpointSHA256':sha(cp.read_bytes()),'sourceStart':str((b/'START.json').relative_to(R)),'sourceStartSHA256':sha((b/'START.json').read_bytes()),'sourceMapSHA256':start.get('sourceMapSHA256'),'bundleID':info.get('CFBundleIdentifier'),'CFBundleVersion':info.get('CFBundleVersion'),'executableSHA256':eh,'latestR465':False,'qualityAccepted':False})
(D/'GALLERY_MANIFEST_R001.json').write_text(json.dumps({'note':'All images are unchanged actual Simulator captures. Build version1 is reused; internal release, source map, executable SHA and run identify the exact build. Images of earlier releases are not R465. No current gacha full-screen capture selected; no claim of screen completion.','images':media},ensure_ascii=False,indent=2)+'\n')
# Actual local resources: verify exact bytes, record each path/hash without uploading the binary payload.
resource_map=json.loads(Path(B['resourceMapPath']).read_text());resources=[]
for rel,h in resource_map.items():
 p=Path(B['frozenSourceRoot'])/'PreparedResources'/rel;actual=sha(p.read_bytes());assert actual==h,rel
 resources.append({'relativePath':rel,'localPath':str(p),'bytes':p.stat().st_size,'sha256':h})
apps=json.loads((Q/'native_completion_r465/ROOT_BUILD_RESULT_R001.json').read_text())['products']
for v in apps.values():assert sha(Path(v['executable']).read_bytes())==v['executableSHA256']
videos=[]
for p in sorted((Q/'enemy_execute_regression_r424').rglob('battle_execute_window_upto_20_seconds.mp4'))[:3]:
 videos.append({'localPath':str(p),'bytes':p.stat().st_size,'sha256':sha(p.read_bytes()),'version':'R424 historical enemy execute capture; not R465','use':'個体別攻撃動作の保存動画。全ゲーム通し動画ではない。','reproduction':'Read adjacent candidate capture manifest/trace; source/UI configuration differs from latest R465.'})
(D/'LOCAL_ONLY_EVIDENCE_R001.json').write_text(json.dumps({'activeBuild':'R465','sourceMapSHA256':B['sourceMapSHA256'],'resourceMapSHA256':B['resourceMapSHA256'],'resources':resources,'products':apps,'videos':videos,'latestR465Video':'NOT_RECORDED','purpose':'Exact active app resources and native executables retained on Mac; not uploaded. Metadata/SHAs support identity, not independent visual or executable validation.','reproduction':'Use shared build_identity source/resource maps, exact frozen project and build driver. Restore all1922originalresources from these absolute local paths. Paths are Mac-specific; archive is not self-contained. Do not run existing build scripts blindly: sealed paths/output ownership require a new isolated target. Simulator runtime26.5 andXcode17F113 used.','excludedCategories':['largeoriginal/editables','allhistorical.appandDerivedData','Simulatorinternaldata','bulkvideo/rawtraces','old307apps','Codexconversations','credentials/signingfiles'],'unindexedOriginals':'Original/editable artwork paths remain in asset manifests and R308 ledger; no assertion that all original files have been rehashed by this sharing task.'},ensure_ascii=False,indent=2)+'\n')
S['files']=sorted(rows.values(),key=lambda r:r['path']);S['count']=len(rows);S['bytes']=sum(r['size'] for r in rows.values());S['images']=len(media);S['localSupplementCount']=sum(r['originCommit']!=S['sourceCheckpoint'] for r in rows.values());(D/'local_only/SELECTION_DRAFT_R002.json').write_text(json.dumps(S,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:S[k] for k in ['count','bytes','images','localSupplementCount']}));print('resource hashes verified',len(resources),'videos',len(videos))

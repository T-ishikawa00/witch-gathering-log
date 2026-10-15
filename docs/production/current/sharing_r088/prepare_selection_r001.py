"""Prepare bounded, fixed-checkpoint audit selection. No refs, pushes or source edits."""
from pathlib import Path
import subprocess,json,hashlib,collections,re
R=Path(__file__).resolve().parents[4];D=Path(__file__).resolve().parent
HEAD='a63990d29ee3e1b9114c512c5abe9e30904c45fe';BASE='1547dde77605a3e16195f892d9add20b66d5c63a'
def git(*a):return subprocess.check_output(['git',*a],cwd=R)
assert git('rev-parse','HEAD').decode().strip()==HEAD
rows={}
for x in git('ls-tree','-rlz',HEAD).split(b'\0'):
 if x:
  a,p=x.split(b'\t');m,k,o,n=a.decode().split();rows[p.decode()]={'path':p.decode(),'mode':m,'gitBlob':o,'size':int(n),'originCommit':HEAD}
text_ext={'.md','.json','.jsonl','.csv','.txt','.log','.py','.swift','.sh','.plist','.storekit','.pbxproj','.xml','.toml','.lock','.yaml','.yml','.ts','.js','.html','.css','.xcprivacy','.xcscheme','.xcconfig','.xcworkspacedata','.strings'}
qa_folders='''final_acceptance_r360 save_crash_completion_r362 economy_release_matrix_r374 research_mechanic_closure_r371 effect_build_comparison_r376 static_159_visual_r374 ally159_evidence_reuse_r374 build_diversity_acceptance_r427 build_diversity_acceptance_r428 asset_completion_reconciliation_r418 state_acceptance_reconciliation_r418 enemy_motion_residual_matrix_r407 enemy_motion_acceptance_r372 enemy_motion_all_regions_r386 enemy_lifecycle_r423 completion_priority_r457 final_asset_gaps_r391 art_completion_acceptance_r450 wardrobe_furniture_source_audit_r431 wardrobe_furniture_runtime_r433 reading_mantle_occlusion_r444 native_reading_mantle_r446 normal_progression_continuation_r443 zero_summon_first_craft_r448 zero_summon_seed_robustness_r452 native_challenge_completion_r449 gacha_completion_acceptance_r451 gacha_local_integration_r453 storekit_event_export_r454 sandbox_ledger_adapter_r459 authority_contract_r461 authority_persistence_r463 native_completion_r456 native_completion_r462 native_completion_r465 inventory_empty_guidance_r464 final_fixed_audit_r460 final_fixed_audit_r466 final_local_integration_r458 device_readiness_r426 furniture_completion_r361'''.split()
chosen={}
for p,row in rows.items():
 suffix=Path(p).suffix.lower()
 if suffix not in text_ext or row['size']>2_000_000:continue
 if any(t in Path(p).parts for t in ['.build','node_modules','__pycache__','.venv','DerivedData']):continue
 want=False
 if p.startswith(('native/WitchApp/','native/WitchGameCore/','native/WitchUITests/','native/StoreKitLocalQA/','native/WitchGathering.xcodeproj/','tools/','docs/design/','docs/production/mission_','src/','data/','tests/')):want=True
 if p.startswith(('native/Art/','native/GeneratedArt/','native/Audio/','native/GeneratedCandidates/','native/AudioCandidates/')):want=True
 if p in ['native/PrivacyInfo.xcprivacy','package.json','package-lock.json','README.md','PROJECT_CURRENT.md','.gitignore']:want=True
 if p.startswith('docs/production/current/') and p.count('/')==3 and (Path(p).suffix=='.md' or Path(p).name.startswith(('CHECKPOINT_R087','CHECKPOINT_R088','DECISION','DESIGN','OPEN_','SOURCE_'))):want=True
 if any(p.startswith('docs/production/current/qa_drafts/'+f+'/') for f in qa_folders):want=True
 if want:chosen[p]=row
# Exact active 240 native build inputs, independent of the general filters.
source_map=json.loads((R/'docs/production/current/qa_drafts/native_completion_r465/build_tools_r001/NATIVE_SOURCE_MAP_R001.json').read_text())
for rel,h in source_map.items():
 p='native/'+rel;assert p in rows,p;chosen[p]=rows[p]
# Latest four image originals, preserving source locations.
for p,row in rows.items():
 if p.startswith('docs/production/current/qa_drafts/native_completion_r465/runtime_tools_r001/runs/f3fdf3c8-7ba7-4c69-ae3f-f58253bbadce/checkpoints/') and p.endswith('/screen.png'):chosen[p]=row
# Read each exact Git object, never substitute dirty working files.
proc=subprocess.Popen(['git','cat-file','--batch'],cwd=R,stdin=subprocess.PIPE,stdout=subprocess.PIPE)
findings=[]
patterns={
 'private_key':rb'-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----',
 'github_token':rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})',
 'openai_key':rb'\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{35,}',
 'aws_key':rb'\bAKIA[A-Z0-9]{16}\b',
 'slack_token':rb'\bxox[baprs]-[A-Za-z0-9-]{20,}',
 'credential_url':rb'https?://[^\s/\"\']+:[^\s/@\"\']+@',
}
for p,row in sorted(chosen.items()):
 proc.stdin.write((row['gitBlob']+'\n').encode());proc.stdin.flush();header=proc.stdout.readline().split();b=proc.stdout.read(int(header[2]));assert proc.stdout.read(1)==b'\n';assert len(b)==row['size']
 row['sha256']=hashlib.sha256(b).hexdigest()
 if p.startswith('native/') and p[7:] in source_map:assert row['sha256']==source_map[p[7:]],p
 if Path(p).suffix.lower() in text_ext:
  b.decode('utf-8')
  for name,pat in patterns.items():
   if re.search(pat,b):findings.append({'path':p,'kind':name})
 if Path(p).suffix.lower() in {'.p8','.p12','.mobileprovision','.key','.pem','.cer'}:findings.append({'path':p,'kind':'credential_extension'})
proc.stdin.close();proc.wait()
result={'sourceCheckpoint':HEAD,'auditedImplementation':'28d3d0b92c840f215a945f47e574fcb30ef2253b','parent':BASE,'branch':'codex/audit-03to05-20261015-r088','count':len(chosen),'bytes':sum(r['size'] for r in chosen.values()),'nativeBuildInputsExact':len(source_map),'files':list(sorted(chosen.values(),key=lambda r:r['path'])),'patternFindings':findings,'scanLimit':'Pattern scan, path/type allowlist and manual selected-image review; no claim to discover arbitrary secret encodings.'}
(D/'local_only/SELECTION_DRAFT_R001.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k!='files'},ensure_ascii=False))

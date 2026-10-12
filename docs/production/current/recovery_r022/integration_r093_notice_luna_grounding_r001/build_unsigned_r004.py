from pathlib import Path
import datetime,hashlib,json,os,subprocess,shutil
root=Path(__file__).resolve().parents[5];out=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,v):
 with p.open('x') as f:json.dump(v,f,indent=2);f.write('\n')
receipt_path=root/'native/build/app_R093_compile_r002/BUILD_RECEIPT.json'
assert sha(receipt_path)=='f91908d541ac816d2ac48bb9b66bbcd371ce61fa9994c24ed0dea1ca2ceb8309'
sim=json.loads(receipt_path.read_text());frozen=Path(sim['source_snapshot']);sources=[]
for rel,h in sim['source_sha256'].items():
 p=frozen/Path(rel).name;assert sha(p)==h,rel;sources.append(p)
assert len(sources)==140 and len({p.name for p in sources})==140
old_receipt=root/'docs/production/current/recovery_r022/integration_r089_dynamic_notice_r001/UNSIGNED_BUILD_RECEIPT_R001.json';base=json.loads(old_receipt.read_text());prior=Path(base['bundle']);assert sha(prior/'WitchGathering')==base['executableSHA256']
prior_map={str(p.relative_to(prior)):sha(p) for p in prior.rglob('*') if p.is_file()}
parent=root/'native/build/app_R093_device_r004';parent.mkdir(exist_ok=False);app=parent/'WitchGathering.app'
subprocess.run(['cp','-cR',str(prior),str(app)],check=True)
sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip();exe=parent/'WitchGathering_new'
cmd=['xcrun','swiftc','-sdk',sdk,'-target','arm64-apple-ios17.0','-swift-version','5','-O','-framework','SwiftUI','-framework','SpriteKit','-framework','UIKit',*map(str,sources),'-o',str(exe)]
dump(out/'UNSIGNED_COMMAND_R004.json',{'at':datetime.datetime.now().astimezone().isoformat(),'argv':cmd,'runtimeSources':140,'sourceReceiptSHA256':sha(receipt_path),'scope':'manual Apple SDK compile/link only; no signing, installation, physical-device test or upload'})
with (out/'UNSIGNED_BUILD_R004.log').open('x') as log:code=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,env={**os.environ,"SDKROOT":sdk}).returncode
if code:
 dump(out/'UNSIGNED_FAILURE_R004.json',{'status':'COMPILE_FAILED','exitCode':code});raise SystemExit(code)
os.replace(exe,app/'WitchGathering')
new_art=Path(sim['bundle'])/'GeneratedArt/LUNA_EXEC_RECOVER_BRIDGE_R088_SOURCE.png';shutil.copy2(new_art,app/'GeneratedArt'/new_art.name)
resources={str(p.relative_to(app)):sha(p) for p in app.rglob('*') if p.is_file() and p.name!='WitchGathering'}
assert all(sha(prior/rel)==h for rel,h in prior_map.items())
assert all(sha(frozen/Path(rel).name)==h for rel,h in sim['source_sha256'].items())
deltas={rel:('added' if rel not in prior_map else 'changed') for rel,h in resources.items() if prior_map.get(rel)!=h};assert deltas=={'GeneratedArt/LUNA_EXEC_RECOVER_BRIDGE_R088_SOURCE.png':'added'},deltas
arch=subprocess.check_output(['file',str(app/'WitchGathering')],text=True).strip()
r={'status':'UNSIGNED_DEVICE_TARGET_MANUAL_COMPILE_LINK_PASS','at':datetime.datetime.now().astimezone().isoformat(),'exitCode':code,'bundle':str(app),'runtimeSourceCount':140,'sourceSHA256':sim['source_sha256'],'sourceSnapshot':str(frozen),'sourceReceiptSHA256':sha(receipt_path),'executableSHA256':sha(app/'WitchGathering'),'resources':resources,'resourceCount':len(resources),'resourceDeltaFromR089Device':deltas,'preservedR089DeviceApp':True,'architecture':arch,'physicalDeviceTested':False,'signingEnabled':False,'installed':False,'upload':False,'packaging':'APFS clone of R089 unsigned Xcode device bundle with R093 executable and new bridge texture; no R093 Xcode packaging validation','logSHA256':sha(out/'UNSIGNED_BUILD_R004.log')}
dump(out/'UNSIGNED_BUILD_RECEIPT_R004.json',r);dump(parent/'BUILD_RECEIPT.json',r);print(r['status'],r['runtimeSourceCount'],r['resourceCount'],r['executableSHA256'])

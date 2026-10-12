from pathlib import Path
import json,hashlib,shutil,subprocess,datetime,os
r=Path(__file__).resolve().parents[5];d=Path(__file__).resolve().parent;sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();base=json.loads((r/'docs/production/current/recovery_r022/integration_r091_equipment_grounding_r001/BUILD_RECEIPT_R003.json').read_text());prior=Path(base['bundle']);assert base['status']=='SIMULATOR_BUILD_PASS' and sha(prior/'WitchGathering')==base['executable_sha256']
for rel,h in base['resource_sha256'].items():assert sha(prior/rel)==h,rel
parent=r/'native/build/app_R093_compile_r002';parent.mkdir(exist_ok=False);app=parent/'WitchGathering.app'
# APFS clone copies resources to an independent new bundle; the previous app stays byte-exact.
subprocess.run(['cp','-cR',str(prior),str(app)],check=True)
resource=r/'native/GeneratedArt/r001/LUNA_EXEC_RECOVER_BRIDGE_R088_SOURCE.png';assert sha(resource)=='7566146524e8c0ef24d1d33a265b71db5ecbe3d1dde1d141c33750dcfcb276d3'
snapshot=r/'native/build/source_R093_compile_r002';snapshot.mkdir(exist_ok=False);sources=sorted((r/'native/WitchGameCore/Sources/WitchGameCore').glob('*.swift'))+sorted((r/'native/WitchApp').glob('*.swift'))+[r/'native/StoreKitLocalQA/ReusableBridge.swift'];frozen=[]
for p in sources:q=snapshot/p.name;shutil.copy2(p,q);frozen.append(q)
shutil.copytree(Path(base['source_snapshot'])/'catalog',snapshot/'catalog')
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip();exe=parent/'WitchGathering_new';cmd=['xcrun','swiftc','-sdk',sdk,'-target','arm64-apple-ios17.0-simulator','-swift-version','5','-O','-framework','SwiftUI','-framework','SpriteKit','-framework','UIKit',*map(str,frozen),'-o',str(exe)]
(d/'BUILD_COMMAND_R002.json').write_text(json.dumps({'at':datetime.datetime.now().astimezone().isoformat(),'argv':cmd,'clonedResourceSource':str(prior),'sourceCount':len(sources)},indent=2)+'\n')
with (d/'BUILD_R002.log').open('x') as log:p=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
if p.returncode:
 (d/'BUILD_FAILURE_RECEIPT_R002.json').write_text(json.dumps({'status':'FAILED_COMPILE','returncode':p.returncode,'bundle':str(app),'source_snapshot':str(snapshot)},indent=2)+'\n');raise SystemExit(p.returncode)
os.replace(exe,app/'WitchGathering');assert sha(prior/'WitchGathering')==base['executable_sha256']
assert all(sha(app/rel)==h and sha(prior/rel)==h for rel,h in base['resource_sha256'].items())
shutil.copy2(resource,app/'GeneratedArt'/resource.name)
resources={p.relative_to(app).as_posix():sha(p) for p in sorted(app.rglob('*')) if p.is_file() and p.name!='WitchGathering'}
receipt={**base,'resource_sha256':resources,'bundle':str(app),'source_snapshot':str(snapshot),'source_sha256':{str(p.relative_to(r)):sha(snapshot/p.name) for p in sources},'executable_sha256':sha(app/'WitchGathering'),'resourceSourceReceipt':'integration_r091_equipment_grounding_r001/BUILD_RECEIPT_R003.json','previousAppPreserved':True,'integration':'R093 notice/R088bridge/ring +R094wardrobe/furniture; noadoption','repairOfCompileFailure':None}
(d/'BUILD_RECEIPT_R002.json').write_text(json.dumps(receipt,indent=2)+'\n');(parent/'BUILD_RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n');(r/'native/build/BUILD_RECEIPT.json').write_text(json.dumps(receipt,indent=2)+'\n');print(receipt['status'],len(sources),len(resources),receipt['executable_sha256'])

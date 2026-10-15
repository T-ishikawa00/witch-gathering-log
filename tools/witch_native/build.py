#!/usr/bin/env python3
"""Build a separate, unsigned local Simulator app. Never signs or uploads."""
from pathlib import Path
import subprocess, shutil, plistlib, json, hashlib, time, argparse, uuid
# Parse help/unknown arguments before creating bundles or rewriting receipts.
argparse.ArgumentParser(description=__doc__).parse_args()
ROOT=Path(__file__).resolve().parents[2]
from storage_guard import check_capacity
check_capacity(ROOT, 'manual-simulator-build-before', heavy=True, expected_bytes=2_000_000_000)
OUT=ROOT/'native/build'; OUT.mkdir(parents=True,exist_ok=True)
stamp=time.strftime('%Y%m%dT%H%M%S')+'_'+uuid.uuid4().hex[:12]
APP=OUT/('app_'+stamp)/'WitchGathering.app';APP.mkdir(parents=True,exist_ok=False)
# The global receipt describes the latest attempt. A failed build must never
# leave the previous successful receipt looking like the current result.
def attempt_receipt(status,**fields):
    value={'status':status,'bundle':str(APP),'physical_device':False,'signing':False,'upload':False,**fields}
    (OUT/'BUILD_RECEIPT.json').write_text(json.dumps(value,ensure_ascii=False,indent=2))
    (APP.parent/'BUILD_RECEIPT.json').write_text(json.dumps(value,ensure_ascii=False,indent=2))
attempt_receipt('BUILD_IN_PROGRESS')
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
sources=sorted((ROOT/'native/WitchGameCore/Sources/WitchGameCore').glob('*.swift'))+sorted((ROOT/'native/WitchApp').glob('*.swift'))+[ROOT/'native/StoreKitLocalQA/ReusableBridge.swift']
snapshot=OUT/('source_'+stamp);snapshot.mkdir(exist_ok=False)
catalog_snapshot=snapshot/'catalog';catalog_snapshot.mkdir()
for p in (ROOT/'native/WitchGameCore/Sources/WitchGameCore/Resources').glob('*.json'):shutil.copy2(p,catalog_snapshot/p.name)
frozen=[]
for p in sources:
 q=snapshot/p.name;shutil.copy2(p,q);frozen.append(q)
# Freeze and decode all resources before compilation. A producer may continue
# working after this point; this build never copies live art again.
from prepare_resources import prepare,app_info
try:resources=prepare(APP,catalog_snapshot)
except Exception as error:
    attempt_receipt('FAILED_RESOURCE_CAPTURE',error=str(error),source_snapshot=str(snapshot))
    raise
(APP.parent/'RESOURCE_CAPTURE.json').write_text(json.dumps(resources,ensure_ascii=False,indent=2))
cmd=['xcrun','swiftc','-sdk',sdk,'-target','arm64-apple-ios17.0-simulator','-swift-version','5','-O','-framework','SwiftUI','-framework','SpriteKit','-framework','UIKit',*map(str,frozen),'-o',str(APP/'WitchGathering')]
p=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
(OUT/'build.log').write_text(p.stdout)
(APP.parent/'build.log').write_text(p.stdout)
print(p.stdout[-12000:])
if p.returncode:
    attempt_receipt('FAILED_COMPILE',returncode=p.returncode,build_log=str(APP.parent/'build.log'),source_snapshot=str(snapshot))
    raise SystemExit(p.returncode)
asset_info=APP/'ASSET_INFO.plist'
plist=app_info(plistlib.loads(asset_info.read_bytes()) if asset_info.exists() else None)
(APP/'Info.plist').write_bytes(plistlib.dumps(plist))
receipt={'status':'SIMULATOR_BUILD_PASS','bundle':str(APP),'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256((snapshot/p.name).read_bytes()).hexdigest() for p in sources},'physical_device':False,'signing':False,'upload':False,'source_snapshot':str(snapshot)}
receipt['resource_snapshot_before_compile']=True
receipt['png_decode_validation']=resources['png_decode_validation']
receipt['source_stability']=resources['source_stability']
receipt['executable_sha256']=hashlib.sha256((APP/'WitchGathering').read_bytes()).hexdigest()
receipt['resource_sha256']={str(p.relative_to(APP)):hashlib.sha256(p.read_bytes()).hexdigest() for p in APP.rglob('*') if p.is_file() and p.name!='WitchGathering'}
(OUT/'BUILD_RECEIPT.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2))
(APP.parent/'BUILD_RECEIPT.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2))
print(APP)
check_capacity(ROOT, 'manual-simulator-build-after', artifact_paths=[APP.parent,snapshot])

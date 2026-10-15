"""Root read-only R454 Debug output/source/resource/protected-product verification."""
from pathlib import Path
from types import SimpleNamespace
import argparse,datetime,hashlib,importlib.util,json,plistlib,sys
BASE=Path(__file__).resolve().parent
ROOT=BASE.parents[6]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-manifest-sha256',required=True)
    parser.add_argument('--root-contract-sha256',required=True)
    parser.add_argument('--build-state-sha256',required=True)
    args=parser.parse_args()
    if any(len(v)!=64 or any(c not in '0123456789abcdef' for c in v) for v in (args.input_manifest_sha256,args.root_contract_sha256,args.build_state_sha256)):
        raise SystemExit('All SHA-256 pins must be 64 lowercase hexadecimal characters')
    sys.dont_write_bytecode=True
    spec=importlib.util.spec_from_file_location('r454_builder_readback',BASE/'build_r001.py');m=importlib.util.module_from_spec(spec);sys.modules[spec.name]=m;spec.loader.exec_module(m)
    inputs,contract,sources,donor,resources=m.validate_inputs(SimpleNamespace(input_manifest_sha256=args.input_manifest_sha256,root_contract_sha256=args.root_contract_sha256))
    sp=BASE/'BUILD_STATE_R001.json';assert sha(sp)==args.build_state_sha256
    state=json.loads(sp.read_text());assert state['phase']=='PASS_DEBUG_ONLY' and set(state['variants'])=={'debug'}
    v=state['variants']['debug'];assert v['phase']=='PASS';app=Path(v['app']);frozen=Path(state['frozen']);project=Path(state['project'])
    for rel,h in sources.items():assert sha(frozen/rel)==h
    for rel,h in resources.items():assert sha(frozen/'PreparedResources'/rel)==h
    for p,h in v['productFiles'].items():assert sha(Path(p))==h
    assert sha(project/'project.pbxproj')==state['generatedProjectPBXSHA256']
    appfiles={}
    for p in app.rglob('*'):
        assert not p.is_symlink()
        if p.is_file():appfiles[str(p.relative_to(app))]=sha(p)
    assert len(appfiles)==1925 and {p:h for p,h in appfiles.items() if p not in {'Info.plist','PkgInfo','WitchGathering'}}==resources
    assert plistlib.loads((app/'Info.plist').read_bytes())['CFBundleIdentifier']=='local.witch.autonomous.r1.storekit.r454'
    preserved=m.verify_preserved_products(inputs)
    row={**v,'schema':'r454-normalized-build-readback-v1','phase':'BUILD_PASS','exitCode':0,'at':datetime.datetime.now().astimezone().isoformat(),'normalizerSHA256':sha(Path(__file__)),'rawStatePath':str(sp),'rawStateSHA256':sha(sp),'appExecutable':{'path':str(app/'WitchGathering'),'sha256':sha(app/'WitchGathering')},'appFiles':appfiles,'frozen':str(frozen),'project':str(project),'sourceCount':238,'resourceCount':1922,'sourceManifestSHA256':sha(frozen/'SOURCE_SHA256.json'),'resourceManifestSHA256':sha(frozen/'RESOURCE_SHA256.json'),'flags':inputs['variants']['debug']['flags'],'liveSourcesMatchFrozen':True,'protectedProductsReadback':preserved,'install':False,'launch':False,'acceptanceLimit':'Build identity and content verification only, no visual quality acceptance.'}
    out=BASE/'postbuild_readback_r001';out.mkdir(exist_ok=False);p=out/'debug_BUILD_PASS.json'
    with p.open('x') as f:json.dump(row,f,ensure_ascii=False,sort_keys=True,indent=2);f.write('\n')
    print(json.dumps({'receipt':str(p),'sha256':sha(p),'appSHA256':row['appExecutable']['sha256']}))
if __name__=='__main__':main()

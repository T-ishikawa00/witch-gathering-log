#!/usr/bin/env python3
"""Assemble app-owned resources only; originals and runtime source indices stay immutable."""
from pathlib import Path
import hashlib,io,json,os,sys,subprocess,tempfile,plistlib
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
class ResourceCapture:
    """Copy validated bytes, then reject any source changed during capture."""
    def __init__(self):self.captured={}
    def read(self,path):
        path=Path(path)
        if path not in self.captured:
            data=path.read_bytes()
            if path.suffix.lower()=='.png':
                with Image.open(io.BytesIO(data)) as image:image.verify()
                with Image.open(io.BytesIO(data)) as image:image.load()
            elif path.suffix.lower()=='.json':json.loads(data)
            elif path.suffix.lower() in {'.plist','.xcprivacy'}:plistlib.loads(data)
            self.captured[path]=data
        return self.captured[path]
    def copy(self,source,target):
        data=self.read(source);target=Path(target);target.parent.mkdir(parents=True,exist_ok=True)
        temporary=target.with_name(target.name+'.resource-tmp')
        temporary.write_bytes(data);os.replace(temporary,target)
    def finish(self):
        changed=[str(path) for path,data in self.captured.items() if not path.exists() or path.read_bytes()!=data]
        if changed:raise RuntimeError('Resource sources changed during capture; rebuild from a stable snapshot: '+json.dumps(changed))
        return {str(path):hashlib.sha256(data).hexdigest() for path,data in self.captured.items()}

def resource_hashes(out):
    return {str(p.relative_to(out)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(Path(out).rglob('*')) if p.is_file()}

def merge_runtime_index(source,capture=None):
    """Merge ordered runtime metadata overlays without copying any assets."""
    source=Path(source)
    read=(capture.read if capture else lambda path:Path(path).read_bytes())
    index=json.loads(read(source/'runtime_index.json'))
    overlays=[source/'generated_runtime_overlay.json',source/'generated_motion_metadata_overlay_r001.json',*sorted(source.glob('runtime_overlay_*.json'))]
    loaded=[]
    for path in overlays:
        if not path.exists():continue
        data=read(path);overlay=json.loads(data)
        priority=overlay.get('mergePriority',0)
        if type(priority) is not int or not 0<=priority<=100000:
            raise ValueError('mergePriority must be an integer from 0 to 100000: '+str(path))
        loaded.append((path,data,overlay,priority))
    # Legacy overlays keep their original lexical order at priority 0. New
    # actor-specific repairs use explicit priorities instead of longer z names.
    fixed=[item for item in loaded if item[0] in overlays[:2]]
    runtime=sorted((item for item in loaded if item[0] not in overlays[:2]),key=lambda item:(item[3],item[0].name))
    applied=[];rejected=[]
    for path,data,overlay,priority in fixed+runtime:
        receipt={'path':path.relative_to(source).as_posix(),'sha256':hashlib.sha256(data).hexdigest(),'status':overlay.get('status','UNSPECIFIED'),'mergePriority':priority}
        if str(overlay.get('status','')).startswith('REJECTED'):
            rejected.append(receipt);continue
        for key,entry in overlay['entries'].items():
            target=index['entries'].setdefault(key,{})
            for field,value in entry.items():
                # These collections are state/clip maps; replace only matching keys.
                if field in ('clips','sequenceFrames') and isinstance(value,dict):
                    if not isinstance(target.get(field),dict):target[field]={}
                    target[field].update(value)
                else:target[field]=value
        applied.append(receipt)
    index['resourceAssembly']={'appliedOverlays':applied,'excludedRejectedOverlays':rejected,'humanApproval':False}
    return index,overlays

def app_info(asset_info=None):
    value={'CFBundleIdentifier':'local.witch.autonomous.r1','CFBundleExecutable':'WitchGathering','CFBundleName':'魔女の採集帳','CFBundleDisplayName':'魔女の採集帳','CFBundleVersion':'1','CFBundleShortVersionString':'0.1.0','CFBundlePackageType':'APPL','LSRequiresIPhoneOS':True,'UIDeviceFamily':[1],'MinimumOSVersion':'17.0','UILaunchScreen':{'UIColorName':'LaunchBackground'},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait'],'UIRequiredDeviceCapabilities':['arm64']}
    if asset_info:value.update(asset_info)
    return value

def compile_asset_catalog(root,out,capture):
    source=root/'native/WitchAssets.xcassets'
    if not source.exists():return {}
    # actool consumes only captured copies, never a changing producer directory.
    with tempfile.TemporaryDirectory(prefix='witch-owned-assets-') as directory:
        frozen=Path(directory)/source.name;compiled=Path(directory)/'compiled';compiled.mkdir()
        for p in sorted(source.rglob('*')):
            if p.is_file():capture.copy(p,frozen/p.relative_to(source))
        info=compiled/'ASSET_INFO.plist'
        process=subprocess.run(['xcrun','actool',str(frozen),'--compile',str(compiled),'--platform','iphonesimulator','--minimum-deployment-target','17.0','--target-device','iphone','--app-icon','AppIcon','--output-partial-info-plist',str(info),'--output-format','human-readable-text'],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        (out/'ASSET_COMPILE.log').write_text(process.stdout)
        if process.returncode:raise RuntimeError('App asset compilation failed: '+process.stdout)
        metadata=plistlib.loads(info.read_bytes())
        assert metadata['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName']=='AppIcon'
        for p in compiled.iterdir():
            if p.is_file():(out/p.name).write_bytes(p.read_bytes())
        return metadata

def copy_frozen(out,source,manifest):
    """Xcode frozen projects never reread the live art directories."""
    out=Path(out);source=Path(source);expected=json.loads(Path(manifest).read_text())
    if resource_hashes(source)!=expected:raise RuntimeError('Frozen resource SHA manifest mismatch')
    capture=ResourceCapture()
    for rel in expected:
        if Path(rel).is_absolute() or '..' in Path(rel).parts:raise ValueError('Unsafe resource path')
        capture.copy(source/rel,out/rel)
    capture.finish()

def prepare(out,catalog_root=None,root=ROOT):
    root=Path(root);capture=ResourceCapture()
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    # Required-reason declarations travel with the exact frozen resource bytes.
    # A missing or malformed app manifest is a packaging failure, not optional art.
    capture.copy(root/'native/PrivacyInfo.xcprivacy',out/'PrivacyInfo.xcprivacy')
    for p in (Path(catalog_root) if catalog_root else root/'native/WitchGameCore/Sources/WitchGameCore/Resources').glob('*.json'):capture.copy(p,out/p.name)
    source=root/'native/Art';index,overlays=merge_runtime_index(source,capture)
    applied=index['resourceAssembly']['appliedOverlays'];rejected=index['resourceAssembly']['excludedRejectedOverlays']
    art=out/'Art';art.mkdir(exist_ok=True)
    paths=set()
    def collect(v):
        if isinstance(v,str) and v.endswith('.png') and not Path(v).is_absolute() and '..' not in Path(v).parts:paths.add(v)
        elif isinstance(v,dict):
            for x in v.values():collect(x)
        elif isinstance(v,list):
            for x in v:collect(x)
    for entry in index['entries'].values():
        for key in ['selectedPNG','sequenceFrames','layers','sceneLayers','clips']:collect(entry.get(key))
    collect(index.get('effects',{}))
    for entry in index['entries'].values():
        if rig:=entry.get('partRig'):
            if Path(rig).is_absolute() or '..' in Path(rig).parts:raise ValueError('Unsafe rig path')
            spec=source/rig;dest=art/rig;capture.copy(spec,dest);collect([p["path"] for p in json.loads(capture.read(spec))["parts"]])
    # R01 scene has explicit front/back masking layers in the runtime hierarchy.
    for p in (source/'Backgrounds/BG_R01_FIELD').glob('*.png'):paths.add(str(p.relative_to(source)))
    for rel in sorted(paths):
        p=source/rel
        if not p.exists():raise FileNotFoundError(p)
        dest=art/rel;capture.copy(p,dest)
    (art/'runtime_index.json').write_text(json.dumps(index,ensure_ascii=False,indent=2))
    capture.copy(source/'effect_contract_candidate_r001.json',art/'effect_contract_candidate_r001.json')
    generated=out/'GeneratedArt';generated.mkdir(exist_ok=True)
    for p in (root/'native/GeneratedArt/r001').glob('*.png'):
        if 'SHEET' not in p.name:capture.copy(p,generated/p.name)
    party=generated/'PartyMotion';party.mkdir(exist_ok=True)
    for p in (root/'native/GeneratedArt/party_motion_r002').glob('*'):
        if p.name=='MANIFEST.json' or '__cast_' in p.name:capture.copy(p,party/p.name)
    walk=generated/'PartyWalk';walk.mkdir(exist_ok=True)
    for p in (root/'native/GeneratedArt/party_walk_r001').glob('*'):
        if p.name=='MANIFEST.json' or '__walk_' in p.name:capture.copy(p,walk/p.name)
    weapon=generated/'WeaponLayers';weapon.mkdir(exist_ok=True)
    for p in (root/'native/GeneratedArt/weapon_layers_r002').glob('*'):
        if p.name=='MANIFEST.json' or p.name.startswith('ERNA_STANDARD_BODY__') or p.name.endswith('_ALPHA_R002.png'):capture.copy(p,weapon/p.name)
    # Additive hand repair overrides the exported pose; the original source stays intact.
    repaired=root/'native/GeneratedArt/weapon_layers_r003/ERNA_TRAVEL__execute.png'
    if repaired.exists():capture.copy(repaired,generated/repaired.name)
    layered=generated/'LayeredMotion';layered.mkdir(exist_ok=True)
    for p in (root/'native/GeneratedArt/layered_motion_r001').glob('*'):
        if p.name=='MANIFEST.json' or ('__walk_' in p.name or '__cast_' in p.name or '__rest_' in p.name) and p.suffix=='.png' and '.tmp' not in p.name:capture.copy(p,layered/p.name)
    rest=generated/'PartyRest';rest.mkdir(exist_ok=True)
    for p in (root/'native/GeneratedArt/party_rest_r001').glob('*'):
        if p.name=='MANIFEST.json' or '__rest_' in p.name and p.suffix=='.png':capture.copy(p,rest/p.name)
    attack=generated/'PartyAttack';attack.mkdir(exist_ok=True)
    for p in (root/'native/GeneratedArt/party_attack_r001').glob('*'):
        if p.name=='MANIFEST.json' or '__attack_' in p.name and p.suffix=='.png' and '.tmp' not in p.name:capture.copy(p,attack/p.name)
    music_source=root/'native/Audio/music_candidate_r001'
    if music_source.exists():
        music=out/'Music';music.mkdir(exist_ok=True)
        manifest_path=music_source/'MANIFEST.json'
        manifest=json.loads(capture.read(manifest_path))
        tracks=manifest.get('tracks',[])
        if len(tracks)!=3 or {t.get('id') for t in tracks}!={'home','field','battle'}:
            raise ValueError('Music candidate must declare exactly the three scene cues')
        capture.copy(manifest_path,music/'MANIFEST.json')
        for track in tracks:
            filename=track.get('file','')
            if filename!=track['id']+'_r001.wav':raise ValueError('Unsafe or unexpected music filename')
            original=music_source/filename
            if hashlib.sha256(capture.read(original)).hexdigest()!=track.get('sha256'):
                raise ValueError('Music score/PCM manifest hash mismatch: '+filename)
            capture.copy(original,music/filename)
    compile_asset_catalog(root,out,capture)
    if [source/'generated_runtime_overlay.json',source/'generated_motion_metadata_overlay_r001.json',*sorted(source.glob('runtime_overlay_*.json'))]!=overlays:
        raise RuntimeError('Resource overlay inventory changed during capture')
    source_hashes=capture.finish()
    result={'art_paths':len(paths),'art_bytes':sum(len(capture.read(source/p)) for p in paths),'candidate_overlays':[p['path'] for p in applied],'excluded_rejected_overlays':[p['path'] for p in rejected], 'source_sha256':source_hashes,'resource_sha256':resource_hashes(out),'png_decode_validation':'PASS','source_stability':'PASS'}
    print(json.dumps({key:value for key,value in result.items() if not key.endswith('sha256')}))
    return result
if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--copy-frozen',nargs=3,metavar=('DESTINATION','SOURCE','RECEIPT'))
    parser.add_argument('--index-only',metavar='OUTPUT',help='Write the merged runtime index JSON only; do not copy assets or run actool')
    parser.add_argument('--root',type=Path,default=ROOT,help=argparse.SUPPRESS)
    parser.add_argument('output',nargs='?')
    parser.add_argument('catalog_snapshot',nargs='?')
    args=parser.parse_args()
    if args.copy_frozen:
        if args.output or args.catalog_snapshot or args.index_only:parser.error('Do not mix --copy-frozen with other output arguments')
        copy_frozen(*args.copy_frozen)
    elif args.index_only:
        if args.output or args.catalog_snapshot:parser.error('Do not mix --index-only with positional output arguments')
        destination=Path(args.index_only)
        if not destination.parent.exists():parser.error('The --index-only output parent directory must already exist')
        capture=ResourceCapture()
        index,overlays=merge_runtime_index(Path(args.root)/'native/Art',capture)
        inventory=[Path(args.root)/'native/Art/generated_runtime_overlay.json',Path(args.root)/'native/Art/generated_motion_metadata_overlay_r001.json',*sorted((Path(args.root)/'native/Art').glob('runtime_overlay_*.json'))]
        if inventory!=overlays:raise RuntimeError('Resource overlay inventory changed during index merge')
        capture.finish()
        destination.write_text(json.dumps(index,ensure_ascii=False,indent=2)+'\n')
    elif args.output:prepare(args.output,args.catalog_snapshot)
    else:parser.error('An output directory or --copy-frozen is required')

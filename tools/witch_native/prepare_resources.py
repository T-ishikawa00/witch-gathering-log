#!/usr/bin/env python3
"""Assemble app-owned resources only; originals and runtime source indices stay immutable."""
from pathlib import Path
import ctypes,errno,hashlib,io,json,os,stat,sys,subprocess,tempfile,plistlib,uuid
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
COPYFILE_ACL=0x00000001
COPYFILE_STAT=0x00000002
COPYFILE_XATTR=0x00000004
COPYFILE_DATA=0x00000008
COPYFILE_ALL=COPYFILE_ACL|COPYFILE_STAT|COPYFILE_XATTR|COPYFILE_DATA
COPYFILE_EXCL=0x00020000
COPYFILE_NOFOLLOW_SRC=0x00040000
COPYFILE_NOFOLLOW_DST=0x00080000
COPYFILE_CLONE_FORCE=0x02000000
CLONE_FLAGS=COPYFILE_ALL|COPYFILE_CLONE_FORCE|COPYFILE_NOFOLLOW_SRC|COPYFILE_NOFOLLOW_DST
FULL_COPY_FLAGS=COPYFILE_ALL|COPYFILE_EXCL|COPYFILE_NOFOLLOW_SRC|COPYFILE_NOFOLLOW_DST
_LIBSYSTEM=None

def _libsystem():
    global _LIBSYSTEM
    if _LIBSYSTEM is None:_LIBSYSTEM=ctypes.CDLL(None,use_errno=True)
    return _LIBSYSTEM

def _darwin_copyfile(source,target,flags):
    """Invoke copyfile(3); CLONE_FORCE succeeds only for an actual clone."""
    if sys.platform != 'darwin':
        raise OSError(errno.ENOTSUP,'forced APFS clone is only available on Darwin',str(target))
    function=_libsystem().copyfile
    function.argtypes=(ctypes.c_char_p,ctypes.c_char_p,ctypes.c_void_p,ctypes.c_uint32)
    function.restype=ctypes.c_int
    ctypes.set_errno(0)
    if function(os.fsencode(source),os.fsencode(target),None,flags)!=0:
        code=ctypes.get_errno() or errno.EIO
        raise OSError(code,os.strerror(code),str(target))

def _sha256_file(path):
    info=Path(path).lstat()
    if not stat.S_ISREG(info.st_mode):raise ValueError('Packaged resource must be a regular non-symlink file: '+str(path))
    digest=hashlib.sha256()
    with open(path,'rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):digest.update(block)
    return digest.hexdigest()

def _xattr_digests(path):
    if callable(getattr(os,'listxattr',None)) and callable(getattr(os,'getxattr',None)):
        names=os.listxattr(path,follow_symlinks=False)
        return {name:hashlib.sha256(os.getxattr(path,name,follow_symlinks=False)).hexdigest() for name in sorted(names)}
    # Some Apple system Pythons omit os.listxattr/getxattr. Bind Darwin's
    # public sys/xattr.h API directly to avoid spawning one xattr process per
    # resource; only value digests leave this function.
    if sys.platform!='darwin':raise OSError(errno.ENOTSUP,'xattr inspection is unavailable on this platform',str(path))
    library=_libsystem();list_fn=library.listxattr;get_fn=library.getxattr
    list_fn.argtypes=(ctypes.c_char_p,ctypes.c_void_p,ctypes.c_size_t,ctypes.c_int);list_fn.restype=ctypes.c_ssize_t
    get_fn.argtypes=(ctypes.c_char_p,ctypes.c_char_p,ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint32,ctypes.c_int);get_fn.restype=ctypes.c_ssize_t
    raw_path=os.fsencode(path);options=0x0001 # XATTR_NOFOLLOW
    ctypes.set_errno(0);length=list_fn(raw_path,None,0,options)
    if length<0:
        code=ctypes.get_errno() or errno.EIO;raise OSError(code,os.strerror(code),str(path))
    if length==0:return {}
    names_buffer=ctypes.create_string_buffer(length)
    ctypes.set_errno(0);actual=list_fn(raw_path,names_buffer,length,options)
    if actual<0:
        code=ctypes.get_errno() or errno.EIO;raise OSError(code,os.strerror(code),str(path))
    names=[name for name in names_buffer.raw[:actual].split(b'\0') if name]
    result={}
    for name in sorted(names):
        ctypes.set_errno(0);value_size=get_fn(raw_path,name,None,0,0,options)
        if value_size<0:
            code=ctypes.get_errno() or errno.EIO;raise OSError(code,os.strerror(code),str(path))
        value_buffer=ctypes.create_string_buffer(value_size or 1)
        ctypes.set_errno(0);read_size=get_fn(raw_path,name,value_buffer,value_size,0,options)
        if read_size<0:
            code=ctypes.get_errno() or errno.EIO;raise OSError(code,os.strerror(code),str(path))
        if read_size!=value_size:raise RuntimeError('Resource xattr changed while being read: '+os.fsdecode(name))
        result[os.fsdecode(name)]=hashlib.sha256(value_buffer.raw[:read_size]).hexdigest()
    return result

def _source_signature(path):
    path=Path(path);info=path.lstat()
    if not stat.S_ISREG(info.st_mode):raise ValueError('Resource source must be a regular non-symlink file: '+str(path))
    xattrs=_xattr_digests(path)
    return {'dev':info.st_dev,'ino':info.st_ino,'mode':info.st_mode,'uid':info.st_uid,'gid':info.st_gid,'nlink':info.st_nlink,
            'mtime_ns':info.st_mtime_ns,'ctime_ns':info.st_ctime_ns,'flags':getattr(info,'st_flags',None),'xattrs_sha256':xattrs}

def _acl_digest(path):
    """Return Darwin's canonical extended-ACL digest, or None when no ACL exists."""
    if sys.platform!='darwin':return None
    library=_libsystem();get_acl=library.acl_get_file;to_text=library.acl_to_text;free_acl=library.acl_free
    get_acl.argtypes=(ctypes.c_char_p,ctypes.c_int);get_acl.restype=ctypes.c_void_p
    to_text.argtypes=(ctypes.c_void_p,ctypes.POINTER(ctypes.c_ssize_t));to_text.restype=ctypes.c_void_p
    free_acl.argtypes=(ctypes.c_void_p,);free_acl.restype=ctypes.c_int
    ctypes.set_errno(0);acl=get_acl(os.fsencode(path),0x00000100) # ACL_TYPE_EXTENDED
    if not acl:
        code=ctypes.get_errno()
        if code in (0,errno.ENOENT):return None
        raise OSError(code,os.strerror(code),str(path))
    try:
        length=ctypes.c_ssize_t();text=to_text(acl,ctypes.byref(length))
        if not text:raise OSError(ctypes.get_errno() or errno.EIO,'acl_to_text failed',str(path))
        try:return hashlib.sha256(ctypes.string_at(text,length.value)).hexdigest()
        finally:free_acl(text)
    finally:free_acl(acl)

def _metadata_signature(path):
    info=Path(path).lstat()
    if not stat.S_ISREG(info.st_mode):raise ValueError('Packaged resource must be a regular non-symlink file: '+str(path))
    return {'mode':stat.S_IMODE(info.st_mode),'uid':info.st_uid,'gid':info.st_gid,'mtime_ns':info.st_mtime_ns,
            'flags':getattr(info,'st_flags',None),'xattrs_sha256':_xattr_digests(path),'acl_sha256':_acl_digest(path)}

def _ensure_real_directory_chain(path):
    """Validate the full path; tolerate only exact macOS /var and /tmp aliases."""
    absolute=Path(path).absolute()
    components=list(reversed((absolute,*absolute.parents)))
    missing=[]
    for component in components:
        if not os.path.lexists(component):
            missing.append(component)
            continue
        info=component.lstat()
        if stat.S_ISLNK(info.st_mode):
            allowed={'/var':'/private/var','/tmp':'/private/tmp'}.get(str(component))
            if not allowed or os.path.realpath(component)!=allowed:
                raise ValueError('Resource output component must be a real directory, not a symlink: '+str(component))
            continue
        if not stat.S_ISDIR(info.st_mode):
            raise ValueError('Resource output component must be a real directory: '+str(component))
    for component in missing:
        component.mkdir()
        info=component.lstat()
        if not stat.S_ISDIR(info.st_mode):raise ValueError('Resource output component changed during creation: '+str(component))

class ResourceCapture:
    """Copy validated bytes, then reject any source changed during capture."""
    def __init__(self,full_copy_fallback_budget_bytes=0,copyfile_fn=None):
        if type(full_copy_fallback_budget_bytes) is not int or full_copy_fallback_budget_bytes<0:
            raise ValueError('full-copy fallback budget must be a nonnegative integer')
        self.captured={};self.source_signatures={};self.copy_actions=[]
        self.full_copy_fallback_budget_bytes=full_copy_fallback_budget_bytes
        self.full_copy_fallback_used_bytes=0
        self.copyfile_fn=copyfile_fn or _darwin_copyfile
    def read(self,path):
        path=Path(path)
        if path not in self.captured:
            before=_source_signature(path)
            data=path.read_bytes()
            if path.suffix.lower()=='.png':
                with Image.open(io.BytesIO(data)) as image:image.verify()
                with Image.open(io.BytesIO(data)) as image:image.load()
            elif path.suffix.lower()=='.json':json.loads(data)
            elif path.suffix.lower() in {'.plist','.xcprivacy'}:plistlib.loads(data)
            after=_source_signature(path)
            if before!=after:raise RuntimeError('Resource source changed while being read: '+str(path))
            self.captured[path]=data;self.source_signatures[path]=after
        return self.captured[path]
    def copy(self,source,target):
        source=Path(source);target=Path(target)
        _ensure_real_directory_chain(target.parent)
        data=self.read(source)
        digest=hashlib.sha256(data).hexdigest()
        if os.path.lexists(target):
            target_info=target.lstat()
            if not stat.S_ISREG(target_info.st_mode):raise ValueError('Resource destination must be a regular non-symlink file: '+str(target))
            if _sha256_file(target)==digest and _metadata_signature(target)==_metadata_signature(source):
                self.copy_actions.append({'source':str(source),'destination':str(target),'method':'SKIPPED_IDENTICAL_SHA256','sha256':digest,'bytes':len(data)})
                return
        temporary=target.with_name(target.name+'.resource-tmp-'+uuid.uuid4().hex)
        method='APFS_CLONE_FORCE'
        try:
            try:self.copyfile_fn(source,temporary,CLONE_FLAGS)
            except OSError as error:
                remaining=self.full_copy_fallback_budget_bytes-self.full_copy_fallback_used_bytes
                if error.errno not in {errno.ENOTSUP,errno.EXDEV} or len(data)>remaining:
                    if error.errno in {errno.ENOTSUP,errno.EXDEV}:
                        raise RuntimeError('Forced APFS clone unavailable and explicit full-copy budget is insufficient; no fallback performed: '+str(source)) from error
                    raise
                if os.path.lexists(temporary):
                    temp_info=temporary.lstat()
                    if not stat.S_ISREG(temp_info.st_mode):raise RuntimeError('Private clone temporary is not a regular file; refusing fallback: '+str(temporary)) from error
                    temporary.unlink()
                self.copyfile_fn(source,temporary,FULL_COPY_FLAGS)
                self.full_copy_fallback_used_bytes+=len(data)
                method='FULL_COPY_EXPLICIT_BUDGET'
            if _sha256_file(temporary)!=digest:
                raise RuntimeError('Copied resource digest differs from validated source: '+str(source))
            if _metadata_signature(temporary)!=_metadata_signature(source):
                raise RuntimeError('Copied resource metadata differs from validated source: '+str(source))
            os.replace(temporary,target)
        finally:
            if os.path.lexists(temporary):
                if temporary.is_dir() and not temporary.is_symlink():raise RuntimeError('Unexpected directory at private resource temporary path: '+str(temporary))
                temporary.unlink()
        self.copy_actions.append({'source':str(source),'destination':str(target),'method':method,'sha256':digest,'bytes':len(data)})
    def finish(self):
        changed=[]
        for path,data in self.captured.items():
            try:
                if _source_signature(path)!=self.source_signatures[path] or path.read_bytes()!=data:changed.append(str(path))
            except (OSError,ValueError):changed.append(str(path))
        if changed:raise RuntimeError('Resource sources changed during capture; rebuild from a stable snapshot: '+json.dumps(changed))
        return {str(path):hashlib.sha256(data).hexdigest() for path,data in self.captured.items()}

def resource_hashes(out):
    return {str(p.relative_to(out)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(Path(out).rglob('*')) if p.is_file()}

def _copy_action_summary(actions):
    summary={}
    for action in actions:
        row=summary.setdefault(action['method'],{'count':0,'logical_bytes':0})
        row['count']+=1;row['logical_bytes']+=action['bytes']
    return summary

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
        compiled_capture=ResourceCapture(capture.full_copy_fallback_budget_bytes-capture.full_copy_fallback_used_bytes,capture.copyfile_fn)
        for p in compiled.iterdir():
            if p.is_file():compiled_capture.copy(p,out/p.name)
        # Compiled outputs are ephemeral; validate them before TemporaryDirectory exits,
        # then merge only actions/accounting into the long-lived source capture.
        compiled_capture.finish()
        capture.copy_actions.extend(compiled_capture.copy_actions)
        capture.full_copy_fallback_used_bytes+=compiled_capture.full_copy_fallback_used_bytes
        return metadata

def copy_frozen(out,source,manifest,full_copy_fallback_budget_bytes=0):
    """Xcode frozen projects never reread the live art directories."""
    out=Path(out);source=Path(source);expected=json.loads(Path(manifest).read_text())
    if not isinstance(expected,dict):raise ValueError('Frozen resource manifest must be an object')
    for rel in expected:
        if not isinstance(rel,str) or Path(rel).is_absolute() or '..' in Path(rel).parts:
            raise ValueError('Unsafe resource path: '+repr(rel))
    if resource_hashes(source)!=expected:raise RuntimeError('Frozen resource SHA manifest mismatch')
    if os.path.lexists(out):_ensure_real_directory_chain(out)
    capture=ResourceCapture(full_copy_fallback_budget_bytes)
    for rel in expected:
        parent=out
        for component in Path(rel).parts[:-1]:
            parent=parent/component
            if os.path.lexists(parent):_ensure_real_directory_chain(parent)
        capture.copy(source/rel,out/rel)
    capture.finish()
    actual_after={}
    for rel,digest in expected.items():
        actual_after[rel]=_sha256_file(out/rel)
        if actual_after[rel]!=digest:raise RuntimeError('Packaged resource readback differs from frozen manifest: '+rel)
    return {'resource_sha256':actual_after,'copy_actions':capture.copy_actions,'copy_method_summary':_copy_action_summary(capture.copy_actions),'full_copy_fallback_budget_bytes':capture.full_copy_fallback_budget_bytes,'full_copy_fallback_used_bytes':capture.full_copy_fallback_used_bytes,'unmanaged_output_files_preserved':True}

def prepare(out,catalog_root=None,root=ROOT,full_copy_fallback_budget_bytes=0):
    root=Path(root);capture=ResourceCapture(full_copy_fallback_budget_bytes)
    out=Path(out)
    _ensure_real_directory_chain(out)
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
    # R130 isolated AIRA wardrobe resource bytes are pinned at assembly time.
    # Their presence does not enable the candidate; the app requires the full QA gate.
    apron_source = root/'native/GeneratedArt/aira_apron_candidate_r130'
    for name, expected in {
        'AIRA_HARVEST_APRON_R130.png': '2ec220a342f8aca0b7379cbc04629133d23860d17b1c51f0303f15fc32d3b54b',
        'AIRA_APRON_REGISTRATION_R001.json': 'e7f96c2ac27c452c720068386c960ca1290b78645baeda0787bc6a4da85ec6c1',
    }.items():
        path = apron_source/name
        if hashlib.sha256(capture.read(path)).hexdigest() != expected:
            raise ValueError('R130 candidate resource source pin mismatch: '+name)
        capture.copy(path,out/'CandidateAppearance/R130'/name)
    # R137 uses these original-art mesh sources only behind isolated R135 QA gates.
    jelly_source = root/'native/GeneratedArt/jelly_mesh_candidate_r135'
    for name, expected in {'candidate_matte.png': '32e1118976c177fdb54a48204ae4643f112414588e4d70bbcc9dd651328de2c3', 'mesh_weights_editable.json': 'd7b0b96c1077711e8160966d8c8fb8cbbd726f7c6f2ed2800cc356c3e5dab2dd', 'clips_editable.json': 'fd1ea3234046bb1cf4234f33e18ff4292441180d65092295a5de5fa311d622b3'}.items():
        path = jelly_source/name
        if hashlib.sha256(capture.read(path)).hexdigest() != expected:
            raise ValueError('R135 mesh resource source pin mismatch: '+name)
        capture.copy(path,out/'CandidateMotion/R135'/name)
    compile_asset_catalog(root,out,capture)
    if [source/'generated_runtime_overlay.json',source/'generated_motion_metadata_overlay_r001.json',*sorted(source.glob('runtime_overlay_*.json'))]!=overlays:
        raise RuntimeError('Resource overlay inventory changed during capture')
    source_hashes=capture.finish()
    result={'art_paths':len(paths),'art_bytes':sum(len(capture.read(source/p)) for p in paths),'candidate_overlays':[p['path'] for p in applied],'excluded_rejected_overlays':[p['path'] for p in rejected], 'source_sha256':source_hashes,'resource_sha256':resource_hashes(out),'copy_actions':capture.copy_actions,'full_copy_fallback_budget_bytes':capture.full_copy_fallback_budget_bytes,'full_copy_fallback_used_bytes':capture.full_copy_fallback_used_bytes,'png_decode_validation':'PASS','source_stability':'PASS'}
    summary={key:value for key,value in result.items() if not key.endswith('sha256') and key!='copy_actions'}
    summary['copy_method_summary']=_copy_action_summary(capture.copy_actions)
    print(json.dumps(summary))
    return result
if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--copy-frozen',nargs=3,metavar=('DESTINATION','SOURCE','RECEIPT'))
    parser.add_argument('--full-copy-fallback-budget-bytes',type=int,default=0,help='Explicit maximum logical bytes allowed for full-copy fallback when forced cloning is unsupported (default: disabled)')
    parser.add_argument('--index-only',metavar='OUTPUT',help='Write the merged runtime index JSON only; do not copy assets or run actool')
    parser.add_argument('--root',type=Path,default=ROOT,help=argparse.SUPPRESS)
    parser.add_argument('output',nargs='?')
    parser.add_argument('catalog_snapshot',nargs='?')
    args=parser.parse_args()
    if args.copy_frozen:
        if args.output or args.catalog_snapshot or args.index_only:parser.error('Do not mix --copy-frozen with other output arguments')
        receipt=copy_frozen(*args.copy_frozen,full_copy_fallback_budget_bytes=args.full_copy_fallback_budget_bytes)
        print(json.dumps({key:value for key,value in receipt.items() if key not in {'resource_sha256','copy_actions'}},ensure_ascii=False))
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
    elif args.output:prepare(args.output,args.catalog_snapshot,full_copy_fallback_budget_bytes=args.full_copy_fallback_budget_bytes)
    else:parser.error('An output directory or --copy-frozen is required')

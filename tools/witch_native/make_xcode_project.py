#!/usr/bin/env python3
"""Reproducible project generation using only source paths in this worktree."""
from pathlib import Path
import hashlib,json,sys,time,shutil,plistlib,argparse
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--freeze',action='store_true',help='Create a new project with frozen source and resources')
arguments=parser.parse_args()
ROOT=Path(__file__).resolve().parents[2];NATIVE=ROOT/'native';project=NATIVE/'WitchGathering.xcodeproj';project.mkdir(exist_ok=True)
frozen=None
if arguments.freeze:
    stamp=time.strftime('%Y%m%dT%H%M%S');frozen=NATIVE/('qa_source_'+stamp);frozen.mkdir()
    project=NATIVE/('WitchGatheringQA_'+stamp+'.xcodeproj');project.mkdir()
    files=list((NATIVE/'WitchApp').glob('*.swift'))+list((NATIVE/'WitchGameCore/Sources/WitchGameCore').glob('*.swift'))+[NATIVE/'StoreKitLocalQA/ReusableBridge.swift']+sorted((NATIVE/'WitchUITests').glob('*.swift'))+list((NATIVE/'WitchGameCore/Sources/WitchGameCore/Resources').glob('*.json'))
    for p in files:
        target=frozen/p.relative_to(NATIVE);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
    (frozen/'SOURCE_SHA256.json').write_text(json.dumps({str(p.relative_to(NATIVE)):hashlib.sha256((frozen/p.relative_to(NATIVE)).read_bytes()).hexdigest() for p in files},indent=2))
    from prepare_resources import prepare
    resources=prepare(frozen/'PreparedResources',frozen/'WitchGameCore/Sources/WitchGameCore/Resources')
    (frozen/'RESOURCE_CAPTURE.json').write_text(json.dumps(resources,ensure_ascii=False,indent=2))
    (frozen/'RESOURCE_SHA256.json').write_text(json.dumps(resources['resource_sha256'],indent=2))
    # Freeze the assembler as well as the inputs used by the QA project.
    shutil.copy2(ROOT/'tools/witch_native/prepare_resources.py',frozen/'prepare_resources.py')
from prepare_resources import ResourceCapture,compile_asset_catalog,app_info
if frozen:
    info_path=frozen/'PreparedResources/ASSET_INFO.plist'
    icon_info=plistlib.loads(info_path.read_bytes()) if info_path.exists() else {}
else:
    icon_output=NATIVE/'build/project_asset_metadata';icon_output.mkdir(parents=True,exist_ok=True)
    icon_capture=ResourceCapture();icon_info=compile_asset_catalog(ROOT,icon_output,icon_capture);icon_capture.finish()
project_info=project/'GameInfo.plist';project_info.write_bytes(plistlib.dumps(app_info(icon_info)))
objects={}
def uid(name):return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name,body):objects[uid(name)]=body;return uid(name)
def q(x):return json.dumps(str(x),ensure_ascii=False)
def arr(values):return '('+','.join(values)+',)'
source=[];refs=[]
for p in sorted((NATIVE/'WitchApp').glob('*.swift'))+sorted((NATIVE/'WitchGameCore/Sources/WitchGameCore').glob('*.swift'))+[NATIVE/'StoreKitLocalQA/ReusableBridge.swift']:
    if frozen:p=frozen/p.relative_to(NATIVE)
    rel=str(p.relative_to(NATIVE));ref=add(rel,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(rel)}; sourceTree = SOURCE_ROOT;');refs.append(ref);source.append(add('build:'+rel,f'isa = PBXBuildFile; fileRef = {ref};'))
appRef=add('appref','isa = PBXFileReference; explicitFileType = wrapper.application; path = WitchGathering.app; sourceTree = BUILT_PRODUCTS_DIR;')
uiRef=add('uitestref','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = WitchUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
uiBuilds=[]
for p in sorted((NATIVE/'WitchUITests').glob('*.swift')):
    if frozen:p=frozen/p.relative_to(NATIVE)
    uiPath=str(p.relative_to(NATIVE))
    uiSrc=add('ui_source:'+uiPath,'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+q(uiPath)+'; sourceTree = SOURCE_ROOT;');refs.append(uiSrc)
    uiBuilds.append(add('ui_build:'+uiPath,f'isa = PBXBuildFile; fileRef = {uiSrc};'))
products=add('products',f'isa = PBXGroup; children = {arr([appRef,uiRef])}; name = Products; sourceTree = "<group>";')
group=add('rootgroup',f'isa = PBXGroup; children = {arr(refs+[products])}; sourceTree = "<group>";')
srcphase=add('sourcephase',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(source)}; runOnlyForDeploymentPostprocessing = 0;')
uisrcphase=add('uisourcephase',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(uiBuilds)}; runOnlyForDeploymentPostprocessing = 0;')
script='/usr/bin/python3 "$SRCROOT/../tools/witch_native/prepare_resources.py" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"'
if frozen:script='/usr/bin/python3 '+q(frozen/'prepare_resources.py')+' --copy-frozen "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH" '+q(frozen/'PreparedResources')+' '+q(frozen/'RESOURCE_SHA256.json')
resphase=add('resourcesphase','isa = PBXShellScriptBuildPhase; alwaysOutOfDate = 1; buildActionMask = 2147483647; files = (); inputPaths = (); outputPaths = (); name = "Prepare owned game resources"; runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = '+q(script)+';')
base={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','CODE_SIGNING_ALLOWED':'NO','TARGETED_DEVICE_FAMILY':'1','ENABLE_USER_SCRIPT_SANDBOXING':'NO','GENERATE_INFOPLIST_FILE':'YES'}
app={**base,'PRODUCT_BUNDLE_IDENTIFIER':'local.witch.autonomous.r1','PRODUCT_NAME':'WitchGathering','GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':str(project_info),'SWIFT_OPTIMIZATION_LEVEL':'-O'}
ui={**base,'PRODUCT_BUNDLE_IDENTIFIER':'local.witch.autonomous.r1.uitests','PRODUCT_NAME':'WitchUITests','TEST_TARGET_NAME':'WitchGathering'}
def configs(name,settings):
    ids=[]
    for c in ['Debug','Release']:
        settings={**settings,'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG $(inherited)' if c=='Debug' else '$(inherited)'}
        ids.append(add(name+c,'isa = XCBuildConfiguration; buildSettings = {'+''.join(k+' = '+q(v)+';' for k,v in settings.items())+'}; name = '+c+';'))
    return add(name+'config',f'isa = XCConfigurationList; buildConfigurations = {arr(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
appconf=configs('app',app);uiconf=configs('ui',ui);projconf=configs('project',base)
appTarget=add('apptarget',f'isa = PBXNativeTarget; buildConfigurationList = {appconf}; buildPhases = {arr([srcphase,resphase])}; buildRules = (); dependencies = (); name = WitchGathering; productName = WitchGathering; productReference = {appRef}; productType = "com.apple.product-type.application";')
proxy=add('proxy',f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {appTarget}; remoteInfo = WitchGathering;')
dep=add('dependency',f'isa = PBXTargetDependency; target = {appTarget}; targetProxy = {proxy};')
uiTarget=add('uitarget',f'isa = PBXNativeTarget; buildConfigurationList = {uiconf}; buildPhases = {arr([uisrcphase])}; buildRules = (); dependencies = {arr([dep])}; name = WitchUITests; productName = WitchUITests; productReference = {uiRef}; productType = "com.apple.product-type.bundle.ui-testing";')
add('project',f'isa = PBXProject; attributes = {{LastUpgradeCheck = 2600;}}; buildConfigurationList = {projconf}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ja; hasScannedForEncodings = 0; knownRegions = (ja,en,Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {arr([appTarget,uiTarget])};')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(k+' = {'+v+'};\n' for k,v in objects.items())+'}; rootObject = '+uid('project')+';}\n')
scheme=project/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
def ref(id,name):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{id}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:{project.name}"/>'
(scheme/'WitchGathering.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref(appTarget,'WitchGathering.app')}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref(uiTarget,'WitchUITests.xctest')}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(appTarget,'WitchGathering.app')}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(appTarget,'WitchGathering.app')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print(project)

import xml.etree.ElementTree as ET
qa=ET.parse(scheme/'WitchGathering.xcscheme');launch=qa.getroot().find('LaunchAction')
args=ET.SubElement(launch,'CommandLineArguments')
for value in ['--qa-isolated','--qa-save-key=storekit-integration-r001','--xcode-local-storekit-qa','--screen=購入検証']:
    ET.SubElement(args,'CommandLineArgument',argument=value,isEnabled='YES')
ET.SubElement(launch,'StoreKitConfigurationFileReference',identifier='../../StoreKitLocalQA/iOSRunner/AppProbe/Products.storekit')
qa.write(scheme/'WitchStoreKitQA.xcscheme',encoding='utf-8',xml_declaration=True)

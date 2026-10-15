"""Bounded R454 native local QA evidence/host exchange. No UI automation or save injection."""
from pathlib import Path
import argparse, datetime, hashlib, json, os, plistlib, re, shutil, subprocess, sys, time

ROOT=Path(__file__).resolve().parents[6]
HERE=Path(__file__).resolve().parent
BASE=HERE.parent
HOST=BASE/'host_runtime_r001'
DEVICE='9A067715-7CF3-40D3-9064-38423223959B'
BUNDLE='local.witch.autonomous.r1.storekit.r454'
SAVE='qa-storekit-authority-r454-save.json'
sys.dont_write_bytecode=True
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write_new(p, value):
    with p.open('x') as f: json.dump(value,f,ensure_ascii=False,indent=2); f.write('\n')
def container(kind):
    return Path(subprocess.check_output(['xcrun','simctl','get_app_container',DEVICE,BUNDLE,kind],text=True,timeout=15).strip()).resolve(strict=True)
def bind():
    app=container('app');data=container('data')
    assert plistlib.loads((app/'Info.plist').read_bytes())['CFBundleIdentifier']==BUNDLE
    active=json.loads((HERE/'ACTIVE_INSTALL.json').read_text())
    assert re.fullmatch(r'INSTALLED_ORIGIN(?:_R[0-9]{3})?\.json',active['receipt'])
    origin=HERE/active['receipt'];assert sha(origin)==active['sha256']
    pins=json.loads(origin.read_text())
    assert sha(app/'WitchGathering')==pins['executableSHA256']
    assert str(data)==pins['dataContainer'] and str(app)==pins['appContainer']
    matches=list(data.glob('Library/Application Support/*/'+SAVE))
    assert len(matches)==1, 'Expected exactly one isolated R454 save'
    support=matches[0].parent
    assert not support.is_symlink()
    return app,data,support
def guard():
    assert shutil.disk_usage(ROOT).free>=20_000_000_000
    total=sum(p.stat().st_size for p in HERE.rglob('*') if p.is_file())
    assert total<30_000_000,'R454 evidence cap reached'
def capture(label, screenshot):
    assert re.fullmatch('[a-z0-9_]+',label)
    guard();app,data,support=bind();out=HERE/'captures'/label;out.mkdir(parents=True,exist_ok=False)
    rows={}
    for p in support.iterdir():
        if p.name in {SAVE,SAVE+'.previous','last_r454_delivery.json','last_purchase.json','last_purchase_update.json'} and p.is_file():
            assert not p.is_symlink() and p.stat().st_size<2_000_000
            raw=p.read_bytes();(out/p.name).write_bytes(raw);rows[p.name]={'sha256':sha(p),'bytes':len(raw)}
    obj=json.loads((support/SAVE).read_text());snap=obj.get('snapshot',obj)
    if screenshot:
        assert len(list(HERE.glob('captures/*/screen.png')))<6
        subprocess.run(['xcrun','simctl','io',DEVICE,'screenshot',str(out/'screen.png')],check=True,capture_output=True,timeout=15)
    state={'at':datetime.datetime.now().astimezone().isoformat(),'label':label,'app':str(app),'data':str(data),'support':str(support),'executableSHA256':sha(app/'WitchGathering'),'saveSHA256':sha(support/SAVE),'revision':snap['revision'],'gearCount':len(snap['gear']),'currency':snap['currency'],'QARecords':snap.get('localStoreKitQARecords'),'pity':snap.get('gachaPity'),'files':rows,'productionEntitlementAuthorized':False}
    if screenshot:state['screenSHA256']=sha(out/'screen.png')
    write_new(out/'STATE.json',state);guard();print(json.dumps(state,ensure_ascii=False))
def serve(seconds,limit):
    assert 1<=seconds<=600 and 1<=limit<=12
    guard();_,_,support=bind();mail=support/'r454-authority-qa'
    ctx=json.loads((HOST/'CONTEXT.json').read_text())
    assert sha(HOST/'PROFILE.json')==ctx['profileFileSHA256']
    started=time.monotonic();handled=[]
    while time.monotonic()-started<seconds and len(handled)<limit:
        guard()
        for request in sorted((mail/'requests').glob('*.json')):
            assert not request.is_symlink() and re.fullmatch('[0-9a-f-]{36}\.json',request.name)
            final=mail/'responses'/request.name
            if final.exists():continue
            pending=final.with_suffix('.pending')
            assert not pending.exists()
            result=subprocess.run([sys.executable,'-B',str(ROOT/'tools/witch_purchase_authority/local_exchange_r454.py'),'--request',str(request),'--profile',str(HOST/'PROFILE.json'),'--profile-sha256',ctx['profileFileSHA256'],'--authority-db',str(HOST/'authority.sqlite'),'--cache-db',str(HOST/'cache.sqlite'),'--expected-account',ctx['testAccountID'],'--expected-token',ctx['appAccountToken'],'--output',str(pending)],capture_output=True,text=True,timeout=15)
            assert result.returncode in (0,2) and pending.is_file(),result.stdout+result.stderr
            # Publish only the complete response. Atomic exclusive link protects an existing response.
            os.link(pending,final)
            response=json.loads(final.read_text())
            row={'request':str(request),'requestSHA256':sha(request),'response':str(final),'responseSHA256':sha(final),'status':response['status'],'returnCode':result.returncode,'elapsed':time.monotonic()-started}
            handled.append(row);write_new(HERE/('EXCHANGE_'+request.stem+'.json'),row)
            print(json.dumps(row),flush=True)
            if len(handled)>=limit:break
        time.sleep(.25)
    print(json.dumps({'status':'BOUNDED_HOST_STOPPED','handled':len(handled),'elapsed':time.monotonic()-started}),flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();s=p.add_subparsers(dest='command',required=True)
    a=s.add_parser('capture');a.add_argument('label');a.add_argument('--screenshot',action='store_true')
    a=s.add_parser('serve');a.add_argument('--seconds',type=int,default=300);a.add_argument('--limit',type=int,default=1)
    a=p.parse_args()
    if a.command=='capture':capture(a.label,a.screenshot)
    else:serve(a.seconds,a.limit)

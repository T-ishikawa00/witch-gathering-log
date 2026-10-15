"""Generate one real adapter export from an isolated, explicitly mocked authority."""
import hashlib, json, sys
from pathlib import Path
ROOT=Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
sys.path.insert(0,str(ROOT));sys.dont_write_bytecode=True
from tools.witch_purchase_authority.authority import CandidateDrawEngine, PurchaseAuthority
from tools.witch_purchase_authority.local_delivery_r453 import LocalDeliveryProfileR453, LocalDeliveryAdapterR453
BASE=ROOT/'docs/production/current/qa_drafts/gacha_local_integration_r453'
HERE=Path(__file__).absolute().parent

def canonical(x): return json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()+b'\n'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    unit=json.loads((HERE/'PYTHON_RESULT_R003.json').read_text());assert unit['status']=='PASS'
    for row in unit['sourcePins']: assert sha(ROOT/row['path'])==row['sha256']
    out=HERE/'authority_fixture';out.mkdir(exist_ok=False)
    profile_file=BASE/'candidate_r004/PROFILE_EXAMPLE_R453.json'
    event_file=BASE/'candidate_r004/EVENT_ENVELOPE_EXAMPLE_R453.json'
    raw=json.loads(profile_file.read_text());event=json.loads(event_file.read_text())
    profile=LocalDeliveryProfileR453.from_mapping(raw)
    auth=PurchaseAuthority(out/'authority.sqlite',bundle_id=profile.bundle_id,
         product_specs=profile.product_specs,summon_pool=profile.summon_pool,
         allow_test_mock_verifier=True,clock=lambda:1800000010)
    auth.register_account(event['testAccountID'],event['appAccountToken'])
    adapter=LocalDeliveryAdapterR453(auth,profile,out/'cache.sqlite')
    grant=adapter.grant_ticket_only(event)
    # Select a fixed test seed solely to exercise non-null latent serialization.
    # This is not a representative RNG distribution or a progression result.
    seed=next(s for s in range(10000) if any(d['qualityID']=='Q4' for d in CandidateDrawEngine(profile.summon_pool,s).draw(3,{})[0]))
    op='45300000-0000-4000-8000-000000000001'
    receipt=adapter.draw_from_ticket_balance(event,operation_id=op,count=3,test_seed=seed)
    state=auth.snapshot(event['testAccountID'])
    assert state['ticket_balance']==1 and state['draw_count']==3
    assert adapter.draw_from_ticket_balance(event,operation_id=op,count=3,test_seed=seed)==receipt
    assert state==auth.snapshot(event['testAccountID'])
    for name,value in [('grant.json',grant),('delivery.json',receipt),('authority_state.json',state)]:
        with (out/name).open('xb') as f: f.write(canonical(value))
    result={'status':'EXPLICIT_MOCK_AUTHORITY_EXPORT_PASS','deliverySHA256':sha(out/'delivery.json'),
            'profileFileSHA256':sha(profile_file),'eventFileSHA256':sha(event_file),
            'profileFingerprint':profile.profile_fingerprint,'seed':seed,'operationID':op,
            'poolCount':len(profile.summon_pool),'ticketsGranted':4,'ticketsRemaining':1,'gearCount':3,
            'gearQualities':[g['qualityID'] for g in receipt['gearInstances']],
            'replayByteStable':True,'sourcePins':unit['sourcePins'],
            'productionEntitlementAuthorized':False,'storeKitTransactionUsed':False,
            'purpose':'Cross-language payload and SaveRepository integration, including non-null latent effect; not RNG/balance proof'}
    with (out/'RESULT.json').open('xb') as f:f.write(canonical(result))
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()

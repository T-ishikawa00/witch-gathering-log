"""Root integration fixture: real synthetic ES256 checks, ledger, and R461 wire responses.

Only public synthetic transaction material is exported. Private keys remain in RAM.
No Apple transaction, network, account authentication, or production entitlement.
"""
import hashlib, json, os
from pathlib import Path
from unittest.mock import patch
from tools.witch_purchase_authority.local_delivery_r453 import LocalDeliveryProfileR453
from tools.witch_purchase_authority.signed_transaction_audit import AuditProduct
from tools.witch_purchase_authority.sandbox_ledger_adapter_r459 import SandboxLedgerRehearsalR459
from tools.witch_purchase_authority.local_service_r461 import (
    LocalAuthorityServiceR461, R461CandidatePolicy, VerifiedPrincipalR461,
    export_cross_language_fixture, _canonical)
from test_signed_transaction_audit import SignedTransactionAuditTests
from test_local_service_r461 import profile_mapping, FixedPrincipalProvider, BUNDLE, PRODUCT, ACCOUNT, TOKEN, BINDING, OPERATION

ROOT=Path('/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg')
BASE=ROOT/'docs/production/current/qa_drafts/authority_contract_r461/root_test_tools_r001'
LEDGER=ROOT/'native/build/ActiveIntegrationR461/python_r001/ledger'

def main():
    assert not LEDGER.exists()
    LEDGER.mkdir()
    SignedTransactionAuditTests.setUpClass()
    crypto=SignedTransactionAuditTests()
    profile=LocalDeliveryProfileR453.from_mapping(profile_mapping())
    with patch('requests.sessions.Session.request', side_effect=AssertionError('NETWORK_FORBIDDEN')) as network:
        rehearsal=SandboxLedgerRehearsalR459.create(database_directory=LEDGER/'r459-sandbox-rehearsal',
            bundle_id=BUNDLE, product_specs=profile.product_specs,
            audit_products={PRODUCT: AuditProduct('Consumable',1)}, summon_pool=profile.summon_pool,
            root_certificates=(crypto.root_der,), fixture_account_bindings={ACCOUNT:TOKEN},
            clock=lambda:crypto.now_ms//1000, clock_ms=lambda:crypto.now_ms)
        policy=R461CandidatePolicy(profile_id=profile.profile_id, profile_fingerprint=profile.profile_fingerprint,
            bundle_id=BUNDLE,draw_count_by_product={PRODUCT:2},test_seed=453,
            quality_payloads={q:{'affixIDs':list(v['affixIDs']),'latentEffectID':v['latentEffectID']}
                              for q,v in profile.quality_payloads.items()})
        service=LocalAuthorityServiceR461(rehearsal=rehearsal, policy=policy, profile=profile,
            principal_provider=FixedPrincipalProvider(VerifiedPrincipalR461(ACCOUNT,TOKEN,BINDING)))
        payload={'bundleId':BUNDLE,'environment':'Sandbox','productId':PRODUCT,
            'transactionId':'r461-synthetic-signed-1','originalTransactionId':'r461-synthetic-signed-1',
            'quantity':1,'appAccountToken':TOKEN,'purchaseDate':crypto.now_ms-1000,
            'signedDate':crypto.now_ms,'type':'Consumable','inAppOwnershipType':'PURCHASED'}
        request=_canonical({'schemaVersion':1,'operationID':OPERATION,'action':'purchaseAndDraw',
                            'signedTransactionJWS':crypto.sign(payload)})
        revoked=dict(payload,revocationDate=crypto.now_ms,revocationReason=0)
        notice={'notificationType':'REFUND','notificationUUID':'577d855c-1984-47c2-87d1-431258d38461',
            'version':'2.0','signedDate':crypto.now_ms,'data':{'environment':'Sandbox','bundleId':BUNDLE,
            'signedTransactionInfo':crypto.sign(revoked)}}
        result=export_cross_language_fixture(BASE/'signed_exchange_fixture',service,request,
            trusted_transport_context='EXPLICIT_SYNTHETIC_PRINCIPAL',
            signed_refund_notification_jws=crypto.sign(notice),allowed_root=BASE)
        network.assert_not_called()
        final=rehearsal.authority.snapshot(ACCOUNT)
        assert final['draw_count']==2 and final['ticket_balance']==0 and final['ticket_debt']==2
        result.update(realCryptographicVerifierUsed=True,syntheticRootNotApple=True,networkCalls=0,
                      privateKeysPersisted=False,finalDrawCount=2,finalTicketBalance=0,finalTicketDebt=2,
                      scope='Synthetic signed chain -> actual R459 adapter -> R461 service; no production authorization')
        with (BASE/'SIGNED_EXCHANGE_RESULT.json').open('x') as f:json.dump(result,f,indent=2);f.write('\n')
        print(json.dumps({'status':'SCOPED_PASS','fixture':result['crossLanguageFixture'],
                          'drawCount':2,'refundDebt':2,'networkCalls':0}))

if __name__=='__main__':main()

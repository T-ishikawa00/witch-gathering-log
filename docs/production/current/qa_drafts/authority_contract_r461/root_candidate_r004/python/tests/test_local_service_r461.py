"""Focused no-network contract tests for the R461 local candidate boundary.

All transaction material is synthetic. These tests do not authorize purchases.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import uuid
from types import SimpleNamespace

from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

from tools.witch_purchase_authority.authority import ProductSpec
from tools.witch_purchase_authority.signed_transaction_audit import AuditProduct
from tools.witch_purchase_authority.sandbox_ledger_adapter_r459 import SandboxLedgerRehearsalR459
from tools.witch_purchase_authority.local_delivery_r453 import LocalDeliveryProfileR453
from tools.witch_purchase_authority.local_service_r461 import (
    DenyAllPrincipalProviderR461, LocalAuthorityServiceR461, R461CandidatePolicy,
    VerifiedPrincipalR461, _canonical, _sha, export_cross_language_fixture,
)

BUNDLE = "local.witch.r461.synthetic"
PRODUCT = "local.witch.r461.ticket-pack"
ACCOUNT = "r461-synthetic-account"
TOKEN = "58a1f012-6410-4dd9-9c71-2e342013b485"
BINDING = "fixture-binding-r461-01"
OPERATION = "26c3c2a8-dac9-48d4-af13-f52d0c0656e2"


def profile_mapping():
    return {
        "schemaVersion": 1, "status": "UNAPPROVED_TEST_OVERLAY",
        "profileID": "r461-synthetic-candidate", "bundleID": BUNDLE,
        "productSpecs": {PRODUCT: {"ticketsPerUnit": 4, "maxQuantity": 1}},
        "summonPool": ["EQ_A_01", "EQ_W_01"],
        "templates": {
            "EQ_A_01": {"definitionID": "EQ_A_01", "slotID": "weapon", "compatibleActorIDs": ["C_APPRENTICE"]},
            "EQ_W_01": {"definitionID": "EQ_W_01", "slotID": "weapon", "compatibleActorIDs": ["C_WITCH"]},
        },
        "qualityPayloads": {
            "Q0": {"affixIDs": [], "latentEffectID": None},
            "Q1": {"affixIDs": ["AFFIX_POWER_TEST"], "latentEffectID": None},
            "Q2": {"affixIDs": ["AFFIX_POWER_TEST", "AFFIX_GUARD_TEST"], "latentEffectID": None},
            "Q3": {"affixIDs": ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"], "latentEffectID": None},
            "Q4": {"affixIDs": ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST", "AFFIX_GUARD_TEST"], "latentEffectID": "LATENT_VITALITY_TEST"},
        },
    }


class SyntheticAuditor:
    """Only for facade mechanics: records calls and supplies synthetic verified shapes."""
    bundle_id = BUNDLE
    environment = "Sandbox"
    root_sha256 = ("a" * 64,)
    products = {PRODUCT: AuditProduct("Consumable", 1)}

    def __init__(self):
        self.audit_calls = 0

    def audit(self, jws, *, expected_account_token):
        self.audit_calls += 1
        if expected_account_token != TOKEN:
            raise ValueError("synthetic account mismatch")
        txid = jws.rsplit(".", 1)[-1]
        return SimpleNamespace(environment="Sandbox", bundle_id=BUNDLE, transaction_id=txid,
            original_transaction_id=f"original-{txid}", product_id=PRODUCT,
            product_type="Consumable", quantity=1, purchase_date_ms=1_800_000_001_000,
            status="OFFLINE_CHAIN_CHECKED_NOT_AUTHORIZATION", grant_authorized=False,
            revocation_checked=False)

    def audit_refund_notification(self, signed_notification, *, expected_account_token):
        self.audit_calls += 1
        txid = signed_notification.rsplit(".", 1)[-1]
        transaction = self.audit(f"a.b.{txid}", expected_account_token=expected_account_token)
        return SimpleNamespace(transaction=transaction,
            notification_uuid="d612c5e9-b104-4b4c-97d3-926145a96c34",
            status="OFFLINE_REFUND_NOTICE_CHECKED_NOT_AUTHORIZATION",
            grant_authorized=False, revocation_checked=False)


class FixedPrincipalProvider:
    def __init__(self, principal):
        self.principal = principal
        self.calls = 0

    def resolve(self, _context):
        self.calls += 1
        return self.principal


class LocalServiceR461Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve(strict=True)
        self.db_dir = self.root / "r459-sandbox-rehearsal"
        now = datetime.now(timezone.utc)
        key = ec.generate_private_key(ec.SECP256R1())
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "NOT APPLE - R461 fixture root")])
        cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
                .public_key(key.public_key()).serial_number(x509.random_serial_number())
                .not_valid_before(now - timedelta(days=1)).not_valid_after(now + timedelta(days=1))
                .add_extension(x509.BasicConstraints(ca=True, path_length=1), critical=True)
                .sign(key, hashes.SHA256()))
        self.profile = LocalDeliveryProfileR453.from_mapping(profile_mapping())
        self.rehearsal = SandboxLedgerRehearsalR459.create(
            database_directory=self.db_dir, bundle_id=BUNDLE,
            product_specs={PRODUCT: ProductSpec(PRODUCT, tickets_per_unit=4, max_quantity=1)},
            audit_products={PRODUCT: AuditProduct("Consumable", 1)},
            summon_pool=("EQ_A_01", "EQ_W_01"), root_certificates=(cert.public_bytes(serialization.Encoding.DER),),
            fixture_account_bindings={ACCOUNT: TOKEN}, clock=lambda: 1_800_000_005,
            clock_ms=lambda: 1_800_000_005_000)
        self.fake_auditor = SyntheticAuditor()
        self.rehearsal.auditor = self.fake_auditor
        quality = {q: {"affixIDs": row["affixIDs"], "latentEffectID": row["latentEffectID"]}
                   for q, row in self.profile.quality_payloads.items()}
        self.policy = R461CandidatePolicy(profile_id=self.profile.profile_id,
            profile_fingerprint=self.profile.profile_fingerprint, bundle_id=BUNDLE,
            draw_count_by_product={PRODUCT: 2}, test_seed=453, quality_payloads=quality)
        self.principal = VerifiedPrincipalR461(ACCOUNT, TOKEN, BINDING)
        self.provider = FixedPrincipalProvider(self.principal)
        self.service = LocalAuthorityServiceR461(rehearsal=self.rehearsal,
            policy=self.policy, profile=self.profile, principal_provider=self.provider)

    def tearDown(self):
        self.temp.cleanup()

    @staticmethod
    def request(operation=OPERATION, jws="a.b.tx-r461-1", extra=None):
        value = {"schemaVersion": 1, "operationID": operation,
                 "action": "purchaseAndDraw", "signedTransactionJWS": jws}
        if extra:
            value.update(extra)
        return _canonical(value)

    def test_default_deny_precedes_jws_and_ledger(self):
        before = self.rehearsal.authority.snapshot(ACCOUNT)
        service = LocalAuthorityServiceR461(rehearsal=self.rehearsal, policy=self.policy,
                                             profile=self.profile)
        raw = self.request()
        response = json.loads(service.handle(raw))
        self.assertEqual(response["errorCode"], "AUTHENTICATION_REQUIRED")
        self.assertIsNone(response["accountBindingSHA256"])
        self.assertIsNone(response["currentState"])
        self.assertEqual(self.fake_auditor.audit_calls, 0)
        self.assertEqual(before, self.rehearsal.authority.snapshot(ACCOUNT))

    def test_unknown_fields_reject_before_provider_or_ledger(self):
        before = self.rehearsal.authority.snapshot(ACCOUNT)
        raw = self.request(extra={"productID": PRODUCT})
        result = json.loads(self.service.handle(raw))
        self.assertEqual(result["errorCode"], "REQUEST_INVALID")
        self.assertEqual(self.provider.calls, 0)
        self.assertEqual(before, self.rehearsal.authority.snapshot(ACCOUNT))

    def test_delivery_and_retry_are_byte_stable_with_fresh_snapshot(self):
        raw = self.request()
        first = self.service.handle(raw)
        before_retry = self.rehearsal.authority.snapshot(ACCOUNT)
        replay = self.service.handle(raw)
        payload = json.loads(first)
        self.assertEqual(first, replay)
        self.assertEqual(payload["status"], "DELIVERED")
        self.assertEqual(payload["authorizationStatus"], "NOT_AUTHORIZED_FOR_PRODUCTION")
        self.assertEqual(payload["requestSHA256"], _sha(raw))
        self.assertEqual(payload["historicalDelivery"]["operationID"], OPERATION)
        self.assertEqual(payload["historicalDelivery"]["drawReceipt"]["idempotencyKey"], OPERATION)
        self.assertEqual(payload["currentState"]["revision"], before_retry["revision"])
        self.assertEqual(len(payload["historicalDelivery"]["deliveredItems"]), 2)
        self.assertEqual(len({r["gearID"] for r in payload["historicalDelivery"]["deliveredItems"]}), 2)
        self.assertEqual(payload["historicalDelivery"]["deliveryFingerprint"],
            _sha(_canonical({k: payload["historicalDelivery"][k] for k in (
                "profileID", "profileFingerprint", "transactionIdentity", "operationID", "drawReceipt", "deliveredItems")})))
        self.assertTrue(first.endswith(b"\n"))
        self.assertEqual(self.rehearsal.authority.snapshot(ACCOUNT)["draw_count"], 2)

    def test_same_operation_with_changed_transaction_rejects_without_second_draw(self):
        self.service.handle(self.request())
        before = self.rehearsal.authority.snapshot(ACCOUNT)
        changed = self.request(jws="a.b.tx-r461-other")
        response = json.loads(self.service.handle(changed))
        self.assertEqual(response["status"], "REJECTED")
        self.assertEqual(response["errorCode"], "OPERATION_ID_COLLISION")
        self.assertEqual(response["currentState"]["status"], "unknown")
        self.assertEqual(before, self.rehearsal.authority.snapshot(ACCOUNT))

    def test_policy_profile_must_bind_all_item_payloads(self):
        bad = R461CandidatePolicy(profile_id=self.profile.profile_id,
            profile_fingerprint="0" * 64, bundle_id=BUNDLE, draw_count_by_product={PRODUCT: 2},
            test_seed=453, quality_payloads={q: {"affixIDs": [], "latentEffectID": None} for q in ("Q0", "Q1", "Q2", "Q3", "Q4")})
        with self.assertRaises(ValueError):
            LocalAuthorityServiceR461(rehearsal=self.rehearsal, policy=bad, profile=self.profile,
                                     principal_provider=self.provider)
        payload_drift = R461CandidatePolicy(profile_id=self.profile.profile_id,
            profile_fingerprint=self.profile.profile_fingerprint, bundle_id=BUNDLE,
            draw_count_by_product={PRODUCT: 2}, test_seed=453,
            quality_payloads={q: {"affixIDs": [], "latentEffectID": None} for q in ("Q0", "Q1", "Q2", "Q3", "Q4")})
        with self.assertRaises(ValueError):
            LocalAuthorityServiceR461(rehearsal=self.rehearsal, policy=payload_drift, profile=self.profile,
                                     principal_provider=self.provider)
        with self.assertRaises(TypeError):
            self.policy.quality_payloads["Q1"]["affixIDs"] = ("AFFIX_GUARD_TEST",)


    def test_policy_pin_survives_restart_and_rejects_profile_drift(self):
        raw = self.request()
        first = self.service.handle(raw)
        restarted = LocalAuthorityServiceR461(rehearsal=self.rehearsal, policy=self.policy,
            profile=self.profile, principal_provider=self.provider)
        self.assertEqual(restarted.handle(raw), first)
        self.assertEqual(self.rehearsal.authority.snapshot(ACCOUNT)["draw_count"], 2)

        changed_mapping = profile_mapping()
        changed_mapping["qualityPayloads"]["Q1"]["affixIDs"] = ["AFFIX_GUARD_TEST"]
        changed_profile = LocalDeliveryProfileR453.from_mapping(changed_mapping)
        changed_quality = {q: {"affixIDs": row["affixIDs"], "latentEffectID": row["latentEffectID"]}
                           for q, row in changed_profile.quality_payloads.items()}
        changed_policy = R461CandidatePolicy(profile_id=changed_profile.profile_id,
            profile_fingerprint=changed_profile.profile_fingerprint, bundle_id=BUNDLE,
            draw_count_by_product={PRODUCT: 2}, test_seed=453, quality_payloads=changed_quality)
        with self.assertRaisesRegex(ValueError, "original pin"):
            LocalAuthorityServiceR461(rehearsal=self.rehearsal, policy=changed_policy,
                profile=changed_profile, principal_provider=self.provider)
        self.assertEqual(self.rehearsal.authority.snapshot(ACCOUNT)["draw_count"], 2)

    def test_synthetic_export_contains_exact_python_request_and_three_responses(self):
        output = self.root / "cross-language-fixture"
        fixture = export_cross_language_fixture(output, self.service, self.request(),
            trusted_transport_context="synthetic-test-context", signed_refund_notification_jws="a.b.tx-r461-1",
            allowed_root=self.root)
        wrapper_bytes = (output / "CROSS_LANGUAGE_FIXTURE.json").read_bytes()
        wrapper = json.loads(wrapper_bytes)
        import base64
        request_bytes = base64.b64decode(wrapper["requestBase64"], validate=True)
        self.assertEqual(request_bytes, self.request())
        self.assertEqual(hashlib.sha256(request_bytes).hexdigest(), wrapper["requestSHA256"])
        self.assertEqual([row["kind"] for row in wrapper["responses"]], ["delivered", "replay", "postRefund"])
        for row in wrapper["responses"]:
            response = base64.b64decode(row["base64"], validate=True)
            self.assertEqual(hashlib.sha256(response).hexdigest(), row["sha256"])
            self.assertTrue(response.endswith(b"\n"))
        refunded = json.loads(base64.b64decode(wrapper["responses"][2]["base64"]))
        self.assertEqual(refunded["currentState"]["status"], "refunded")
        self.assertIsNone(refunded["historicalDelivery"])
        self.assertFalse(fixture["productionEntitlementAuthorized"])


    def test_root_unauthenticated_envelopes_have_null_correlation(self):
        denied = LocalAuthorityServiceR461(rehearsal=self.rehearsal, policy=self.policy, profile=self.profile)
        response = json.loads(denied.handle(self.request()))
        self.assertIsNone(response["operationID"])
        self.assertIsNone(response["accountBindingSHA256"])
        class BrokenProvider:
            def resolve(self, context): raise RuntimeError("synthetic provider failure")
        broken = LocalAuthorityServiceR461(rehearsal=self.rehearsal, policy=self.policy,
            profile=self.profile, principal_provider=BrokenProvider())
        response = json.loads(broken.handle(self.request()))
        self.assertEqual(response["errorCode"], "AUTHENTICATION_PROVIDER_ERROR")
        self.assertIsNone(response["operationID"])
        invalid = json.loads(self.request()); invalid["action"] = "unsupported"
        response = json.loads(self.service.handle(_canonical(invalid)))
        self.assertEqual(response["errorCode"], "REQUEST_INVALID")
        self.assertIsNone(response["operationID"])

    def test_root_policy_drift_rejection_retains_authenticated_binding(self):
        self.service.policy = R461CandidatePolicy(profile_id=self.profile.profile_id,
            profile_fingerprint=self.profile.profile_fingerprint, bundle_id=BUNDLE,
            draw_count_by_product={PRODUCT: 2}, test_seed=999,
            quality_payloads=self.policy.quality_payloads)
        before = self.rehearsal.authority.snapshot(ACCOUNT)
        response = json.loads(self.service.handle(self.request()))
        self.assertEqual(response["errorCode"], "AUTHORITY_REJECTED")
        self.assertEqual(response["operationID"], OPERATION)
        self.assertEqual(response["accountBindingSHA256"], _sha(BINDING.encode()))
        self.assertIsNone(response["historicalDelivery"])
        self.assertIsNone(response["currentState"])
        self.assertEqual(before, self.rehearsal.authority.snapshot(ACCOUNT))

    def test_root_metadata_pin_cannot_redirect_to_another_database(self):
        foreign = self.root / "foreign" / "r459-sandbox-rehearsal" / "authority.sqlite"
        foreign.parent.mkdir(parents=True); foreign.write_bytes(b"")
        original = self.rehearsal.authority.db_path
        try:
            self.rehearsal.authority.db_path = str(foreign)
            with self.assertRaises(ValueError):
                LocalAuthorityServiceR461(rehearsal=self.rehearsal, policy=self.policy,
                    profile=self.profile, principal_provider=self.provider)
            self.assertEqual(foreign.read_bytes(), b"")
        finally:
            self.rehearsal.authority.db_path = original


if __name__ == "__main__":
    unittest.main()

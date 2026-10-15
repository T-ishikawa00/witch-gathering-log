"""Real ES256/X.509 checks using ephemeral, explicitly non-Apple test keys.

No signed receipt, private key or account data is written to disk. No network.
"""
import base64
from dataclasses import asdict, replace
from datetime import datetime, timedelta, timezone
import json
import unittest
from pathlib import Path
from unittest.mock import patch
from importlib.util import find_spec

# The existing stdlib-only authority suite stays runnable without installing
# this optional crypto audit. Its dedicated pinned-venv run must have zero skips.
if any(find_spec(name) is None for name in ("cryptography", "jwt", "appstoreserverlibrary")):
    raise unittest.SkipTest("Optional crypto audit requires signed_audit_requirements.lock in its isolated venv")

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID, ObjectIdentifier
import jwt

from signed_transaction_audit_r459 import AuditProduct, OfflineTransactionAuditor, SignedAuditError
from authority_r459 import ProductSpec, PurchaseAuthority, DuplicateTransaction, InjectedFailure
from sandbox_ledger_adapter_r459 import SandboxLedgerRehearsalR459


BUNDLE = "local.witch.synthetic.audit"
PRODUCT = "local.witch.synthetic.ticket"
TOKEN = "ffb73c4d-e219-40ef-952f-bd6b515a9870"
OTHER_TOKEN = "f5229530-1aa0-4555-848f-cfe2e2b85ce7"


def certificate(subject, key, issuer, issuer_key, *, ca, now, path_length=None, apple_oid=None):
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, subject)])
    builder = (x509.CertificateBuilder().subject_name(name).issuer_name(issuer or name)
               .public_key(key.public_key()).serial_number(x509.random_serial_number())
               .not_valid_before(now - timedelta(days=1)).not_valid_after(now + timedelta(days=1))
               .add_extension(x509.BasicConstraints(ca=ca, path_length=path_length), critical=True)
               .add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False,
                   key_encipherment=False, data_encipherment=False, key_agreement=False,
                   key_cert_sign=ca, crl_sign=ca, encipher_only=None, decipher_only=None), critical=True)
               .add_extension(x509.SubjectKeyIdentifier.from_public_key(key.public_key()), critical=False)
               .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(issuer_key.public_key()), critical=False))
    if apple_oid:
        # A synthetic extension tests upstream validation; it does not turn this
        # locally generated chain into an Apple-issued certificate.
        builder = builder.add_extension(x509.UnrecognizedExtension(ObjectIdentifier(apple_oid), b"\x05\x00"), critical=False)
    return builder.sign(issuer_key, hashes.SHA256())


class SignedTransactionAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.now = datetime.now(timezone.utc)
        cls.now_ms = int(cls.now.timestamp() * 1000)
        cls.root_key, cls.inter_key, cls.leaf_key = [ec.generate_private_key(ec.SECP256R1()) for _ in range(3)]
        cls.root = certificate("NOT APPLE - local audit root", cls.root_key, None, cls.root_key,
                               ca=True, path_length=1, now=cls.now)
        cls.inter = certificate("NOT APPLE - local audit issuer", cls.inter_key, cls.root.subject, cls.root_key,
                                ca=True, path_length=0, now=cls.now, apple_oid="1.2.840.113635.100.6.2.1")
        cls.leaf = certificate("NOT APPLE - local audit leaf", cls.leaf_key, cls.inter.subject, cls.inter_key,
                               ca=False, now=cls.now, apple_oid="1.2.840.113635.100.6.11.1")
        cls.root_der = cls.root.public_bytes(serialization.Encoding.DER)
        cls.chain = [base64.b64encode(c.public_bytes(serialization.Encoding.DER)).decode("ascii")
                     for c in (cls.leaf, cls.inter, cls.root)]

    def setUp(self):
        self.no_network = patch("requests.sessions.Session.request", side_effect=AssertionError("NETWORK_FORBIDDEN_IN_OFFLINE_TEST"))
        self.network = self.no_network.start()
        self.addCleanup(self.no_network.stop)
        self.auditor = self.make_auditor()
        self.payload = {"bundleId": BUNDLE, "environment": "Sandbox", "productId": PRODUCT,
                        "transactionId": "synthetic-1001", "originalTransactionId": "synthetic-1001",
                        "quantity": 1, "appAccountToken": TOKEN, "purchaseDate": self.now_ms - 1000,
                        "signedDate": self.now_ms, "type": "Consumable", "inAppOwnershipType": "PURCHASED"}

    def make_auditor(self, **changes):
        args = dict(root_certificates=(self.root_der,), bundle_id=BUNDLE,
                    products={PRODUCT: AuditProduct("Consumable", 2)}, clock_ms=lambda: self.now_ms)
        args.update(changes)
        return OfflineTransactionAuditor(**args)

    def sign(self, payload=None, *, key=None, headers=None):
        return jwt.encode(payload or self.payload, key or self.leaf_key, algorithm="ES256",
                          headers=headers or {"x5c": self.chain})

    def audit(self, token, expected=TOKEN):
        return self.auditor.audit(token, expected_account_token=expected)

    def assert_rejected_payload(self, **changes):
        data = dict(self.payload, **changes)
        with self.assertRaises(SignedAuditError):
            self.audit(self.sign(data))

    def test_real_signed_chain_passes_strict_checks_but_cannot_authorize_grant(self):
        result = self.audit(self.sign())
        self.assertTrue(self.auditor._verifier._chain_verifier.enable_strict_checks)
        self.assertEqual((result.transaction_id, result.quantity), ("synthetic-1001", 1))
        self.assertEqual(result.status, "OFFLINE_CHAIN_CHECKED_NOT_AUTHORIZATION")
        self.assertFalse(result.grant_authorized)
        self.assertFalse(result.revocation_checked)
        self.assertNotIn(TOKEN, json.dumps(asdict(result)))
        self.network.assert_not_called()

    def test_tampered_payload_rejected_without_raw_data_in_error(self):
        parts = self.sign().split(".")
        parts[1] = base64.urlsafe_b64encode(json.dumps(dict(self.payload, quantity=2)).encode()).decode().rstrip("=")
        with self.assertRaisesRegex(SignedAuditError, "^SIGNATURE_OR_CHAIN_REJECTED$"):
            self.audit(".".join(parts))

    def test_audit_report_does_not_allow_constructor_or_replace_to_authorize(self):
        result = self.audit(self.sign())
        with self.assertRaisesRegex((TypeError, ValueError), "init=False"):
            replace(result, grant_authorized=True)
        with self.assertRaises(TypeError):
            type(result)(**asdict(result))
        self.assertFalse(result.grant_authorized)

    def test_signature_from_other_key_rejected(self):
        with self.assertRaises(SignedAuditError):
            self.audit(self.sign(key=ec.generate_private_key(ec.SECP256R1())))

    def test_untrusted_root_cannot_be_supplied_by_jws_chain(self):
        alternate = ec.generate_private_key(ec.SECP256R1())
        alternate_root = certificate("NOT APPLE - other root", alternate, None, alternate, ca=True, path_length=1, now=self.now)
        auditor = self.make_auditor(root_certificates=(alternate_root.public_bytes(serialization.Encoding.DER),))
        with self.assertRaises(SignedAuditError):
            auditor.audit(self.sign(), expected_account_token=TOKEN)

    def test_required_leaf_oid_is_checked(self):
        leaf = certificate("NOT APPLE - wrong leaf usage", self.leaf_key, self.inter.subject, self.inter_key, ca=False, now=self.now)
        chain = [base64.b64encode(leaf.public_bytes(serialization.Encoding.DER)).decode()] + self.chain[1:]
        with self.assertRaises(SignedAuditError):
            self.audit(self.sign(headers={"x5c": chain}))

    def test_wrong_bundle_and_environment_rejected(self):
        self.assert_rejected_payload(bundleId="other.app")
        for env in ("Production", "Xcode", "LocalTesting", "Unknown", None):
            with self.subTest(env=env): self.assert_rejected_payload(environment=env)

    def test_xcode_local_and_production_configuration_never_bypass_signature(self):
        for env in ("Production", "Xcode", "LocalTesting", "", None):
            with self.subTest(env=env), self.assertRaises(SignedAuditError): self.make_auditor(environment=env)

    def test_missing_or_different_account_binding_rejected(self):
        with self.assertRaises(SignedAuditError): self.audit(self.sign(), OTHER_TOKEN)
        for token in (None, "", "not-a-uuid", "00000000-0000-0000-0000-000000000000", True):
            with self.subTest(token=token): self.assert_rejected_payload(appAccountToken=token)

    def test_uuid_case_normalizes_without_losing_binding(self):
        self.assertEqual(self.audit(self.sign(dict(self.payload, appAccountToken=TOKEN.upper()))).quantity, 1)

    def test_quantity_types_and_bounds_rejected(self):
        for quantity in (True, False, "1", 1.0, None, 0, -1, 3, 10**100):
            with self.subTest(quantity=quantity): self.assert_rejected_payload(quantity=quantity)

    def test_product_and_type_policy(self):
        self.assert_rejected_payload(productId="unlisted")
        self.assert_rejected_payload(type="Auto-Renewable Subscription")
        self.assert_rejected_payload(type="Non-Consumable")

    def test_revoked_or_family_shared_transaction_is_not_purchase_candidate(self):
        for field in ("revocationDate", "revocationReason", "revocationType"):
            with self.subTest(field=field): self.assert_rejected_payload(**{field: 0})
        self.assert_rejected_payload(inAppOwnershipType="FAMILY_SHARED")
        self.assert_rejected_payload(inAppOwnershipType=None)

    def test_future_invalid_or_out_of_order_dates(self):
        for changes in ({"signedDate": self.now_ms + 300001}, {"purchaseDate": self.now_ms + 1},
                        {"purchaseDate": True}, {"signedDate": str(self.now_ms)},
                        {"signedDate": None}, {"purchaseDate": 0}):
            with self.subTest(changes=changes): self.assert_rejected_payload(**changes)

    def test_historical_restore_time_is_not_arbitrarily_expired(self):
        signed = self.now_ms - 3600_000
        result = self.audit(self.sign(dict(self.payload, signedDate=signed, purchaseDate=signed-1000)))
        self.assertEqual(result.signed_date_ms, signed)
        self.assertFalse(result.grant_authorized)

    def test_invalid_identifiers_are_rejected(self):
        for field in ("transactionId", "originalTransactionId", "productId"):
            for value in (None, "", " a", "\x00id", "x"*300, 123):
                with self.subTest(field=field, value=value): self.assert_rejected_payload(**{field: value})

    def test_malformed_and_oversized_tokens(self):
        for token in (None, "", "a.b.c.d", "a.b.c", "="*8, "x"*65537, self.sign()+"\n"):
            with self.subTest(token_type=type(token).__name__), self.assertRaises(SignedAuditError): self.audit(token)

    def test_header_downgrade_missing_chain_and_critical_header_rejected(self):
        for headers in ({"x5c": self.chain[:2]}, {"x5c": []}, {"x5c": self.chain, "crit": ["custom"]}):
            with self.subTest(headers=list(headers)), self.assertRaises(SignedAuditError): self.audit(self.sign(headers=headers))
        # PyJWT strips b64=True while encoding. Insert the header explicitly;
        # rejection must be at the unsupported-header boundary, before crypto.
        parts = self.sign().split(".")
        header = dict(jwt.get_unverified_header(".".join(parts)), b64=True)
        parts[0] = base64.urlsafe_b64encode(json.dumps(header).encode()).decode().rstrip("=")
        self.assertIn("b64", jwt.get_unverified_header(".".join(parts)))
        with self.assertRaisesRegex(SignedAuditError, "^UNSUPPORTED_JWS_HEADER$"):
            self.audit(".".join(parts))
        token = jwt.encode(self.payload, "synthetic-32-byte-hmac-key-for-test", algorithm="HS256", headers={"x5c": self.chain})
        with self.assertRaises(SignedAuditError): self.audit(token)

    def test_duplicate_json_keys_rejected_even_before_signature(self):
        parts = self.sign().split(".")
        raw = json.dumps(self.payload)[:-1] + ', "quantity": 2}'
        parts[1] = base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")
        with self.assertRaisesRegex(SignedAuditError, "^MALFORMED_JWS_JSON$"): self.audit(".".join(parts))

    def test_invalid_configuration_and_unreviewed_version(self):
        for changes in ({"root_certificates": ()}, {"products": {}}, {"bundle_id": ""}):
            with self.subTest(changes=changes), self.assertRaises(SignedAuditError): self.make_auditor(**changes)
        with patch("signed_transaction_audit_r459.version", return_value="3.1.1"), self.assertRaises(SignedAuditError): self.make_auditor()

    def test_nonconsumable_configuration_and_quantity(self):
        with self.assertRaises(SignedAuditError): AuditProduct("Non-Consumable", 2)
        auditor = self.make_auditor(products={PRODUCT: AuditProduct("Non-Consumable")})
        token = self.sign(dict(self.payload, type="Non-Consumable"))
        result = auditor.audit(token, expected_account_token=TOKEN)
        self.assertEqual(result.product_type, "Non-Consumable")
        self.assertFalse(result.grant_authorized)

    def make_rehearsal(self, suffix="main", *, auditor=None):
        import tempfile
        from pathlib import Path
        temp = tempfile.TemporaryDirectory(prefix="r459-test-")
        self.addCleanup(temp.cleanup)
        root = Path(temp.name).resolve() / "r459-sandbox-rehearsal"
        rehearsal = SandboxLedgerRehearsalR459.create(
            database_directory=root, bundle_id=BUNDLE,
            product_specs={PRODUCT: ProductSpec(PRODUCT, tickets_per_unit=3, max_quantity=2)},
            audit_products={PRODUCT: AuditProduct("Consumable", 2)}, summon_pool=("EQ_W_01",),
            root_certificates=(self.root_der,), fixture_account_bindings={"fixture-account": TOKEN},
            clock=lambda: self.now_ms // 1000, clock_ms=lambda: self.now_ms)
        return rehearsal

    def test_r459_signed_sandbox_purchase_reaches_same_atomic_ledger_and_replays(self):
        rehearsal = self.make_rehearsal()
        signed = self.sign(dict(self.payload, transactionId="r459-purchase-1", originalTransactionId="r459-original-1"))
        first = rehearsal.purchase(account_id="fixture-account", signed_transaction_jws=signed,
            operation_id="r459-op-1", draw_count=0, test_seed=17)
        repeated = rehearsal.purchase(account_id="fixture-account", signed_transaction_jws=signed,
            operation_id="r459-op-1", draw_count=0, test_seed=17)
        self.assertEqual(first, repeated)
        self.assertEqual(first["status"], "NOT_AUTHORIZED_FOR_PRODUCTION")
        self.assertFalse(first["grantAuthorized"])
        self.assertFalse(first["revocationChecked"])
        self.assertEqual(rehearsal.authority.snapshot("fixture-account")["ticket_balance"], 3)
        with self.assertRaises(DuplicateTransaction):
            rehearsal.purchase(account_id="fixture-account", signed_transaction_jws=signed,
                operation_id="r459-op-2", draw_count=0, test_seed=17)
        self.assertEqual(rehearsal.authority.snapshot("fixture-account")["ticket_balance"], 3)

    def test_r459_invalid_signature_identity_policy_and_revocation_never_mutate_ledger(self):
        rehearsal = self.make_rehearsal()
        cases = [
            (self.sign(dict(self.payload, bundleId="other.bundle")), TOKEN),
            (self.sign(dict(self.payload, environment="Production")), TOKEN),
            (self.sign(dict(self.payload, appAccountToken=OTHER_TOKEN)), TOKEN),
            (self.sign(dict(self.payload, productId="unknown.product")), TOKEN),
            (self.sign(dict(self.payload, revocationDate=self.now_ms)), TOKEN),
            (self.sign(key=ec.generate_private_key(ec.SECP256R1())), TOKEN),
        ]
        for i, (signed, expected_token) in enumerate(cases):
            with self.subTest(index=i), self.assertRaises(SignedAuditError):
                rehearsal.auditor.audit(signed, expected_account_token=expected_token)
        self.assertEqual(rehearsal.authority.snapshot("fixture-account")["purchase_count"], 0)
        with self.assertRaises(ValueError):
            rehearsal.purchase(account_id="unbound-account", signed_transaction_jws=self.sign(),
                operation_id="bad", draw_count=0, test_seed=1)
        self.assertEqual(rehearsal.authority.snapshot("fixture-account")["ticket_balance"], 0)

    def test_r459_signed_refund_notification_is_atomic_and_replay_safe(self):
        rehearsal = self.make_rehearsal()
        tx_payload = dict(self.payload, transactionId="r459-refund-tx", originalTransactionId="r459-refund-orig")
        purchase_jws = self.sign(tx_payload)
        rehearsal.purchase(account_id="fixture-account", signed_transaction_jws=purchase_jws,
            operation_id="r459-buy", draw_count=0, test_seed=2)
        revoked_payload = dict(tx_payload, revocationDate=self.now_ms, revocationReason=0)
        revoked_jws = self.sign(revoked_payload)
        notification = {"notificationType":"REFUND", "notificationUUID":"e323a60a-2f4f-49f3-a871-a0b36cafe459",
            "version":"2.0", "signedDate":self.now_ms,
            "data":{"environment":"Sandbox", "bundleId":BUNDLE, "signedTransactionInfo":revoked_jws}}
        notification_jws = self.sign(notification)
        with self.assertRaises(InjectedFailure):
            rehearsal.refund(account_id="fixture-account", signed_notification_jws=notification_jws,
                fail_at="after_domain_mutation")
        self.assertEqual(rehearsal.authority.snapshot("fixture-account")["ticket_balance"], 3)
        result = rehearsal.refund(account_id="fixture-account", signed_notification_jws=notification_jws)
        replay = rehearsal.refund(account_id="fixture-account", signed_notification_jws=notification_jws)
        self.assertEqual(result["result"]["delivery_receipt"]["clawed_back"], 3)
        self.assertEqual(replay["result"]["duplicate_notification"], True)
        self.assertEqual(replay["result"]["delivery_receipt"], result["result"]["delivery_receipt"])
        self.assertFalse(result["grantAuthorized"])
        self.assertFalse(result["onlineRevocationChecked"])
        self.assertEqual(rehearsal.authority.snapshot("fixture-account")["ticket_balance"], 0)



    def test_r459_canonicalizes_symlinked_parent_before_creating_new_root(self):
        import os, tempfile
        from pathlib import Path
        temp=tempfile.TemporaryDirectory(prefix="r459-parent-")
        self.addCleanup(temp.cleanup)
        real=Path(temp.name).resolve()/"canonical"
        real.mkdir()
        alias=Path(temp.name)/"alias"
        os.symlink(real, alias, target_is_directory=True)
        rehearsal=SandboxLedgerRehearsalR459.create(database_directory=alias/"r459-sandbox-rehearsal",
            bundle_id=BUNDLE, product_specs={PRODUCT: ProductSpec(PRODUCT, 3, 2)},
            audit_products={PRODUCT: AuditProduct("Consumable", 2)}, summon_pool=("EQ_W_01",),
            root_certificates=(self.root_der,), fixture_account_bindings={"fixture-account": TOKEN},
            clock=lambda:self.now_ms//1000, clock_ms=lambda:self.now_ms)
        self.assertEqual(rehearsal.database_path.parent, real/"r459-sandbox-rehearsal")
        self.assertEqual((alias/"r459-sandbox-rehearsal").resolve(), rehearsal.database_path.parent)

    def test_r459_rejects_unbound_generic_records_and_public_rehearsal_construction(self):
        from types import SimpleNamespace
        from authority_r459 import VerificationUnavailable
        rehearsal = self.make_rehearsal()
        arbitrary = SimpleNamespace(environment="Sandbox", bundle_id=BUNDLE, transaction_id="x",
            original_transaction_id="x", product_id=PRODUCT, quantity=1,
            app_account_token=TOKEN, purchase_time=self.now_ms // 1000, verified_by="APPLE_SANDBOX_SIGNATURE_VERIFIED_NOT_AUTHORIZED")
        with self.assertRaises(VerificationUnavailable):
            rehearsal.authority._purchase_and_draw_verified("fixture-account", "x", arbitrary, 0, test_seed=1)
        with self.assertRaises(VerificationUnavailable):
            rehearsal.authority._apply_notification_payload("fixture-account", arbitrary, fail_at=None)
        with self.assertRaises(VerificationUnavailable):
            rehearsal.authority._apply_notification_payload("fixture-account", {"environment":"Sandbox"}, fail_at=None)
        with self.assertRaises(TypeError):
            SandboxLedgerRehearsalR459(authority=rehearsal.authority, auditor=rehearsal.auditor,
                database_path=rehearsal.database_path, bundle_id=BUNDLE, account_bindings={}, capability=None)
        from authority_r459 import SandboxVerifiedPurchaseR459, PurchaseAuthority, _SANDBOX_FACTORY_KEY, VerificationUnavailable
        with self.assertRaises(TypeError):
            SandboxVerifiedPurchaseR459("Sandbox", BUNDLE, "x", "x", PRODUCT, 1, TOKEN, self.now_ms // 1000, object())
        import tempfile
        with tempfile.TemporaryDirectory(prefix="r459-foreign-db-") as foreign_dir:
            foreign = PurchaseAuthority(Path(foreign_dir)/"arbitrary.sqlite", bundle_id=BUNDLE,
                product_specs={PRODUCT: ProductSpec(PRODUCT, 3, 2)}, summon_pool=("EQ_W_01",))
            with self.assertRaises(VerificationUnavailable):
                foreign._bind_sandbox_rehearsal(_SANDBOX_FACTORY_KEY)

    def test_r459_refund_notification_rejects_bad_uuid_and_dates_before_ledger_write(self):
        rehearsal = self.make_rehearsal()
        tx = dict(self.payload, transactionId="r459-invalid-refund", originalTransactionId="r459-invalid-refund")
        for changes in ({"bundleId":"other.bundle"}, {"environment":"Production"},
                        {"appAccountToken":OTHER_TOKEN}, {"productId":"unknown.product"},
                        {"revocationReason":True}):
            revoked = dict(tx, signedDate=self.now_ms, revocationDate=self.now_ms, revocationReason=0)
            revoked.update(changes)
            notice = {"notificationType":"REFUND", "notificationUUID":"e323a60a-2f4f-49f3-a871-a0b36cafe451",
                "version":"2.0", "signedDate":self.now_ms,
                "data":{"environment":"Sandbox", "bundleId":BUNDLE, "signedTransactionInfo":self.sign(revoked)}}
            with self.subTest(changes=changes), self.assertRaises(SignedAuditError):
                rehearsal.auditor.audit_refund_notification(self.sign(notice), expected_account_token=TOKEN)
        for notification_id, outer_date, revoke_date, tx_signed in (
            ("not-a-uuid", self.now_ms, self.now_ms, self.now_ms),
            ("e323a60a-2f4f-49f3-a871-a0b36cafe458", True, self.now_ms, self.now_ms),
            ("e323a60a-2f4f-49f3-a871-a0b36cafe457", self.now_ms+300001, self.now_ms, self.now_ms),
            ("e323a60a-2f4f-49f3-a871-a0b36cafe456", self.now_ms, self.now_ms-2000, self.now_ms),
            ("e323a60a-2f4f-49f3-a871-a0b36cafe455", self.now_ms, self.now_ms+1, self.now_ms),
            ("e323a60a-2f4f-49f3-a871-a0b36cafe452", self.now_ms-500, self.now_ms-100, self.now_ms),
        ):
            revoked = dict(tx, signedDate=tx_signed, revocationDate=revoke_date, revocationReason=0)
            notice = {"notificationType":"REFUND", "notificationUUID":notification_id,
                "version":"2.0", "signedDate":outer_date,
                "data":{"environment":"Sandbox", "bundleId":BUNDLE,
                        "signedTransactionInfo":self.sign(revoked)}}
            with self.subTest(notification_id=notification_id), self.assertRaises(SignedAuditError):
                rehearsal.auditor.audit_refund_notification(self.sign(notice), expected_account_token=TOKEN)
        self.assertEqual(rehearsal.authority.snapshot("fixture-account")["purchase_count"], 0)

    def test_r459_refund_tombstone_prevents_later_signed_purchase_grant(self):
        from authority_r459 import PurchaseAlreadyRefunded
        rehearsal = self.make_rehearsal()
        txid="r459-refunded-before-delivery"
        revoked=dict(self.payload, transactionId=txid, originalTransactionId=txid,
                     revocationDate=self.now_ms, revocationReason=0)
        notice={"notificationType":"REFUND", "notificationUUID":"e323a60a-2f4f-49f3-a871-a0b36cafe453",
                "version":"2.0", "signedDate":self.now_ms,
                "data":{"environment":"Sandbox", "bundleId":BUNDLE, "signedTransactionInfo":self.sign(revoked)}}
        rehearsal.refund(account_id="fixture-account", signed_notification_jws=self.sign(notice))
        later=dict(self.payload, transactionId=txid, originalTransactionId=txid)
        with self.assertRaises(PurchaseAlreadyRefunded):
            rehearsal.purchase(account_id="fixture-account", signed_transaction_jws=self.sign(later),
                               operation_id="late-purchase", draw_count=0, test_seed=3)
        snap=rehearsal.authority.snapshot("fixture-account")
        self.assertEqual((snap["purchase_count"],snap["ticket_balance"],snap["revision"]),(0,0,0))

    def test_r459_signed_notification_uuid_collision_and_failure_are_atomic(self):
        rehearsal = self.make_rehearsal()
        tx = dict(self.payload, transactionId="r459-notification-tx", originalTransactionId="r459-notification-tx",
                  revocationDate=self.now_ms, revocationReason=0)
        def signed_notice(uuid_value, product_payload=tx):
            notice = {"notificationType":"REFUND", "notificationUUID":uuid_value,
                "version":"2.0", "signedDate":self.now_ms,
                "data":{"environment":"Sandbox", "bundleId":BUNDLE,
                        "signedTransactionInfo":self.sign(product_payload)}}
            return self.sign(notice)
        event_id="e323a60a-2f4f-49f3-a871-a0b36cafe454"
        payload=signed_notice(event_id)
        with self.assertRaises(InjectedFailure):
            rehearsal.refund(account_id="fixture-account", signed_notification_jws=payload, fail_at="after_notification_insert")
        self.assertEqual(rehearsal.authority.snapshot("fixture-account")["revision"], 0)
        first=rehearsal.refund(account_id="fixture-account", signed_notification_jws=payload)
        replay=rehearsal.refund(account_id="fixture-account", signed_notification_jws=payload)
        self.assertEqual(first["result"]["delivery_status"], "RECORDED")
        self.assertEqual(replay["result"]["delivery_status"], "REPLAYED")
        conflicting=signed_notice(event_id, dict(tx, transactionId="other", originalTransactionId="other"))
        from authority_r459 import IdempotencyCollision
        with self.assertRaises(IdempotencyCollision):
            rehearsal.refund(account_id="fixture-account", signed_notification_jws=conflicting)
        snap=rehearsal.authority.snapshot("fixture-account")
        self.assertEqual((snap["purchase_count"],snap["ticket_balance"]),(0,0))


    def test_r459_signed_draw_rollback_and_refund_spent_ticket_debt(self):
        rehearsal = self.make_rehearsal()
        signed = self.sign()
        with self.assertRaises(InjectedFailure):
            rehearsal.purchase(account_id="fixture-account", signed_transaction_jws=signed,
                operation_id="signed-draw", draw_count=1, test_seed=17, fail_at="after_draw_write")
        before = rehearsal.authority.snapshot("fixture-account")
        self.assertEqual((before["purchase_count"], before["ticket_balance"], before["revision"]), (0,0,0))
        first = rehearsal.purchase(account_id="fixture-account", signed_transaction_jws=signed,
            operation_id="signed-draw", draw_count=1, test_seed=17)
        self.assertEqual(first, rehearsal.purchase(account_id="fixture-account", signed_transaction_jws=signed,
            operation_id="signed-draw", draw_count=1, test_seed=17))
        self.assertEqual(rehearsal.authority.snapshot("fixture-account")["ticket_balance"], 2)
        revoked = dict(self.payload, revocationDate=self.now_ms, revocationReason=0)
        notice = {"notificationType":"REFUND", "notificationUUID":"e323a60a-2f4f-49f3-a871-a0b36cafe450",
            "version":"2.0", "signedDate":self.now_ms,
            "data":{"environment":"Sandbox", "bundleId":BUNDLE, "signedTransactionInfo":self.sign(revoked)}}
        rehearsal.refund(account_id="fixture-account", signed_notification_jws=self.sign(notice))
        after = rehearsal.authority.snapshot("fixture-account")
        self.assertEqual((after["ticket_balance"], after["ticket_debt"]), (0,1))

    def test_r459_mock_entrypoints_remain_disabled_for_bound_sandbox_record(self):
        from authority_r459 import SandboxVerifiedPurchaseR459, _SANDBOX_FACTORY_KEY, VerificationUnavailable
        rehearsal = self.make_rehearsal()
        record = SandboxVerifiedPurchaseR459("Sandbox", BUNDLE, "test", "test", PRODUCT, 1,
            TOKEN, self.now_ms//1000, rehearsal._capability, _factory_key=_SANDBOX_FACTORY_KEY)
        with self.assertRaises(VerificationUnavailable):
            rehearsal.authority.purchase_and_draw_mock("fixture-account", "wrong-api", record, 0, test_seed=1)
        with self.assertRaises(VerificationUnavailable):
            rehearsal.authority.refund_mock("fixture-account", record)
        self.assertEqual(rehearsal.authority.snapshot("fixture-account")["purchase_count"], 0)

if __name__ == "__main__": unittest.main()

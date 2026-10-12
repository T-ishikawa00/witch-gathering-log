"""Real ES256/X.509 checks using ephemeral, explicitly non-Apple test keys.

No signed receipt, private key or account data is written to disk. No network.
"""
import base64
from dataclasses import asdict, replace
from datetime import datetime, timedelta, timezone
import json
import unittest
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

from signed_transaction_audit import AuditProduct, OfflineTransactionAuditor, SignedAuditError


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
        with patch("signed_transaction_audit.version", return_value="3.1.1"), self.assertRaises(SignedAuditError): self.make_auditor()

    def test_nonconsumable_configuration_and_quantity(self):
        with self.assertRaises(SignedAuditError): AuditProduct("Non-Consumable", 2)
        auditor = self.make_auditor(products={PRODUCT: AuditProduct("Non-Consumable")})
        token = self.sign(dict(self.payload, type="Non-Consumable"))
        result = auditor.audit(token, expected_account_token=TOKEN)
        self.assertEqual(result.product_type, "Non-Consumable")
        self.assertFalse(result.grant_authorized)


if __name__ == "__main__": unittest.main()

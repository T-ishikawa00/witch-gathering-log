"""R454 one-shot host exchange tests; explicit local mock only."""
from __future__ import annotations
import base64
from contextlib import closing, redirect_stdout
import hashlib
import io
import json
import sqlite3
import tempfile
import unittest
import uuid
from pathlib import Path

from tools.witch_purchase_authority.authority import ProductSpec, PurchaseAuthority, MockVerifiedPurchase
from tools.witch_purchase_authority.local_delivery_r453 import LocalDeliveryProfileR453, _canonical
from tools.witch_purchase_authority.local_exchange_r454 import process_request, main

BUNDLE = "local.witch.r453.fixture"
ACCOUNT = "r454-test-account"
TOKEN = "9eb01254-16f7-4ac8-8db7-4556f7dabc20"
PRODUCT = "local.witch.test.ticket"
TX = "r454-tx-1"


def profile():
    return {
        "schemaVersion": 1, "status": "UNAPPROVED_TEST_OVERLAY",
        "profileID": "r454-explicit-local-profile", "bundleID": BUNDLE,
        "productSpecs": {PRODUCT: {"ticketsPerUnit": 1, "maxQuantity": 1}},
        "summonPool": ["EQ_W_01"],
        "templates": {"EQ_W_01": {"definitionID": "EQ_W_01", "slotID": "weapon", "compatibleActorIDs": ["C_WITCH"]}},
        "qualityPayloads": {
            "Q0": {"affixIDs": [], "latentEffectID": None},
            "Q1": {"affixIDs": ["AFFIX_POWER_TEST"], "latentEffectID": None},
            "Q2": {"affixIDs": ["AFFIX_POWER_TEST", "AFFIX_GUARD_TEST"], "latentEffectID": None},
            "Q3": {"affixIDs": ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST"], "latentEffectID": None},
            "Q4": {"affixIDs": ["AFFIX_POWER_TEST", "AFFIX_VITALITY_TEST"], "latentEffectID": "LATENT_VITALITY_TEST"},
        },
    }


def event(**changes):
    row = {
        "schemaVersion": 1, "eventKind": "purchase", "verification": "EXPLICIT_TEST_MOCK",
        "environment": "Xcode", "bundleID": BUNDLE, "transactionID": TX,
        "originalTransactionID": "r454-original-1", "productID": PRODUCT,
        "productKind": "consumable", "quantity": 1, "appAccountToken": TOKEN,
        "purchaseTime": 1_800_000_454, "idempotencyKey": f"storekit-xcode:{TX}:entitlement",
        "testAccountID": ACCOUNT,
    }
    row.update(changes)
    return row


def request(profile_fp, **changes):
    row = {
        "schemaVersion": 1, "status": "XCODE_LOCAL_QA_REQUEST",
        "requestID": str(uuid.UUID("45400000-0000-4000-8000-000000000001")),
        "operationID": str(uuid.UUID("45400000-0000-4000-8000-000000000002")),
        "profileFingerprint": profile_fp, "event": event(), "count": 1, "testSeed": 453,
    }
    row.update(changes)
    return _canonical(row)


class LocalExchangeR454Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve(strict=True)
        self.profile_raw = profile()
        self.profile_obj = LocalDeliveryProfileR453.from_mapping(self.profile_raw)
        self.authority_path = self.root / "authority.sqlite"
        self.cache_path = self.root / "cache.sqlite"
        self.authority = PurchaseAuthority(
            self.authority_path, bundle_id=BUNDLE,
            product_specs={PRODUCT: ProductSpec(PRODUCT, tickets_per_unit=1, max_quantity=1)},
            summon_pool=("EQ_W_01",), allow_test_mock_verifier=True,
            clock=lambda: 1_800_000_460,
        )
        self.authority.register_account(ACCOUNT, TOKEN)
        self.profile_fp = self.profile_obj.profile_fingerprint

    def tearDown(self):
        self.temp.cleanup()

    def call(self, data):
        return process_request(data, profile_mapping=self.profile_raw,
            expected_profile_fingerprint=self.profile_fp, authority=self.authority,
            delivery_cache_path=self.cache_path, expected_token=TOKEN, expected_account=ACCOUNT)

    def decode(self, response):
        return json.loads(response.decode("utf-8"))

    def test_ticket_delivery_replay_and_cold_authority_read_are_idempotent(self):
        data = request(self.profile_fp)
        response1 = self.call(data)
        response2 = self.call(data)
        self.assertEqual(response1, response2)
        decoded = self.decode(response1)
        self.assertEqual(decoded["status"], "DELIVERY")
        self.assertEqual(decoded["requestSHA256"], hashlib.sha256(data).hexdigest())
        receipt_bytes = base64.b64decode(decoded["receiptBase64"], validate=True)
        self.assertEqual(hashlib.sha256(receipt_bytes).hexdigest(), decoded["receiptSHA256"])
        receipt = json.loads(receipt_bytes)
        self.assertEqual(receipt_bytes, _canonical(receipt) + b"\n")
        self.assertFalse(receipt.get("productionEntitlementAuthorized", True))
        self.assertEqual(receipt["status"], "LOCAL_TEST_ONLY_GEAR_DELIVERY")
        self.assertEqual(len(receipt["gearInstances"]), 1)
        self.assertFalse(receipt["productionEntitlementAuthorized"])
        self.assertNotIn("requestID", receipt)
        self.assertNotIn(TOKEN.encode(), response1)
        before = self.authority.snapshot(ACCOUNT)
        reopened = PurchaseAuthority(
            self.authority_path, bundle_id=BUNDLE,
            product_specs={PRODUCT: ProductSpec(PRODUCT, tickets_per_unit=1, max_quantity=1)},
            summon_pool=("EQ_W_01",), allow_test_mock_verifier=True)
        self.assertEqual(before, reopened.snapshot(ACCOUNT))
        self.assertEqual(before["ticket_balance"], 0)
        self.assertEqual(before["draw_count"], 1)

    def test_identity_and_profile_reject_before_cache_or_authority_mutation(self):
        before = self.authority.snapshot(ACCOUNT)
        for data, kwargs in (
            (request(self.profile_fp, event=event(testAccountID="other-account")), {}),
            (request(self.profile_fp, event=event(appAccountToken=str(uuid.uuid4()))), {}),
            (request("0" * 64), {}),
            (request(self.profile_fp, testSeed=454), {}),
        ):
            response = self.decode(process_request(data, profile_mapping=self.profile_raw,
                expected_profile_fingerprint=kwargs.get("fingerprint", self.profile_fp),
                authority=self.authority, delivery_cache_path=self.cache_path,
                expected_token=TOKEN, expected_account=ACCOUNT))
            self.assertEqual(response["status"], "REJECTED")
            self.assertNotIn(TOKEN, json.dumps(response))
            self.assertEqual(before, self.authority.snapshot(ACCOUNT))
            self.assertFalse(self.cache_path.exists())

    def test_refund_blocks_replay_without_regrant(self):
        data = request(self.profile_fp)
        first = self.decode(self.call(data))
        self.assertEqual(first["status"], "DELIVERY")
        self.authority.refund_mock(ACCOUNT, MockVerifiedPurchase(
            "Xcode", BUNDLE, TX, "r454-original-1", PRODUCT, 1, TOKEN,
            1_800_000_454, verified_by="EXPLICIT_TEST_MOCK"))
        after_refund = self.authority.snapshot(ACCOUNT)
        second = self.decode(self.call(data))
        self.assertEqual(second["status"], "REJECTED")
        self.assertEqual(after_refund, self.authority.snapshot(ACCOUNT))
        self.assertNotIn(TOKEN, json.dumps(second))

    def test_duplicate_keys_and_nonpurchase_request_reject_without_mutation(self):
        before = self.authority.snapshot(ACCOUNT)
        malformed = b'{"schemaVersion":1,"schemaVersion":1}'
        response = self.decode(self.call(malformed))
        self.assertEqual(response["status"], "REJECTED")
        revoked = request(self.profile_fp, event=event(eventKind="revocation", idempotencyKey=f"storekit-xcode:{TX}:revocation"))
        self.assertEqual(self.decode(self.call(revoked))["status"], "REJECTED")
        self.assertEqual(before, self.authority.snapshot(ACCOUNT))
        self.assertFalse(self.cache_path.exists())

    def test_cli_existing_output_rejects_before_opening_authority_or_cache(self):
        profile_path = self.root / "profile.json"
        request_path = self.root / "request.json"
        output_path = self.root / "existing.json"
        profile_bytes = _canonical(self.profile_raw)
        request_bytes = request(self.profile_fp)
        profile_path.write_bytes(profile_bytes)
        request_path.write_bytes(request_bytes)
        output_path.write_text("preserve", encoding="utf-8")
        db_before = self.authority.snapshot(ACCOUNT)
        with redirect_stdout(io.StringIO()):
            status = main(["--request", str(request_path), "--profile", str(profile_path),
                "--profile-sha256", hashlib.sha256(profile_bytes).hexdigest(),
                "--authority-db", str(self.authority_path), "--cache-db", str(self.cache_path),
                "--expected-account", ACCOUNT, "--expected-token", TOKEN,
                "--output", str(output_path)])
        self.assertEqual(status, 2)
        self.assertEqual(output_path.read_text(encoding="utf-8"), "preserve")
        self.assertEqual(db_before, self.authority.snapshot(ACCOUNT))
        self.assertFalse(self.cache_path.exists())

    def test_cli_missing_output_parent_rejects_before_authority_or_cache_mutation(self):
        profile_path = self.root / "profile.json"
        request_path = self.root / "request.json"
        profile_bytes = _canonical(self.profile_raw)
        profile_path.write_bytes(profile_bytes)
        request_path.write_bytes(request(self.profile_fp))
        db_before = self.authority.snapshot(ACCOUNT)
        missing_parent_output = self.root / "absent" / "delivery.json"
        captured = io.StringIO()
        with redirect_stdout(captured):
            status = main(["--request", str(request_path), "--profile", str(profile_path),
                "--profile-sha256", hashlib.sha256(profile_bytes).hexdigest(),
                "--authority-db", str(self.authority_path), "--cache-db", str(self.cache_path),
                "--expected-account", ACCOUNT, "--expected-token", TOKEN,
                "--output", str(missing_parent_output)])
        self.assertEqual(status, 2)
        self.assertIn("LOCAL_DELIVERY_REJECTED", captured.getvalue())
        self.assertFalse(missing_parent_output.parent.exists())
        self.assertEqual(db_before, self.authority.snapshot(ACCOUNT))
        self.assertFalse(self.cache_path.exists())


if __name__ == "__main__":
    unittest.main()

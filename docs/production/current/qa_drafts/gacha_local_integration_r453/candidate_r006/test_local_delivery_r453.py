"""Focused local fixture tests for the isolated R453 receipt delivery adapter."""
from __future__ import annotations

import copy
from contextlib import closing
from contextlib import redirect_stderr
import hashlib
import io
import json
import os
import sqlite3
import tempfile
import unittest
import uuid
from pathlib import Path

from tools.witch_purchase_authority.authority import (
    AuthorityError, IdempotencyCollision, InsufficientPaidTickets, InvalidPurchase, MockVerifiedPurchase,
    ProductSpec, PurchaseAuthority, PurchaseAlreadyRefunded, VerificationUnavailable,
)
from tools.witch_purchase_authority.local_delivery_r453 import (
    DeliveryPayloadCollision, LocalDeliveryAdapterR453, LocalDeliveryError,
    LocalDeliveryProfileR453, main,
)


BUNDLE = "local.witch.r453.fixture"
PRODUCT = "local.witch.candidate.ticket-pack"
TOKEN = "e1a5b740-13ad-4d4c-8e9f-56fa66a3c914"
ACCOUNT = "r453-account-a"
TX_ID = "r453-tx-1001"


def profile_mapping():
    return {
        "schemaVersion": 1,
        "status": "UNAPPROVED_TEST_OVERLAY",
        "profileID": "r098-local-candidate-r453",
        "bundleID": BUNDLE,
        "productSpecs": {PRODUCT: {"ticketsPerUnit": 4, "maxQuantity": 2}},
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


def event_mapping(**changes):
    row = {
        "schemaVersion": 1, "eventKind": "purchase", "verification": "EXPLICIT_TEST_MOCK",
        "environment": "Xcode", "bundleID": BUNDLE, "transactionID": TX_ID,
        "originalTransactionID": "r453-original-1001", "productID": PRODUCT,
        "productKind": "consumable", "quantity": 1, "appAccountToken": TOKEN,
        "purchaseTime": 1_800_000_001,
        "idempotencyKey": f"storekit-xcode:{TX_ID}:entitlement", "testAccountID": ACCOUNT,
    }
    row.update(changes)
    return row


class LocalDeliveryR453Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve(strict=True)
        self.authority_path = self.root / "authority.sqlite"
        self.cache_path = self.root / "delivery-cache.sqlite"
        self.profile_raw = profile_mapping()
        self.profile = LocalDeliveryProfileR453.from_mapping(self.profile_raw)
        self.authority = PurchaseAuthority(
            self.authority_path, bundle_id=BUNDLE,
            product_specs={PRODUCT: ProductSpec(PRODUCT, tickets_per_unit=4, max_quantity=2)},
            summon_pool=("EQ_A_01", "EQ_W_01"), allow_test_mock_verifier=True,
            clock=lambda: 1_800_000_010,
        )
        self.authority.register_account(ACCOUNT, TOKEN)
        self.adapter = LocalDeliveryAdapterR453(self.authority, self.profile, self.cache_path)

    def tearDown(self):
        self.temp.cleanup()

    def test_ticket_grant_then_separate_draw_emits_core_gear_payload(self):
        grant = self.adapter.grant_ticket_only(event_mapping())
        self.assertEqual(grant["status"], "LOCAL_TEST_ONLY_TICKET_GRANT")
        self.assertEqual(grant["gearInstances"], [])
        self.assertEqual(grant["drawReceipt"]["ticketsGranted"], 4)
        self.assertEqual(self.authority.snapshot(ACCOUNT)["ticket_balance"], 4)
        self.assertEqual(self.authority.snapshot(ACCOUNT)["draw_count"], 0)

        delivery = self.adapter.draw_from_ticket_balance(
            event_mapping(), operation_id=str(uuid.uuid4()), count=3, test_seed=34)
        self.assertEqual(delivery["status"], "LOCAL_TEST_ONLY_GEAR_DELIVERY")
        self.assertFalse(delivery["productionEntitlementAuthorized"])
        self.assertEqual(len(delivery["gearInstances"]), 3)
        self.assertEqual(len(delivery["gearProvenance"]), 3)
        self.assertEqual(self.authority.snapshot(ACCOUNT)["ticket_balance"], 1)
        self.assertEqual(self.authority.snapshot(ACCOUNT)["draw_count"], 3)
        self.assertEqual(delivery["postPityState"], delivery["drawReceipt"]["pityAfter"])
        for item, provenance in zip(delivery["gearInstances"], delivery["gearProvenance"]):
            self.assertEqual(set(item), {
                "id", "definitionID", "ownerID", "protected", "enhancement", "refinement",
                "latentEffectID", "candidateLatentSlots", "qualityID", "affixIDs", "investmentDust",
            })
            self.assertIsNone(item["ownerID"])
            self.assertEqual(item["enhancement"], 0)
            self.assertEqual(item["refinement"], 0)
            self.assertTrue(all(value.endswith("_TEST") for value in item["affixIDs"]))
            if item["latentEffectID"] is not None:
                self.assertTrue(item["latentEffectID"].endswith("_TEST"))
            self.assertEqual(provenance["gearID"], item["id"])
            self.assertEqual(provenance["transactionID"], TX_ID)
        self.assertEqual(len({item["id"] for item in delivery["gearInstances"]}), 3)

    def test_replay_is_byte_stable_and_payload_collision_is_rejected(self):
        self.adapter.grant_ticket_only(event_mapping())
        operation_id = str(uuid.uuid4())
        first = self.adapter.draw_from_ticket_balance(event_mapping(), operation_id=operation_id, count=4, test_seed=89)
        before = self.authority.snapshot(ACCOUNT)
        replay = self.adapter.draw_from_ticket_balance(event_mapping(), operation_id=operation_id, count=4, test_seed=89)
        self.assertEqual(first, replay)
        self.assertEqual(before, self.authority.snapshot(ACCOUNT))
        self.assertEqual(len({row["id"] for row in first["gearInstances"]}), 4)
        with self.assertRaises(DeliveryPayloadCollision):
            self.adapter.draw_from_ticket_balance(event_mapping(), operation_id=operation_id, count=2, test_seed=89)
        self.assertEqual(before, self.authority.snapshot(ACCOUNT))

    def test_profile_payload_collision_is_rejected_before_second_draw(self):
        self.adapter.grant_ticket_only(event_mapping())
        operation_id = str(uuid.uuid4())
        first = self.adapter.draw_from_ticket_balance(event_mapping(), operation_id=operation_id, count=1, test_seed=13)
        changed = copy.deepcopy(self.profile_raw)
        changed["qualityPayloads"]["Q1"]["affixIDs"] = ["AFFIX_GUARD_TEST"]
        other_profile = LocalDeliveryProfileR453.from_mapping(changed)
        other_adapter = LocalDeliveryAdapterR453(self.authority, other_profile, self.cache_path)
        before = self.authority.snapshot(ACCOUNT)
        with self.assertRaises(DeliveryPayloadCollision):
            other_adapter.draw_from_ticket_balance(event_mapping(), operation_id=operation_id, count=1, test_seed=13)
        self.assertEqual(before, self.authority.snapshot(ACCOUNT))
        self.assertEqual(len(first["gearInstances"]), 1)

    def test_retry_reconstructs_payload_if_sidecar_write_fails_after_authority_commit(self):
        self.adapter.grant_ticket_only(event_mapping())
        operation_id = str(uuid.uuid4())
        store = self.adapter._store

        def fail_once(_operation_id, _request_sha, _receipt):
            raise OSError("simulated local delivery-cache write failure")

        self.adapter._store = fail_once
        with self.assertRaises(OSError):
            self.adapter.draw_from_ticket_balance(event_mapping(), operation_id=operation_id, count=2, test_seed=29)
        after_authority_commit = self.authority.snapshot(ACCOUNT)
        self.assertEqual(after_authority_commit["draw_count"], 2)
        self.adapter._store = store
        replayed = self.adapter.draw_from_ticket_balance(event_mapping(), operation_id=operation_id, count=2, test_seed=29)
        self.assertEqual(self.authority.snapshot(ACCOUNT), after_authority_commit)
        self.assertEqual(len(replayed["gearInstances"]), 2)
        self.assertEqual(len({item["id"] for item in replayed["gearInstances"]}), 2)

    def test_refund_tombstone_is_current_state_and_blocks_later_delivery(self):
        self.adapter.grant_ticket_only(event_mapping())
        operation_id = str(uuid.uuid4())
        delivered = self.adapter.draw_from_ticket_balance(event_mapping(), operation_id=operation_id, count=2, test_seed=77)
        revoked = event_mapping(eventKind="revocation", idempotencyKey=f"storekit-xcode:{TX_ID}:revocation")
        revocation = self.adapter.revoke(revoked)
        self.assertEqual(revocation["status"], "LOCAL_TEST_ONLY_REVOKED")
        self.assertFalse(revocation["previouslyExportedGearRetracted"])
        with self.assertRaises(PurchaseAlreadyRefunded):
            self.adapter.draw_from_ticket_balance(event_mapping(), operation_id=operation_id, count=2, test_seed=77)
        self.assertEqual(len(delivered["gearInstances"]), 2)
        self.assertEqual(self.authority.snapshot(ACCOUNT)["ticket_debt"], 2)
        with self.assertRaises(PurchaseAlreadyRefunded):
            self.adapter.grant_ticket_only(event_mapping())

    def test_bad_identity_envelopes_reject_without_authority_mutation(self):
        before = self.authority.snapshot(ACCOUNT)
        invalid_rows = [
            event_mapping(environment="Production"),
            event_mapping(bundleID="other.bundle"),
            event_mapping(productKind="nonConsumable"),
            event_mapping(appAccountToken=str(uuid.uuid4())),
            event_mapping(quantity=True),
            event_mapping(idempotencyKey="caller-selected"),
            event_mapping(verification="APPLE_VERIFIED"),
            {**event_mapping(), "clientGearInstances": [{"definitionID": "EQ_W_01"}]},
        ]
        for index, bad in enumerate(invalid_rows):
            with self.subTest(index=index), self.assertRaises(AuthorityError):
                self.adapter.grant_ticket_only(bad)
        self.assertEqual(before, self.authority.snapshot(ACCOUNT))

    def test_draw_rejects_original_transaction_mismatch_against_current_purchase_row(self):
        self.adapter.grant_ticket_only(event_mapping())
        before = self.authority.snapshot(ACCOUNT)
        with self.assertRaises(LocalDeliveryError):
            self.adapter.draw_from_ticket_balance(
                event_mapping(originalTransactionID="different-original"),
                operation_id=str(uuid.uuid4()), count=1, test_seed=5)
        self.assertEqual(before, self.authority.snapshot(ACCOUNT))

    def test_refund_tombstone_before_purchase_suppresses_late_ticket_grant(self):
        revoked = event_mapping(eventKind="revocation", idempotencyKey=f"storekit-xcode:{TX_ID}:revocation")
        tombstone = self.adapter.revoke(revoked)
        self.assertEqual(tombstone["currentTransactionStatus"], "refund_tombstone")
        before = self.authority.snapshot(ACCOUNT)
        with self.assertRaises(PurchaseAlreadyRefunded):
            self.adapter.grant_ticket_only(event_mapping())
        self.assertEqual(before, self.authority.snapshot(ACCOUNT))

    def test_apple_jws_entrypoint_remains_fail_closed(self):
        with self.assertRaises(VerificationUnavailable):
            self.authority.ingest_apple_jws("not-a-real-jws")

    def test_profile_schema_version_and_template_identity_are_strict(self):
        fractional = copy.deepcopy(self.profile_raw)
        fractional["schemaVersion"] = 1.0
        with self.assertRaises(LocalDeliveryError):
            LocalDeliveryProfileR453.from_mapping(fractional)
        mismatch = copy.deepcopy(self.profile_raw)
        mismatch["templates"]["EQ_A_01"]["definitionID"] = "EQ_W_01"
        with self.assertRaises(LocalDeliveryError):
            LocalDeliveryProfileR453.from_mapping(mismatch)
        with self.assertRaises(LocalDeliveryError):
            self.adapter.grant_ticket_only(event_mapping(schemaVersion=1.0))

    def test_fifo_source_join_checks_environment_bundle_and_transaction(self):
        self.adapter.grant_ticket_only(event_mapping())
        with closing(sqlite3.connect(self.authority_path)) as db:
            db.execute("UPDATE purchases SET bundle_id=? WHERE transaction_id=?", ("other.bundle", TX_ID))
            db.commit()
        before = self.authority.snapshot(ACCOUNT)
        with self.assertRaises(LocalDeliveryError):
            self.adapter.draw_from_ticket_balance(event_mapping(), operation_id=str(uuid.uuid4()), count=1, test_seed=51)
        self.assertEqual(before, self.authority.snapshot(ACCOUNT))

    def test_hardlinked_cache_cannot_alias_authority_database(self):
        alias = self.root / "authority-hardlink.sqlite"
        os.link(self.authority_path, alias)
        with self.assertRaises(LocalDeliveryError):
            LocalDeliveryAdapterR453(self.authority, self.profile, alias)

    def test_cli_output_collision_rejects_before_authority_mutation(self):
        profile_path = self.root / "profile.json"
        event_path = self.root / "event.json"
        output_path = self.root / "already-there.json"
        profile_path.write_text(json.dumps(self.profile_raw), encoding="utf-8")
        event_path.write_text(json.dumps(event_mapping()), encoding="utf-8")
        output_path.write_text("preserve", encoding="utf-8")
        before = self.authority.snapshot(ACCOUNT)
        argv = ["--allow-test-mock-verifier", "--profile-json", str(profile_path),
                "--profile-sha256", hashlib.sha256(profile_path.read_bytes()).hexdigest(),
                "--event-json", str(event_path), "--authority-db", str(self.authority_path),
                "--delivery-cache-db", str(self.cache_path), "--output-json", str(output_path)]
        errors = io.StringIO()
        with redirect_stderr(errors):
            status = main(argv)
        self.assertEqual(status, 2)
        self.assertIn("output path already exists", errors.getvalue())
        self.assertEqual(output_path.read_text(encoding="utf-8"), "preserve")
        self.assertEqual(before, self.authority.snapshot(ACCOUNT))
        future_cache = self.root / "future-cache.sqlite"
        args_with_alias = ["--allow-test-mock-verifier", "--profile-json", str(profile_path),
                           "--profile-sha256", hashlib.sha256(profile_path.read_bytes()).hexdigest(),
                           "--event-json", str(event_path), "--authority-db", str(self.authority_path),
                           "--delivery-cache-db", str(future_cache), "--output-json", str(future_cache)]
        with redirect_stderr(io.StringIO()) as alias_errors:
            alias_status = main(args_with_alias)
        self.assertEqual(alias_status, 2)
        self.assertIn("distinct from the delivery cache", alias_errors.getvalue())
        self.assertFalse(future_cache.exists())
        self.assertEqual(before, self.authority.snapshot(ACCOUNT))

    def test_atomic_expected_fifo_lot_rejects_interleaved_spend_without_spilling(self):
        self.adapter.grant_ticket_only(event_mapping())
        later = MockVerifiedPurchase("Xcode", BUNDLE, "r453-tx-1002", "r453-original-1002",
                                     PRODUCT, 1, TOKEN, 1_800_000_002,
                                     verified_by="EXPLICIT_TEST_MOCK")
        self.authority.purchase_and_draw_mock(ACCOUNT, "second-purchase", later, 0, test_seed=6)
        draw_key = f"r453:draw:{uuid.uuid4()}"
        original_draw = self.authority.draw_mock
        competitor_state = {}

        def interleave(account_id, operation_key, count, *, test_seed, **kwargs):
            if operation_key == draw_key:
                original_draw(account_id, "competing-draw", 2, test_seed=71)
                competitor_state["snapshot"] = self.authority.snapshot(ACCOUNT)
            return original_draw(account_id, operation_key, count, test_seed=test_seed, **kwargs)

        self.authority.draw_mock = interleave
        try:
            with self.assertRaises(InsufficientPaidTickets):
                self.adapter.draw_from_ticket_balance(
                    event_mapping(), operation_id=draw_key.removeprefix("r453:draw:"), count=3, test_seed=72)
        finally:
            self.authority.draw_mock = original_draw

        self.assertEqual(self.authority.snapshot(ACCOUNT), competitor_state["snapshot"])
        history = self.authority.history(ACCOUNT)
        self.assertEqual(len(history), 2)
        self.assertEqual({row["operation_idempotency_key"] for row in history}, {"competing-draw"})
        self.assertEqual({row["source_transaction_id"] for row in history}, {TX_ID})
        self.assertEqual({row["purchase_transaction_id"] for row in history}, {None})

    def test_source_identity_binding_changes_only_bound_operation_fingerprint(self):
        self.adapter.grant_ticket_only(event_mapping())
        legacy = self.authority.draw_mock(ACCOUNT, "legacy-draw", 1, test_seed=4)
        before = self.authority.snapshot(ACCOUNT)
        self.assertEqual(legacy, self.authority.draw_mock(ACCOUNT, "legacy-draw", 1, test_seed=4))
        self.assertEqual(before, self.authority.snapshot(ACCOUNT))
        with self.assertRaises(IdempotencyCollision):
            self.authority.draw_mock(ACCOUNT, "legacy-draw", 1, test_seed=4,
                                     expected_source_identity=("Xcode", BUNDLE, TX_ID))
        for invalid_identity in (
            ["Xcode", BUNDLE, TX_ID],
            ("StoreKit", BUNDLE, TX_ID),
            ("Xcode", "other.bundle", TX_ID),
            ("Xcode", BUNDLE, "  "),
        ):
            with self.assertRaises(InvalidPurchase):
                self.authority.draw_mock(
                    ACCOUNT, f"invalid-source-{uuid.uuid4()}", 1, test_seed=4,
                    expected_source_identity=invalid_identity,
                )
        self.assertEqual(before, self.authority.snapshot(ACCOUNT))


if __name__ == "__main__":
    unittest.main()

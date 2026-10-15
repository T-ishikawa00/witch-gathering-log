"""Focused local fixture tests for the isolated R453 receipt delivery adapter."""
from __future__ import annotations

import copy
import tempfile
import unittest
import uuid
from pathlib import Path

from tools.witch_purchase_authority.authority import (
    AuthorityError, ProductSpec, PurchaseAuthority, PurchaseAlreadyRefunded,
    VerificationUnavailable,
)
from tools.witch_purchase_authority.local_delivery_r453 import (
    DeliveryPayloadCollision, LocalDeliveryAdapterR453, LocalDeliveryError,
    LocalDeliveryProfileR453,
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
            "EQ_A_01": {"definitionID": "EQ_A_01", "slotID": "body", "compatibleActorIDs": ["AIRA", "ELNA"]},
            "EQ_W_01": {"definitionID": "EQ_W_01", "slotID": "weapon", "compatibleActorIDs": ["AIRA", "ELNA"]},
        },
        "qualityPayloads": {
            "Q0": {"affixIDs": [], "latentEffectID": None},
            "Q1": {"affixIDs": ["AFFIX_POWER_TEST"], "latentEffectID": None},
            "Q2": {"affixIDs": ["AFFIX_POWER_TEST", "AFFIX_GUARD_TEST"], "latentEffectID": None},
            "Q3": {"affixIDs": ["AFFIX_POWER_TEST", "AFFIX_GUARD_TEST", "AFFIX_FOCUS_TEST"], "latentEffectID": None},
            "Q4": {"affixIDs": ["AFFIX_POWER_TEST", "AFFIX_GUARD_TEST", "AFFIX_FOCUS_TEST"], "latentEffectID": "LATENT_FOCUS_TEST"},
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
        self.root = Path(self.temp.name)
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
        replay = self.adapter.draw_from_ticket_balance(event_mapping(), operation_id=operation_id, count=2, test_seed=89)
        self.assertEqual(first, replay)
        self.assertEqual(before, self.authority.snapshot(ACCOUNT))
        self.assertEqual(len({row["id"] for row in first["gearInstances"]}), 4)
        with self.assertRaises(DeliveryPayloadCollision):
            self.adapter.draw_from_ticket_balance(event_mapping(), operation_id=operation_id, count=1, test_seed=89)
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


if __name__ == "__main__":
    unittest.main()

import concurrent.futures
import sqlite3
import tempfile
import unittest
from pathlib import Path
from authority_r459 import (
    AuthorityError, IdempotencyCollision, InjectedFailure, InvalidPurchase,
    MockNotificationDelivery, ProductSpec, PurchaseAuthority, VerificationUnavailable,
)

BUNDLE = "local.witch.atomic-fixture"
PRODUCT = "local.witch.test.ticket-pack"
POOL = ("EQ_W_01", "EQ_A_01")


def notice(nid, kind, *, txid="tx-atomic", token="token-a", product=PRODUCT, qty=2, fixture_marker="EXPLICIT_TEST_MOCK_NOTIFICATION"):
    return MockNotificationDelivery(nid, kind, "Xcode", BUNDLE, txid, txid, product, qty, token, 1_799_000_000, fixture_marker)


class NotificationAtomicityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "authority.sqlite"
        self.auth = PurchaseAuthority(self.path, bundle_id=BUNDLE,
            product_specs={PRODUCT: ProductSpec(PRODUCT, 3, max_quantity=3)},
            summon_pool=POOL, allow_test_mock_verifier=True, clock=lambda: 1_800_000_000)
        self.auth.register_account("account-a", "token-a")
        self.auth.register_account("account-b", "token-b")

    def tearDown(self):
        self.tmp.cleanup()

    def sql_counts(self):
        with sqlite3.connect(self.path) as db:
            return tuple(db.execute("SELECT (SELECT COUNT(*) FROM notification_inbox),"
                                    "(SELECT COUNT(*) FROM purchases),"
                                    "(SELECT COUNT(*) FROM refunds),"
                                    "(SELECT COUNT(*) FROM ticket_ledger)").fetchone())

    def test_purchase_notification_grant_and_ledger_commit_together_and_replay_once(self):
        event = notice("notice-purchase", "PURCHASE")
        first = self.auth.apply_notification_mock("account-a", event)
        self.assertEqual(first["delivery_receipt"]["outcome"], "GRANTED_TEST_ONLY")
        self.assertFalse(first["production_entitlement_authorized"])
        self.assertTrue(first["fixture_mutation"])
        self.assertEqual(self.auth.snapshot("account-a")["ticket_balance"], 6)
        self.assertEqual(self.sql_counts(), (1, 1, 0, 1))
        retry = self.auth.apply_notification_mock("account-a", event)
        self.assertTrue(retry["duplicate_notification"])
        self.assertEqual(self.auth.snapshot("account-a")["ticket_balance"], 6)
        self.assertEqual(self.sql_counts(), (1, 1, 0, 1))

    def test_notification_id_payload_collision_rejects_without_any_change(self):
        self.auth.apply_notification_mock("account-a", notice("same-id", "PURCHASE"))
        before = (self.auth.snapshot("account-a"), self.sql_counts())
        with self.assertRaises(IdempotencyCollision):
            self.auth.apply_notification_mock("account-a", notice("same-id", "PURCHASE", qty=1))
        self.assertEqual((self.auth.snapshot("account-a"), self.sql_counts()), before)

    def test_refund_delivery_updates_grant_ledger_in_same_transaction(self):
        self.auth.apply_notification_mock("account-a", notice("buy", "PURCHASE"))
        self.auth.apply_notification_mock("account-a", notice("refund", "REFUND"))
        state = self.auth.snapshot("account-a")
        self.assertEqual((state["ticket_balance"], state["ticket_debt"], state["revision"]), (0, 0, 2))
        self.assertEqual(self.sql_counts(), (2, 1, 1, 2))
        duplicate_refund = self.auth.apply_notification_mock("account-a", notice("refund", "REFUND"))
        self.assertEqual(duplicate_refund["delivery_receipt"]["outcome"], "REFUNDED_TEST_ONLY")
        self.assertEqual(duplicate_refund["current_transaction"]["transaction_status"], "refunded")
        self.assertEqual(duplicate_refund["current_transaction"]["account_ticket_balance"], 0)
        self.assertEqual(self.auth.snapshot("account-a")["revision"], 2)

    def test_purchase_replay_after_refund_separates_historical_grant_from_current_state(self):
        event = notice("historical-purchase", "PURCHASE")
        original = self.auth.apply_notification_mock("account-a", event)
        self.assertEqual(original["delivery_receipt"]["outcome"], "GRANTED_TEST_ONLY")
        self.auth.apply_notification_mock("account-a", notice("later-refund", "REFUND"))

        replay = self.auth.apply_notification_mock("account-a", event)
        self.assertTrue(replay["duplicate_notification"])
        self.assertEqual(replay["delivery_status"], "REPLAYED")
        self.assertEqual(replay["delivery_receipt"]["outcome"], "GRANTED_TEST_ONLY", "immutable history remains available")
        self.assertEqual(replay["current_transaction"]["transaction_status"], "refunded")
        self.assertEqual(replay["current_transaction"]["account_ticket_balance"], 0)
        self.assertEqual(replay["current_transaction"]["tickets_remaining"], 0)
        self.assertNotIn("outcome", replay, "a historical grant must not be returned as current outcome")
        self.assertNotIn("tickets_usable", replay, "current entitlement must come from current_transaction")

    def test_purchase_replays_after_consumption_show_zero_current_value(self):
        event = notice("consumed-purchase", "PURCHASE")
        self.auth.apply_notification_mock("account-a", event)
        self.auth.draw_mock("account-a", "consume-all", 6, test_seed=77)

        same_id = self.auth.apply_notification_mock("account-a", event)
        self.assertTrue(same_id["duplicate_notification"])
        self.assertEqual(same_id["delivery_receipt"]["outcome"], "GRANTED_TEST_ONLY")
        self.assertEqual(same_id["current_transaction"]["transaction_status"], "consumed")
        self.assertEqual(same_id["current_transaction"]["tickets_spent"], 6)
        self.assertEqual(same_id["current_transaction"]["account_ticket_balance"], 0)

        another_delivery = self.auth.apply_notification_mock("account-a", notice("new-id-same-purchase", "PURCHASE"))
        self.assertFalse(another_delivery["duplicate_notification"])
        self.assertEqual(another_delivery["delivery_receipt"]["outcome"], "DUPLICATE_TRANSACTION")
        self.assertEqual(another_delivery["current_transaction"]["transaction_status"], "consumed")
        self.assertEqual(another_delivery["current_transaction"]["account_ticket_balance"], 0)
        self.assertEqual(self.auth.snapshot("account-a")["ticket_balance"], 0)

    def test_tombstone_same_and_new_notification_replays_keep_current_state_separate(self):
        refund_event = notice("tombstone-refund", "REFUND")
        first = self.auth.apply_notification_mock("account-a", refund_event)
        self.assertEqual(first["delivery_receipt"]["outcome"], "REFUND_TOMBSTONE_TEST_ONLY")
        same_id = self.auth.apply_notification_mock("account-a", refund_event)
        self.assertTrue(same_id["duplicate_notification"])
        self.assertEqual(same_id["delivery_receipt"]["outcome"], "REFUND_TOMBSTONE_TEST_ONLY")
        self.assertEqual(same_id["current_transaction"]["transaction_status"], "refund_tombstone")
        self.assertEqual(same_id["current_transaction"]["account_ticket_balance"], 0)

        late_purchase = self.auth.apply_notification_mock("account-a", notice("different-late-purchase", "PURCHASE"))
        self.assertEqual(late_purchase["delivery_receipt"]["outcome"], "SUPPRESSED_REFUNDED")
        self.assertEqual(late_purchase["current_transaction"]["transaction_status"], "refund_tombstone")
        self.assertEqual(late_purchase["current_transaction"]["account_ticket_balance"], 0)

    def test_refund_first_tombstone_suppresses_late_purchase(self):
        refund = self.auth.apply_notification_mock("account-a", notice("refund-first", "REFUND"))
        late = self.auth.apply_notification_mock("account-a", notice("purchase-late", "PURCHASE"))
        self.assertEqual(refund["delivery_receipt"]["outcome"], "REFUND_TOMBSTONE_TEST_ONLY")
        self.assertEqual(late["delivery_receipt"]["outcome"], "SUPPRESSED_REFUNDED")
        self.assertEqual(self.auth.snapshot("account-a")["ticket_balance"], 0)
        self.assertEqual(self.sql_counts(), (2, 0, 1, 0))

    def test_purchase_then_refund_with_draw_spend_creates_debt_atomically(self):
        self.auth.apply_notification_mock("account-a", notice("buy", "PURCHASE"))
        # Consume tickets through the existing mock draw path; notification refund must see its lot.
        self.auth.draw_mock("account-a", "draw-2", 2, test_seed=41)
        out = self.auth.apply_notification_mock("account-a", notice("refund", "REFUND"))
        state = self.auth.snapshot("account-a")
        self.assertEqual(out["delivery_receipt"]["outcome"], "REFUNDED_TEST_ONLY")
        self.assertEqual((state["ticket_balance"], state["ticket_debt"]), (0, 2))
        self.assertEqual(out["current_transaction"]["transaction_status"], "refunded")
        self.assertEqual(out["current_transaction"]["tickets_spent"], 2)
        self.assertEqual(out["current_transaction"]["account_ticket_debt"], 2)
        with sqlite3.connect(self.path) as db:
            self.assertEqual(db.execute("SELECT event_type,amount FROM ticket_ledger ORDER BY ledger_id").fetchall(),
                             [("grant", 6), ("draw_spend", 2), ("refund_clawback", 4), ("refund_debt", 2)])

    def test_faults_rollback_notification_and_economic_rows_then_retry(self):
        for point in ("after_notification_insert", "after_purchase_insert", "after_domain_mutation", "before_commit"):
            with self.subTest(point=point):
                path = Path(self.tmp.name) / f"{point}.sqlite"
                auth = PurchaseAuthority(path, bundle_id=BUNDLE,
                    product_specs={PRODUCT: ProductSpec(PRODUCT, 3, max_quantity=3)},
                    summon_pool=POOL, allow_test_mock_verifier=True, clock=lambda: 1_800_000_000)
                auth.register_account("account-a", "token-a")
                with self.assertRaises(InjectedFailure):
                    auth.apply_notification_mock("account-a", notice("fault", "PURCHASE"), fail_at=point)
                with sqlite3.connect(path) as db:
                    self.assertEqual(db.execute("SELECT COUNT(*) FROM notification_inbox").fetchone()[0], 0)
                    self.assertEqual(db.execute("SELECT COUNT(*) FROM purchases").fetchone()[0], 0)
                    self.assertEqual(db.execute("SELECT COUNT(*) FROM ticket_ledger").fetchone()[0], 0)
                self.assertEqual(auth.snapshot("account-a")["ticket_balance"], 0)
                auth.apply_notification_mock("account-a", notice("fault", "PURCHASE"))
                self.assertEqual(auth.snapshot("account-a")["ticket_balance"], 6)

    def test_refund_fault_rolls_back_tombstone_and_retry_can_suppress_purchase(self):
        auth = PurchaseAuthority(Path(self.tmp.name)/"refund-fault.sqlite", bundle_id=BUNDLE,
            product_specs={PRODUCT: ProductSpec(PRODUCT,3,3)}, summon_pool=POOL,
            allow_test_mock_verifier=True, clock=lambda:1_800_000_000)
        auth.register_account("account-a","token-a")
        with self.assertRaises(InjectedFailure): auth.apply_notification_mock("account-a", notice("r","REFUND"), fail_at="before_commit")
        self.assertEqual(auth.snapshot("account-a")["ticket_balance"],0)
        self.assertEqual(auth.apply_notification_mock("account-a",notice("r","REFUND"))["delivery_receipt"]["outcome"],"REFUND_TOMBSTONE_TEST_ONLY")
        self.assertEqual(auth.apply_notification_mock("account-a",notice("p","PURCHASE"))["delivery_receipt"]["outcome"],"SUPPRESSED_REFUNDED")

    def test_refund_fault_points_rollback_inbox_refund_and_ticket_ledger_together(self):
        for point in ("after_notification_insert", "after_domain_mutation", "before_commit"):
            with self.subTest(point=point):
                path = Path(self.tmp.name) / f"refund-{point}.sqlite"
                auth = PurchaseAuthority(path, bundle_id=BUNDLE,
                    product_specs={PRODUCT: ProductSpec(PRODUCT, 3, max_quantity=3)},
                    summon_pool=POOL, allow_test_mock_verifier=True, clock=lambda: 1_800_000_000)
                auth.register_account("account-a", "token-a")
                auth.apply_notification_mock("account-a", notice("buy", "PURCHASE"))
                before = auth.snapshot("account-a")
                with self.assertRaises(InjectedFailure):
                    auth.apply_notification_mock("account-a", notice("refund", "REFUND"), fail_at=point)
                self.assertEqual(auth.snapshot("account-a"), before)
                with sqlite3.connect(path) as db:
                    self.assertEqual(db.execute("SELECT COUNT(*) FROM notification_inbox WHERE notification_id='refund'").fetchone()[0], 0)
                    self.assertEqual(db.execute("SELECT COUNT(*) FROM refunds").fetchone()[0], 0)
                    self.assertEqual(db.execute("SELECT status,tickets_remaining FROM purchases").fetchone(), ("verified", 6))
                committed = auth.apply_notification_mock("account-a", notice("refund", "REFUND"))
                self.assertEqual(committed["delivery_receipt"]["outcome"], "REFUNDED_TEST_ONLY")
                self.assertEqual(auth.snapshot("account-a")["ticket_balance"], 0)

    def test_wrong_account_product_and_unverified_inputs_fail_closed(self):
        with self.assertRaises(InvalidPurchase):
            self.auth.apply_notification_mock("account-b", notice("wrong-owner", "PURCHASE", token="token-a"))
        with self.assertRaises(InvalidPurchase):
            self.auth.apply_notification_mock("account-a", notice("wrong-product", "PURCHASE", product="unknown"))
        with self.assertRaises(InvalidPurchase):
            self.auth.apply_notification_mock("account-a", notice("real-looking", "PURCHASE", token="token-a", fixture_marker="APPLE_VERIFIED"))
        self.assertEqual(self.sql_counts(), (0, 0, 0, 0))

    def test_cancel_unfinished_and_product_failure_are_audited_without_grant(self):
        for i, kind in enumerate(("UNFINISHED", "CANCELLED", "PRODUCT_FAILURE")):
            result = self.auth.apply_notification_mock("account-a", notice(f"non-grant-{i}", kind, txid=f"tx-{i}"))
            self.assertEqual(result["delivery_receipt"]["outcome"], "OBSERVED_NO_GRANT")
        self.assertEqual(self.auth.snapshot("account-a")["ticket_balance"], 0)
        self.assertEqual(self.sql_counts(), (3, 0, 0, 0))

    def test_duplicate_notification_race_commits_one_grant(self):
        event = notice("race", "PURCHASE")
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            results = list(pool.map(lambda _: self.auth.apply_notification_mock("account-a", event), range(6)))
        self.assertEqual(sum(not row["duplicate_notification"] for row in results), 1)
        self.assertEqual(self.auth.snapshot("account-a")["ticket_balance"], 6)
        self.assertEqual(self.sql_counts(), (1, 1, 0, 1))

    def test_existing_authority_rows_survive_inbox_schema_upgrade(self):
        self.auth.apply_notification_mock("account-a", notice("buy-before-version-marker", "PURCHASE"))
        before = self.auth.snapshot("account-a")
        with sqlite3.connect(self.path) as db:
            db.execute("DROP TABLE notification_inbox")  # prior schema has no inbox table
            db.execute("PRAGMA user_version=2")
        reopened = PurchaseAuthority(self.path, bundle_id=BUNDLE,
            product_specs={PRODUCT: ProductSpec(PRODUCT,3,3)}, summon_pool=POOL,
            allow_test_mock_verifier=True, clock=lambda:1_800_000_000)
        self.assertEqual(reopened.snapshot("account-a"), before)
        with sqlite3.connect(self.path) as db:
            self.assertEqual(db.execute("PRAGMA user_version").fetchone()[0],3)
        self.assertEqual(reopened.apply_notification_mock("account-a", notice("second", "PURCHASE", txid="tx-second"))["delivery_receipt"]["outcome"],"GRANTED_TEST_ONLY")
        self.assertEqual(reopened.snapshot("account-a")["ticket_balance"],12)

    def test_mock_jws_path_remains_rejected(self):
        with self.assertRaises(VerificationUnavailable): self.auth.ingest_apple_jws("synthetic.jws")
        self.assertEqual(self.sql_counts(), (0, 0, 0, 0))


if __name__ == "__main__": unittest.main()

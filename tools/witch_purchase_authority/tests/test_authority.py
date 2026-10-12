import concurrent.futures
import tempfile
import unittest
from pathlib import Path

from authority import (
    AuthorityError, CandidateDrawEngine, DuplicateTransaction, IdempotencyCollision,
    InjectedFailure, InvalidPurchase, MockVerifiedPurchase, ProductSpec,
    PurchaseAlreadyRefunded, PurchaseAuthority, VerificationUnavailable,
)

BUNDLE = "local.witch.reference.test"
PRODUCT = "local.witch.test.ticket-pack"
POOL = ("EQ_W_01", "EQ_A_01", "EQ_S_01")


def tx(txid="tx-001", *, token="acct-token-a", product=PRODUCT, quantity=1, original=None, env="Xcode", bundle=BUNDLE):
    return MockVerifiedPurchase(env, bundle, txid, original or txid, product, quantity, token, 1_799_000_000)


class PurchaseAuthorityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "authority.sqlite"
        self.auth = PurchaseAuthority(self.db, bundle_id=BUNDLE,
            product_specs={PRODUCT: ProductSpec(PRODUCT, tickets_per_unit=3, max_quantity=2)},
            summon_pool=POOL, allow_test_mock_verifier=True, clock=lambda: 1_800_000_000)
        self.auth.register_account("account-a", "acct-token-a")
        self.auth.register_account("account-b", "acct-token-b")

    def tearDown(self):
        self.tmp.cleanup()

    def process(self, *, account="account-a", key="op-1", purchase=None, count=2, seed=17, fail=None):
        return self.auth.purchase_and_draw_mock(account, key, purchase or tx(), count, test_seed=seed, fail_at=fail)

    def test_purchase_draw_atomic_idempotency_and_persistent_history(self):
        first = self.process()
        retry = self.process()
        self.assertEqual(first, retry)
        state = self.auth.snapshot("account-a")
        self.assertEqual((state["ticket_balance"], state["draw_count"], state["purchase_count"], state["idempotency_count"]), (1, 2, 1, 1))
        self.assertEqual(len(self.auth.history("account-a")), 2)
        self.assertEqual(self.auth.history("account-a")[0]["pity_before_json"], '{"drawsSinceMid":0,"drawsSinceTop":0,"guaranteeTargetOnNextTop":false,"targetTemplateID":null}')
        self.assertNotEqual(self.auth.history("account-a")[0]["pity_before_json"], self.auth.history("account-a")[1]["pity_before_json"])

    def test_idempotency_key_payload_collision_rejected(self):
        self.process()
        with self.assertRaises(IdempotencyCollision):
            self.process(key="op-1", count=1)

    def test_same_transaction_different_key_cannot_regrant(self):
        self.process()
        with self.assertRaises(DuplicateTransaction):
            self.process(key="op-2")
        self.assertEqual(self.auth.snapshot("account-a")["ticket_balance"], 1)
        self.assertEqual(len(self.auth.history("account-a")), 2)

    def test_draw_history_records_actual_source_ticket_lot_across_purchase_operations(self):
        first=tx(txid="lot-first")
        second=tx(txid="lot-second")
        self.process(purchase=first,count=0,key="buy-first")
        self.process(purchase=second,count=2,key="buy-second")
        rows=self.auth.history("account-a")
        self.assertEqual(len(rows),2)
        self.assertEqual({r["source_transaction_id"] for r in rows},{"lot-first"})
        self.assertEqual({r["purchase_transaction_id"] for r in rows},{"lot-second"})

    def test_user_token_binding_bundle_environment_product_and_quantity(self):
        with self.assertRaises(InvalidPurchase): self.process(account="account-b", purchase=tx(token="acct-token-a"))
        with self.assertRaises(InvalidPurchase): self.process(purchase=tx(bundle="other.bundle"))
        with self.assertRaises(InvalidPurchase): self.process(purchase=tx(env="Production"))
        with self.assertRaises(InvalidPurchase): self.process(purchase=tx(product="unknown.product"))
        with self.assertRaises(InvalidPurchase): self.process(purchase=tx(quantity=3), count=3)
        self.assertEqual(self.auth.snapshot("account-a")["purchase_count"], 0)

    def test_apple_jws_fails_closed_and_mock_hook_must_be_enabled(self):
        with self.assertRaises(VerificationUnavailable): self.auth.ingest_apple_jws("eyJhbGciOi...fake")
        other = PurchaseAuthority(Path(self.tmp.name)/"no_mock.sqlite", bundle_id=BUNDLE,
            product_specs={PRODUCT: ProductSpec(PRODUCT,3)}, summon_pool=POOL)
        other.register_account("account-a", "acct-token-a")
        with self.assertRaises(VerificationUnavailable):
            other.purchase_and_draw_mock("account-a","op",tx(),1,test_seed=1)

    def test_every_injected_failure_rolls_back_then_same_event_retries(self):
        for phase in ("after_purchase_insert","after_grant","after_rng","after_ticket_spend","after_draw_write","before_commit"):
            with self.subTest(phase=phase):
                db=Path(self.tmp.name)/(phase+".sqlite")
                auth=PurchaseAuthority(db,bundle_id=BUNDLE,product_specs={PRODUCT:ProductSpec(PRODUCT,3)},summon_pool=POOL,allow_test_mock_verifier=True,clock=lambda:1_800_000_000)
                auth.register_account("account-a","acct-token-a")
                with self.assertRaises(InjectedFailure): auth.purchase_and_draw_mock("account-a","op",tx(txid="tx-"+phase),2,test_seed=9,fail_at=phase)
                clean=auth.snapshot("account-a")
                self.assertEqual((clean["ticket_balance"],clean["draw_count"],clean["purchase_count"],clean["idempotency_count"]),(0,0,0,0))
                self.assertEqual(clean["revision"],0)
                self.assertEqual(clean["pity"],{"drawsSinceTop":0,"drawsSinceMid":0,"targetTemplateID":None,"guaranteeTargetOnNextTop":False})
                import sqlite3
                with sqlite3.connect(db) as check:
                    self.assertEqual(check.execute("SELECT COUNT(*) FROM ticket_ledger").fetchone()[0],0)
                committed=auth.purchase_and_draw_mock("account-a","op",tx(txid="tx-"+phase),2,test_seed=9)
                self.assertEqual(len(committed.draws),2)
                self.assertEqual(auth.snapshot("account-a")["ticket_balance"],1)

    def test_concurrent_duplicate_callback_same_key_has_one_commit(self):
        purchase=tx(txid="concurrent-tx")
        def call(_): return self.auth.purchase_and_draw_mock("account-a","same-operation",purchase,3,test_seed=123)
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results=list(pool.map(call,range(8)))
        self.assertTrue(all(r==results[0] for r in results))
        state=self.auth.snapshot("account-a")
        self.assertEqual((state["purchase_count"],state["draw_count"],state["ticket_balance"],state["idempotency_count"]),(1,3,0,1))

    def test_concurrent_two_terminal_retries_cannot_double_consume_transaction(self):
        purchase=tx(txid="two-terminal-tx")
        def call(i):
            try: return ("ok",self.auth.purchase_and_draw_mock("account-a",f"terminal-{i}",purchase,1,test_seed=1))
            except DuplicateTransaction: return ("duplicate",None)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool: result=list(pool.map(call,[1,2]))
        self.assertEqual(sum(x[0]=="ok" for x in result),1)
        self.assertEqual(sum(x[0]=="duplicate" for x in result),1)
        self.assertEqual((self.auth.snapshot("account-a")["draw_count"],self.auth.snapshot("account-a")["ticket_balance"]),(1,2))

    def test_refund_claws_unspent_and_blocks_spent_reuse(self):
        purchase=tx(txid="refund-tx")
        self.process(purchase=purchase,count=1)
        result=self.auth.refund_mock("account-a",purchase)
        self.assertEqual(result,{"clawed_back":2,"debt_added":1,"duplicate":0,"tombstone":0})
        self.assertEqual(self.auth.refund_mock("account-a",purchase),{"clawed_back":0,"debt_added":0,"duplicate":1,"tombstone":0})
        state=self.auth.snapshot("account-a")
        self.assertEqual((state["ticket_balance"],state["ticket_debt"],state["draw_count"]),(0,1,1))
        self.assertEqual(self.auth.history("account-a")[0]["purchase_status"],"refunded")
        with self.assertRaises(PurchaseAlreadyRefunded): self.process(key="after-refund",purchase=purchase,count=0)
        # A later verified purchase first repays the spent-ticket debt; it cannot be drawn again.
        later=tx(txid="new-after-refund")
        receipt=self.process(key="new-purchase",purchase=later,count=0)
        self.assertEqual(receipt.tickets_debt_offset,1)
        self.assertEqual(self.auth.snapshot("account-a")["ticket_balance"],2)
        self.assertEqual(self.auth.snapshot("account-a")["ticket_debt"],0)

    def test_refund_failure_rolls_back_and_can_retry(self):
        purchase=tx(txid="refund-fault")
        self.process(purchase=purchase,count=1)
        with self.assertRaises(InjectedFailure): self.auth.refund_mock("account-a",purchase,fail_at="after_refund_state")
        self.assertEqual((self.auth.snapshot("account-a")["ticket_balance"],self.auth.snapshot("account-a")["ticket_debt"]),(2,0))
        self.assertEqual(self.auth.refund_mock("account-a",purchase),{"clawed_back":2,"debt_added":1,"duplicate":0,"tombstone":0})

    def test_refund_before_purchase_writes_tombstone_and_rejects_late_delivery(self):
        purchase=tx(txid="refund-first")
        result=self.auth.refund_mock("account-a",purchase)
        self.assertEqual(result,{"clawed_back":0,"debt_added":0,"duplicate":0,"tombstone":1})
        self.assertEqual(self.auth.refund_mock("account-a",purchase),{"clawed_back":0,"debt_added":0,"duplicate":1,"tombstone":1})
        with self.assertRaises(PurchaseAlreadyRefunded): self.process(purchase=purchase,key="late-storekit-delivery")
        self.assertEqual((self.auth.snapshot("account-a")["ticket_balance"],self.auth.snapshot("account-a")["purchase_count"],self.auth.snapshot("account-a")["draw_count"]),(0,0,0))
        with self.assertRaises(InvalidPurchase): self.auth.refund_mock("account-b",purchase)

    def test_refund_tombstone_fault_rolls_back_and_late_purchase_is_retryable(self):
        purchase=tx(txid="refund-tombstone-fault")
        with self.assertRaises(InjectedFailure): self.auth.refund_mock("account-a",purchase,fail_at="after_refund_state")
        import sqlite3
        with sqlite3.connect(self.db) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM refunds").fetchone()[0],0)
        committed=self.process(purchase=purchase,key="purchase-after-rolled-back-refund",count=1)
        self.assertEqual(len(committed.draws),1)

    def test_idempotent_purchase_retry_after_refund_is_not_replayed_as_success(self):
        purchase=tx(txid="idempotent-refund")
        original=self.process(purchase=purchase,count=1,key="purchase-operation")
        self.auth.refund_mock("account-a",purchase)
        with self.assertRaises(PurchaseAlreadyRefunded): self.process(purchase=purchase,count=1,key="purchase-operation")
        self.assertEqual(self.auth.snapshot("account-a")["draw_count"],len(original.draws))

    def test_ticket_only_purchase_can_be_drawn_later_under_operation_uuid(self):
        purchase=tx(txid="ticket-only")
        bought=self.process(purchase=purchase,count=0,key="ticket-only-purchase")
        self.assertEqual((bought.tickets_granted,bought.tickets_drawn,bought.tickets_remaining_from_purchase),(3,0,3))
        result=self.auth.draw_mock("account-a","draw-operation-uuid-1",2,test_seed=62)
        self.assertEqual(result,self.auth.draw_mock("account-a","draw-operation-uuid-1",2,test_seed=62))
        self.assertEqual(result.transaction_identity,"PAID_TICKET_BALANCE")
        rows=self.auth.history("account-a")
        self.assertEqual(len(rows),2)
        self.assertTrue(all(r["operation_kind"]=="balance_draw" and r["purchase_transaction_id"] is None for r in rows))
        self.assertTrue(all(r["source_transaction_id"]=="ticket-only" for r in rows))
        self.assertEqual(self.auth.snapshot("account-a")["ticket_balance"],1)

    def test_balance_draw_rejects_refunded_ticket_provenance_on_idempotent_retry(self):
        purchase=tx(txid="balance-refund-retry")
        self.process(purchase=purchase,count=0,key="buy-before-balance-draw")
        self.auth.draw_mock("account-a","balance-draw-op",1,test_seed=88)
        self.auth.refund_mock("account-a",purchase)
        with self.assertRaises(PurchaseAlreadyRefunded):
            self.auth.draw_mock("account-a","balance-draw-op",1,test_seed=88)

    def test_balance_draw_numeric_inputs_are_strict_integers(self):
        self.process(purchase=tx(txid="strict-draw-numbers"),count=0,key="strict-buy")
        for bad in (True,1.0,1.5):
            with self.subTest(count=bad), self.assertRaises(InvalidPurchase):
                self.auth.draw_mock("account-a",f"bad-count-{bad}",bad,test_seed=1)

    def test_old_schema_is_rejected_instead_of_silently_partially_used(self):
        import sqlite3
        old=Path(self.tmp.name)/"old-schema.sqlite"
        with sqlite3.connect(old) as db: db.execute("CREATE TABLE purchases(transaction_id TEXT)")
        with self.assertRaises(AuthorityError):
            PurchaseAuthority(old,bundle_id=BUNDLE,product_specs={PRODUCT:ProductSpec(PRODUCT,3)},summon_pool=POOL,allow_test_mock_verifier=True)

    def test_balance_draw_failures_are_atomic_and_retryable(self):
        self.process(purchase=tx(txid="draw-fault"),count=0,key="buy")
        before=self.auth.snapshot("account-a")
        with self.assertRaises(InjectedFailure): self.auth.draw_mock("account-a","draw-fail-key",2,test_seed=10,fail_at="after_draw_write")
        self.assertEqual(self.auth.snapshot("account-a"),before)
        result=self.auth.draw_mock("account-a","draw-fail-key",2,test_seed=10)
        self.assertEqual(len(result.draws),2)
        self.assertEqual(self.auth.snapshot("account-a")["ticket_balance"],1)

    def test_quantity_draw_count_seed_and_product_spec_require_strict_bounded_ints(self):
        for bad in (True,1.0,1.5):
            with self.subTest(quantity=bad), self.assertRaises(InvalidPurchase): self.process(purchase=tx(txid=f"q{bad}",quantity=bad),count=1)
            with self.subTest(draw_count=bad), self.assertRaises(InvalidPurchase): self.process(purchase=tx(txid=f"d{bad}"),count=bad)
            with self.subTest(seed=bad), self.assertRaises(InvalidPurchase): self.process(purchase=tx(txid=f"s{bad}"),count=1,seed=bad)
        with self.assertRaises(ValueError): ProductSpec(PRODUCT,True,1)
        with self.assertRaises(ValueError): ProductSpec(PRODUCT,1.0,1)

    def test_candidate_rng_quality_distribution_and_pity_boundaries_are_explicit(self):
        self.assertTrue(CandidateDrawEngine.TEST_ONLY)
        engine=CandidateDrawEngine(POOL,7)
        draws,pity=engine.draw(1,{"drawsSinceTop":99,"drawsSinceMid":0,"targetTemplateID":None,"guaranteeTargetOnNextTop":False})
        self.assertEqual(draws[0]["qualityID"],"Q4")
        self.assertEqual(pity["drawsSinceTop"],0)
        draws,pity=CandidateDrawEngine(POOL,7).draw(1,{"drawsSinceTop":0,"drawsSinceMid":19,"targetTemplateID":None,"guaranteeTargetOnNextTop":False})
        self.assertIn(draws[0]["qualityID"],["Q3","Q4"])


if __name__ == "__main__": unittest.main()

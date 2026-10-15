"""Local-only reference authority for Witch paid-draw consistency tests.

This module intentionally has no HTTP server, Apple JWS verifier, production RNG,
StoreKit wiring, or production product catalog. Every successful purchase path is
an explicitly test-only mock path.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from contextlib import closing
import hashlib
import json
import random
import sqlite3
import time
from pathlib import Path
from typing import Any, Mapping


class AuthorityError(Exception):
    pass


class VerificationUnavailable(AuthorityError):
    pass


class InvalidPurchase(AuthorityError):
    pass


class DuplicateTransaction(AuthorityError):
    pass


class PurchaseAlreadyRefunded(AuthorityError):
    pass


class IdempotencyCollision(AuthorityError):
    pass


class InsufficientPaidTickets(AuthorityError):
    pass


class InjectedFailure(AuthorityError):
    pass


def _bounded_int(value: Any, *, minimum: int, maximum: int, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
        raise InvalidPurchase(f"{label} must be an integer in [{minimum}, {maximum}]")
    return value


@dataclass(frozen=True)
class ProductSpec:
    product_id: str
    tickets_per_unit: int
    max_quantity: int = 1

    def __post_init__(self) -> None:
        if not isinstance(self.product_id, str) or not self.product_id:
            raise ValueError("invalid test product spec")
        if any(isinstance(v, bool) or not isinstance(v, int) or v <= 0 for v in (self.tickets_per_unit, self.max_quantity)):
            raise ValueError("invalid test product spec")


@dataclass(frozen=True)
class MockVerifiedPurchase:
    """Only construct this in test fixtures; it is not an Apple verification result."""
    environment: str
    bundle_id: str
    transaction_id: str
    original_transaction_id: str
    product_id: str
    quantity: int
    app_account_token: str
    purchase_time: int
    verified_by: str = "EXPLICIT_TEST_MOCK"


_SANDBOX_FACTORY_KEY = object()

@dataclass(frozen=True, init=False)
class SandboxVerifiedPurchaseR459:
    environment: str
    bundle_id: str
    transaction_id: str
    original_transaction_id: str
    product_id: str
    quantity: int
    app_account_token: str
    purchase_time: int
    _capability: object

    def __init__(self, environment, bundle_id, transaction_id, original_transaction_id, product_id,
                 quantity, app_account_token, purchase_time, capability, *, _factory_key):
        if _factory_key is not _SANDBOX_FACTORY_KEY:
            raise TypeError("Sandbox verification records are issued only by the rehearsal adapter")
        for name, value in locals().copy().items():
            if name in {"self", "_factory_key"}: continue
            object.__setattr__(self, "_capability" if name == "capability" else name, value)

@dataclass(frozen=True, init=False)
class SandboxVerifiedNotificationR459:
    notification_id: str
    event_kind: str
    environment: str
    bundle_id: str
    transaction_id: str
    original_transaction_id: str
    product_id: str
    quantity: int
    app_account_token: str
    purchase_time: int
    _capability: object

    def __init__(self, notification_id, event_kind, environment, bundle_id, transaction_id,
                 original_transaction_id, product_id, quantity, app_account_token, purchase_time,
                 capability, *, _factory_key):
        if _factory_key is not _SANDBOX_FACTORY_KEY:
            raise TypeError("Sandbox notification records are issued only by the rehearsal adapter")
        values = locals().copy()
        for name, value in values.items():
            if name in {"self", "_factory_key"}: continue
            object.__setattr__(self, "_capability" if name == "capability" else name, value)

    def payload(self) -> dict[str, Any]:
        return {
            "notification_id": self.notification_id, "event_kind": self.event_kind,
            "environment": self.environment, "bundle_id": self.bundle_id,
            "transaction_id": self.transaction_id, "original_transaction_id": self.original_transaction_id,
            "product_id": self.product_id, "quantity": self.quantity,
            "app_account_token": self.app_account_token, "purchase_time": self.purchase_time,
        }

@dataclass(frozen=True)
class MockNotificationDelivery:
    """Only local fixtures; never an Apple signature-verification result."""
    notification_id: str
    event_kind: str
    environment: str
    bundle_id: str
    transaction_id: str
    original_transaction_id: str
    product_id: str
    quantity: int
    app_account_token: str
    purchase_time: int
    fixture_marker: str = "EXPLICIT_TEST_MOCK_NOTIFICATION"

    def payload(self) -> dict[str, Any]:
        if self.fixture_marker != "EXPLICIT_TEST_MOCK_NOTIFICATION":
            raise InvalidPurchase("notification fixture marker is required")
        for field in ("notification_id", "environment", "bundle_id", "transaction_id",
                      "original_transaction_id", "product_id", "app_account_token"):
            value = getattr(self, field)
            if not isinstance(value, str) or not value.strip():
                raise InvalidPurchase(f"{field} must be a nonempty string")
        if self.event_kind not in {"PURCHASE", "REFUND", "UNFINISHED", "CANCELLED", "PRODUCT_FAILURE"}:
            raise InvalidPurchase("unsupported mock notification kind")
        _bounded_int(self.quantity, minimum=1, maximum=2**31-1, label="notification quantity")
        _bounded_int(self.purchase_time, minimum=0, maximum=2**63-1, label="notification purchase time")
        return asdict(self)


@dataclass(frozen=True)
class DrawReceipt:
    account_id: str
    idempotency_key: str
    transaction_identity: str
    tickets_granted: int
    tickets_debt_offset: int
    tickets_drawn: int
    tickets_remaining_from_purchase: int
    draws: tuple[dict[str, Any], ...]
    pity_after: dict[str, Any]
    status: str = "COMMITTED_TEST_ONLY"


class CandidateDrawEngine:
    """Deterministic, test-seeded candidate draw; never production randomness."""
    TEST_ONLY = True
    QUALITY_BP = (("Q0", 3500), ("Q1", 4000), ("Q2", 2000), ("Q3", 400), ("Q4", 100))

    def __init__(self, pool: tuple[str, ...], seed: int):
        if not pool or len(set(pool)) != len(pool) or any(not isinstance(p,str) or not p for p in pool):
            raise ValueError("server candidate pool must contain unique nonempty IDs")
        _bounded_int(seed, minimum=0, maximum=2**63-1, label="test seed")
        self.pool = tuple(sorted(pool))
        self.rng = random.Random(seed)

    def draw(self, count: int, pity: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
        _bounded_int(count, minimum=0, maximum=50, label="draw count")
        p = dict(pity)
        p.setdefault("drawsSinceTop", 0)
        p.setdefault("drawsSinceMid", 0)
        p.setdefault("targetTemplateID", None)
        p.setdefault("guaranteeTargetOnNextTop", False)
        out: list[dict[str, Any]] = []
        for index in range(count):
            pity_before = dict(p)
            roll = self.rng.randrange(10_000)
            if p["drawsSinceTop"] >= 99:
                roll = 9_999
            acc = 0
            quality = "Q4"
            for candidate, bp in self.QUALITY_BP:
                acc += bp
                if roll < acc:
                    quality = candidate
                    break
            if quality in ("Q0", "Q1", "Q2") and p["drawsSinceMid"] >= 19:
                quality = "Q3"
            if quality == "Q4":
                p["drawsSinceTop"] = 0
            else:
                p["drawsSinceTop"] += 1
            if quality in ("Q3", "Q4"):
                p["drawsSinceMid"] = 0
            else:
                p["drawsSinceMid"] += 1
            target = p.get("targetTemplateID")
            if quality == "Q4" and target:
                hit = bool(p.get("guaranteeTargetOnNextTop")) or self.rng.randrange(10_000) < 5_000
                if hit:
                    gear_id = target
                    p["guaranteeTargetOnNextTop"] = False
                else:
                    choices = [g for g in self.pool if g != target] or list(self.pool)
                    gear_id = choices[self.rng.randrange(len(choices))]
                    p["guaranteeTargetOnNextTop"] = True
            else:
                gear_id = self.pool[self.rng.randrange(len(self.pool))]
            out.append({"drawIndex": index, "qualityID": quality, "gearTemplateID": gear_id,
                        "pityBefore": pity_before, "pityAfter": dict(p)})
        return out, p


def _canonical(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _digest(obj: Any) -> str:
    return hashlib.sha256(_canonical(obj).encode("utf-8")).hexdigest()


def _identity(tx: MockVerifiedPurchase) -> str:
    return "/".join((tx.environment, tx.bundle_id, tx.transaction_id))


def _validate_mock_transaction(tx: MockVerifiedPurchase) -> None:
    if type(tx) is not MockVerifiedPurchase or tx.verified_by != "EXPLICIT_TEST_MOCK":
        raise VerificationUnavailable("explicit test-only mock record is required")
    for field in ("environment","bundle_id","transaction_id","original_transaction_id","product_id","app_account_token"):
        value=getattr(tx,field)
        if not isinstance(value,str) or not value:
            raise InvalidPurchase(f"{field} must be a nonempty string")


def _receipt_from_json(value: str) -> DrawReceipt:
    data = json.loads(value)
    data["draws"] = tuple(data.get("draws", ()))
    return DrawReceipt(**data)


class PurchaseAuthority:
    """SQLite single-node reference implementation; test/mock verifier only."""
    def __init__(
        self,
        db_path: str | Path,
        *,
        bundle_id: str,
        product_specs: Mapping[str, ProductSpec],
        summon_pool: tuple[str, ...],
        allow_test_mock_verifier: bool = False,
        clock=time.time,
    ) -> None:
        if not bundle_id or not product_specs or not summon_pool:
            raise ValueError("bundle, product whitelist, and server pool are required")
        if any(not isinstance(k,str) or not isinstance(v,ProductSpec) or k != v.product_id for k,v in product_specs.items()):
            raise ValueError("product whitelist keys must exactly match ProductSpec.product_id")
        self.db_path = str(db_path)
        self.bundle_id = bundle_id
        self.product_specs = dict(product_specs)
        self.summon_pool = tuple(sorted(summon_pool))
        self.allow_test_mock_verifier = allow_test_mock_verifier
        self._sandbox_capability = None
        self.clock = clock
        self._initialize()

    def _bind_sandbox_rehearsal(self, factory_key: object) -> object:
        if factory_key is not _SANDBOX_FACTORY_KEY or self._sandbox_capability is not None:
            raise VerificationUnavailable("Sandbox authority may only be bound once by its factory")
        self._sandbox_capability = object()
        return self._sandbox_capability

    def _connect(self) -> sqlite3.Connection:
        con = sqlite3.connect(self.db_path, timeout=15.0, isolation_level=None)
        con.row_factory = sqlite3.Row
        con.execute("PRAGMA foreign_keys=ON")
        con.execute("PRAGMA busy_timeout=15000")
        return con

    def _initialize(self) -> None:
        Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)
        with closing(self._connect()) as db:
            version=db.execute("PRAGMA user_version").fetchone()[0]
            existing={r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'") if r[0] != 'sqlite_sequence'}
            if version not in (0,2,3) or (version == 0 and existing):
                raise AuthorityError("reference database schema mismatch; use a fresh isolated test database")
            db.execute("PRAGMA journal_mode=WAL")
            db.executescript("""
              CREATE TABLE IF NOT EXISTS accounts(
                account_id TEXT PRIMARY KEY,
                app_account_token TEXT NOT NULL UNIQUE,
                ticket_balance INTEGER NOT NULL DEFAULT 0 CHECK(ticket_balance >= 0),
                ticket_debt INTEGER NOT NULL DEFAULT 0 CHECK(ticket_debt >= 0),
                pity_json TEXT NOT NULL DEFAULT '{\"drawsSinceTop\":0,\"drawsSinceMid\":0,\"targetTemplateID\":null,\"guaranteeTargetOnNextTop\":false}',
                revision INTEGER NOT NULL DEFAULT 0
              );
              CREATE TABLE IF NOT EXISTS purchases(
                environment TEXT NOT NULL,
                bundle_id TEXT NOT NULL,
                transaction_id TEXT NOT NULL,
                original_transaction_id TEXT NOT NULL,
                account_id TEXT NOT NULL REFERENCES accounts(account_id),
                product_id TEXT NOT NULL,
                quantity INTEGER NOT NULL,
                tickets_granted INTEGER NOT NULL,
                tickets_remaining INTEGER NOT NULL,
                tickets_spent INTEGER NOT NULL DEFAULT 0,
                tickets_debt_offset INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL CHECK(status IN ('verified','refunded')),
                purchase_time INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                PRIMARY KEY(environment,bundle_id,transaction_id)
              );
              CREATE TABLE IF NOT EXISTS idempotency(
                account_id TEXT NOT NULL REFERENCES accounts(account_id),
                idempotency_key TEXT NOT NULL,
                request_fingerprint TEXT NOT NULL,
                response_json TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                PRIMARY KEY(account_id,idempotency_key)
              );
              CREATE TABLE IF NOT EXISTS draws(
                draw_id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id TEXT NOT NULL REFERENCES accounts(account_id),
                operation_idempotency_key TEXT NOT NULL,
                operation_kind TEXT NOT NULL CHECK(operation_kind IN ('purchase_draw','balance_draw')),
                purchase_environment TEXT,
                purchase_bundle_id TEXT,
                purchase_transaction_id TEXT,
                source_environment TEXT NOT NULL,
                source_bundle_id TEXT NOT NULL,
                source_transaction_id TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                gear_template_id TEXT NOT NULL,
                quality_id TEXT NOT NULL,
                pity_before_json TEXT NOT NULL,
                pity_after_json TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                FOREIGN KEY(source_environment,source_bundle_id,source_transaction_id)
                  REFERENCES purchases(environment,bundle_id,transaction_id),
                UNIQUE(account_id,operation_idempotency_key,ordinal)
              );
              CREATE TABLE IF NOT EXISTS ticket_ledger(
                ledger_id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id TEXT NOT NULL REFERENCES accounts(account_id),
                environment TEXT NOT NULL,
                bundle_id TEXT NOT NULL,
                transaction_id TEXT NOT NULL,
                event_type TEXT NOT NULL CHECK(event_type IN ('grant','debt_offset','draw_spend','refund_clawback','refund_debt')),
                amount INTEGER NOT NULL CHECK(amount > 0),
                created_at INTEGER NOT NULL,
                FOREIGN KEY(environment,bundle_id,transaction_id)
                  REFERENCES purchases(environment,bundle_id,transaction_id)
              );
              CREATE TABLE IF NOT EXISTS refunds(
                environment TEXT NOT NULL,
                bundle_id TEXT NOT NULL,
                transaction_id TEXT NOT NULL,
                original_transaction_id TEXT NOT NULL,
                product_id TEXT NOT NULL,
                quantity INTEGER NOT NULL,
                app_account_token TEXT NOT NULL,
                account_id TEXT NOT NULL REFERENCES accounts(account_id),
                created_at INTEGER NOT NULL,
                PRIMARY KEY(environment,bundle_id,transaction_id)
              );
              CREATE TABLE IF NOT EXISTS notification_inbox(
                notification_id TEXT PRIMARY KEY,
                payload_sha256 TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                account_id TEXT NOT NULL REFERENCES accounts(account_id),
                outcome TEXT NOT NULL,
                result_json TEXT NOT NULL,
                received_at INTEGER NOT NULL
              );
            """)
            db.execute("PRAGMA user_version=3")

    def register_account(self, account_id: str, app_account_token: str) -> None:
        if not account_id or not app_account_token:
            raise ValueError("authenticated account and appAccountToken required")
        with closing(self._connect()) as db:
            db.execute("BEGIN IMMEDIATE")
            try:
                db.execute("INSERT INTO accounts(account_id,app_account_token) VALUES(?,?)", (account_id, app_account_token))
                db.execute("COMMIT")
            except sqlite3.IntegrityError as exc:
                db.execute("ROLLBACK")
                raise AuthorityError("account or appAccountToken already registered") from exc

    def ingest_apple_jws(self, signed_transaction_jws: str, **_kwargs: Any) -> None:
        """Fail closed until a real Apple certificate/JWS adapter is implemented."""
        del signed_transaction_jws
        raise VerificationUnavailable("Apple JWS verification adapter is not connected; transaction rejected")

    def purchase_and_draw_mock(
        self, account_id: str, idempotency_key: str, tx: MockVerifiedPurchase, draw_count: int,
        *, test_seed: int, fail_at: str | None = None,
    ) -> DrawReceipt:
        return self._purchase_and_draw_verified(account_id, idempotency_key, tx, draw_count,
            test_seed=test_seed, fail_at=fail_at)

    def _purchase_and_draw_sandbox(self, account_id: str, idempotency_key: str,
                                   tx: SandboxVerifiedPurchaseR459, draw_count: int, *,
                                   test_seed: int, fail_at: str | None = None) -> DrawReceipt:
        if type(tx) is not SandboxVerifiedPurchaseR459 or self._sandbox_capability is None or tx._capability is not self._sandbox_capability:
            raise VerificationUnavailable("Sandbox verification record is not bound to this isolated authority")
        return self._purchase_and_draw_verified(account_id, idempotency_key, tx, draw_count,
                                                test_seed=test_seed, fail_at=fail_at)

    def _purchase_and_draw_verified(
        self,
        account_id: str,
        idempotency_key: str,
        tx: MockVerifiedPurchase | SandboxVerifiedPurchaseR459,
        draw_count: int,
        *,
        test_seed: int,
        fail_at: str | None = None,
    ) -> DrawReceipt:
        if type(tx) is MockVerifiedPurchase:
            if not self.allow_test_mock_verifier:
                raise VerificationUnavailable("explicit test-only verifier injection is disabled")
            _validate_mock_transaction(tx)
            allowed_environment = "Xcode"
            verification_kind = "EXPLICIT_TEST_MOCK"
        elif type(tx) is SandboxVerifiedPurchaseR459 and self._sandbox_capability is not None and tx._capability is self._sandbox_capability:
            allowed_environment = "Sandbox"
            verification_kind = "SANDBOX_SIGNATURE_CHECKED_NOT_AUTHORIZATION"
        else:
            raise VerificationUnavailable("unsupported verified transaction record")
        if not isinstance(idempotency_key,str) or not idempotency_key or len(idempotency_key) > 200:
            raise InvalidPurchase("idempotency key required")
        spec = self.product_specs.get(tx.product_id)
        _bounded_int(tx.quantity, minimum=1, maximum=spec.max_quantity if spec else 0, label="transaction quantity")
        _bounded_int(tx.purchase_time, minimum=0, maximum=2**63-1, label="purchase timestamp")
        _bounded_int(draw_count, minimum=0, maximum=50, label="draw count")
        _bounded_int(test_seed, minimum=0, maximum=2**63-1, label="test seed")
        identity = _identity(tx)
        if spec is None:
            raise InvalidPurchase("product is not in server whitelist")
        if tx.bundle_id != self.bundle_id or tx.environment != allowed_environment:
            raise InvalidPurchase("bundle/environment is not allowed by the test profile")
        if draw_count > tx.quantity * spec.tickets_per_unit:
            raise InvalidPurchase("draw count exceeds this verified purchase grant")
        request = {
            "account_id": account_id, "identity": identity, "original_transaction_id": tx.original_transaction_id,
            "product_id": tx.product_id, "quantity": tx.quantity, "app_account_token": tx.app_account_token,
            "purchase_time": tx.purchase_time, "draw_count": draw_count,
            "pool": list(self.summon_pool), "rules": "UNAPPROVED_R3_CANDIDATE", "test_seed": test_seed,
        }
        if verification_kind != "EXPLICIT_TEST_MOCK":
            request["verification"] = verification_kind
        fingerprint = _digest(request)
        db = self._connect()
        try:
            db.execute("BEGIN IMMEDIATE")
            account = db.execute("SELECT * FROM accounts WHERE account_id=?", (account_id,)).fetchone()
            if account is None:
                raise InvalidPurchase("authenticated account is not registered")
            if account["app_account_token"] != tx.app_account_token:
                raise InvalidPurchase("appAccountToken is bound to a different account")
            old_cmd = db.execute("SELECT request_fingerprint,response_json FROM idempotency WHERE account_id=? AND idempotency_key=?", (account_id,idempotency_key)).fetchone()
            if old_cmd:
                if old_cmd["request_fingerprint"] != fingerprint:
                    raise IdempotencyCollision("idempotency key reused with a different request")
                tx_status = db.execute("SELECT status FROM purchases WHERE environment=? AND bundle_id=? AND transaction_id=?", (tx.environment,tx.bundle_id,tx.transaction_id)).fetchone()
                if tx_status and tx_status["status"] == "refunded":
                    raise PurchaseAlreadyRefunded("idempotent purchase operation is now refunded; original receipt is not replayed")
                db.execute("COMMIT")
                return _receipt_from_json(old_cmd["response_json"])
            tombstone = db.execute("SELECT * FROM refunds WHERE environment=? AND bundle_id=? AND transaction_id=?", (tx.environment,tx.bundle_id,tx.transaction_id)).fetchone()
            if tombstone:
                if (tombstone["account_id"] != account_id or tombstone["product_id"] != tx.product_id
                    or tombstone["quantity"] != tx.quantity or tombstone["app_account_token"] != tx.app_account_token):
                    raise InvalidPurchase("refund tombstone conflicts with the later purchase identity")
                raise PurchaseAlreadyRefunded("transaction was revoked before purchase delivery; no tickets or draws granted")
            old_tx = db.execute("SELECT account_id,product_id,status FROM purchases WHERE environment=? AND bundle_id=? AND transaction_id=?", (tx.environment,tx.bundle_id,tx.transaction_id)).fetchone()
            if old_tx:
                raise DuplicateTransaction("StoreKit transaction identity was already consumed or refunded")
            now = int(self.clock())
            tickets = tx.quantity * spec.tickets_per_unit
            debt_offset = min(tickets, account["ticket_debt"])
            usable = tickets - debt_offset
            db.execute("INSERT INTO purchases(environment,bundle_id,transaction_id,original_transaction_id,account_id,product_id,quantity,tickets_granted,tickets_remaining,tickets_debt_offset,status,purchase_time,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,'verified',?,?)", (tx.environment,tx.bundle_id,tx.transaction_id,tx.original_transaction_id,account_id,tx.product_id,tx.quantity,tickets,usable,debt_offset,tx.purchase_time,now))
            if fail_at == "after_purchase_insert": raise InjectedFailure(fail_at)
            db.execute("UPDATE accounts SET ticket_debt=ticket_debt-?,ticket_balance=ticket_balance+?,revision=revision+1 WHERE account_id=?", (debt_offset,usable,account_id))
            db.execute("INSERT INTO ticket_ledger(account_id,environment,bundle_id,transaction_id,event_type,amount,created_at) VALUES(?,?,?,?,?,?,?)", (account_id,tx.environment,tx.bundle_id,tx.transaction_id,"debt_offset" if debt_offset else "grant",debt_offset if debt_offset else tickets,now))
            if debt_offset and usable:
                db.execute("INSERT INTO ticket_ledger(account_id,environment,bundle_id,transaction_id,event_type,amount,created_at) VALUES(?,?,?,?,?,?,?)", (account_id,tx.environment,tx.bundle_id,tx.transaction_id,"grant",usable,now))
            if fail_at == "after_grant": raise InjectedFailure(fail_at)
            refreshed = db.execute("SELECT * FROM accounts WHERE account_id=?", (account_id,)).fetchone()
            if refreshed["ticket_balance"] < draw_count:
                raise InsufficientPaidTickets("purchase proceeds were applied to refund debt; insufficient drawable tickets")
            if refreshed["ticket_debt"] > 0 and draw_count:
                raise InsufficientPaidTickets("paid draws are blocked while refund debt remains")
            pity_before = json.loads(refreshed["pity_json"])
            engine = CandidateDrawEngine(self.summon_pool, test_seed)
            generated, pity_after = engine.draw(draw_count, pity_before)
            if fail_at == "after_rng": raise InjectedFailure(fail_at)
            spend = draw_count
            spent_sources: list[tuple[str, str, str]] = []
            lots = db.execute("SELECT environment,bundle_id,transaction_id,tickets_remaining FROM purchases WHERE account_id=? AND status='verified' AND tickets_remaining>0 ORDER BY purchase_time,environment,bundle_id,transaction_id", (account_id,)).fetchall()
            for lot in lots:
                if not spend: break
                used = min(spend, lot["tickets_remaining"])
                spent_sources.extend([(lot["environment"],lot["bundle_id"],lot["transaction_id"])] * used)
                db.execute("UPDATE purchases SET tickets_remaining=tickets_remaining-?,tickets_spent=tickets_spent+?,updated_at=? WHERE environment=? AND bundle_id=? AND transaction_id=?", (used,used,now,lot["environment"],lot["bundle_id"],lot["transaction_id"]))
                db.execute("INSERT INTO ticket_ledger(account_id,environment,bundle_id,transaction_id,event_type,amount,created_at) VALUES(?,?,?,?,?,?,?)", (account_id,lot["environment"],lot["bundle_id"],lot["transaction_id"],"draw_spend",used,now))
                spend -= used
            if spend:
                raise InsufficientPaidTickets("verified ticket lots do not cover draw")
            if fail_at == "after_ticket_spend": raise InjectedFailure(fail_at)
            for d, source in zip(generated, spent_sources):
                db.execute("INSERT INTO draws(account_id,operation_idempotency_key,operation_kind,purchase_environment,purchase_bundle_id,purchase_transaction_id,source_environment,source_bundle_id,source_transaction_id,ordinal,gear_template_id,quality_id,pity_before_json,pity_after_json,created_at) VALUES(?,?,'purchase_draw',?,?,?,?,?,?,?,?,?,?,?,?)", (account_id,idempotency_key,tx.environment,tx.bundle_id,tx.transaction_id,*source,d["drawIndex"],d["gearTemplateID"],d["qualityID"],_canonical(d["pityBefore"]),_canonical(d["pityAfter"]),now))
            db.execute("UPDATE accounts SET ticket_balance=ticket_balance-?,pity_json=?,revision=revision+1 WHERE account_id=?", (draw_count,_canonical(pity_after),account_id))
            if fail_at == "after_draw_write": raise InjectedFailure(fail_at)
            post = db.execute("SELECT ticket_balance FROM accounts WHERE account_id=?", (account_id,)).fetchone()
            purchase_post = db.execute("SELECT tickets_remaining FROM purchases WHERE environment=? AND bundle_id=? AND transaction_id=?", (tx.environment,tx.bundle_id,tx.transaction_id)).fetchone()
            receipt = DrawReceipt(account_id,idempotency_key,identity,tickets,debt_offset,draw_count,min(tickets,purchase_post["tickets_remaining"]),tuple(generated),pity_after)
            response = _canonical(asdict(receipt))
            db.execute("INSERT INTO idempotency(account_id,idempotency_key,request_fingerprint,response_json,created_at) VALUES(?,?,?,?,?)", (account_id,idempotency_key,fingerprint,response,now))
            if fail_at == "before_commit": raise InjectedFailure(fail_at)
            db.execute("COMMIT")
            return receipt
        except Exception:
            try: db.execute("ROLLBACK")
            except sqlite3.Error: pass
            raise
        finally:
            db.close()

    def draw_mock(
        self,
        account_id: str,
        idempotency_key: str,
        count: int,
        *,
        test_seed: int,
        expected_source_identity: tuple[str, str, str] | None = None,
        fail_at: str | None = None,
    ) -> DrawReceipt:
        """Spend already stored paid tickets; an operation UUID, not a purchase ID, owns the draw."""
        if not self.allow_test_mock_verifier:
            raise VerificationUnavailable("balance draw mock is available only in explicit test mode")
        if not isinstance(idempotency_key,str) or not idempotency_key or len(idempotency_key) > 200:
            raise InvalidPurchase("idempotency key required")
        _bounded_int(count, minimum=1, maximum=50, label="draw count")
        _bounded_int(test_seed, minimum=0, maximum=2**63-1, label="test seed")
        request = {"account_id":account_id,"operation":"balance_draw","count":count,
                   "pool":list(self.summon_pool),"rules":"UNAPPROVED_R3_CANDIDATE","test_seed":test_seed}
        if expected_source_identity is not None:
            if (not isinstance(expected_source_identity, tuple) or len(expected_source_identity) != 3
                or any(not isinstance(value, str) or not value.strip() or value != value.strip()
                       for value in expected_source_identity)):
                raise InvalidPurchase("expected source identity must be a tuple of nonempty environment, bundle, and transaction strings")
            if expected_source_identity[0] != "Xcode" or expected_source_identity[1] != self.bundle_id:
                raise InvalidPurchase("expected source identity environment/bundle does not match this test authority")
            # Keep legacy operation fingerprints byte-for-byte stable for callers
            # that do not bind an expected source lot.
            request["expected_source_identity"] = list(expected_source_identity)
        fingerprint=_digest(request)
        db=self._connect()
        try:
            db.execute("BEGIN IMMEDIATE")
            account=db.execute("SELECT * FROM accounts WHERE account_id=?",(account_id,)).fetchone()
            if account is None: raise InvalidPurchase("authenticated account is not registered")
            old=db.execute("SELECT request_fingerprint,response_json FROM idempotency WHERE account_id=? AND idempotency_key=?",(account_id,idempotency_key)).fetchone()
            if old:
                if old["request_fingerprint"] != fingerprint:
                    raise IdempotencyCollision("idempotency key reused with a different balance-draw request")
                revoked=db.execute("SELECT 1 FROM draws d JOIN purchases p ON p.environment=d.source_environment AND p.bundle_id=d.source_bundle_id AND p.transaction_id=d.source_transaction_id WHERE d.account_id=? AND d.operation_idempotency_key=? AND p.status='refunded' LIMIT 1",(account_id,idempotency_key)).fetchone()
                if revoked: raise PurchaseAlreadyRefunded("balance-draw receipt includes ticket provenance that is now refunded")
                db.execute("COMMIT")
                return _receipt_from_json(old["response_json"])
            if account["ticket_debt"] > 0:
                raise InsufficientPaidTickets("paid draws are blocked while refund debt remains")
            if account["ticket_balance"] < count:
                raise InsufficientPaidTickets("insufficient paid ticket balance")
            if expected_source_identity is not None:
                first_lot = db.execute(
                    "SELECT environment,bundle_id,transaction_id,tickets_remaining FROM purchases "
                    "WHERE account_id=? AND status='verified' AND tickets_remaining>0 "
                    "ORDER BY purchase_time,environment,bundle_id,transaction_id LIMIT 1",
                    (account_id,),
                ).fetchone()
                actual_source = None if first_lot is None else (
                    first_lot["environment"], first_lot["bundle_id"], first_lot["transaction_id"])
                if actual_source != expected_source_identity or first_lot["tickets_remaining"] < count:
                    raise InsufficientPaidTickets("expected FIFO source lot does not have enough remaining tickets")
            pity_before=json.loads(account["pity_json"])
            generated,pity_after=CandidateDrawEngine(self.summon_pool,test_seed).draw(count,pity_before)
            if fail_at == "after_rng": raise InjectedFailure(fail_at)
            now=int(self.clock()); spend=count
            sources:list[tuple[str,str,str]]=[]
            lots=db.execute("SELECT environment,bundle_id,transaction_id,tickets_remaining FROM purchases WHERE account_id=? AND status='verified' AND tickets_remaining>0 ORDER BY purchase_time,environment,bundle_id,transaction_id",(account_id,)).fetchall()
            for lot in lots:
                if not spend: break
                used=min(spend,lot["tickets_remaining"])
                sources.extend([(lot["environment"],lot["bundle_id"],lot["transaction_id"])]*used)
                db.execute("UPDATE purchases SET tickets_remaining=tickets_remaining-?,tickets_spent=tickets_spent+?,updated_at=? WHERE environment=? AND bundle_id=? AND transaction_id=?",(used,used,now,lot["environment"],lot["bundle_id"],lot["transaction_id"]))
                db.execute("INSERT INTO ticket_ledger(account_id,environment,bundle_id,transaction_id,event_type,amount,created_at) VALUES(?,?,?,?,?,?,?)",(account_id,lot["environment"],lot["bundle_id"],lot["transaction_id"],"draw_spend",used,now))
                spend-=used
            if spend: raise InsufficientPaidTickets("verified ticket lots do not cover balance draw")
            if fail_at == "after_ticket_spend": raise InjectedFailure(fail_at)
            for item,source in zip(generated,sources):
                db.execute("INSERT INTO draws(account_id,operation_idempotency_key,operation_kind,purchase_environment,purchase_bundle_id,purchase_transaction_id,source_environment,source_bundle_id,source_transaction_id,ordinal,gear_template_id,quality_id,pity_before_json,pity_after_json,created_at) VALUES(?,?,'balance_draw',NULL,NULL,NULL,?,?,?,?,?,?,?,?,?)",(account_id,idempotency_key,*source,item["drawIndex"],item["gearTemplateID"],item["qualityID"],_canonical(item["pityBefore"]),_canonical(item["pityAfter"]),now))
            db.execute("UPDATE accounts SET ticket_balance=ticket_balance-?,pity_json=?,revision=revision+1 WHERE account_id=?",(count,_canonical(pity_after),account_id))
            if fail_at == "after_draw_write": raise InjectedFailure(fail_at)
            receipt=DrawReceipt(account_id,idempotency_key,"PAID_TICKET_BALANCE",0,0,count,0,tuple(generated),pity_after)
            db.execute("INSERT INTO idempotency(account_id,idempotency_key,request_fingerprint,response_json,created_at) VALUES(?,?,?,?,?)",(account_id,idempotency_key,fingerprint,_canonical(asdict(receipt)),now))
            if fail_at == "before_commit": raise InjectedFailure(fail_at)
            db.execute("COMMIT")
            return receipt
        except Exception:
            try: db.execute("ROLLBACK")
            except sqlite3.Error: pass
            raise
        finally: db.close()

    def refund_mock(self, account_id: str, tx: MockVerifiedPurchase, *, fail_at: str | None = None) -> dict[str, int]:
        return self._refund_verified(account_id, tx, fail_at=fail_at)

    def _refund_sandbox(self, account_id: str, tx: SandboxVerifiedPurchaseR459, *, fail_at: str | None = None) -> dict[str, int]:
        if type(tx) is not SandboxVerifiedPurchaseR459 or self._sandbox_capability is None or tx._capability is not self._sandbox_capability:
            raise VerificationUnavailable("Sandbox verification record is not bound to this isolated authority")
        return self._refund_verified(account_id, tx, fail_at=fail_at)

    def _refund_verified(self, account_id: str, tx: MockVerifiedPurchase | SandboxVerifiedPurchaseR459, *, fail_at: str | None = None) -> dict[str, int]:
        if type(tx) is MockVerifiedPurchase:
            if not self.allow_test_mock_verifier:
                raise VerificationUnavailable("explicit test-only verifier injection is disabled")
            _validate_mock_transaction(tx)
            allowed_environment = "Xcode"
        elif type(tx) is SandboxVerifiedPurchaseR459 and self._sandbox_capability is not None and tx._capability is self._sandbox_capability:
            allowed_environment = "Sandbox"
        else:
            raise VerificationUnavailable("unsupported verified refund record")
        spec=self.product_specs.get(tx.product_id)
        if spec is None: raise InvalidPurchase("refund product is not in server whitelist")
        _bounded_int(tx.quantity,minimum=1,maximum=spec.max_quantity,label="refund quantity")
        _bounded_int(tx.purchase_time,minimum=0,maximum=2**63-1,label="refund transaction timestamp")
        if tx.bundle_id != self.bundle_id or tx.environment != allowed_environment:
            raise InvalidPurchase("refund bundle/environment is not allowed by test profile")
        ident = (tx.environment,tx.bundle_id,tx.transaction_id)
        db=self._connect()
        try:
            db.execute("BEGIN IMMEDIATE")
            account=db.execute("SELECT * FROM accounts WHERE account_id=?",(account_id,)).fetchone()
            if account is None: raise InvalidPurchase("authenticated account is not registered")
            if account["app_account_token"] != tx.app_account_token:
                raise InvalidPurchase("refund appAccountToken is bound to a different account")
            row=db.execute("SELECT p.*,a.app_account_token AS bound_token FROM purchases p JOIN accounts a USING(account_id) WHERE p.environment=? AND p.bundle_id=? AND p.transaction_id=?",ident).fetchone()
            if row is None:
                old=db.execute("SELECT * FROM refunds WHERE environment=? AND bundle_id=? AND transaction_id=?",ident).fetchone()
                if old:
                    if (old["account_id"] != account_id or old["product_id"] != tx.product_id
                        or old["quantity"] != tx.quantity or old["app_account_token"] != tx.app_account_token
                        or old["original_transaction_id"] != tx.original_transaction_id):
                        raise InvalidPurchase("refund tombstone identity conflicts with repeated notification")
                    db.execute("COMMIT")
                    return {"clawed_back":0,"debt_added":0,"duplicate":1,"tombstone":1}
                now=int(self.clock())
                if fail_at == "before_refund": raise InjectedFailure(fail_at)
                db.execute("INSERT INTO refunds(environment,bundle_id,transaction_id,original_transaction_id,product_id,quantity,app_account_token,account_id,created_at) VALUES(?,?,?,?,?,?,?,?,?)",(*ident,tx.original_transaction_id,tx.product_id,tx.quantity,tx.app_account_token,account_id,now))
                if fail_at == "after_refund_state": raise InjectedFailure(fail_at)
                db.execute("COMMIT")
                return {"clawed_back":0,"debt_added":0,"duplicate":0,"tombstone":1}
            if row["account_id"] != account_id or row["product_id"] != tx.product_id or row["original_transaction_id"] != tx.original_transaction_id:
                raise InvalidPurchase("refund user/product/original-transaction mismatch")
            if row["quantity"] != tx.quantity:
                raise InvalidPurchase("refund quantity differs from verified purchase")
            if row["bound_token"] != tx.app_account_token:
                raise InvalidPurchase("refund appAccountToken is bound to a different account")
            seen=db.execute("SELECT 1 FROM refunds WHERE environment=? AND bundle_id=? AND transaction_id=?",ident).fetchone()
            if seen: db.execute("COMMIT"); return {"clawed_back":0,"debt_added":0,"duplicate":1,"tombstone":0}
            if row["status"] == "refunded": db.execute("COMMIT"); return {"clawed_back":0,"debt_added":0,"duplicate":1}
            now=int(self.clock()); unspent=row["tickets_remaining"]; spent=row["tickets_spent"]
            debt_repaid=row["tickets_debt_offset"]
            if fail_at == "before_refund": raise InjectedFailure(fail_at)
            db.execute("UPDATE accounts SET ticket_balance=ticket_balance-?,ticket_debt=ticket_debt+?+?,revision=revision+1 WHERE account_id=?", (unspent,spent,debt_repaid,account_id))
            if unspent:
                db.execute("INSERT INTO ticket_ledger(account_id,environment,bundle_id,transaction_id,event_type,amount,created_at) VALUES(?,?,?,?,?,?,?)", (account_id,*ident,"refund_clawback",unspent,now))
            if spent:
                db.execute("INSERT INTO ticket_ledger(account_id,environment,bundle_id,transaction_id,event_type,amount,created_at) VALUES(?,?,?,?,?,?,?)", (account_id,*ident,"refund_debt",spent,now))
            if debt_repaid:
                db.execute("INSERT INTO ticket_ledger(account_id,environment,bundle_id,transaction_id,event_type,amount,created_at) VALUES(?,?,?,?,?,?,?)", (account_id,*ident,"refund_debt",debt_repaid,now))
            db.execute("UPDATE purchases SET tickets_remaining=0,status='refunded',updated_at=? WHERE environment=? AND bundle_id=? AND transaction_id=?", (now,*ident))
            db.execute("INSERT INTO refunds(environment,bundle_id,transaction_id,original_transaction_id,product_id,quantity,app_account_token,account_id,created_at) VALUES(?,?,?,?,?,?,?,?,?)", (*ident,tx.original_transaction_id,tx.product_id,tx.quantity,tx.app_account_token,account_id,now))
            if fail_at == "after_refund_state": raise InjectedFailure(fail_at)
            db.execute("COMMIT")
            return {"clawed_back":unspent,"debt_added":spent+debt_repaid,"duplicate":0,"tombstone":0}
        except Exception:
            try: db.execute("ROLLBACK")
            except sqlite3.Error: pass
            raise
        finally: db.close()

    def _notification_current_state(self, db: sqlite3.Connection, account_id: str, ident: tuple[str, str, str]) -> dict[str, Any]:
        account = db.execute("SELECT ticket_balance,ticket_debt,revision FROM accounts WHERE account_id=?", (account_id,)).fetchone()
        purchase = db.execute("SELECT * FROM purchases WHERE environment=? AND bundle_id=? AND transaction_id=?", ident).fetchone()
        refund = db.execute("SELECT * FROM refunds WHERE environment=? AND bundle_id=? AND transaction_id=?", ident).fetchone()
        if account is None:
            raise InvalidPurchase("authenticated account is not registered")
        if purchase is None and refund is None:
            status = "not_found"
        elif purchase is None:
            status = "refund_tombstone"
        elif purchase["status"] == "refunded":
            status = "refunded"
        elif purchase["tickets_remaining"] == 0 and purchase["tickets_spent"] > 0:
            status = "consumed"
        else:
            status = "verified"
        return {
            "transaction_id": ident[2],
            "transaction_status": status,
            "purchase_status": purchase["status"] if purchase is not None else None,
            "tickets_granted": purchase["tickets_granted"] if purchase is not None else 0,
            "tickets_remaining": purchase["tickets_remaining"] if purchase is not None else 0,
            "tickets_spent": purchase["tickets_spent"] if purchase is not None else 0,
            "tickets_debt_offset": purchase["tickets_debt_offset"] if purchase is not None else 0,
            "account_ticket_balance": account["ticket_balance"],
            "account_ticket_debt": account["ticket_debt"],
            "account_revision": account["revision"],
            "production_entitlement_authorized": False,
        }

    @staticmethod
    def _notification_response(notification_id: str, duplicate: bool, receipt: dict[str, Any], current: dict[str, Any]) -> dict[str, Any]:
        return {
            "notification_id": notification_id,
            "delivery_status": "REPLAYED" if duplicate else "RECORDED",
            "duplicate_notification": duplicate,
            "delivery_receipt": receipt,
            "current_transaction": current,
            "production_entitlement_authorized": False,
            "fixture_mutation": not duplicate,
        }

    def apply_notification_mock(
        self, account_id: str, delivery: MockNotificationDelivery, *, fail_at: str | None = None
    ) -> dict[str, Any]:
        if type(delivery) is not MockNotificationDelivery or not self.allow_test_mock_verifier:
            raise VerificationUnavailable("mock notification ingestion is disabled")
        return self._apply_notification_payload(account_id, delivery.payload(), fail_at=fail_at, environment="Xcode")

    def apply_notification_sandbox(
        self, account_id: str, delivery: SandboxVerifiedNotificationR459, *, fail_at: str | None = None
    ) -> dict[str, Any]:
        if type(delivery) is not SandboxVerifiedNotificationR459 or self._sandbox_capability is None or delivery._capability is not self._sandbox_capability:
            raise VerificationUnavailable("Sandbox notification record is not bound to this isolated authority")
        return self._apply_notification_payload(account_id, delivery.payload(), fail_at=fail_at, environment="Sandbox")

    def _apply_notification_payload(self, account_id: str, payload: dict[str, Any], *, fail_at: str | None, environment: str) -> dict[str, Any]:
        """Atomically record a local mock notification and return its receipt separately from current state.

        This method is isolated test infrastructure. A delivery receipt records what that event
        did at its original commit time; current_transaction is freshly read on every response.
        Neither result is a production entitlement or Apple verification result.
        """
        if payload["bundle_id"] != self.bundle_id or payload["environment"] != environment:
            raise InvalidPurchase("bundle/environment is not allowed by the isolated profile")
        spec = self.product_specs.get(payload["product_id"])
        if spec is None:
            raise InvalidPurchase("notification product is not in server whitelist")
        _bounded_int(payload["quantity"], minimum=1, maximum=spec.max_quantity, label="notification quantity")
        encoded = _canonical(payload)
        digest = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
        ident = (payload["environment"], payload["bundle_id"], payload["transaction_id"])
        now = int(self.clock())
        db = self._connect()
        try:
            db.execute("BEGIN IMMEDIATE")
            account = db.execute("SELECT * FROM accounts WHERE account_id=?", (account_id,)).fetchone()
            if account is None:
                raise InvalidPurchase("authenticated account is not registered")
            if account["app_account_token"] != payload["app_account_token"]:
                raise InvalidPurchase("notification account token is bound to another account")
            old = db.execute("SELECT payload_sha256,result_json,account_id FROM notification_inbox WHERE notification_id=?",
                             (payload["notification_id"],)).fetchone()
            if old:
                if old["payload_sha256"] != digest:
                    raise IdempotencyCollision("notification ID reused with different payload")
                if old["account_id"] != account_id:
                    raise InvalidPurchase("notification receipt belongs to another account")
                historical_receipt = json.loads(old["result_json"])
                current = self._notification_current_state(db, account_id, ident)
                response = self._notification_response(payload["notification_id"], True, historical_receipt, current)
                db.execute("COMMIT")
                return response

            kind = payload["event_kind"]
            receipt: dict[str, Any] = {
                "notification_id": payload["notification_id"],
                "event_kind": kind,
                "payload_sha256": digest,
                "received_at": now,
                "outcome": "PENDING",
                "production_entitlement_authorized": False,
            }
            # Inbox delivery receipt and all mock domain changes commit or roll back together.
            db.execute("INSERT INTO notification_inbox VALUES(?,?,?,?,?,?,?)",
                       (payload["notification_id"], digest, encoded, account_id, "PENDING", "{}", now))
            if fail_at == "after_notification_insert": raise InjectedFailure(fail_at)
            row = db.execute("SELECT * FROM purchases WHERE environment=? AND bundle_id=? AND transaction_id=?", ident).fetchone()
            tombstone = db.execute("SELECT * FROM refunds WHERE environment=? AND bundle_id=? AND transaction_id=?", ident).fetchone()
            if kind in {"UNFINISHED", "CANCELLED", "PRODUCT_FAILURE"}:
                receipt["outcome"] = "OBSERVED_NO_GRANT"
            elif kind == "PURCHASE":
                if tombstone:
                    if (tombstone["account_id"] != account_id or tombstone["product_id"] != payload["product_id"]
                        or tombstone["quantity"] != payload["quantity"]
                        or tombstone["app_account_token"] != payload["app_account_token"]
                        or tombstone["original_transaction_id"] != payload["original_transaction_id"]):
                        raise InvalidPurchase("purchase conflicts with prior refund tombstone")
                    receipt["outcome"] = "SUPPRESSED_REFUNDED"
                elif row:
                    if (row["account_id"] != account_id or row["product_id"] != payload["product_id"]
                        or row["quantity"] != payload["quantity"]
                        or row["original_transaction_id"] != payload["original_transaction_id"]):
                        raise InvalidPurchase("purchase identity conflicts with prior transaction")
                    receipt["outcome"] = "DUPLICATE_TRANSACTION"
                else:
                    tickets = payload["quantity"] * spec.tickets_per_unit
                    offset = min(tickets, account["ticket_debt"])
                    usable = tickets - offset
                    db.execute("INSERT INTO purchases(environment,bundle_id,transaction_id,original_transaction_id,account_id,product_id,quantity,tickets_granted,tickets_remaining,tickets_debt_offset,status,purchase_time,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,'verified',?,?)",
                               (*ident, payload["original_transaction_id"], account_id, payload["product_id"], payload["quantity"], tickets, usable, offset, payload["purchase_time"], now))
                    if fail_at == "after_purchase_insert": raise InjectedFailure(fail_at)
                    db.execute("UPDATE accounts SET ticket_debt=ticket_debt-?,ticket_balance=ticket_balance+?,revision=revision+1 WHERE account_id=?",
                               (offset, usable, account_id))
                    if offset:
                        db.execute("INSERT INTO ticket_ledger(account_id,environment,bundle_id,transaction_id,event_type,amount,created_at) VALUES(?,?,?,?,?,?,?)",
                                   (account_id, *ident, "debt_offset", offset, now))
                    if usable:
                        db.execute("INSERT INTO ticket_ledger(account_id,environment,bundle_id,transaction_id,event_type,amount,created_at) VALUES(?,?,?,?,?,?,?)",
                                   (account_id, *ident, "grant", usable, now))
                    if fail_at == "after_domain_mutation": raise InjectedFailure(fail_at)
                    receipt.update(outcome="GRANTED_TEST_ONLY", tickets_granted=tickets,
                                   debt_offset=offset, tickets_usable=usable)
            else:  # REFUND
                if tombstone:
                    if (tombstone["account_id"] != account_id or tombstone["product_id"] != payload["product_id"]
                        or tombstone["quantity"] != payload["quantity"]
                        or tombstone["app_account_token"] != payload["app_account_token"]
                        or tombstone["original_transaction_id"] != payload["original_transaction_id"]):
                        raise InvalidPurchase("refund notification conflicts with prior tombstone")
                    receipt["outcome"] = "DUPLICATE_REFUND"
                elif row is None:
                    db.execute("INSERT INTO refunds(environment,bundle_id,transaction_id,original_transaction_id,product_id,quantity,app_account_token,account_id,created_at) VALUES(?,?,?,?,?,?,?,?,?)",
                               (*ident, payload["original_transaction_id"], payload["product_id"], payload["quantity"], payload["app_account_token"], account_id, now))
                    receipt["outcome"] = "REFUND_TOMBSTONE_TEST_ONLY"
                else:
                    if (row["account_id"] != account_id or row["product_id"] != payload["product_id"]
                        or row["quantity"] != payload["quantity"]
                        or row["original_transaction_id"] != payload["original_transaction_id"]):
                        raise InvalidPurchase("refund user/product/transaction mismatch")
                    unspent, spent, offset = row["tickets_remaining"], row["tickets_spent"], row["tickets_debt_offset"]
                    db.execute("UPDATE accounts SET ticket_balance=ticket_balance-?,ticket_debt=ticket_debt+?+?,revision=revision+1 WHERE account_id=?",
                               (unspent, spent, offset, account_id))
                    for event_type, amount in (("refund_clawback", unspent), ("refund_debt", spent + offset)):
                        if amount:
                            db.execute("INSERT INTO ticket_ledger(account_id,environment,bundle_id,transaction_id,event_type,amount,created_at) VALUES(?,?,?,?,?,?,?)",
                                       (account_id, *ident, event_type, amount, now))
                    db.execute("UPDATE purchases SET tickets_remaining=0,status='refunded',updated_at=? WHERE environment=? AND bundle_id=? AND transaction_id=?",
                               (now, *ident))
                    db.execute("INSERT INTO refunds(environment,bundle_id,transaction_id,original_transaction_id,product_id,quantity,app_account_token,account_id,created_at) VALUES(?,?,?,?,?,?,?,?,?)",
                               (*ident, payload["original_transaction_id"], payload["product_id"], payload["quantity"], payload["app_account_token"], account_id, now))
                    if fail_at == "after_domain_mutation": raise InjectedFailure(fail_at)
                    receipt.update(outcome="REFUNDED_TEST_ONLY", clawed_back=unspent, debt_added=spent + offset)
            receipt["production_entitlement_authorized"] = False
            db.execute("UPDATE notification_inbox SET outcome=?,result_json=? WHERE notification_id=?",
                       (receipt["outcome"], _canonical(receipt), payload["notification_id"]))
            if fail_at == "before_commit": raise InjectedFailure(fail_at)
            current = self._notification_current_state(db, account_id, ident)
            response = self._notification_response(payload["notification_id"], False, receipt, current)
            db.execute("COMMIT")
            return response
        except Exception:
            try: db.execute("ROLLBACK")
            except sqlite3.Error: pass
            raise
        finally:
            db.close()

    def snapshot(self, account_id: str) -> dict[str, Any]:
        with closing(self._connect()) as db:
            account=db.execute("SELECT * FROM accounts WHERE account_id=?", (account_id,)).fetchone()
            if account is None: raise InvalidPurchase("unknown account")
            return {
                "account_id":account["account_id"],"ticket_balance":account["ticket_balance"],"ticket_debt":account["ticket_debt"],
                "pity":json.loads(account["pity_json"]),"revision":account["revision"],
                "purchase_count":db.execute("SELECT COUNT(*) FROM purchases WHERE account_id=?",(account_id,)).fetchone()[0],
                "draw_count":db.execute("SELECT COUNT(*) FROM draws WHERE account_id=?",(account_id,)).fetchone()[0],
                "idempotency_count":db.execute("SELECT COUNT(*) FROM idempotency WHERE account_id=?",(account_id,)).fetchone()[0],
            }

    def history(self, account_id: str) -> list[dict[str, Any]]:
        with closing(self._connect()) as db:
            return [dict(r) for r in db.execute("SELECT d.*,p.status AS purchase_status,source.product_id AS source_product_id FROM draws d LEFT JOIN purchases p ON p.environment=d.purchase_environment AND p.bundle_id=d.purchase_bundle_id AND p.transaction_id=d.purchase_transaction_id JOIN purchases source ON source.environment=d.source_environment AND source.bundle_id=d.source_bundle_id AND source.transaction_id=d.source_transaction_id WHERE d.account_id=? ORDER BY d.draw_id",(account_id,))]

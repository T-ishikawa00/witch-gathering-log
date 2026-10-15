"""Explicit local-only receipt-to-gear delivery adapter (R453 candidate).

This module is a host-side fixture exporter. It is not an Apple verifier, server,
production RNG, StoreKit sink, or authorization boundary. Every successful path
requires an explicitly marked Xcode mock event and an UNAPPROVED_TEST_OVERLAY
profile. `PurchaseAuthority.ingest_apple_jws` remains fail-closed.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
import uuid
from typing import Any, Mapping

try:  # package import and direct fixture CLI are both supported
    from .authority import (
        AuthorityError, DrawReceipt, InvalidPurchase, MockVerifiedPurchase,
        ProductSpec, PurchaseAlreadyRefunded, PurchaseAuthority,
    )
except ImportError:  # pragma: no cover - exercised only by direct script invocation
    from authority import (  # type: ignore
        AuthorityError, DrawReceipt, InvalidPurchase, MockVerifiedPurchase,
        ProductSpec, PurchaseAlreadyRefunded, PurchaseAuthority,
    )


SCHEMA_VERSION = 1
PROFILE_STATUS = "UNAPPROVED_TEST_OVERLAY"
RULES_ID = "UNAPPROVED_R3_CANDIDATE"
DELIVERY_NAMESPACE = uuid.UUID("53d44b2a-f256-4c8f-91dc-1d9dfd69c453")
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_EVENT_KEYS = {
    "schemaVersion", "eventKind", "verification", "environment", "bundleID",
    "transactionID", "originalTransactionID", "productID", "productKind",
    "quantity", "appAccountToken", "purchaseTime", "idempotencyKey",
    "testAccountID",
}


class LocalDeliveryError(AuthorityError):
    """Invalid local delivery request, current-state mismatch, or cache collision."""


class DeliveryPayloadCollision(LocalDeliveryError):
    pass


def _canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def _sha(value: Any) -> str:
    return hashlib.sha256(_canonical(value)).hexdigest()


def _fingerprinted(receipt: dict[str, Any]) -> dict[str, Any]:
    value = dict(receipt)
    value["receiptFingerprint"] = ""
    value["receiptFingerprint"] = _sha({k: v for k, v in value.items() if k != "receiptFingerprint"})
    return value


def _strict_int(value: Any, label: str, low: int, high: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise LocalDeliveryError(f"{label} must be an integer in [{low}, {high}]")
    return value


def _text(value: Any, label: str, limit: int = 256) -> str:
    if not isinstance(value, str) or not value.strip() or value != value.strip() or len(value) > limit:
        raise LocalDeliveryError(f"{label} must be nonempty text of at most {limit} characters")
    return value


def _uuid_text(value: Any, label: str) -> str:
    raw = _text(value, label, 64)
    try:
        parsed = uuid.UUID(raw)
    except (ValueError, AttributeError) as exc:
        raise LocalDeliveryError(f"{label} must be a UUID") from exc
    if str(parsed) != raw.lower():
        raise LocalDeliveryError(f"{label} must use canonical UUID spelling")
    return str(parsed)


@dataclass(frozen=True)
class LocalDeliveryProfileR453:
    profile_id: str
    bundle_id: str
    product_specs: dict[str, ProductSpec]
    summon_pool: tuple[str, ...]
    templates: dict[str, dict[str, Any]]
    quality_payloads: dict[str, dict[str, Any]]
    profile_fingerprint: str

    @classmethod
    def from_mapping(cls, raw: Any) -> "LocalDeliveryProfileR453":
        if not isinstance(raw, dict):
            raise LocalDeliveryError("profile must be a JSON object")
        expected = {"schemaVersion", "status", "profileID", "bundleID", "productSpecs", "summonPool", "templates", "qualityPayloads"}
        if set(raw) != expected:
            raise LocalDeliveryError("profile fields must exactly match the R453 schema")
        _strict_int(raw["schemaVersion"], "profile schemaVersion", SCHEMA_VERSION, SCHEMA_VERSION)
        if raw["status"] != PROFILE_STATUS:
            raise LocalDeliveryError("only schema-1 UNAPPROVED_TEST_OVERLAY profiles are accepted")
        profile_id = _text(raw["profileID"], "profileID")
        bundle_id = _text(raw["bundleID"], "bundleID")
        product_rows = raw["productSpecs"]
        if not isinstance(product_rows, dict) or not product_rows:
            raise LocalDeliveryError("productSpecs must be a nonempty object")
        specs: dict[str, ProductSpec] = {}
        for product_id, row in product_rows.items():
            _text(product_id, "product ID")
            if not isinstance(row, dict) or set(row) != {"ticketsPerUnit", "maxQuantity"}:
                raise LocalDeliveryError("each product spec must contain only ticketsPerUnit and maxQuantity")
            specs[product_id] = ProductSpec(product_id,
                _strict_int(row["ticketsPerUnit"], "ticketsPerUnit", 1, 1_000_000),
                _strict_int(row["maxQuantity"], "maxQuantity", 1, 100))
        pool = raw["summonPool"]
        if not isinstance(pool, list) or not pool:
            raise LocalDeliveryError("summonPool must be a nonempty unique list")
        for template_id in pool:
            _text(template_id, "summon template ID")
        if len(pool) != len(set(pool)):
            raise LocalDeliveryError("summonPool must be a nonempty unique list")
        templates_raw = raw["templates"]
        if not isinstance(templates_raw, dict) or set(pool) != set(templates_raw):
            raise LocalDeliveryError("templates must exactly match the pinned summon pool")
        templates: dict[str, dict[str, Any]] = {}
        for template_id, row in templates_raw.items():
            _text(template_id, "template map key")
            if not isinstance(row, dict) or set(row) != {"definitionID", "slotID", "compatibleActorIDs"}:
                raise LocalDeliveryError("template payload fields do not match the R453 schema")
            definition_id = _text(row["definitionID"], "definitionID")
            if definition_id != template_id:
                raise LocalDeliveryError("template map key must equal the Core definitionID")
            slot_id = _text(row["slotID"], "slotID")
            actors = row["compatibleActorIDs"]
            if not isinstance(actors, list) or not actors:
                raise LocalDeliveryError("compatibleActorIDs must be a nonempty unique list")
            for actor in actors:
                _text(actor, "compatible actor ID")
            if len(set(actors)) != len(actors):
                raise LocalDeliveryError("compatibleActorIDs must be a nonempty unique list")
            templates[template_id] = {"definitionID": definition_id, "slotID": slot_id,
                                      "compatibleActorIDs": sorted(actors)}
        qualities = raw["qualityPayloads"]
        if not isinstance(qualities, dict) or set(qualities) != {f"Q{i}" for i in range(5)}:
            raise LocalDeliveryError("qualityPayloads must explicitly define Q0 through Q4")
        normalized: dict[str, dict[str, Any]] = {}
        for quality, row in qualities.items():
            if not isinstance(row, dict) or set(row) != {"affixIDs", "latentEffectID"}:
                raise LocalDeliveryError("quality payload requires affixIDs and latentEffectID")
            affixes = row["affixIDs"]
            if not isinstance(affixes, list) or len(affixes) > 4:
                raise LocalDeliveryError("affixIDs must be a unique list of at most four test IDs")
            for affix in affixes:
                if not _text(affix, "affixID").endswith("_TEST"):
                    raise LocalDeliveryError("only explicitly test-namespaced affix IDs are accepted")
            if len(set(affixes)) != len(affixes):
                raise LocalDeliveryError("affixIDs must be a unique list of at most four test IDs")
            latent = row["latentEffectID"]
            if latent is not None and not _text(latent, "latentEffectID").endswith("_TEST"):
                raise LocalDeliveryError("latentEffectID must be null or explicitly test-namespaced")
            normalized[quality] = {"affixIDs": list(affixes), "latentEffectID": latent}
        canonical_profile = {
            "schemaVersion": SCHEMA_VERSION, "status": PROFILE_STATUS,
            "profileID": profile_id, "bundleID": bundle_id,
            "productSpecs": {k: {"ticketsPerUnit": v.tickets_per_unit, "maxQuantity": v.max_quantity} for k, v in sorted(specs.items())},
            "summonPool": sorted(pool), "templates": templates,
            "qualityPayloads": normalized,
        }
        return cls(profile_id, bundle_id, specs, tuple(sorted(pool)), templates, normalized, _sha(canonical_profile))


@dataclass(frozen=True)
class LocalStoreKitEventR453:
    event_kind: str
    environment: str
    bundle_id: str
    transaction_id: str
    original_transaction_id: str
    product_id: str
    product_kind: str
    quantity: int
    app_account_token: str
    purchase_time: int
    idempotency_key: str
    test_account_id: str

    @classmethod
    def from_mapping(cls, raw: Any, profile: LocalDeliveryProfileR453) -> "LocalStoreKitEventR453":
        if not isinstance(raw, dict) or set(raw) != _EVENT_KEYS:
            raise LocalDeliveryError("event fields must exactly match the R453 test envelope")
        _strict_int(raw["schemaVersion"], "event schemaVersion", SCHEMA_VERSION, SCHEMA_VERSION)
        if raw["verification"] != "EXPLICIT_TEST_MOCK":
            raise LocalDeliveryError("event must carry the explicit local mock verification marker")
        event_kind = raw["eventKind"]
        if not isinstance(event_kind, str) or event_kind not in {"purchase", "revocation"}:
            raise LocalDeliveryError("only purchase and revocation mock events are accepted")
        if raw["environment"] != "Xcode" or raw["bundleID"] != profile.bundle_id:
            raise LocalDeliveryError("event environment or bundle does not match the test profile")
        if raw["productKind"] != "consumable":
            raise LocalDeliveryError("R453 ticket delivery accepts only consumable products")
        transaction_id = _text(raw["transactionID"], "transactionID")
        delivery_kind = "revocation" if event_kind == "revocation" else "entitlement"
        expected_key = f"storekit-xcode:{transaction_id}:{delivery_kind}"
        if raw["idempotencyKey"] != expected_key:
            raise LocalDeliveryError("idempotencyKey does not match the immutable StoreKit delivery identity")
        product_id = _text(raw["productID"], "productID")
        spec = profile.product_specs.get(product_id)
        if spec is None:
            raise LocalDeliveryError("product is not in the explicitly supplied test profile")
        quantity = _strict_int(raw["quantity"], "quantity", 1, spec.max_quantity)
        return cls(
            event_kind=event_kind, environment="Xcode", bundle_id=profile.bundle_id,
            transaction_id=transaction_id,
            original_transaction_id=_text(raw["originalTransactionID"], "originalTransactionID"),
            product_id=product_id, product_kind="consumable", quantity=quantity,
            app_account_token=_uuid_text(raw["appAccountToken"], "appAccountToken"),
            purchase_time=_strict_int(raw["purchaseTime"], "purchaseTime", 0, 2**63 - 1),
            idempotency_key=expected_key, test_account_id=_text(raw["testAccountID"], "testAccountID"),
        )

    def as_mock_purchase(self) -> MockVerifiedPurchase:
        return MockVerifiedPurchase(self.environment, self.bundle_id, self.transaction_id,
            self.original_transaction_id, self.product_id, self.quantity, self.app_account_token,
            self.purchase_time, verified_by="EXPLICIT_TEST_MOCK")

    def public_identity(self) -> dict[str, Any]:
        return {
            "environment": self.environment, "bundleID": self.bundle_id,
            "transactionID": self.transaction_id,
            "originalTransactionID": self.original_transaction_id,
            "productID": self.product_id, "productKind": self.product_kind,
            "quantity": self.quantity,
            "appAccountTokenSHA256": hashlib.sha256(self.app_account_token.encode()).hexdigest(),
            "testAccountIDSHA256": hashlib.sha256(self.test_account_id.encode()).hexdigest(),
            "purchaseTime": self.purchase_time,
        }


def _draw_receipt_payload(receipt: DrawReceipt) -> dict[str, Any]:
    return {
        "accountIDSHA256": hashlib.sha256(receipt.account_id.encode()).hexdigest(),
        "idempotencyKey": receipt.idempotency_key,
        "transactionIdentity": receipt.transaction_identity,
        "ticketsGranted": receipt.tickets_granted,
        "ticketsDebtOffset": receipt.tickets_debt_offset,
        "ticketsDrawn": receipt.tickets_drawn,
        "ticketsRemainingFromPurchase": receipt.tickets_remaining_from_purchase,
        "draws": list(receipt.draws),
        "pityAfter": receipt.pity_after,
        "status": receipt.status,
    }


class LocalDeliveryAdapterR453:
    """Deterministic, explicit-test-only adapter over an existing PurchaseAuthority."""
    def __init__(self, authority: PurchaseAuthority, profile: LocalDeliveryProfileR453, delivery_db_path: str | Path):
        if not authority.allow_test_mock_verifier:
            raise LocalDeliveryError("PurchaseAuthority must have its explicit test-mock gate enabled")
        if authority.bundle_id != profile.bundle_id or authority.summon_pool != profile.summon_pool:
            raise LocalDeliveryError("authority bundle/pool differs from the pinned local test profile")
        if {k: (v.tickets_per_unit, v.max_quantity) for k, v in authority.product_specs.items()} != \
           {k: (v.tickets_per_unit, v.max_quantity) for k, v in profile.product_specs.items()}:
            raise LocalDeliveryError("authority products differ from the pinned local test profile")
        self.authority = authority
        self.profile = profile
        self.delivery_db_path = str(delivery_db_path)
        cache_path = Path(self.delivery_db_path).absolute()
        authority_path = Path(authority.db_path).absolute()
        if _has_symlink_component(cache_path) or _same_file_if_present(cache_path, authority_path):
            raise LocalDeliveryError("delivery cache must be separate from the PurchaseAuthority database and must not use symlinks or hardlinks")
        self._initialize_delivery_cache()

    def _initialize_delivery_cache(self) -> None:
        cache_path = Path(self.delivery_db_path)
        if cache_path.is_symlink():
            raise LocalDeliveryError("delivery cache cannot be a symlink")
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(self.delivery_db_path) as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("CREATE TABLE IF NOT EXISTS deliveries (operation_id TEXT PRIMARY KEY, request_sha256 TEXT NOT NULL, profile_sha256 TEXT NOT NULL, receipt_json TEXT NOT NULL, receipt_sha256 TEXT NOT NULL)")

    def _read_authority(self, event: LocalStoreKitEventR453) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        db_path = Path(self.authority.db_path)
        if not db_path.is_file() or db_path.is_symlink():
            raise LocalDeliveryError("authority database must be an existing regular local file")
        uri = db_path.resolve().as_uri() + "?mode=ro"
        with sqlite3.connect(uri, uri=True) as db:
            db.row_factory = sqlite3.Row
            db.execute("PRAGMA query_only=ON")
            account = db.execute("SELECT account_id,app_account_token,ticket_balance,ticket_debt,revision,pity_json FROM accounts WHERE account_id=?", (event.test_account_id,)).fetchone()
            if account is None or account["app_account_token"] != event.app_account_token:
                raise LocalDeliveryError("test account token does not match the authority account")
            purchase = db.execute("SELECT * FROM purchases WHERE environment=? AND bundle_id=? AND transaction_id=?", (event.environment, event.bundle_id, event.transaction_id)).fetchone()
            tombstone = db.execute("SELECT * FROM refunds WHERE environment=? AND bundle_id=? AND transaction_id=?", (event.environment, event.bundle_id, event.transaction_id)).fetchone()
            if tombstone or (purchase and purchase["status"] == "refunded"):
                raise PurchaseAlreadyRefunded("current authority state is refunded or tombstoned")
            if purchase:
                expected = (event.test_account_id, event.product_id, event.quantity, event.original_transaction_id, event.purchase_time)
                actual = (purchase["account_id"], purchase["product_id"], purchase["quantity"], purchase["original_transaction_id"], purchase["purchase_time"])
                if actual != expected or purchase["status"] != "verified":
                    raise LocalDeliveryError("current transaction row does not match the full event identity")
            lots = [dict(r) for r in db.execute("SELECT environment,bundle_id,transaction_id,tickets_remaining,purchase_time FROM purchases WHERE account_id=? AND status='verified' AND tickets_remaining>0 ORDER BY purchase_time,environment,bundle_id,transaction_id", (event.test_account_id,)).fetchall()]
            return dict(account), lots

    def _authority_has_operation(self, account_id: str, operation_key: str) -> bool:
        db_path = Path(self.authority.db_path)
        if not db_path.is_file() or db_path.is_symlink():
            raise LocalDeliveryError("authority database must be an existing regular local file")
        with sqlite3.connect(db_path.resolve().as_uri() + "?mode=ro", uri=True) as db:
            db.execute("PRAGMA query_only=ON")
            row = db.execute("SELECT 1 FROM idempotency WHERE account_id=? AND idempotency_key=?", (account_id, operation_key)).fetchone()
        return row is not None

    @staticmethod
    def _mock(event: LocalStoreKitEventR453) -> MockVerifiedPurchase:
        return event.as_mock_purchase()

    def _cached(self, operation_id: str, request_sha: str) -> dict[str, Any] | None:
        with sqlite3.connect(self.delivery_db_path) as db:
            row = db.execute("SELECT request_sha256,profile_sha256,receipt_json,receipt_sha256 FROM deliveries WHERE operation_id=?", (operation_id,)).fetchone()
        if row is None:
            return None
        if row[0] != request_sha or row[1] != self.profile.profile_fingerprint:
            raise DeliveryPayloadCollision("stable operation ID was reused with a different request/profile payload")
        receipt = json.loads(row[2])
        expected_receipt_fp = _sha({k: v for k, v in receipt.items() if k != "receiptFingerprint"})
        if _sha(receipt) != row[3] or receipt.get("receiptFingerprint") != expected_receipt_fp:
            raise LocalDeliveryError("stored delivery receipt fingerprint does not match its bytes")
        return receipt

    def _store(self, operation_id: str, request_sha: str, receipt: dict[str, Any]) -> None:
        encoded = _canonical(receipt).decode("utf-8")
        receipt_sha = _sha(receipt)
        with sqlite3.connect(self.delivery_db_path, isolation_level=None) as db:
            db.execute("BEGIN IMMEDIATE")
            old = db.execute("SELECT request_sha256,profile_sha256,receipt_json,receipt_sha256 FROM deliveries WHERE operation_id=?", (operation_id,)).fetchone()
            if old:
                if old[0] != request_sha or old[1] != self.profile.profile_fingerprint or old[2] != encoded:
                    db.execute("ROLLBACK")
                    raise DeliveryPayloadCollision("stable operation ID collided with a different payload")
                db.execute("COMMIT")
                return
            db.execute("INSERT INTO deliveries VALUES(?,?,?,?,?)", (operation_id, request_sha, self.profile.profile_fingerprint, encoded, receipt_sha))
            db.execute("COMMIT")

    def _operation_uuid_for_event(self, event: LocalStoreKitEventR453, purpose: str) -> str:
        return str(uuid.uuid5(DELIVERY_NAMESPACE, f"{event.bundle_id}\n{event.transaction_id}\n{purpose}"))

    def grant_ticket_only(self, event_mapping: Any, *, test_seed: int = 0) -> dict[str, Any]:
        event = LocalStoreKitEventR453.from_mapping(event_mapping, self.profile)
        if event.event_kind != "purchase":
            raise LocalDeliveryError("grant_ticket_only requires a purchase event")
        _strict_int(test_seed, "testSeed", 0, 2**63 - 1)
        operation_id = self._operation_uuid_for_event(event, "ticket-grant")
        request = {"operationID": operation_id, "event": event.public_identity(), "testSeed": test_seed,
                   "kind": "ticket-only-grant", "profileFingerprint": self.profile.profile_fingerprint}
        request_sha = _sha(request)
        cached = self._cached(operation_id, request_sha)
        grant_key = f"r453:grant:{operation_id}"
        authority_has_grant = self._authority_has_operation(event.test_account_id, grant_key)
        if cached is not None and not authority_has_grant:
            raise LocalDeliveryError("cached ticket receipt has no matching authority idempotency record")
        # The authority performs replay/current-refund checks even when our export is cached.
        result = self.authority.purchase_and_draw_mock(event.test_account_id, grant_key, self._mock(event), 0, test_seed=test_seed)
        self._read_authority(event)
        fresh_receipt = _fingerprinted({
            "schemaVersion": SCHEMA_VERSION, "status": "LOCAL_TEST_ONLY_TICKET_GRANT",
            "candidateRulesID": RULES_ID, "profileID": self.profile.profile_id,
            "profileFingerprint": self.profile.profile_fingerprint,
            "operationID": operation_id, "receiptFingerprint": "",
            "transaction": event.public_identity(), "drawReceipt": _draw_receipt_payload(result), "gearInstances": [],
            "gearProvenance": [], "postPityState": result.pity_after,
            "productionEntitlementAuthorized": False,
        })
        if cached is not None and cached != fresh_receipt:
            raise DeliveryPayloadCollision("replayed ticket-grant receipt differs from its cached payload")
        receipt = cached or fresh_receipt
        self._store(operation_id, request_sha, receipt)
        return receipt

    def draw_from_ticket_balance(self, event_mapping: Any, *, operation_id: str, count: int, test_seed: int) -> dict[str, Any]:
        event = LocalStoreKitEventR453.from_mapping(event_mapping, self.profile)
        if event.event_kind != "purchase":
            raise LocalDeliveryError("draw requires the original purchase event")
        operation_id = _uuid_text(operation_id, "operationID")
        _strict_int(count, "drawCount", 1, 50)
        _strict_int(test_seed, "testSeed", 0, 2**63 - 1)
        request = {"operationID": operation_id, "event": event.public_identity(), "count": count,
                   "testSeed": test_seed, "kind": "balance-draw", "profileFingerprint": self.profile.profile_fingerprint}
        request_sha = _sha(request)
        cached = self._cached(operation_id, request_sha)
        account, lots = self._read_authority(event)
        draw_key = f"r453:draw:{operation_id}"
        authority_has_draw = self._authority_has_operation(event.test_account_id, draw_key)
        if cached is not None and not authority_has_draw:
            raise LocalDeliveryError("cached gear receipt has no matching authority idempotency record")
        if not authority_has_draw:
            if account["ticket_debt"] > 0:
                raise LocalDeliveryError("ticket debt blocks delivery")
            expected_lot = (event.environment, event.bundle_id, event.transaction_id)
            first_lot = None if not lots else (lots[0]["environment"], lots[0]["bundle_id"], lots[0]["transaction_id"])
            if first_lot != expected_lot or lots[0]["tickets_remaining"] < count:
                raise LocalDeliveryError("draw must be fully covered by the referenced current transaction's FIFO ticket lot")
        draw_receipt: DrawReceipt = self.authority.draw_mock(event.test_account_id, draw_key, count, test_seed=test_seed)
        # The authority can spend only FIFO lots. Re-read committed provenance and current state before exporting gear.
        rows = [r for r in self.authority.history(event.test_account_id) if r["operation_idempotency_key"] == draw_key]
        expected_identity = (event.environment, event.bundle_id, event.transaction_id)
        if len(rows) != count or any(
            (r["purchase_environment"], r["purchase_bundle_id"], r["purchase_transaction_id"]) != expected_identity
            or (r["source_environment"], r["source_bundle_id"], r["source_transaction_id"]) != expected_identity
            for r in rows
        ):
            raise LocalDeliveryError("committed draw purchase/source rows do not match the full referenced transaction identity")
        self._read_authority(event)
        generated_items = [self._gear_payload(event, operation_id, row) for row in draw_receipt.draws]
        normalized_items = [{k: v for k, v in item.items() if k != "deliveryProvenance"} for item in generated_items]
        fresh_receipt = _fingerprinted({
            "schemaVersion": SCHEMA_VERSION, "status": "LOCAL_TEST_ONLY_GEAR_DELIVERY",
            "candidateRulesID": RULES_ID, "profileID": self.profile.profile_id,
            "profileFingerprint": self.profile.profile_fingerprint,
            "operationID": operation_id, "receiptFingerprint": "",
            "transaction": event.public_identity(), "drawReceipt": _draw_receipt_payload(draw_receipt),
            "gearInstances": normalized_items,
            "gearProvenance": [dict(item["deliveryProvenance"], gearID=item["id"]) for item in generated_items],
            "postPityState": {
                "drawsSinceTop": draw_receipt.pity_after["drawsSinceTop"],
                "drawsSinceMid": draw_receipt.pity_after["drawsSinceMid"],
                "targetTemplateID": draw_receipt.pity_after.get("targetTemplateID"),
                "guaranteeTargetOnNextTop": draw_receipt.pity_after["guaranteeTargetOnNextTop"],
            },
            "productionEntitlementAuthorized": False,
        })
        # A replay must reproduce byte-identical item payloads; cache binds the stable operation to its profile and request.
        if cached is not None and cached != fresh_receipt:
            raise DeliveryPayloadCollision("replayed authority draw generated a different gear payload")
        receipt = cached or fresh_receipt
        self._store(operation_id, request_sha, receipt)
        return receipt

    def revoke(self, event_mapping: Any) -> dict[str, Any]:
        event = LocalStoreKitEventR453.from_mapping(event_mapping, self.profile)
        if event.event_kind != "revocation":
            raise LocalDeliveryError("revoke requires a revocation event")
        operation_id = self._operation_uuid_for_event(event, "revocation")
        request = {"operationID": operation_id, "event": event.public_identity(), "kind": "revocation", "profileFingerprint": self.profile.profile_fingerprint}
        request_sha = _sha(request)
        cached = self._cached(operation_id, request_sha)
        db_path = Path(self.authority.db_path)
        if not db_path.is_file() or db_path.is_symlink():
            raise LocalDeliveryError("authority database must be an existing regular local file")
        with sqlite3.connect(db_path.resolve().as_uri() + "?mode=ro", uri=True) as db:
            db.row_factory = sqlite3.Row
            db.execute("PRAGMA query_only=ON")
            row = db.execute("SELECT p.account_id,p.product_id,p.quantity,p.original_transaction_id,p.purchase_time,a.app_account_token FROM purchases p JOIN accounts a ON a.account_id=p.account_id WHERE p.environment=? AND p.bundle_id=? AND p.transaction_id=?", (event.environment, event.bundle_id, event.transaction_id)).fetchone()
        if row is not None:
            expected = (event.test_account_id, event.product_id, event.quantity, event.original_transaction_id, event.purchase_time, event.app_account_token)
            actual = (row["account_id"], row["product_id"], row["quantity"], row["original_transaction_id"], row["purchase_time"], row["app_account_token"])
            if actual != expected:
                raise LocalDeliveryError("revocation identity does not match the current authority purchase row")
        outcome = self.authority.refund_mock(event.test_account_id, self._mock(event))
        with sqlite3.connect(db_path.resolve().as_uri() + "?mode=ro", uri=True) as db:
            db.row_factory = sqlite3.Row
            db.execute("PRAGMA query_only=ON")
            row = db.execute("SELECT status,tickets_remaining,tickets_spent FROM purchases WHERE environment=? AND bundle_id=? AND transaction_id=?", (event.environment, event.bundle_id, event.transaction_id)).fetchone()
        status = "refund_tombstone" if row is None else row["status"]
        fresh_receipt = _fingerprinted({
            "schemaVersion": SCHEMA_VERSION, "status": "LOCAL_TEST_ONLY_REVOKED",
            "candidateRulesID": RULES_ID, "profileID": self.profile.profile_id,
            "profileFingerprint": self.profile.profile_fingerprint, "operationID": operation_id,
            "receiptFingerprint": "", "transaction": event.public_identity(),
            "refundOutcome": outcome, "currentTransactionStatus": status,
            "previouslyExportedGearRetracted": False,
            "productionEntitlementAuthorized": False,
        })
        receipt = cached or fresh_receipt
        self._store(operation_id, request_sha, receipt)
        return receipt

    def _gear_payload(self, event: LocalStoreKitEventR453, operation_id: str, draw: Mapping[str, Any]) -> dict[str, Any]:
        quality = draw.get("qualityID")
        template_id = draw.get("gearTemplateID")
        template = self.profile.templates.get(template_id)
        quality_payload = self.profile.quality_payloads.get(quality)
        if template is None or quality_payload is None:
            raise LocalDeliveryError("authority draw references an unknown template or quality")
        ordinal = _strict_int(draw.get("drawIndex"), "drawIndex", 0, 49)
        item_id = str(uuid.uuid5(DELIVERY_NAMESPACE,
            f"{self.profile.profile_fingerprint}\n{event.test_account_id}\n{event.transaction_id}\n{operation_id}\n{ordinal}\n{_sha(dict(draw))}"))
        return {
            "id": item_id, "definitionID": template["definitionID"], "ownerID": None,
            "protected": False, "enhancement": 0, "refinement": 0,
            "latentEffectID": quality_payload["latentEffectID"], "candidateLatentSlots": None,
            "qualityID": quality, "affixIDs": list(quality_payload["affixIDs"]), "investmentDust": 0,
            "deliveryProvenance": {
                "status": "LOCAL_TEST_ONLY", "profileID": self.profile.profile_id,
                "transactionID": event.transaction_id, "operationID": operation_id,
                "drawOrdinal": ordinal, "drawRowFingerprint": _sha(dict(draw)),
            },
        }


def export_fixture(profile_mapping: Any, authority: PurchaseAuthority, delivery_db_path: str | Path,
                   event_mapping: Any, operation_id: str | None = None, count: int = 0, test_seed: int = 0) -> dict[str, Any]:
    """Test harness API. Count 0 exports a ticket grant; positive count draws separately."""
    profile = LocalDeliveryProfileR453.from_mapping(profile_mapping)
    adapter = LocalDeliveryAdapterR453(authority, profile, delivery_db_path)
    event = LocalStoreKitEventR453.from_mapping(event_mapping, profile)
    if event.event_kind == "revocation":
        return adapter.revoke(event_mapping)
    if count == 0:
        return adapter.grant_ticket_only(event_mapping, test_seed=test_seed)
    if operation_id is None:
        raise LocalDeliveryError("positive draw count requires a stable operation UUID")
    return adapter.draw_from_ticket_balance(event_mapping, operation_id=operation_id, count=count, test_seed=test_seed)


def _read_json(path: Path) -> Any:
    if _has_symlink_component(path) or not path.is_file():
        raise LocalDeliveryError("input must be a regular, non-symlink JSON file")
    return json.loads(path.read_text(encoding="utf-8"))


def _has_symlink_component(path: Path) -> bool:
    """Reject a path if any existing component is a symlink."""
    absolute = path.absolute()
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current = current / part
        try:
            if current.is_symlink():
                return True
        except OSError:
            return True
    return False


def _same_file_if_present(left: Path, right: Path) -> bool:
    try:
        return left.exists() and right.exists() and os.path.samefile(left, right)
    except OSError as exc:
        raise LocalDeliveryError("could not safely compare file identities") from exc


def _preflight_paths(args: argparse.Namespace) -> None:
    """Validate all paths before PurchaseAuthority can initialize or mutate a database."""
    profile, event = args.profile_json.absolute(), args.event_json.absolute()
    authority, cache, output = args.authority_db.absolute(), args.delivery_cache_db.absolute(), args.output_json.absolute()
    for path, label in ((profile, "profile"), (event, "event"), (authority, "authority database")):
        if _has_symlink_component(path) or not path.is_file():
            raise LocalDeliveryError(f"{label} must be an existing regular file with no symlinked components")
    if _has_symlink_component(cache):
        raise LocalDeliveryError("delivery cache path cannot contain symlinked components")
    if cache.exists() and not cache.is_file():
        raise LocalDeliveryError("delivery cache must be a regular file when it exists")
    if _same_file_if_present(authority, cache):
        raise LocalDeliveryError("delivery cache must not alias authority database, including hardlinks")
    if any(_same_file_if_present(cache, source) for source in (profile, event)):
        raise LocalDeliveryError("delivery cache must not alias profile or event input files")
    if _has_symlink_component(output.parent) or not output.parent.is_dir():
        raise LocalDeliveryError("output parent must already exist as a real directory with no symlinked components")
    if output.exists() or output.is_symlink():
        raise LocalDeliveryError("output path already exists; exporter never overwrites")
    if Path(os.path.normpath(str(output))) == Path(os.path.normpath(str(cache))):
        raise LocalDeliveryError("output path must be distinct from the delivery cache destination")
    for input_path in (profile, event, authority, cache):
        if _same_file_if_present(output, input_path):
            raise LocalDeliveryError("output path aliases an input or database file")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="R453 explicit test-only local delivery fixture exporter")
    parser.add_argument("--allow-test-mock-verifier", action="store_true", required=True,
                        help="required explicit acknowledgement; does not verify Apple transactions")
    parser.add_argument("--profile-json", type=Path, required=True)
    parser.add_argument("--profile-sha256", required=True)
    parser.add_argument("--event-json", type=Path, required=True)
    parser.add_argument("--authority-db", type=Path, required=True)
    parser.add_argument("--delivery-cache-db", type=Path, required=True)
    parser.add_argument("--count", type=int, default=0)
    parser.add_argument("--operation-id")
    parser.add_argument("--test-seed", type=int, default=0)
    parser.add_argument("--output-json", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        _preflight_paths(args)
        profile_raw = _read_json(args.profile_json)
        if not _HEX64.fullmatch(args.profile_sha256):
            raise LocalDeliveryError("profile SHA-256 must be lowercase hex")
        if hashlib.sha256(args.profile_json.read_bytes()).hexdigest() != args.profile_sha256:
            raise LocalDeliveryError("profile file-byte SHA-256 mismatch")
        profile = LocalDeliveryProfileR453.from_mapping(profile_raw)
        event_raw = _read_json(args.event_json)
        LocalStoreKitEventR453.from_mapping(event_raw, profile)
        authority = PurchaseAuthority(args.authority_db, bundle_id=profile.bundle_id,
            product_specs=profile.product_specs, summon_pool=profile.summon_pool, allow_test_mock_verifier=True)
        out = export_fixture(profile_raw, authority, args.delivery_cache_db, event_raw,
            operation_id=args.operation_id, count=args.count, test_seed=args.test_seed)
        output = args.output_json
        fd = os.open(output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(_canonical(out) + b"\n")
        return 0
    except (LocalDeliveryError, AuthorityError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "REJECTED_TEST_ONLY", "error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":  # pragma: no cover - CLI not run during candidate preparation
    raise SystemExit(main())

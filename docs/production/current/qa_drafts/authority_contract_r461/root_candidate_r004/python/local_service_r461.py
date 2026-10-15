"""No-network, fail-closed candidate facade over the isolated R459 Sandbox ledger.

This is a contract/rehearsal module, not a server or production authorization path.
"""
from __future__ import annotations

import hashlib
import base64
import json
import re
import sqlite3
import uuid
from contextlib import closing
from dataclasses import asdict, dataclass
from pathlib import Path
from types import MappingProxyType
from typing import Any, Callable, Mapping, Protocol

try:
    from .signed_transaction_audit import SignedAuditError
    from .sandbox_ledger_adapter_r459 import SandboxLedgerRehearsalR459
    from .local_delivery_r453 import LocalDeliveryProfileR453
    from .authority import (AuthorityError, DuplicateTransaction, IdempotencyCollision,
                            InsufficientPaidTickets, PurchaseAlreadyRefunded)
except ImportError:  # explicit package staging
    from signed_transaction_audit import SignedAuditError  # type: ignore
    from sandbox_ledger_adapter_r459 import SandboxLedgerRehearsalR459  # type: ignore
    from local_delivery_r453 import LocalDeliveryProfileR453  # type: ignore
    from authority import (AuthorityError, DuplicateTransaction, IdempotencyCollision,
                          InsufficientPaidTickets, PurchaseAlreadyRefunded)  # type: ignore

MAX_REQUEST_BYTES = 70_000
MAX_JWS_BYTES = 65_536
MAX_RESPONSE_BYTES = 1_048_576
_ACTION = "purchaseAndDraw"
_PRODUCTION_DENIED = "NOT_AUTHORIZED_FOR_PRODUCTION"
_OPERATION_KEY = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_GEAR_NAMESPACE = uuid.UUID("f3df7ca0-a779-45a8-a7f9-c2c5e797a461")
_REQUEST_KEYS = {"schemaVersion", "operationID", "action", "signedTransactionJWS"}
_RESPONSE_KEYS = {"schemaVersion", "status", "operationID", "requestSHA256", "accountBindingSHA256",
                  "authorizationStatus", "historicalDelivery", "currentState", "errorCode"}


def _canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
                      allow_nan=False).encode("utf-8")


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _strict_json(data: bytes) -> dict[str, Any]:
    def unique(pairs):
        out = {}
        for key, value in pairs:
            if key in out:
                raise ValueError("duplicate JSON key")
            out[key] = value
        return out
    if type(data) is not bytes or not 1 <= len(data) <= MAX_REQUEST_BYTES:
        raise ValueError("request size outside limit")
    parsed = json.loads(data.decode("utf-8"), object_pairs_hook=unique,
                        parse_constant=lambda _: (_ for _ in ()).throw(ValueError("non-finite JSON")))
    if type(parsed) is not dict:
        raise ValueError("request must be an object")
    canonical = _canonical(parsed)
    if data not in (canonical, canonical + b"\n"):
        raise ValueError("request must use canonical JSON bytes")
    return parsed


def _canonical_uuid(value: Any) -> str:
    if type(value) is not str or not _OPERATION_KEY.fullmatch(value):
        raise ValueError("operationID must be a lowercase canonical UUID")
    if str(uuid.UUID(value)) != value:
        raise ValueError("operationID must be a lowercase canonical UUID")
    return value


@dataclass(frozen=True)
class VerifiedPrincipalR461:
    """Out-of-band result of an authenticated identity provider; never a request field."""
    account_id: str
    app_account_token: str
    stable_binding_id: str


class PrincipalProviderR461(Protocol):
    def resolve(self, trusted_transport_context: Any) -> VerifiedPrincipalR461 | None: ...


class DenyAllPrincipalProviderR461:
    """Default provider: denies without inspecting the request JWS or ledger."""
    def resolve(self, trusted_transport_context: Any) -> None:
        return None


@dataclass(frozen=True)
class R461CandidatePolicy:
    profile_id: str
    profile_fingerprint: str
    bundle_id: str
    draw_count_by_product: Mapping[str, int]
    test_seed: int
    quality_payloads: Mapping[str, Mapping[str, Any]]
    candidate_rules_id: str = "UNAPPROVED_R3_CANDIDATE"

    def __post_init__(self):
        if type(self.profile_id) is not str or not self.profile_id.strip():
            raise ValueError("profile_id is required")
        if type(self.profile_fingerprint) is not str or not re.fullmatch(r"[0-9a-f]{64}", self.profile_fingerprint):
            raise ValueError("profile fingerprint must be lowercase SHA-256")
        if type(self.bundle_id) is not str or not self.bundle_id.strip():
            raise ValueError("bundle_id is required")
        if type(self.candidate_rules_id) is not str or not self.candidate_rules_id.strip():
            raise ValueError("candidate_rules_id is required")
        if type(self.test_seed) is not int or not 0 <= self.test_seed <= 2**63 - 1:
            raise ValueError("server candidate seed must be a bounded integer")
        if not isinstance(self.draw_count_by_product, Mapping) or not self.draw_count_by_product:
            raise ValueError("a server-owned candidate draw policy is required")
        if any(type(k) is not str or not k or type(v) is not int or v < 1 or v > 50
               for k, v in self.draw_count_by_product.items()):
            raise ValueError("product draw policy is invalid")
        if set(self.quality_payloads) != {"Q0", "Q1", "Q2", "Q3", "Q4"}:
            raise ValueError("candidate quality payload must explicitly cover Q0 through Q4")
        for quality, payload in self.quality_payloads.items():
            if not isinstance(payload, Mapping) or set(payload) != {"affixIDs", "latentEffectID"}:
                raise ValueError(f"candidate payload for {quality} has invalid fields")
            affixes = payload["affixIDs"]
            latent = payload["latentEffectID"]
            if type(affixes) not in (list, tuple) or any(type(a) is not str or not a for a in affixes):
                raise ValueError(f"candidate affixes for {quality} are invalid")
            if latent is not None and (type(latent) is not str or not latent):
                raise ValueError(f"candidate latent for {quality} is invalid")
        # A frozen dataclass alone does not freeze nested dictionaries or lists.
        frozen_payloads = {
            quality: MappingProxyType({"affixIDs": tuple(payload["affixIDs"]),
                                       "latentEffectID": payload["latentEffectID"]})
            for quality, payload in self.quality_payloads.items()
        }
        object.__setattr__(self, "draw_count_by_product", MappingProxyType(dict(self.draw_count_by_product)))
        object.__setattr__(self, "quality_payloads", MappingProxyType(frozen_payloads))


class LocalAuthorityServiceR461:
    """Single-request facade. No listener, production authorization, or network."""
    def __init__(self, *, rehearsal: SandboxLedgerRehearsalR459,
                 policy: R461CandidatePolicy,
                 profile: LocalDeliveryProfileR453,
                 principal_provider: PrincipalProviderR461 | None = None):
        if type(rehearsal) is not SandboxLedgerRehearsalR459:
            raise TypeError("R461 requires the explicit R459 rehearsal facade")
        if type(profile) is not LocalDeliveryProfileR453:
            raise TypeError("R461 requires an explicit immutable R453 test profile")
        if rehearsal.status != "NOT_AUTHORIZED_FOR_PRODUCTION" or rehearsal.bundle_id != policy.bundle_id:
            raise ValueError("rehearsal does not match the fixed candidate bundle/policy")
        if (profile.bundle_id != policy.bundle_id
                or profile.profile_id != policy.profile_id
                or policy.profile_fingerprint != profile.profile_fingerprint
                or tuple(sorted(rehearsal.authority.summon_pool)) != profile.summon_pool
                or set(profile.templates) != set(rehearsal.authority.summon_pool)):
            raise ValueError("candidate profile must match R459 bundle, pool, and fingerprint")
        if {k: (v.tickets_per_unit, v.max_quantity) for k, v in profile.product_specs.items()} != \
           {k: (v.tickets_per_unit, v.max_quantity) for k, v in rehearsal.authority.product_specs.items()}:
            raise ValueError("candidate profile product policy differs from R459 authority")
        if set(policy.draw_count_by_product) != set(rehearsal.auditor.products):
            raise ValueError("candidate draw policy must exactly cover the rehearsal product allowlist")
        for product_id, draw_count in policy.draw_count_by_product.items():
            product = rehearsal.auditor.products[product_id]
            spec = rehearsal.authority.product_specs[product_id]
            if product.product_type != "Consumable" or draw_count > spec.tickets_per_unit * product.max_quantity:
                raise ValueError("purchaseAndDraw policy is incompatible with the fixed consumable rehearsal")
        profile_quality = {q: {"affixIDs": tuple(row["affixIDs"]), "latentEffectID": row["latentEffectID"]}
                           for q, row in profile.quality_payloads.items()}
        if dict(policy.quality_payloads) != profile_quality:
            raise ValueError("candidate item payload must exactly match the hashed R453 profile")
        self.rehearsal = rehearsal
        self.policy = policy
        self.profile = profile
        self.principal_provider = principal_provider or DenyAllPrincipalProviderR461()
        self._configuration_json, self._configuration_sha256 = self._configuration_snapshot()
        self._bind_policy_pin_to_ledger(self._configuration_json, self._configuration_sha256)

    def _configuration_snapshot(self) -> tuple[bytes, str]:
        """Canonical full policy snapshot; supplied profile hashes alone are insufficient."""
        profile = self.profile
        authority = self.rehearsal.authority
        profile_document = {
            "schemaVersion": 1, "status": "UNAPPROVED_TEST_OVERLAY",
            "profileID": profile.profile_id, "bundleID": profile.bundle_id,
            "productSpecs": {key: {"ticketsPerUnit": value.tickets_per_unit,
                                   "maxQuantity": value.max_quantity}
                             for key, value in sorted(profile.product_specs.items())},
            "summonPool": sorted(profile.summon_pool),
            "templates": {key: dict(value) for key, value in sorted(profile.templates.items())},
            "qualityPayloads": {key: {"affixIDs": list(value["affixIDs"]),
                                      "latentEffectID": value["latentEffectID"]}
                                for key, value in sorted(profile.quality_payloads.items())},
        }
        # Independently recompute the R453 profile digest from its full canonical content.
        computed_profile_sha = _sha(_canonical(profile_document))
        if computed_profile_sha != profile.profile_fingerprint:
            raise ValueError("R453 profile content no longer matches its fingerprint")
        policy_document = {
            "candidateRulesID": self.policy.candidate_rules_id,
            "profileID": self.policy.profile_id,
            "profileFingerprint": self.policy.profile_fingerprint,
            "bundleID": self.policy.bundle_id,
            "drawCountByProduct": dict(sorted(self.policy.draw_count_by_product.items())),
            "testSeed": self.policy.test_seed,
            "qualityPayloads": {key: {"affixIDs": list(value["affixIDs"]),
                                       "latentEffectID": value["latentEffectID"]}
                                for key, value in sorted(self.policy.quality_payloads.items())},
        }
        ledger_document = {
            "bundleID": authority.bundle_id,
            "summonPool": list(authority.summon_pool),
            "productSpecs": {key: {"ticketsPerUnit": value.tickets_per_unit,
                                   "maxQuantity": value.max_quantity}
                             for key, value in sorted(authority.product_specs.items())},
            "auditorBundleID": self.rehearsal.auditor.bundle_id,
            "auditorEnvironment": "Sandbox",  # R459 auditor constructor rejects every other environment
            "auditorRootSHA256": list(self.rehearsal.auditor.root_sha256),
            "auditorProducts": {key: {"productType": value.product_type,
                                      "maxQuantity": value.max_quantity}
                                for key, value in sorted(self.rehearsal.auditor.products.items())},
        }
        encoded = _canonical({"schemaVersion": 1, "profile": profile_document,
                              "policy": policy_document, "ledgerPolicy": ledger_document})
        return encoded, _sha(encoded)

    def _bind_policy_pin_to_ledger(self, configuration_json: bytes, configuration_sha256: str) -> None:
        """Persist one metadata-only immutable policy pin inside this exact rehearsal DB."""
        db_path = Path(self.rehearsal.authority.db_path)
        rehearsal_root = db_path.parent
        if (rehearsal_root.name != "r459-sandbox-rehearsal" or rehearsal_root.is_symlink()
                or db_path.name != "authority.sqlite" or db_path.is_symlink()
                or not db_path.is_file() or rehearsal_root.resolve(strict=True) != rehearsal_root):
            raise ValueError("policy pin requires the exact marked R459 rehearsal ledger")
        marker = rehearsal_root / "R459_LOCAL_REHEARSAL_ONLY"
        if (db_path != Path(self.rehearsal.database_path) or db_path.stat().st_nlink != 1
                or not marker.is_file() or marker.is_symlink()
                or marker.read_text(encoding="utf-8") != "NOT_AUTHORIZED_FOR_PRODUCTION\n"):
            raise ValueError("policy pin cannot redirect or modify an unmarked ledger")
        with closing(sqlite3.connect(str(db_path), timeout=10.0, isolation_level=None)) as db:
            db.execute("PRAGMA busy_timeout=10000")
            db.execute("BEGIN IMMEDIATE")
            try:
                db.execute("""CREATE TABLE IF NOT EXISTS r461_service_policy_pin(
                    singleton INTEGER PRIMARY KEY CHECK(singleton=1),
                    schema_version INTEGER NOT NULL CHECK(schema_version=1),
                    policy_sha256 TEXT NOT NULL,
                    policy_json BLOB NOT NULL
                )""")
                columns = [row[1] for row in db.execute("PRAGMA table_info(r461_service_policy_pin)")]
                if columns != ["singleton", "schema_version", "policy_sha256", "policy_json"]:
                    raise ValueError("R461 policy metadata table schema mismatch")
                row = db.execute("SELECT schema_version,policy_sha256,policy_json "
                                  "FROM r461_service_policy_pin WHERE singleton=1").fetchone()
                if row is None:
                    db.execute("INSERT INTO r461_service_policy_pin "
                               "(singleton,schema_version,policy_sha256,policy_json) VALUES(1,1,?,?)",
                               (configuration_sha256, configuration_json))
                    row = db.execute("SELECT schema_version,policy_sha256,policy_json "
                                     "FROM r461_service_policy_pin WHERE singleton=1").fetchone()
                if row != (1, configuration_sha256, configuration_json):
                    raise ValueError("R461 policy/profile drift from this ledger's original pin")
                db.execute("COMMIT")
            except Exception:
                if db.in_transaction:
                    db.execute("ROLLBACK")
                raise

    def _configuration_is_pinned(self) -> bool:
        current_json, current_sha = self._configuration_snapshot()
        return current_sha == self._configuration_sha256 and current_json == self._configuration_json

    def handle(self, request_bytes: bytes, *, trusted_transport_context: Any = None) -> bytes:
        request_sha = _sha(request_bytes) if type(request_bytes) is bytes else _sha(b"")
        operation_id = None
        binding_sha = None
        try:
            request = _strict_json(request_bytes)
            if set(request) != _REQUEST_KEYS:
                raise ValueError("request fields mismatch")
            if type(request["schemaVersion"]) is not int or request["schemaVersion"] != 1:
                raise ValueError("schemaVersion must be integer 1")
            operation_id = _canonical_uuid(request["operationID"])
            if request["action"] != _ACTION:
                raise ValueError("unsupported action")
            jws = request["signedTransactionJWS"]
            if (type(jws) is not str or not 1 <= len(jws.encode("utf-8")) <= MAX_JWS_BYTES
                    or not re.fullmatch(r"[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", jws)):
                raise ValueError("signed JWS size outside limit")
        except (ValueError, UnicodeError, TypeError, KeyError, RecursionError):
            return self._response("REJECTED", operation_id, request_sha, None, None, None, "REQUEST_INVALID")

        # Authenticate out-of-band before any signed-payload decoding or ledger read/write.
        try:
            principal = self.principal_provider.resolve(trusted_transport_context)
        except Exception:
            return self._response("REJECTED", operation_id, request_sha, None, None, None, "AUTHENTICATION_PROVIDER_ERROR")
        if type(principal) is not VerifiedPrincipalR461 or not self._principal_matches_rehearsal(principal):
            return self._response("REJECTED", operation_id, request_sha, None, None, None, "AUTHENTICATION_REQUIRED")
        binding_sha = _sha(principal.stable_binding_id.encode("utf-8"))
        # The policy is pinned inside the same R459 database; refuse in-process drift too.
        try:
            if not self._configuration_is_pinned():
                return self._response("REJECTED", operation_id, request_sha, binding_sha, None, None, "AUTHORITY_REJECTED")
        except Exception:
            return self._response("REJECTED", operation_id, request_sha, binding_sha, None, None, "AUTHORITY_REJECTED")

        audited = None
        error_code = None
        receipt = None
        try:
            # Audit once for server policy; the R459 facade independently audits before mutation.
            audited = self.rehearsal.auditor.audit(jws, expected_account_token=principal.app_account_token)
            if audited.bundle_id != self.policy.bundle_id or audited.environment != "Sandbox":
                raise ValueError("transaction outside fixed rehearsal profile")
            draw_count = self.policy.draw_count_by_product.get(audited.product_id)
            if audited.product_type != "Consumable" or draw_count is None:
                raise ValueError("transaction product not permitted by candidate policy")
            spec = self.rehearsal.authority.product_specs[audited.product_id]
            if draw_count > audited.quantity * spec.tickets_per_unit:
                raise ValueError("candidate draw exceeds signed quantity")
            result = self.rehearsal.purchase(account_id=principal.account_id,
                signed_transaction_jws=jws, operation_id=operation_id,
                draw_count=draw_count, test_seed=self.policy.test_seed)
            if result.get("grantAuthorized") is not False or result.get("revocationChecked") is not False:
                raise ValueError("rehearsal result exceeded its non-authorizing contract")
            receipt = result["receipt"]
        except PurchaseAlreadyRefunded:
            error_code = "TRANSACTION_REFUNDED"
        except IdempotencyCollision:
            error_code = "OPERATION_ID_COLLISION"
        except InsufficientPaidTickets:
            error_code = "INSUFFICIENT_TICKETS"
        except (SignedAuditError, DuplicateTransaction):
            error_code = "TRANSACTION_REJECTED"
        except (AuthorityError, ValueError, TypeError, KeyError):
            error_code = "AUTHORITY_REJECTED"
        except Exception:
            error_code = "REQUEST_FAILED"

        try:
            current, rows = self._read_current(principal.account_id, audited, operation_id)
        except Exception:
            # Fail closed if the fresh current-state snapshot cannot be read consistently.
            return self._response("REJECTED", operation_id, request_sha, binding_sha, None, None, "CURRENT_STATE_UNAVAILABLE")

        matching = [row for row in rows if row["operation_idempotency_key"] == operation_id]
        current_status = current["status"]
        if current_status == "refunded":
            error_code = error_code or "TRANSACTION_REFUNDED"
            receipt = None
        elif receipt is not None and (current_status != "active" or not matching):
            error_code = "CURRENT_STATE_NOT_DELIVERABLE"
            receipt = None

        try:
            historical = self._historical_delivery(receipt, audited, operation_id) if receipt is not None else None
        except Exception:
            # The committed draw remains replayable; never emit a partial delivery.
            historical = None
            error_code = "DELIVERY_PROJECTION_FAILED"
        op_status = "delivered" if matching else "not_delivered"
        state = {
            "revision": current["revision"], "status": current_status,
            "ticketBalance": current["ticketBalance"], "ticketDebt": current["ticketDebt"],
            "operationStatus": op_status,
        }
        status = "DELIVERED" if historical is not None and error_code is None else "REJECTED"
        return self._response(status, operation_id, request_sha, binding_sha, historical, state, error_code)

    def _principal_matches_rehearsal(self, principal: VerifiedPrincipalR461) -> bool:
        if any(type(v) is not str or not v or v != v.strip() for v in
               (principal.account_id, principal.app_account_token, principal.stable_binding_id)):
            return False
        return self.rehearsal.account_bindings.get(principal.account_id) == principal.app_account_token

    def _read_current(self, account_id: str, audited: Any, operation_id: str) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        """One readonly SQLite snapshot, avoiding cross-revision balance/refund answers."""
        db_path = Path(self.rehearsal.authority.db_path)
        if db_path.is_symlink() or not db_path.is_file():
            raise ValueError("rehearsal ledger path is unavailable")
        uri = db_path.resolve(strict=True).as_uri() + "?mode=ro"
        with closing(sqlite3.connect(uri, uri=True, timeout=5.0)) as db:
            db.row_factory = sqlite3.Row
            db.execute("PRAGMA query_only=ON")
            db.execute("BEGIN")
            account = db.execute("SELECT revision,ticket_balance,ticket_debt FROM accounts WHERE account_id=?", (account_id,)).fetchone()
            if account is None:
                raise ValueError("principal account missing")
            rows: list[dict[str, Any]] = []
            status = "unknown"
            if audited is not None:
                ident = (audited.environment, audited.bundle_id, audited.transaction_id)
                purchase = db.execute("SELECT account_id,original_transaction_id,product_id,quantity,status FROM purchases WHERE environment=? AND bundle_id=? AND transaction_id=?", ident).fetchone()
                tombstone = db.execute("SELECT account_id,original_transaction_id,product_id,quantity FROM refunds WHERE environment=? AND bundle_id=? AND transaction_id=?", ident).fetchone()
                # Never reveal transaction state for a different account binding.
                valid_purchase = (purchase is not None and purchase["account_id"] == account_id
                    and (purchase["original_transaction_id"], purchase["product_id"], purchase["quantity"])
                    == (audited.original_transaction_id, audited.product_id, audited.quantity))
                valid_tombstone = (tombstone is not None and tombstone["account_id"] == account_id
                    and (tombstone["original_transaction_id"], tombstone["product_id"], tombstone["quantity"])
                    == (audited.original_transaction_id, audited.product_id, audited.quantity))
                if valid_tombstone:
                    status = "refunded"
                elif valid_purchase:
                    if (purchase["original_transaction_id"], purchase["product_id"], purchase["quantity"]) != \
                       (audited.original_transaction_id, audited.product_id, audited.quantity):
                        raise ValueError("current purchase identity mismatch")
                    status = "refunded" if purchase["status"] == "refunded" else "active"
                if valid_purchase or valid_tombstone:
                    rows = [dict(row) for row in db.execute(
                        "SELECT ordinal,gear_template_id,quality_id,pity_before_json,pity_after_json,operation_idempotency_key,purchases.status AS purchase_status,source_environment,source_bundle_id,source_transaction_id "
                        "FROM draws JOIN purchases ON purchases.environment=draws.source_environment AND purchases.bundle_id=draws.source_bundle_id AND purchases.transaction_id=draws.source_transaction_id "
                        "WHERE draws.account_id=? AND draws.source_environment=? AND draws.source_bundle_id=? AND draws.source_transaction_id=? "
                        "ORDER BY ordinal", (account_id, *ident)).fetchall()]
            db.execute("COMMIT")
            return ({"revision": int(account["revision"]), "ticketBalance": int(account["ticket_balance"]),
                     "ticketDebt": int(account["ticket_debt"]), "status": status}, rows)

    def _historical_delivery(self, receipt: Any, audited: Any, operation_id: str) -> dict[str, Any]:
        raw = asdict(receipt)
        transaction = {
            "environment": audited.environment, "bundleID": audited.bundle_id,
            "transactionID": audited.transaction_id, "originalTransactionID": audited.original_transaction_id,
            "productID": audited.product_id, "quantity": audited.quantity,
        }
        draw_receipt = {
            "accountIDSHA256": _sha(receipt.account_id.encode("utf-8")),
            "idempotencyKey": raw["idempotency_key"], "transactionIdentity": raw["transaction_identity"],
            "ticketsGranted": raw["tickets_granted"], "ticketsDebtOffset": raw["tickets_debt_offset"],
            "ticketsDrawn": raw["tickets_drawn"], "ticketsRemainingFromPurchase": raw["tickets_remaining_from_purchase"],
            "draws": raw["draws"], "pityAfter": raw["pity_after"], "status": raw["status"],
        }
        items = []
        for index, draw in enumerate(raw["draws"]):
            quality = draw.get("qualityID")
            payload = self.policy.quality_payloads.get(quality)
            if payload is None:
                raise ValueError("quality payload missing from fixed candidate profile")
            draw_sha = _sha(_canonical(draw))
            stable_id = str(uuid.uuid5(_GEAR_NAMESPACE,
                f"{operation_id}\n{index}\n{draw_sha}"))
            items.append({
                "gearID": stable_id, "definitionID": draw["gearTemplateID"], "qualityID": quality,
                "affixIDs": list(payload["affixIDs"]), "latentEffectID": payload["latentEffectID"],
                "drawIndex": index, "drawRowFingerprint": draw_sha,
            })
        body = {"transactionIdentity": transaction, "operationID": operation_id,
                "drawReceipt": draw_receipt, "deliveredItems": items}
        fingerprint = _sha(_canonical({"profileID": self.profile.profile_id,
                                      "profileFingerprint": self.profile.profile_fingerprint, **body}))
        return {"profileID": self.profile.profile_id,
                "profileFingerprint": self.profile.profile_fingerprint,
                **body, "deliveryFingerprint": fingerprint}

    @staticmethod
    def _response(status: str, operation_id: str | None, request_sha: str,
                  binding_sha: str | None, historical: dict[str, Any] | None,
                  current: dict[str, Any] | None, error: str | None) -> bytes:
        # Unauthenticated replies carry no trusted correlation identity.
        if binding_sha is None:
            operation_id = None
        response = {"schemaVersion": 1, "status": status, "operationID": operation_id,
                    "requestSHA256": request_sha, "accountBindingSHA256": binding_sha,
                    "authorizationStatus": _PRODUCTION_DENIED,
                    "historicalDelivery": historical, "currentState": current, "errorCode": error}
        encoded = _canonical(response) + b"\n"
        if len(encoded) > MAX_RESPONSE_BYTES:
            raise ValueError("R461 response exceeds 1 MiB")
        return encoded


def export_cross_language_fixture(directory: str | Path, service: LocalAuthorityServiceR461,
                                  request_bytes: bytes, *, trusted_transport_context: Any,
                                  signed_refund_notification_jws: str,
                                  allowed_root: str | Path) -> dict[str, Any]:
    """Test-only fixture export: synthetic delivery, replay, then post-refund rejection."""
    dest = Path(directory)
    root = Path(allowed_root).resolve(strict=True)
    parent = dest.parent
    cursor = parent
    while cursor != cursor.parent:
        if cursor.is_symlink():
            raise ValueError("fixture path cannot traverse symlink directories")
        if cursor == root:
            break
        cursor = cursor.parent
    try:
        resolved_parent = parent.resolve(strict=True)
        resolved_parent.relative_to(root)
    except (OSError, ValueError):
        raise ValueError("fixture destination must be under its explicit allowed root") from None
    if dest.exists() or dest.is_symlink() or not resolved_parent.is_dir():
        raise ValueError("fixture destination must be a new child of an existing nonsymlink directory")
    principal = service.principal_provider.resolve(trusted_transport_context)
    if type(principal) is not VerifiedPrincipalR461:
        raise ValueError("fixture export requires an explicit synthetic principal")
    request = _strict_json(request_bytes)
    first = service.handle(request_bytes, trusted_transport_context=trusted_transport_context)
    replay = service.handle(request_bytes, trusted_transport_context=trusted_transport_context)
    first_value = json.loads(first)
    replay_value = json.loads(replay)
    if first_value["status"] != "DELIVERED" or replay != first:
        raise ValueError("synthetic delivery/replay did not produce byte-equivalent response")
    refund = service.rehearsal.refund(account_id=principal.account_id,
        signed_notification_jws=signed_refund_notification_jws)
    rejected = service.handle(request_bytes, trusted_transport_context=trusted_transport_context)
    rejected_value = json.loads(rejected)
    if (rejected_value["status"] != "REJECTED" or rejected_value["historicalDelivery"] is not None
        or rejected_value["currentState"] is None or rejected_value["currentState"]["status"] != "refunded"
        or rejected_value["currentState"]["revision"] <= first_value["currentState"]["revision"]):
        raise ValueError("post-refund response did not report fresh rejecting state")
    dest.mkdir(mode=0o700)
    files = {"request.json": request_bytes, "delivered.json": first, "replay.json": replay,
             "post_refund_rejected.json": rejected}
    rows = []
    for name, content in files.items():
        path = dest / name
        with path.open("xb") as stream:
            stream.write(content)
        rows.append({"path": name, "sizeBytes": len(content), "sha256": _sha(content)})
    transaction = first_value["historicalDelivery"]["transactionIdentity"]
    draw_receipt = first_value["historicalDelivery"]["drawReceipt"]
    wrapper = {
        "schemaVersion": 1,
        "requestBase64": base64.b64encode(request_bytes).decode("ascii"),
        "requestSHA256": _sha(request_bytes),
        "operationID": request["operationID"],
        "expectedStoreKit": {
            "environment": transaction["environment"], "bundleID": transaction["bundleID"],
            "transactionID": transaction["transactionID"],
            "originalTransactionID": transaction["originalTransactionID"],
            "productID": transaction["productID"], "quantity": transaction["quantity"],
            "accountBindingSHA256": first_value["accountBindingSHA256"],
            "accountIDSHA256": draw_receipt["accountIDSHA256"],
        },
        "responses": [
            {"kind": "delivered", "base64": base64.b64encode(first).decode("ascii"), "sha256": _sha(first)},
            {"kind": "replay", "base64": base64.b64encode(replay).decode("ascii"), "sha256": _sha(replay)},
            {"kind": "postRefund", "base64": base64.b64encode(rejected).decode("ascii"), "sha256": _sha(rejected)},
        ],
        "status": "SYNTHETIC_TEST_ONLY_NOT_APPLE_AUTHORIZATION",
        "productionEntitlementAuthorized": False,
        "privateKeyExported": False,
    }
    encoded = _canonical(wrapper) + b"\n"
    with (dest / "CROSS_LANGUAGE_FIXTURE.json").open("xb") as stream:
        stream.write(encoded)
    return {"schema": "r461-synthetic-cross-language-fixture-v1", "status": wrapper["status"],
            "operationID": wrapper["operationID"], "files": rows,
            "crossLanguageFixture": {"path": "CROSS_LANGUAGE_FIXTURE.json", "sizeBytes": len(encoded),
                                     "sha256": _sha(encoded)},
            "refundOutcome": refund, "productionEntitlementAuthorized": False,
            "realAppleTransaction": False}

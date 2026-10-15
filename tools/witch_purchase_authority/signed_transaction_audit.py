"""Offline cryptographic audit only. Never authorizes a grant or contacts Apple.

Uses Apple's pinned verifier with strict certificate-chain checks. Trust roots
are explicit auditor configuration, not taken from the untrusted JWS. Synthetic
roots can exercise the real crypto path in tests but cannot prove an Apple sale.
The existing PurchaseAuthority.ingest_apple_jws() remains closed.
"""
from __future__ import annotations

import base64
from dataclasses import dataclass, field
import hashlib
from importlib.metadata import version
import json
import re
import time
from types import MappingProxyType
from typing import Callable, Mapping
from uuid import UUID

from appstoreserverlibrary.models.Environment import Environment
from appstoreserverlibrary.signed_data_verifier import SignedDataVerifier


class SignedAuditError(ValueError):
    """A stable error code; never includes a receipt, account token or payload."""


@dataclass(frozen=True)
class AuditProduct:
    product_type: str
    max_quantity: int = 1

    def __post_init__(self):
        if self.product_type not in ("Consumable", "Non-Consumable"):
            raise SignedAuditError("UNSUPPORTED_PRODUCT_TYPE")
        if type(self.max_quantity) is not int or not 1 <= self.max_quantity <= 100:
            raise SignedAuditError("INVALID_QUANTITY_POLICY")
        if self.product_type == "Non-Consumable" and self.max_quantity != 1:
            raise SignedAuditError("INVALID_NONCONSUMABLE_QUANTITY_POLICY")


@dataclass(frozen=True)
class AuditedTransaction:
    environment: str
    bundle_id: str
    transaction_id: str
    original_transaction_id: str
    product_id: str
    product_type: str
    quantity: int
    purchase_date_ms: int
    signed_date_ms: int
    jws_sha256: str
    root_sha256: tuple[str, ...]
    status: str = field(default="OFFLINE_CHAIN_CHECKED_NOT_AUTHORIZATION", init=False)
    revocation_checked: bool = field(default=False, init=False)
    grant_authorized: bool = field(default=False, init=False)


def _text(value, code: str, maximum: int = 256) -> str:
    if not isinstance(value, str) or not value or len(value) > maximum:
        raise SignedAuditError(code)
    if value != value.strip() or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise SignedAuditError(code)
    return value


def _uuid(value) -> UUID:
    try:
        text = _text(value, "INVALID_ACCOUNT_TOKEN", 36)
        token = UUID(text)
        if len(text) != 36 or str(token) != text.lower() or token.int == 0:
            raise ValueError()
        return token
    except (ValueError, AttributeError, TypeError):
        raise SignedAuditError("INVALID_ACCOUNT_TOKEN") from None


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise SignedAuditError("DUPLICATE_JSON_KEY")
        result[key] = value
    return result


def _json_segment(segment: str) -> dict:
    try:
        raw = base64.b64decode(segment + "=" * (-len(segment) % 4), altchars=b"-_", validate=True)
        data = json.loads(raw.decode("utf-8"), object_pairs_hook=_unique_object,
                          parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
        if type(data) is not dict:
            raise ValueError()
        return data
    except (ValueError, UnicodeError, RecursionError):
        raise SignedAuditError("MALFORMED_JWS_JSON") from None


class OfflineTransactionAuditor:
    """Sandbox-format audit with no ledger, network, API or production route.

    `expected_account_token` must come from a separately authenticated account
    binding in a future service. Checking equality alone does not authenticate
    that account. This auditor deliberately cannot produce a grant authorization.
    """

    def __init__(self, *, root_certificates: tuple[bytes, ...], bundle_id: str,
                 products: Mapping[str, AuditProduct], environment: str = "Sandbox",
                 clock_ms: Callable[[], int] | None = None):
        # 3.1.2 fixes Apple's stale-OCSP advisory GHSA-8f6j-263m-g72x. This
        # offline audit does not perform OCSP at all and says so in every result.
        if version("app-store-server-library") != "3.1.2":
            raise SignedAuditError("UNREVIEWED_VERIFIER_VERSION")
        if environment != "Sandbox":
            # Xcode/LocalTesting skip signature checks in the upstream library.
            # Production is outside this local audit's authority and scope.
            raise SignedAuditError("UNSUPPORTED_AUDIT_ENVIRONMENT")
        if (type(root_certificates) is not tuple or not 1 <= len(root_certificates) <= 4
                or any(type(c) is not bytes or not 1 <= len(c) <= 16384 for c in root_certificates)):
            raise SignedAuditError("INVALID_TRUST_ROOT_CONFIGURATION")
        self.bundle_id = _text(bundle_id, "INVALID_BUNDLE_CONFIGURATION")
        if not products or len(products) > 256:
            raise SignedAuditError("INVALID_PRODUCT_CONFIGURATION")
        for key, spec in products.items():
            _text(key, "INVALID_PRODUCT_CONFIGURATION")
            if type(spec) is not AuditProduct:
                raise SignedAuditError("INVALID_PRODUCT_CONFIGURATION")
        self.products = MappingProxyType(dict(products))
        self.root_sha256 = tuple(hashlib.sha256(c).hexdigest() for c in root_certificates)
        self._clock = clock_ms or (lambda: time.time_ns() // 1_000_000)
        self._verifier = SignedDataVerifier(list(root_certificates), False, Environment.SANDBOX, bundle_id)
        # Never disable the library's X509_STRICT checks, including in tests.

    def audit(self, signed_transaction: str, *, expected_account_token: str) -> AuditedTransaction:
        expected = _uuid(expected_account_token)
        if (type(signed_transaction) is not str or not 1 <= len(signed_transaction) <= 65536
                or not re.fullmatch(r"[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", signed_transaction)):
            raise SignedAuditError("MALFORMED_JWS")
        header_part, payload_part, _ = signed_transaction.split(".")
        header, payload = _json_segment(header_part), _json_segment(payload_part)
        # Parsing here is validation of untrusted syntax, not authentication.
        if header.get("alg") != "ES256" or "crit" in header or "b64" in header:
            raise SignedAuditError("UNSUPPORTED_JWS_HEADER")
        chain = header.get("x5c")
        if (type(chain) is not list or len(chain) != 3
                or any(type(c) is not str or not 1 <= len(c) <= 16384 for c in chain)):
            raise SignedAuditError("INVALID_JWS_CHAIN_HEADER")
        try:
            self._verifier.verify_and_decode_signed_transaction(signed_transaction)
        except Exception:
            # No untrusted JWT text or credential-bearing library traceback
            # escapes this boundary. Every library error remains fail-closed.
            raise SignedAuditError("SIGNATURE_OR_CHAIN_REJECTED") from None
        return self._audit_verified_transaction_payload(payload, signed_transaction,
            expected_account_token=expected, allow_revocation=False)

    def _audit_verified_transaction_payload(self, payload: dict, signed_transaction: str, *,
                                            expected_account_token: UUID,
                                            allow_revocation: bool) -> AuditedTransaction:
        """Shared exact-type transaction policy after JWS signature verification."""
        if payload.get("environment") != "Sandbox" or payload.get("bundleId") != self.bundle_id:
            raise SignedAuditError("APP_OR_ENVIRONMENT_MISMATCH")
        if _uuid(payload.get("appAccountToken")) != expected_account_token:
            raise SignedAuditError("ACCOUNT_BINDING_MISMATCH")
        product_id = _text(payload.get("productId"), "INVALID_PRODUCT")
        spec = self.products.get(product_id)
        if spec is None or payload.get("type") != spec.product_type:
            raise SignedAuditError("PRODUCT_POLICY_MISMATCH")
        quantity = payload.get("quantity")
        if type(quantity) is not int or not 1 <= quantity <= spec.max_quantity:
            raise SignedAuditError("QUANTITY_POLICY_MISMATCH")
        if payload.get("inAppOwnershipType") != "PURCHASED":
            raise SignedAuditError("UNSUPPORTED_OWNERSHIP")
        revocation = payload.get("revocationDate")
        if not allow_revocation and any(payload.get(k) is not None for k in ("revocationDate", "revocationReason", "revocationType")):
            raise SignedAuditError("REVOKED_TRANSACTION")
        if allow_revocation:
            if type(revocation) is not int or revocation <= 0:
                raise SignedAuditError("REFUND_NOTICE_MISSING_REVOCATION")
            reason = payload.get("revocationReason")
            if reason is not None and (type(reason) is not int or reason not in (0, 1)):
                raise SignedAuditError("INVALID_REVOCATION_FIELDS")
            revocation_type = payload.get("revocationType")
            if revocation_type is not None:
                _text(revocation_type, "INVALID_REVOCATION_FIELDS", 64)
        now = self._clock()
        purchase, signed = payload.get("purchaseDate"), payload.get("signedDate")
        if (type(now) is not int or now <= 0 or type(purchase) is not int or type(signed) is not int
                or not 0 < purchase <= signed <= now + 300_000):
            raise SignedAuditError("INVALID_TRANSACTION_DATES")
        if allow_revocation and not purchase <= revocation <= signed:
            raise SignedAuditError("INVALID_TRANSACTION_DATES")
        transaction_id = _text(payload.get("transactionId"), "INVALID_TRANSACTION_ID", 128)
        original_id = _text(payload.get("originalTransactionId"), "INVALID_ORIGINAL_TRANSACTION_ID", 128)
        return AuditedTransaction("Sandbox", self.bundle_id, transaction_id, original_id,
            product_id, spec.product_type, quantity, purchase, signed,
            hashlib.sha256(signed_transaction.encode("ascii")).hexdigest(), self.root_sha256)

    def audit_refund_notification(self, signed_notification: str, *, expected_account_token: str):
        return _audit_refund_notice(self, signed_notification, expected_account_token=expected_account_token)

@dataclass(frozen=True)
class AuditedRefundNoticeR459:
    transaction: AuditedTransaction
    notification_uuid: str
    notification_jws_sha256: str
    revocation_date_ms: int
    status: str = field(default="OFFLINE_REFUND_NOTICE_CHECKED_NOT_AUTHORIZATION", init=False)
    grant_authorized: bool = field(default=False, init=False)
    revocation_checked: bool = field(default=False, init=False)


def _strict_signed_envelope(signed: str) -> tuple[dict, dict]:
    if (type(signed) is not str or not 1 <= len(signed) <= 65536
            or not re.fullmatch(r"[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", signed)):
        raise SignedAuditError("MALFORMED_JWS")
    header_part, payload_part, _ = signed.split(".")
    header, payload = _json_segment(header_part), _json_segment(payload_part)
    if header.get("alg") != "ES256" or "crit" in header or "b64" in header:
        raise SignedAuditError("UNSUPPORTED_JWS_HEADER")
    chain = header.get("x5c")
    if type(chain) is not list or len(chain) != 3 or any(type(c) is not str or not 1 <= len(c) <= 16384 for c in chain):
        raise SignedAuditError("INVALID_JWS_CHAIN_HEADER")
    return header, payload


def _audit_refund_notice(self: OfflineTransactionAuditor, signed_notification: str, *, expected_account_token: str) -> AuditedRefundNoticeR459:
    expected = _uuid(expected_account_token)
    _, notification = _strict_signed_envelope(signed_notification)
    try:
        decoded_notice = self._verifier.verify_and_decode_notification(signed_notification)
    except Exception:
        raise SignedAuditError("NOTIFICATION_SIGNATURE_OR_CHAIN_REJECTED") from None
    if (notification.get("notificationType") != "REFUND"
            or decoded_notice.rawNotificationType != "REFUND"
            or decoded_notice.data is None):
        raise SignedAuditError("NOT_A_REFUND_NOTIFICATION")
    notification_uuid = notification.get("notificationUUID")
    try:
        parsed_notification_uuid = UUID(_text(notification_uuid, "INVALID_NOTIFICATION_UUID", 36))
    except (ValueError, TypeError, AttributeError):
        raise SignedAuditError("INVALID_NOTIFICATION_UUID") from None
    if str(parsed_notification_uuid) != notification_uuid.lower() or parsed_notification_uuid.int == 0:
        raise SignedAuditError("INVALID_NOTIFICATION_UUID")
    outer_signed_date = notification.get("signedDate")
    now = self._clock()
    if type(now) is not int or now <= 0 or type(outer_signed_date) is not int or not 0 < outer_signed_date <= now + 300_000:
        raise SignedAuditError("INVALID_NOTIFICATION_DATES")
    data = notification.get("data")
    if type(data) is not dict or data.get("environment") != "Sandbox" or data.get("bundleId") != self.bundle_id:
        raise SignedAuditError("APP_OR_ENVIRONMENT_MISMATCH")
    signed_transaction = data.get("signedTransactionInfo")
    _, payload = _strict_signed_envelope(signed_transaction)
    try:
        decoded_tx = self._verifier.verify_and_decode_signed_transaction(signed_transaction)
    except Exception:
        raise SignedAuditError("REFUND_TRANSACTION_SIGNATURE_OR_CHAIN_REJECTED") from None
    if decoded_tx.environment != Environment.SANDBOX or decoded_tx.bundleId != self.bundle_id:
        raise SignedAuditError("APP_OR_ENVIRONMENT_MISMATCH")
    tx = self._audit_verified_transaction_payload(payload, signed_transaction,
        expected_account_token=expected, allow_revocation=True)
    revocation = payload["revocationDate"]
    if revocation > outer_signed_date:
        raise SignedAuditError("INVALID_NOTIFICATION_DATES")
    return AuditedRefundNoticeR459(tx, str(parsed_notification_uuid),
        hashlib.sha256(signed_notification.encode("ascii")).hexdigest(), revocation)


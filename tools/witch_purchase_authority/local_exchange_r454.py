"""Single-request local QA JSON exchange; never a StoreKit verifier or network service."""
from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
from typing import Any

try:
    from .authority import AuthorityError, PurchaseAuthority
    from .local_delivery_r453 import (
        LocalDeliveryAdapterR453, LocalDeliveryError, LocalDeliveryProfileR453,
        LocalStoreKitEventR453, _canonical, _has_symlink_component,
        _read_input_bytes, _same_file_if_present,
    )
except ImportError:  # pragma: no cover - direct explicit CLI invocation
    from authority import AuthorityError, PurchaseAuthority  # type: ignore
    from local_delivery_r453 import (  # type: ignore
        LocalDeliveryAdapterR453, LocalDeliveryError, LocalDeliveryProfileR453,
        LocalStoreKitEventR453, _canonical, _has_symlink_component,
        _read_input_bytes, _same_file_if_present,
    )

REQUEST_LIMIT = 64 * 1024
RESPONSE_LIMIT = 1024 * 1024
TICKET_PRODUCT_ID = "local.witch.test.ticket"
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_REQUEST_FIELDS = {"schemaVersion", "status", "requestID", "operationID", "profileFingerprint", "event", "count", "testSeed"}


def _strict_object(data: bytes) -> dict[str, Any]:
    def no_duplicates(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise LocalDeliveryError("duplicate JSON object key")
            result[key] = value
        return result
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=no_duplicates, parse_constant=lambda _: (_ for _ in ()).throw(LocalDeliveryError("non-finite JSON number")))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise LocalDeliveryError("request must be valid UTF-8 JSON") from exc
    if not isinstance(value, dict):
        raise LocalDeliveryError("request must be a JSON object")
    return value


def _uuid(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value or value != value.strip() or len(value) > 64:
        raise LocalDeliveryError(f"{label} must be a UUID")
    import uuid
    try:
        parsed = uuid.UUID(value)
    except (ValueError, AttributeError) as exc:
        raise LocalDeliveryError(f"{label} must be a UUID") from exc
    if str(parsed) != value.lower():
        raise LocalDeliveryError(f"{label} must use canonical UUID spelling")
    return str(parsed)


def _request(data: bytes, profile: LocalDeliveryProfileR453, expected_profile_fingerprint: str,
             expected_token: str, expected_account: str) -> tuple[dict[str, Any], str, str, str]:
    if not isinstance(data, bytes) or not 1 <= len(data) <= REQUEST_LIMIT:
        raise LocalDeliveryError("request must be 1..65536 bytes")
    request = _strict_object(data)
    if set(request) != _REQUEST_FIELDS:
        raise LocalDeliveryError("request fields do not match the R454 schema")
    if isinstance(request["schemaVersion"], bool) or request["schemaVersion"] != 1 or not isinstance(request["schemaVersion"], int):
        raise LocalDeliveryError("schemaVersion must be integer 1")
    if request["status"] != "XCODE_LOCAL_QA_REQUEST":
        raise LocalDeliveryError("request must use the explicit local QA status")
    request_id = _uuid(request["requestID"], "requestID")
    operation_id = _uuid(request["operationID"], "operationID")
    if not isinstance(expected_profile_fingerprint, str) or not _HEX64.fullmatch(expected_profile_fingerprint):
        raise LocalDeliveryError("expected profile fingerprint must be lowercase SHA-256")
    if profile.profile_fingerprint != expected_profile_fingerprint or request["profileFingerprint"] != expected_profile_fingerprint:
        raise LocalDeliveryError("request/profile fingerprint does not match the pinned profile")
    if not isinstance(expected_token, str) or not expected_token or not isinstance(expected_account, str) or not expected_account:
        raise LocalDeliveryError("expected local QA identity is unavailable")
    event = LocalStoreKitEventR453.from_mapping(request["event"], profile)
    if event.event_kind != "purchase" or event.product_id != TICKET_PRODUCT_ID or event.quantity != 1:
        raise LocalDeliveryError("R454 accepts one explicit mock consumable ticket event only")
    if event.app_account_token != expected_token or event.test_account_id != expected_account:
        raise LocalDeliveryError("request identity does not match the pinned local QA identity")
    spec = profile.product_specs.get(TICKET_PRODUCT_ID)
    if spec is None or spec.tickets_per_unit != 1:
        raise LocalDeliveryError("pinned profile lacks the R454 one-ticket test product")
    if isinstance(request["count"], bool) or request["count"] != 1 or not isinstance(request["count"], int):
        raise LocalDeliveryError("count must be integer 1")
    seed = request["testSeed"]
    if isinstance(seed, bool) or not isinstance(seed, int) or not 0 <= seed <= 2**63 - 1:
        raise LocalDeliveryError("testSeed must be an integer in the supported range")
    if seed != 453:
        raise LocalDeliveryError("testSeed must equal the pinned R454 seed 453")
    return request, request_id, operation_id, hashlib.sha256(data).hexdigest()


def _response(status: str, request_id: str | None, operation_id: str | None,
              request_sha: str, *, receipt: dict[str, Any] | None = None,
              error: str | None = None) -> bytes:
    response: dict[str, Any] = {
        "schemaVersion": 1, "status": status, "requestID": request_id,
        "operationID": operation_id, "requestSHA256": request_sha,
    }
    if receipt is not None:
        exact = _canonical(receipt) + b"\n"
        response["receiptBase64"] = base64.b64encode(exact).decode("ascii")
        response["receiptSHA256"] = hashlib.sha256(exact).hexdigest()
    else:
        response["error"] = error or "request rejected"
    encoded = _canonical(response) + b"\n"
    if len(encoded) > RESPONSE_LIMIT:
        raise LocalDeliveryError("response exceeds the 1 MiB limit")
    return encoded


def _safe_error_code(exc: BaseException) -> str:
    if isinstance(exc, LocalDeliveryError):
        return "LOCAL_DELIVERY_REJECTED"
    if isinstance(exc, AuthorityError):
        return "AUTHORITY_REJECTED"
    if isinstance(exc, sqlite3.Error):
        return "DATABASE_ERROR"
    if isinstance(exc, OSError):
        return "LOCAL_IO_ERROR"
    return "REQUEST_INVALID"


def process_request(request_bytes: bytes, *, profile_mapping: Any,
                    expected_profile_fingerprint: str, authority: PurchaseAuthority,
                    delivery_cache_path: str | Path, expected_token: str,
                    expected_account: str) -> bytes:
    """Validate identity before adapter/cache mutation; return one bounded JSON response."""
    request_sha = hashlib.sha256(request_bytes).hexdigest() if isinstance(request_bytes, bytes) else hashlib.sha256(b"").hexdigest()
    request_id = operation_id = None
    try:
        profile = LocalDeliveryProfileR453.from_mapping(profile_mapping)
        request, request_id, operation_id, request_sha = _request(
            request_bytes, profile, expected_profile_fingerprint, expected_token, expected_account)
        if not authority.allow_test_mock_verifier or authority.bundle_id != profile.bundle_id:
            raise LocalDeliveryError("authority is not the explicitly enabled matching local QA authority")
        adapter = LocalDeliveryAdapterR453(authority, profile, delivery_cache_path)
        event = request["event"]
        adapter.grant_ticket_only(event, test_seed=request["testSeed"])
        receipt = adapter.draw_from_ticket_balance(
            event, operation_id=operation_id, count=1, test_seed=request["testSeed"])
        # Keep the embedded R453 receipt byte-for-byte schema-compatible; request
        # correlation is carried only by the outer R454 response envelope.
        return _response("DELIVERY", request_id, operation_id, request_sha, receipt=receipt)
    except (AuthorityError, OSError, ValueError, TypeError, KeyError, sqlite3.Error) as exc:
        return _response("REJECTED", request_id, operation_id, request_sha, error=_safe_error_code(exc))


def _safe_cli_paths(request_path: Path, profile_path: Path, authority_path: Path,
                    cache_path: Path, output_path: Path) -> tuple[bytes, bytes]:
    paths = [(request_path, "request"), (profile_path, "profile"), (authority_path, "authority")]
    for path, label in paths:
        if _has_symlink_component(path) or not path.is_file():
            raise LocalDeliveryError(f"{label} must be a regular file")
    for path, label in ((cache_path, "cache"), (output_path, "output")):
        if any(parent.is_symlink() for parent in (path, *path.parents)):
            raise LocalDeliveryError(f"{label} path cannot include symlinks")
    if not output_path.parent.is_dir() or output_path.parent.resolve(strict=True) != output_path.parent:
        raise LocalDeliveryError("output parent must be an existing canonical directory")
    if output_path.exists() or output_path.is_symlink():
        raise LocalDeliveryError("output already exists")
    if _same_file_if_present(authority_path, cache_path):
        raise LocalDeliveryError("cache cannot alias authority database")
    if any(_same_file_if_present(cache_path, source) for source in (request_path, profile_path)):
        raise LocalDeliveryError("cache cannot alias request or profile")
    if output_path.absolute() == cache_path.absolute():
        raise LocalDeliveryError("output and cache paths must differ")
    if any(_same_file_if_present(output_path, source) for source in (request_path, profile_path, authority_path, cache_path)):
        raise LocalDeliveryError("output cannot alias an input or database")
    if request_path.stat().st_size > REQUEST_LIMIT:
        raise LocalDeliveryError("request exceeds 64 KiB")
    if profile_path.stat().st_size > RESPONSE_LIMIT:
        raise LocalDeliveryError("profile exceeds 1 MiB")
    request_bytes = _read_input_bytes(request_path)
    profile_bytes = _read_input_bytes(profile_path)
    if len(request_bytes) > REQUEST_LIMIT:
        raise LocalDeliveryError("request exceeds 64 KiB")
    if len(profile_bytes) > RESPONSE_LIMIT:
        raise LocalDeliveryError("profile exceeds 1 MiB")
    return request_bytes, profile_bytes


def main(argv: list[str] | None = None) -> int:
    import argparse
    parser = argparse.ArgumentParser(description="One-shot local R454 QA JSON exchange; no network or Apple verification")
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--profile-sha256", required=True)
    parser.add_argument("--authority-db", type=Path, required=True)
    parser.add_argument("--cache-db", type=Path, required=True)
    parser.add_argument("--expected-account", required=True)
    parser.add_argument("--expected-token", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        request_bytes, profile_bytes = _safe_cli_paths(args.request, args.profile, args.authority_db,
                                                        args.cache_db, args.output)
        if not _HEX64.fullmatch(args.profile_sha256) or hashlib.sha256(profile_bytes).hexdigest() != args.profile_sha256:
            raise LocalDeliveryError("profile file-byte SHA-256 mismatch")
        profile_mapping = _strict_object(profile_bytes)
        profile = LocalDeliveryProfileR453.from_mapping(profile_mapping)
        # Validate the entire request before constructing PurchaseAuthority, which may initialize storage.
        _request(request_bytes, profile, profile.profile_fingerprint, args.expected_token, args.expected_account)
        specs = profile.product_specs
        authority = PurchaseAuthority(args.authority_db, bundle_id=profile.bundle_id,
                                     product_specs=specs, summon_pool=profile.summon_pool,
                                     allow_test_mock_verifier=True)
        response = process_request(request_bytes, profile_mapping=profile_mapping,
            expected_profile_fingerprint=profile.profile_fingerprint, authority=authority,
            delivery_cache_path=args.cache_db, expected_token=args.expected_token,
            expected_account=args.expected_account)
        fd = os.open(args.output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(response)
        return 0 if json.loads(response)["status"] == "DELIVERY" else 2
    except (AuthorityError, OSError, ValueError, TypeError, KeyError, sqlite3.Error, LocalDeliveryError) as exc:
        print(json.dumps({"status": "REJECTED", "error": _safe_error_code(exc)}, separators=(",", ":")))
        return 2


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())

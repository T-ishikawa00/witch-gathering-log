"""Explicit local Sandbox-to-ledger rehearsal; never production authorization."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from types import SimpleNamespace
from typing import Mapping
import os

from authority_r459 import ProductSpec, PurchaseAuthority
from signed_transaction_audit_r459 import AuditProduct, OfflineTransactionAuditor


@dataclass(frozen=True)
class SandboxLedgerRehearsalR459:
    authority: PurchaseAuthority
    auditor: OfflineTransactionAuditor
    database_path: Path
    bundle_id: str
    account_bindings: Mapping[str, str]
    status: str = "LOCAL_SANDBOX_REHEARSAL_NOT_AUTHORIZED_FOR_PRODUCTION"

    @classmethod
    def create(
        cls, *, database_directory: Path, bundle_id: str,
        product_specs: Mapping[str, ProductSpec], audit_products: Mapping[str, AuditProduct],
        summon_pool: tuple[str, ...], root_certificates: tuple[bytes, ...],
        fixture_account_bindings: Mapping[str, str], clock=None, clock_ms=None,
    ) -> "SandboxLedgerRehearsalR459":
        """Create a new, empty, explicitly named rehearsal DB; existing paths reject."""
        root = Path(database_directory)
        if root.is_symlink() or root.exists() or root.name != "r459-sandbox-rehearsal":
            raise ValueError("R459 requires a new r459-sandbox-rehearsal directory")
        if not fixture_account_bindings:
            raise ValueError("explicit fixture account bindings are required")
        if set(product_specs) != set(audit_products):
            raise ValueError("ledger and signature-verifier product policies must match exactly")
        for key, spec in product_specs.items():
            audit = audit_products[key]
            if type(audit) is not AuditProduct or audit.max_quantity != spec.max_quantity:
                raise ValueError("transaction quantity policy must match the rehearsal ledger")
        root.mkdir(mode=0o700, parents=False, exist_ok=False)
        marker = root / "R459_LOCAL_REHEARSAL_ONLY"
        fd = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write("NOT_AUTHORIZED_FOR_PRODUCTION\n")
            stream.flush()
            os.fsync(stream.fileno())
        db_path = root / "authority.sqlite"
        authority = PurchaseAuthority(db_path, bundle_id=bundle_id, product_specs=product_specs,
            summon_pool=summon_pool, allow_test_mock_verifier=False,
            **({"clock": clock} if clock is not None else {}))
        auditor = OfflineTransactionAuditor(root_certificates=root_certificates, bundle_id=bundle_id,
            products=audit_products, environment="Sandbox", clock_ms=clock_ms)
        for account_id, token in fixture_account_bindings.items():
            if not account_id or not token:
                raise ValueError("fixture account binding values must be nonempty")
            authority.register_account(account_id, token)
        return cls(authority, auditor, db_path, bundle_id, dict(fixture_account_bindings))

    def purchase(self, *, account_id: str, signed_transaction_jws: str, operation_id: str,
                 draw_count: int, test_seed: int, fail_at: str | None = None) -> dict:
        """Verify a signed Sandbox transaction, then atomically use the existing ledger path."""
        token = self.account_bindings.get(account_id)
        if token is None:
            raise ValueError("account is not in the explicit rehearsal fixture binding")
        audited = self.auditor.audit(signed_transaction_jws, expected_account_token=token)
        if audited.environment != "Sandbox" or audited.bundle_id != self.bundle_id:
            raise ValueError("verified transaction is outside this Sandbox rehearsal")
        if audited.grant_authorized or audited.revocation_checked or audited.status != "OFFLINE_CHAIN_CHECKED_NOT_AUTHORIZATION":
            raise ValueError("auditor result is not the expected non-authorizing audit result")
        verified = SimpleNamespace(
            environment=audited.environment, bundle_id=audited.bundle_id,
            transaction_id=audited.transaction_id, original_transaction_id=audited.original_transaction_id,
            product_id=audited.product_id, quantity=audited.quantity, app_account_token=token,
            purchase_time=audited.purchase_date_ms // 1000,
        )
        receipt = self.authority._purchase_and_draw_verified(
            account_id, operation_id, verified, draw_count, test_seed=test_seed, fail_at=fail_at,
            verification_kind="APPLE_SANDBOX_SIGNATURE_VERIFIED_NOT_AUTHORIZED",
            allowed_environment="Sandbox")
        return {"status": self.status, "auditStatus": audited.status,
                "grantAuthorized": False, "revocationChecked": False,
                "receipt": receipt}

    def refund(self, *, account_id: str, signed_notification_jws: str,
               fail_at: str | None = None) -> dict:
        """Verify a signed Sandbox REFUND notification and atomically apply its transaction identity."""
        token = self.account_bindings.get(account_id)
        if token is None:
            raise ValueError("account is not in the explicit rehearsal fixture binding")
        notice = self.auditor.audit_refund_notification(signed_notification_jws,
            expected_account_token=token)
        if notice.grant_authorized or notice.revocation_checked:
            raise ValueError("refund audit cannot claim production authorization or online revocation lookup")
        tx = notice.transaction
        verified = SimpleNamespace(
            environment=tx.environment, bundle_id=tx.bundle_id, transaction_id=tx.transaction_id,
            original_transaction_id=tx.original_transaction_id, product_id=tx.product_id,
            quantity=tx.quantity, app_account_token=token, purchase_time=tx.purchase_date_ms // 1000,
        )
        result = self.authority._refund_verified(account_id, verified, fail_at=fail_at,
            verification_kind="APPLE_SANDBOX_REFUND_SIGNATURE_VERIFIED_NOT_AUTHORIZED",
            allowed_environment="Sandbox")
        return {"status": self.status, "auditStatus": notice.status,
                "grantAuthorized": False, "onlineRevocationChecked": False,
                "notificationUUID": notice.notification_uuid, "result": result}

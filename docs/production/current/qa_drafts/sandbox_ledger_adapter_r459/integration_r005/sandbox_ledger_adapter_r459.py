"""Factory-only local Sandbox rehearsal adapter; explicitly non-authorizing."""
from pathlib import Path
from typing import Mapping
import os

from authority_r459 import (
    ProductSpec, PurchaseAuthority, SandboxVerifiedPurchaseR459,
    SandboxVerifiedNotificationR459, _SANDBOX_FACTORY_KEY,
)
from signed_transaction_audit_r459 import AuditProduct, OfflineTransactionAuditor

_FACTORY_KEY = object()

class SandboxLedgerRehearsalR459:
    __slots__ = ("authority", "auditor", "database_path", "bundle_id", "account_bindings", "status", "_capability")

    def __init__(self, *, authority, auditor, database_path, bundle_id, account_bindings, capability, _factory_key):
        if _factory_key is not _FACTORY_KEY:
            raise TypeError("use SandboxLedgerRehearsalR459.create with a new isolated directory")
        self.authority, self.auditor = authority, auditor
        self.database_path, self.bundle_id = Path(database_path), bundle_id
        self.account_bindings, self._capability = dict(account_bindings), capability
        self.status = "NOT_AUTHORIZED_FOR_PRODUCTION"

    @classmethod
    def create(cls, *, database_directory: Path, bundle_id: str,
               product_specs: Mapping[str, ProductSpec], audit_products: Mapping[str, AuditProduct],
               summon_pool: tuple[str, ...], root_certificates: tuple[bytes, ...],
               fixture_account_bindings: Mapping[str, str], clock=None, clock_ms=None):
        requested = Path(database_directory).expanduser()
        if requested.is_symlink() or requested.name != "r459-sandbox-rehearsal":
            raise ValueError("R459 requires a new r459-sandbox-rehearsal directory")
        # Canonicalize the existing parent (not the not-yet-created child) so
        # macOS /var -> /private/var aliases cannot create two logical roots.
        parent = requested.parent.resolve(strict=True)
        root = parent / requested.name
        if root.exists() or root.is_symlink():
            raise ValueError("R459 requires a new r459-sandbox-rehearsal directory")
        if not fixture_account_bindings or set(product_specs) != set(audit_products):
            raise ValueError("explicit account bindings and matching product policies are required")
        for key, spec in product_specs.items():
            audit = audit_products[key]
            if type(audit) is not AuditProduct or audit.max_quantity != spec.max_quantity:
                raise ValueError("transaction quantity policy must match the rehearsal ledger")
        if any(not isinstance(a, str) or not a or not isinstance(t, str) or not t for a,t in fixture_account_bindings.items()):
            raise ValueError("fixture account binding values must be nonempty")
        root.mkdir(mode=0o700, parents=False, exist_ok=False)
        marker = root / "R459_LOCAL_REHEARSAL_ONLY"
        fd = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write("NOT_AUTHORIZED_FOR_PRODUCTION\n"); stream.flush(); os.fsync(stream.fileno())
        db_path = root / "authority.sqlite"
        authority = PurchaseAuthority(db_path, bundle_id=bundle_id, product_specs=product_specs,
            summon_pool=summon_pool, allow_test_mock_verifier=False,
            **({"clock": clock} if clock is not None else {}))
        capability = authority._bind_sandbox_rehearsal(_SANDBOX_FACTORY_KEY)
        auditor = OfflineTransactionAuditor(root_certificates=root_certificates, bundle_id=bundle_id,
            products=audit_products, environment="Sandbox", clock_ms=clock_ms)
        for account_id, token in fixture_account_bindings.items():
            authority.register_account(account_id, token)
        return cls(authority=authority, auditor=auditor, database_path=db_path, bundle_id=bundle_id,
                   account_bindings=fixture_account_bindings, capability=capability, _factory_key=_FACTORY_KEY)

    def purchase(self, *, account_id: str, signed_transaction_jws: str, operation_id: str,
                 draw_count: int, test_seed: int, fail_at: str | None = None) -> dict:
        token = self.account_bindings.get(account_id)
        if token is None: raise ValueError("account is not in the explicit rehearsal fixture binding")
        audited = self.auditor.audit(signed_transaction_jws, expected_account_token=token)
        if audited.environment != "Sandbox" or audited.bundle_id != self.bundle_id or audited.grant_authorized or audited.revocation_checked or audited.status != "OFFLINE_CHAIN_CHECKED_NOT_AUTHORIZATION":
            raise ValueError("audit result is outside the non-authorizing Sandbox rehearsal")
        verified = SandboxVerifiedPurchaseR459(audited.environment, audited.bundle_id, audited.transaction_id,
            audited.original_transaction_id, audited.product_id, audited.quantity, token,
            audited.purchase_date_ms // 1000, self._capability, _factory_key=_SANDBOX_FACTORY_KEY)
        receipt = self.authority._purchase_and_draw_sandbox(account_id, operation_id, verified, draw_count,
            test_seed=test_seed, fail_at=fail_at)
        return {"status": self.status, "auditStatus": audited.status, "grantAuthorized": False,
                "revocationChecked": False, "receipt": receipt}

    def refund(self, *, account_id: str, signed_notification_jws: str, fail_at: str | None = None) -> dict:
        token = self.account_bindings.get(account_id)
        if token is None: raise ValueError("account is not in the explicit rehearsal fixture binding")
        notice = self.auditor.audit_refund_notification(signed_notification_jws, expected_account_token=token)
        if notice.grant_authorized or notice.revocation_checked:
            raise ValueError("offline refund audit cannot authorize or claim online revocation checking")
        tx = notice.transaction
        delivery = SandboxVerifiedNotificationR459(notice.notification_uuid, "REFUND", "Sandbox", tx.bundle_id,
            tx.transaction_id, tx.original_transaction_id, tx.product_id, tx.quantity, token,
            tx.purchase_date_ms // 1000, self._capability, _factory_key=_SANDBOX_FACTORY_KEY)
        result = self.authority.apply_notification_sandbox(account_id, delivery, fail_at=fail_at)
        return {"status": self.status, "auditStatus": notice.status, "grantAuthorized": False,
                "onlineRevocationChecked": False, "notificationUUID": notice.notification_uuid, "result": result}

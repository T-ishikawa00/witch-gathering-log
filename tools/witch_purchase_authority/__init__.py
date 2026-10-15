"""Explicitly local/test-only paid purchase authority reference."""
from .authority import (
    AuthorityError, CandidateDrawEngine, DrawReceipt, DuplicateTransaction,
    IdempotencyCollision, InjectedFailure, InsufficientPaidTickets,
    InvalidPurchase, MockNotificationDelivery, MockVerifiedPurchase, ProductSpec, PurchaseAlreadyRefunded, PurchaseAuthority,
    VerificationUnavailable,
)

__all__ = [
    "AuthorityError", "CandidateDrawEngine", "DrawReceipt", "DuplicateTransaction",
    "IdempotencyCollision", "InjectedFailure", "InsufficientPaidTickets",
    "InvalidPurchase", "MockNotificationDelivery", "MockVerifiedPurchase", "ProductSpec", "PurchaseAlreadyRefunded", "PurchaseAuthority",
    "VerificationUnavailable",
]

# R459 integration R005 independent diff review

Reviewed `MANIFEST_R005.json` SHA-256 `b7bd4e75ebae14fde448c0de0e183941937460b8e1f2fb0934122f9947e6d905` and `ROOT_DELTA_R005.diff` SHA-256 `b61a5c33445bde39ce2628adebdbdfadc458305f97e5a0093f3e123b0baf594c`. No tests or runtime actions were performed.

The two API guards are appropriately placed: `purchase_and_draw_mock()` and `refund_mock()` now require the exact `MockVerifiedPurchase` type and the enabled test-mock flag before delegating. This closes the remaining naming-based ambiguity where a capability-bound Sandbox record might be passed to a mock-only method. The dedicated Sandbox adapter continues to use its typed, capability-bound routes.

The added signed-flow test checks rollback after a draw write, retry/replay equality, and refund debt after one ticket has been spent: with three tickets granted, one spent, and two remaining, it expects balance 0 and debt 1 after refund. The second test proves the mock-named APIs reject a Sandbox record and leave purchase count unchanged. The arithmetic and code paths are consistent with the existing ledger implementation.

No actionable defect was found in this small delta. The manifest records the two new tests as not yet run; this review does not upgrade the reported R004 test pass or establish runtime/Apple-production authorization.

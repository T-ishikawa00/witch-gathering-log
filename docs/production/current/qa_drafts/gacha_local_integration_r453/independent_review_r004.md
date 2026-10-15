# R453 Core importer and large-text comparison review

Read-only source review on 2026-10-15. No build, test, Simulator, save, source, or provider mutation was performed.

## R453 finding

No direct defect was found in the candidate importer’s local transaction mechanics. `LocalPurchaseDeliveryQAImporterR453.swift` (SHA-256 `6fcea9aa68a4e2b6470c244ee27b2a0169723897696d866a86b0b78d9423bb93`) gates construction to explicit DEBUG test mode and rejects Release use (lines 16–25). It caps and hashes input bytes, checks an exact JSON shape, item/provenance joins, unique gear IDs, ordered pity transitions, and account/bundle/token pins (lines 31–49, 76–151). Gear append and pity update occur together in one `SaveRepository.transact` call. SaveRepository checks an existing operation receipt and its request fingerprint before revision comparison, so a same-operation replay is idempotent and a conflicting payload is rejected (SaveRepository.swift:524–545). The importer refreshes the provider on each bounded CAS retry and rejects a mismatched pre-draw pity snapshot (importer:34–64).

One material boundary remains: provider validation and local save commit are two separate systems. A refund/tombstone may arrive after `currentDelivery()` has returned but before the local save transaction commits; this importer cannot atomically serialize those events. The R453 contract already states these databases are not one transaction and that revocation does not retract previously imported gear. Treat current-provider revalidation as a bounded mock-QA check, not a production refund-safe delivery guarantee. Production entitlement remains unauthenticated and unavailable by design; no Apple signature or live StoreKit path is established here.

A smaller input-validation gap: `pity(_:)` accepts any string as `targetTemplateID` (lines 155–162), although the ordinary summon command later rejects a target outside the selected pool (GameEngine.swift:1203–1208). A malformed but correctly self-fingerprinted fixture can therefore persist an unusable target. This is a P2 hardening issue for fixture integrity, not an exploit boundary: the type is explicitly test-only and the provider/profile are trusted QA inputs. Minimal follow-up is to validate a non-null target against the pinned profile summon pool before commit, and add a no-save-mutation rejection case. Do not label this as production payment authorization.

## XXXL comparison control

Current `InventoryView` places results in a `LazyVStack` inside the surrounding scroll-based content and emits a per-gear “比較” button within every row (`WorkflowViews.swift:306, 360–379`). At accessibility sizes it changes the actor and quality pickers to menu controls, and the row actions to a vertical stack (`274–294, 367–374`). No source-level gate disables comparison based on size; the ordinary comparison action remains present.

Reachability at XXXL is still **unverified**, rather than a demonstrated code defect. R417 failed before its swipe because the expected count string differed from the actual two-line localized value. R430’s retained frames show the list did move and a later gear title entered the viewport, but no fully visible, hittable “比較” button was captured. That is evidence of a test-measurement gap, not proof that the product control is unreachable. A valid acceptance needs one actual swipe on the unique hittable inventory scroll view and a fully visible comparison control after scrolling; this review did not run that test.

## Scope

The importer and current inventory source are dirty-worktree files, not part of fixed commit `83f5be4a86f62de0e017533a6a005415e1156acb6`. The R453 test owner’s results were not independently rerun or promoted. This review does not establish StoreKit completion, release readiness, or XXXL comparison acceptance.

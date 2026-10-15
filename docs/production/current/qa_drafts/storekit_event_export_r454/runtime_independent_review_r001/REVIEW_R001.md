# R454 scoped runtime independent review

## Verdict

No P1 integrity defect found within the explicitly local-Xcode / mock-authority QA scope. `RUNTIME_RESULT_R001.json` reports `PASS_SCOPED_LOCAL_XCODE_TO_MOCK_AUTHORITY`; its SHA-256 is `ec784e713b85b1cdaef76a6ee1ab73ef703074ac4e8c34d7878ae5e80afce10a`. This is bounded local QA evidence, not production entitlement, StoreKit server authority, or real-money acceptance.

## Cross-checks

- R004 build receipt `debug_BUILD_PASS.json` SHA-256 `733b12f9e71b651533be74a351047f9154c1c971232f60915df7cf6b07a6a679` binds executable SHA `d4629570f955590affebb909f95f66744eb3dae9a6170eecc23ddccbee824539`, 238 source files and 1,922 resources. The built bundle ID is `local.witch.autonomous.r1.storekit.r454`, minimum OS 17.0, and `SKIncludeConsumableInAppPurchaseHistory=true`; R004 runtime gate requires iOS 18+ and this plist value.
- Installed origin R004 SHA-256 `cdc41ac4e074b0cc209bbf49dd0e1f4e24734b46ce1986005bb0f8fe3de817de` agrees with the runtime result's executable and final save pins.
- The retained purchase capture is revision 2, StoreKit QA record transaction `2`, one local QA ticket. The authority request carries transaction/original ID `2`, product `local.witch.test.ticket`, consumable quantity 1, Xcode environment, matching bundle, token and operation ID. Both successful host responses validate their request/response hashes and contain the same receipt bytes/fingerprint: operation `be488897-f5f2-5202-119c-39fca441b223`, fingerprint `03a8b59106de64eda937f13a6e32887b090b9c2f898b0dc897be167b0213abb7`.
- The accepted receipt draws one ticket and reports zero remaining, producing one gear instance `aa47bc4a-ed95-5fe7-b2e9-121a5c2db908` (`EQ_S_01`, Q1) and pity 0→1. Save goes from revision 2 to 3 exactly once. Gear receipt and duplicate replay saves are byte-identical at SHA `63936957bb1ac8c592ee485b17591d294856652c04c06afc2d1766bc70a38034`.
- The mock host refund records debt +1 and rejects the subsequent request. Gear remains in the local save; refund clawback is 0. Restore does not append a consumable or change save bytes. Cold relaunch preserves the same revision-3 primary save exactly. The three request/response files copied after the data-container remount match the original hashes recorded in the exchange rows.
- Runtime closes at 1,014.91/1,200 seconds, 6/6 screenshots, 2,258,731/30,000,000 evidence bytes. It records the normal R445 save and protected PBX unchanged, and app stopped.

## Limits and minor boundary

The app's local `storekit_qa_ticket` field remains 1 after the host draw even though the host draw receipt says one ticket drawn and zero remaining. The importer intentionally leaves client currency untouched; this is a split local QA purchase record and mock host ledger, not proof of end-to-end in-game paid-ticket spending. Keep that distinction explicit. The host refund is simulated and does not claw back previously delivered gear. The runtime result also correctly says non-consumable restore coverage is inherited from R377 rather than freshly retested here.

No source, app, Simulator, or save operation was performed by this review.

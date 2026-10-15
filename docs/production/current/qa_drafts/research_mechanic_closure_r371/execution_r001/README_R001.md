# R371 isolated Core runner

Preparation only. No build or XCTest has been started. Root may review and invoke the one-shot runner using the exact input-manifest and runner SHA pins below.

The runner stages the exact R368 successful package rows from the pinned R368 manifest: 54 base/overridden Core sources, one required R355 candidate helper, and two resources. It adds the R371 test file. It reuses the prior R359 membrane pass receipt read-only. Exactly 15 test identifiers are required in one `swift test` invocation; 14 new unique event traces must be produced and validate as MECHANISM_ONLY with an actual PASS HP-ledger verdict.

Limits are fixed at 120 seconds wall time, 350,000,000 allocated bytes, 12,000,000,000 free-byte floor, one invocation, and at most two jobs. No Simulator, save access, reward mutation, live source edit, retry, or cleanup is performed. Any failure is retained as incomplete evidence.

Runner SHA-256: `ba4ff2f8cb73569e4e28e721cc7597b84c9424c5ea01577068feadde5849f70a`
Input manifest SHA-256: `4718ab0a9e43fca8c4707847f5e0587126aa746071e8fd431d80bb942c4bcc93`
Candidate R002 manifest SHA-256: `1f0c1bf80831bcce532a36a0a677d8051dbc62e3d3d8b9fa6c6f81891ab89d78`

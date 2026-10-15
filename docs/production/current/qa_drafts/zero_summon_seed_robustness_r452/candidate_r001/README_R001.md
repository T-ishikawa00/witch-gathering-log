# R452 two-seed zero-summon follow-up

Prepared, not executed. This adds two independent virtual 30-day free_no_ad Core cases using seeds 100069 and 200071. It does not rerun R448 seed 100049, modify R448 files, change the simulated schedule or economic policy, touch a live save, or launch an app.

The XCTest body is copied from R448 candidate R002. Its only intended differences are the R452 labels/output directories, the exact two-seed allowlist, and a distinct deterministic operation-ID namespace. It retains the first-craft R179 route, actual Core dispatches, challenge/campaign/research goals, gear-provenance joins, and assertions for zero free/paid summons and synthetic grants. The candidate-only economic profile is still unapproved; this is not human-play or release evidence.

The runner stages a fresh package and scratch directory under one exclusive R452 batch output. The first selected XCTest invocation builds and runs seed 100069. The second uses swift test --skip-build against the same staged package and compiled scratch output for seed 200071. Each gets a distinct preregistered run ID, case receipt, log, report directory, and origin-join sidecar; one aggregate RUN.json links both. It requires exactly the two expected case events and parses each exact Test Case passed-duration line, avoiding the old summary-regex problem with the 0 unexpected suffix.

Caps: one build invocation; 600 seconds total wall time; each XCTest case at most 90 seconds; 500 MB allocated compiler scratch; 60 MB allocated total evidence; 12 GB free-space floor; two jobs; one attempt per seed. Any incomplete process, missing report, identity/source drift, unclassified gear UUID, or limit breach retains evidence and is not a pass. No test/build command has been run for R452.

Runtime binding is to the actual R446 identity on the R445 Release install. R447 is a compile-only iPhoneOS artifact for the same frozen R445 source-map SHA; the candidate does not claim a launched R447 identity.

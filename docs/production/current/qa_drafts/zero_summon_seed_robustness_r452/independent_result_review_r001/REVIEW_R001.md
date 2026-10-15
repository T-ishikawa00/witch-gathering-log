# R452 independent result review

R452 completed two independent 30-day Core cases for seeds 100069 and 200071. Each exact selected test ran once and passed: one XCTest method, zero failures, zero skips. The cases used the same runtime profile/configuration and app identity; their action journals show one `RC_EQ_F_01` craft and 11 evolution operations each, alongside 30 campaign wins, 15 challenge wins, five research completions, and zero defeats. Summons and synthetic grants were zero in both reports.

The 96 `naturalGearAcquisitionRecords` in each final report are a bounded retained ledger. Across 30 daily snapshots, the natural acquisition UUID union is 1,440 per case and matches `GEAR_ORIGIN_JOIN_R002.naturalIDs`. Those counts describe different windows and should not be conflated.

There is one accounting mismatch: each day-30 owned-gear array contains 1,445 UUIDs, while `GEAR_ORIGIN_JOIN_R002.finalGearIDs` contains 1,444. The omitted ID is `036d0113-4efe-54af-8b7d-de645b956f58` (natural `EQ_FEET_02`) in both seeds. The full final-owned UUID join therefore needs clarification. The origin groups themselves contain 4 starter, 1 crafted, and 1,440 natural UUIDs, with zero unclassified IDs.

The sealed run reports its source/protected inputs unchanged, 119.389 seconds total, one compile, scratch below 500 MB, evidence below 60 MB, and free space above the 12 GB floor. The receipt lists no owned processes; a separate point-in-time process-name check found no Swift/XCTest process. The original R448 incomplete run remains separate and unchanged.

This closes only a two-seed scripted virtual Core sample. It does not establish player-paced UI, game balance, StoreKit behavior, production readiness, or formal adoption.

Evidence hashes: `RUN.json` SHA-256 `979cfd6fd62bb75ae14e79dae9a8129d11f182a8c7475630aa22cc0b14358845`; root execution seal SHA-256 `5d878bda0d5922b4f20d37a95c2e07b39183539194a9a79368224d478cd55704`.

# R376/R377 item provenance and R374 partial-result review

Read-only join of selected UUIDs against the R368 saved cohort, daily item snapshots, natural-acquisition records, and the test setup.

R368 candidate manifest: `a4d38d7eee4ff40aca49f0b8a0675fcb293874eb015e871a8934d147fd7c00f4`; report: `23266207d0a393a7782c6ad827e2cf771cae6879040f014223fe096efbb4d215`; final cohort save: `067c4e86733fe07eb5457381a30d140b285fbd2685ab18e5667f47577c74e655`. The test setup starts with `makeNewSnapshot()`, asserts exactly four starter gear instances, and sets only fresh-save first-craft eligibility. The free/no-ad 30-day simulation records 155 free mock summons, zero paid draws, 96 natural-acquisition records, and no synthetic ticket grants. It is not an ordinary-play accessibility result.

## Compared UUIDs

- `BC499DA8-3B80-5536-BAFB-5143888B392C` — R376 barrier control, EQ_W_01 Q0; natural UUID record: day 1, roll 4, R01, EQ_W_01 Q0, op 36810000-0001-4001-8000-000000000005.
- `6CA40746-2A06-4374-A92D-F321927D48BE` — R376 poison candidate, EQ_W_P1 Q0; no natural UUID record; first daily inventory appearance day 1; same-day free-summon template matches at ops 36810000-0001-4001-8000-000000000019, 36810000-0001-4001-8000-00000000001a. Exact UUID-to-draw join is unavailable..
- `68C84620-D911-48E4-983C-15E4EF8F202E` — R377 barrier candidate, EQ_W_G2 Q0; no natural UUID record; first daily inventory appearance day 2; same-day free-summon template matches at ops 36810000-0001-4001-8000-00000000002f. Exact UUID-to-draw join is unavailable..
- `31292F32-5F63-5F71-84D9-B69BB4FC303A` — R377 counter candidate, EQ_S_01 Q1; natural UUID record: day 7, roll 326, R03, EQ_S_01 Q1, op 36810000-0001-4001-8000-000000000091.
- `B72CE760-9884-5D4F-8111-8709C8369782` — R377 counter control, EQ_S_01 Q1; natural UUID record: day 2, roll 79, R01, EQ_S_01 Q1, op 36810000-0001-4001-8000-00000000001F.
- `7058F310-16D8-5EE8-8F36-374C8FC1C128` — R377 heal candidate, EQ_AMU_01 Q1; natural UUID record: day 2, roll 90, R01, EQ_AMU_01 Q1, op 36810000-0001-4001-8000-00000000001F.
- `B2DDC107-838F-5593-9E6B-65288DA526DC` — R377 heal control, EQ_AMU_01 Q1; natural UUID record: day 2, roll 55, R01, EQ_AMU_01 Q1, op 36810000-0001-4001-8000-00000000001F.
- `83F34619-8C4D-5FFA-8B4C-98EDDE4C9351` — R377 chase candidate, EQ_F_01 Q1; natural UUID record: day 4, roll 159, R02, EQ_F_01 Q1, op 36810000-0001-4001-8000-00000000004D.
- `F37EC259-FF87-583E-AFA4-D4A32C9D25F3` — R377 chase control, EQ_F_01 Q1; natural UUID record: day 1, roll 7, R01, EQ_F_01 Q1, op 36810000-0001-4001-8000-000000000005.

The saved R368 party also has Witch G2 `2CADE21F-CFAF-4D0A-8D4B-945D4E57B119`, outside R377’s eight paired candidate/control UUID rows; across R376 and R377 there are nine distinct comparison UUIDs. It first appears in the day 8 daily snapshot and has a same-day W_G2 free-summon result; the exact UUID-to-draw relation is not emitted.

## R374 partial run

R374 RUN SHA: `7e294ac6000836bb8334effdce011b1748e96c5ea50ee8c75db46dfb1786cd40`. The run planned 16 cases. At the readback, six were PASS and the seventh was RUNNING. The six completed reports all use seed 100049, each report 30 campaign wins, 15 challenge wins, and five completed research items. Cases include simulated rewarded-ad, free/no-ad, and ticket-grant candidates; these remain test-only treatments. The remaining cases and multi-seed behavior are unverified. The R377 pair ledger also explicitly notes differing natural latent slots, so matched quality/upgrade fields do not isolate latent-effect causality.

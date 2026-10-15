# R448 zero-summon first-craft pilot (prepared, not run)

This candidate adapts the already-passing R368 free/no-ad 30-day seed-100049 progression test to make summons unavailable in the test path. It uses the R445 frozen Core source map, R368's exact first-craft/runtime helper and test-support files, and the R195 product-input table. The only progression-route change is that `summonAvailable` returns zero without dispatching `.mockSummon`; actual campaign/challenge, gather, craft, evolution, enhancement, refinement, daily-claim, save-reopen, and R350 acquisition commands remain Core dispatches.

The test requires 30 campaign victories, 15 challenge victories, five unlocked regions, the real R179 first craft and comparison, at least one evolution/enhancement/refinement, positive natural acquisitions, zero free/paid summon draws, zero synthetic grants, and no unexplained new gear UUID. It does not claim ordinary human-play evidence, adoption of candidate economy policy, or a purchase result.

## Fixed execution contract

- One test: `EconomyCohortProgressionR355Tests/testR448FreeNoAdZeroSummonFirstCraftProgression`.
- Case: `free_no_ad`, 30 virtual days, seed `100049`, attempt `1`.
- Run ID: `44800000-0001-4001-8000-000000000001`.
- One compile; at most 600 seconds total and 90 seconds for the XCTest; at most 500 MB allocated compiler scratch and 50 MB allocated evidence; 12 GB free-space floor; two jobs.
- No Simulator, app launch/install, live-save access, native clock changes, synthetic gear, or grants. Existing R368/R445 evidence is read-only input.
- Failures are retained. The runner has a single-use lock and no automatic retry.

## Root seal required before execution

`runner_r001/INPUT_MANIFEST_R001.json` is deliberately `PREPARED_UNSEALED_ROOT_IDENTITY`. Root must bind the exact current R447-compatible `last_standard_play_identity_r169.json` path, size, and SHA, change the manifest to `PREPARED_NOT_RUN`, and regenerate the invocation pins. Until then, `--execute` must hold. The R445 Release build is a frozen Core source donor, not proof that the current app identity matches it.

The manifest also pins `staged_rows.tmp.json` as a redundant review aid; the runner cross-checks it against the manifest row table. It is not an execution package or separate source of authority.

The runner's default is verify-only. Root-owned invocation after sealing:

```text
python3 <absolute path>/runner_r001/run_r448.py --manifest-sha256 <sealed manifest SHA256> --runner-sha256 <runner SHA256>
```

Add `--execute` only after Root has reviewed the sealed manifest and the R447 closure. This candidate has not been executed, compiled, or run in Simulator.

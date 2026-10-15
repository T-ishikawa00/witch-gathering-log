# R456 builder independent source review

**Disposition: HOLD before invocation.** Read-only inspection only; no runner, build, install, launch, or Simulator action. Candidate and contract remain unsealed templates, and this review does not certify R454 or R456 execution.

## Blocking findings

1. **Final time/output caps are not enforced (P1).** `build_one()` checks aggregate time and allocated output only while `xcodebuild` is still running (lines 219–224). After the second build returns, product inspection and hashing occur (278–305), then the result records `aggregateSeconds` and `allocatedOutputBytes` (306–313) without rejecting values above the 600-second or 2 GB limits. A build that crosses a cap immediately before process exit, or final validation that crosses 600 seconds, can still be written as `BUILD_COMMANDS_PASS`. Require final elapsed/free/output checks immediately before success receipt creation.

2. **Frozen source/project integrity is not revalidated after the build (P1).** Preflight hashes every frozen source and the generated PBX (153–168), but post-build checks only compare the two JSON map objects (300–303). They do not rehash the frozen files, source-map files, generated project PBX, or resource-map files against the originally sealed digests. Mutated source/project files could therefore go undetected while a passing receipt is emitted. Recheck exact sealed file/tree pins after both targets and before success.

3. **Built app resources are not audited (P1).** For each SDK product, the post-build loop checks app directory, Info.plist identity/key, and executable presence/hash (282–299). It never compares either packaged app’s resources to the pinned 1,922-file R454 resource map or checks the two target bundles for equivalent resource contents. The receipt can claim both SDK builds passed while required resources are absent or divergent. Add a read-only per-product resource inventory/hash comparison before `BUILD_COMMANDS_PASS`.

## Other bounded observations

- `build_one()` kills only the spawned process group on timeout/error (225 onward). The outside-compiler scan checks descendant ancestry, not escaped process groups; if an Xcode child deliberately changes process group and outlives `xcodebuild`, cleanup is not proven. No execution evidence exists to say this occurred; validate exact owned-process cleanup in the runner design before relying on a stopped-run guarantee.
- The input template repeats the same `worktree` key (lines 4 and 6). Both values currently match, so normal JSON readers agree, but remove the duplicate when Root creates the sealed manifest.
- Positives: unique R456 bundle ID; Release-only conditions; signing disabled; install/launch disabled; fresh output path required; exact prior-product hashes are rechecked before and after commands; R454 project/resource/source pins are required; R445/R447/R454 preservation intent is explicit in the plan. No broad destructive or cleanup command was found.

The candidate manifest’s 238-source and 1,922-resource values are declarations only until Root seals the exact R454 R004 inputs. No code was changed by this review.

# R465 dual-SDK build candidate

Status: PREPARED_UNSEALED. The candidate was not built, installed, or launched.

The Root-owned freeze completed at `native/qa_source_20261015T080035` with 240 source files and 1,922 resources. This candidate builds that frozen Release configuration for iOS Simulator and unsigned iPhoneOS, with the normal R169/R179/R342/R350/R352/R353 flags, using an isolated output under `native/build/ActiveIntegrationR465/r465-r001`.

Before execution, Root must review and seal `INPUT_MANIFEST_R001.json` and `ROOT_SEAL_R001.template.json`, then rename/write the sealed root seal as `ROOT_SEAL_R001.json`. The input manifest status must be changed to `ROOT_SEALED_READY_TO_BUILD`, and its SHA-256 copied into the root seal. The driver SHA must match both files. No install or launch is part of this candidate.

The R462 prior-products manifest is referenced by path and hash instead of copied into this small input manifest. `R462_PRODUCT_PROTECTION_R001.json` separately records complete file hashes for the successful R462 Simulator and iPhoneOS products and is bound to the exact R462 build receipt. The builder rechecks those trees before and after R465. The empty `prepared_inputs/` directory was created during preparation but is unused; the driver owns a separate, not-yet-created `owned_generated_r001/` directory so it does not collide with it.

Root review commands (verify only; do not run the build until separately authorized):

```sh
python3 -m ast docs/production/current/qa_drafts/native_completion_r465/build_tools_r001/build_r465.py
python3 docs/production/current/qa_drafts/native_completion_r465/build_tools_r001/build_r465.py --verify-only --seal-sha256 <Root-sealed SHA-256>
```

Build bounds are one attempt, at most 600 seconds total, at most 600 seconds per target, at most 2,000,000,000 allocated output bytes, a 2,000,000,000-byte safety reserve, and a 20,000,000,000-byte free-space floor from a 22,000,000,000-byte start. Freeze, resource copying, install, and launch are disabled.

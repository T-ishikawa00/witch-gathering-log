# R454 isolated StoreKit Debug builder candidate

Source preparation only. This candidate is unsealed and has not frozen sources, built, installed, or launched an app. Root must verify the final 238-source map and all protection pins, then seal the exact input and contract hashes before any invocation.

The runner performs one source freeze followed by one Debug build, within a 600-second combined process limit. It caps allocated output at 2 GB plus a 2 GB safety reserve, requires at least 20 GB free before starting, and has install/launch disabled. It protects the prior R445 installed app, its data container and evidence, the prior containers enumerated by the R445 install receipt, and inherited build products. The external-tree receipt references are read-only; the runner refuses changed hashes, symlinks, paths outside the allowlist, or a missing protection pin.

The build uses bundle identifier `local.witch.autonomous.r1.storekit.r454`, `Debug`, and only the `DEBUG` compilation condition. Its generated shared scheme receives the exact R454 test token and profile fingerprint, plus the relative StoreKit configuration identifier `../../StoreKitLocalQA/iOSRunner/AppProbe/Products.storekit`. The StoreKit profile fingerprint is `62ce1ce493d34a7864cd7c7c1a5ee17aebdc8891b2b7b8dcb4eb7e6534c06e99`. The separate Core test output at `native/build/ActiveIntegrationR454/core_r001` is preserved; this candidate uses `native/build/ActiveIntegrationR454/native_r001/<input-key>`.

After Root seals, the planned invocations are one `freeze` and one `build --variant debug` using the exact sealed SHA arguments printed in the seal. The readback normalizer only verifies the retained output and writes a build receipt under this candidate folder. Neither script installs or launches the app.

To later use Xcode's **Run Without Building**, point Xcode at the exact generated project path recorded in `BUILD_STATE_R001.json`, select the `WitchGathering` scheme and the 9A Simulator destination, and set Derived Data to the exact `workspace` path from that same state. Confirm the Debug product exists at `workspace/Build/Products/Debug-iphonesimulator/WitchGathering.app`; do not copy or rebuild it. The generated scheme already carries the sealed StoreKit configuration and launch arguments. Any install or launch remains a separate, explicitly reviewed action.

This candidate does not validate StoreKit behavior, UI, purchase completion, or production commerce. The R453 Core importer tests and mock local delivery are separate evidence; they do not establish a native StoreKit runtime pass.

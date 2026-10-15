# R446 preservation readback: three saved-state additions

The terminal closure remains **INCOMPLETE_RETAINED**. Its only reported unexpected data additions are three small plist files under the new R445 app’s own `Library/Saved Application State` directory. They were absent from the six-path prelaunch data inventory and appeared about 13 seconds after the capture session began, before the first labeled screenshot.

| File | Bytes / mode | Created (JST) | SHA-256 | Plist keys / format |
|---|---:|---|---|---|
| `Library/Saved Application State/local.witch.autonomous.r1.completion.r445.savedState/5F21554A-B60B-4443-AAE5-44EA0F7EE051/data.data` | 1028 / 0o644 | 2026-10-15T04:44:10.758054+09:00 | `a80b0708ebbd025a0c436a68a93e99cb42cad2bec007cf0799639e352382d144` | CanvasRestorationUserActivityTypeKey, CanvasRestorationUserActivityUserInfoDataKey; XML plist |
| `Library/Saved Application State/local.witch.autonomous.r1.completion.r445.savedState/5F21554A-B60B-4443-AAE5-44EA0F7EE051/userInfo.data` | 376 / 0o644 | 2026-10-15T04:44:10.756452+09:00 | `5a58b7333aeab8c082fa451c1084a119f9847f83bc166bdb4308d159b4e820ba` | com.apple.SwiftUI.sceneID; XML plist |
| `Library/Saved Application State/local.witch.autonomous.r1.completion.r445.savedState/KnownSceneSessions/data.data` | 1247 / 0o644 | 2026-10-15T04:44:11.063617+09:00 | `fcceb7c4143342f9d9bc83662dee0774de45a87454953d8f9de717970c364d8c` | 5F21554A-B60B-4443-AAE5-44EA0F7EE051; binary plist |

The keys point to Canvas/SpriteKit restoration data, SwiftUI scene identity, and the `KnownSceneSessions` registry. This supports treating the files as simulator/app lifecycle state rather than user save data; it does not make them whitelisted or erase the closure mismatch. Their combined size is 2,651 bytes. No file was changed or removed.

Other closure checks show no unexpected changed or missing data files, no support-file or archive mismatches, exact installed app and protected trees, and byte-identical cold-before/cold-after primary saves. The allowed Application Support save/identity files changed through the ordinary UI flow, and `save.json.lock` appeared as an allowed new file. Two files in the app-specific Metal cache were separately reported. No app PID remained. These facts narrow the remaining mismatch to the three saved-state files, but the run stays **INCOMPLETE_RETAINED** rather than a blanket preservation pass.

Evidence: `SESSION.json` SHA-256 `8e1dbb235856169db4094393a4c71157a6b7cbb014096b5100ff51b483e8e2d5`; `CLOSURE.json` SHA-256 `01b33e7a5d35a52b25769e3df67a72657dfeab8fc6b41656c67ec50782be1518`. This readback is observational only; no cleanup or rerun was performed.

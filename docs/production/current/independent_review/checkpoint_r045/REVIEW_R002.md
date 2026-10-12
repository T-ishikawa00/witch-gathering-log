# R045 checkpoint integrity review R002

**Status: PASS**

I checked every listed path, size, and SHA-256 across both manifests: 724 files totaling 1,266,505,127 bytes. No file was missing, no digest/size mismatched, and no path appeared in both manifests. Declared counts and byte totals agree. The candidate payload is 561 files / 144,093,374 bytes; the local media delta is 163 files / 1,122,411,753 bytes.

The payload checkpoint base `93dff6a7c380227266e175a969c422a6a73031d3` is an ancestor of HEAD `a63ab3a56ba66183f0fa6722ef6eab635c6454b7`. All 561 payload paths exist in both HEAD and the index. The 163 media-delta paths are not in HEAD or the index, consistent with the manifest's local-only-media scope.

No listed path matched the declared cache/build/DerivedData/xcresult exclusions. Active `wardrobe_home_r094/runner_candidate_r005` is not in either manifest. The payload intentionally contains image files (`.png`/`.jpg`) and the media delta contains image/video files; these are listed deliverables rather than build/cache output.

At review time, `native/WitchGathering.xcodeproj/project.pbxproj` was modified in the worktree and was not in either manifest. This review does not claim that change is committed.

R001 is preserved. Its git-membership fields mistakenly calculated over the union of payload and media paths; this R002 corrects those counts by reporting the two manifest sets separately. Full per-file checks are in [FILE_CHECKS_R001.json](FILE_CHECKS_R001.json).

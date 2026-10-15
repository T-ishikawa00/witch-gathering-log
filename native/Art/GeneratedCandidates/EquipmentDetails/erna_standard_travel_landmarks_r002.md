# Erna standard/travel full-frame landmark survey R002

Status: `UNAPPROVED_VISUAL_MEASUREMENT_CANDIDATE`. Read-only inspection of source art; no PNG, renderer, or runtime overlay was changed.

## Coverage and identity

- Surveyed all 54 body images from `native/GeneratedArt/layered_motion_r001/`: 27 standard and 27 travel across walk, anticipate, execute, recover, idle, hit, and resolve.
- Frame records in `erna_standard_travel_landmarks_r002.json` include the exact `runtimeBodyAssetID`, runtime and source frame indices, `[256,256]` canvas, and verified per-PNG SHA-256. All 54 paths and hashes were checked against the source files.
- Each frame has separate neck/collar, chest, waist, screen-right ankle, and free-hand records. Coordinates are visual readings from 2x enlarged contacts with a 16-source-pixel grid; approximate tolerance is about 4 px. Existing individual waist and ankle readings were retained and rechecked against the contact sheets. No terminal-frame value was propagated across a clip.
- `freeHand` means the non-staff/gesture hand, distinct from the existing authored staff-grip pivot. It is measured in 27 frames and `unknown` in 27 frames where travel's cape/sleeve hides it or identity cannot be separated confidently.

## Visual observations

The standard outfit leaves more of the central bodice, arms, waist seam, and both boots visually distinct. The travel outfit adds a broad cape/high collar that covers the neck/upper chest and one arm through most states; those hidden non-grip hand points are recorded as unknown. The lower skirt still allows boot landmarks in the reviewed frames, but does not expose a clean body layer for arbitrary leg overlays. These notes describe the reviewed pixels only; they do not approve either outfit or establish overlay masks/depth.

## Contact evidence

Fourteen state contacts are stored in `native/Art/GeneratedCandidates/EquipmentDetails/erna_landmark_contacts_r002/`, with costume, state, frame label, source image, and 16px grid. They are measurement aids, not runtime art.

The source landmark file `erna_standard_travel_landmarks_r001.json` is preserved unchanged. No renderer or `runtime_overlay` file was edited. Coordinate interpretation, mask/depth behavior, and Human visual acceptance remain pending.

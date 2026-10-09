# B_R01_B 苔冠の古樹 — base v1

Status: independent source/base-sprite prototype, not a final G2 acceptance, animation set, engine integration, or iPhone performance pass. Created 2026-10-08 after the initial boar appearance/motion was accepted for proceeding with R01 art.

## Canon and visual QA
- Sources: SOURCE_REFERENCE_BRIEF.md; R01_REMAINING_ASSET_SPECS.md; R2 docs/02_BESTIARY_VISUAL_R2.md section 06. Approved characters and boar v2 inspected for palette, light and clustered sprite direction.
- Living ancient tree, broad heavy crown, low fork, twisted growth-ring wood cues, subdued moss, tiny white duct lights. Complete independent tree; no blue crystal, temple, architecture, floor, stone, pedestal, label, UI, blood or death.
- Upper-left warm light; slightly elevated 3/4 view. House-larger scale is intended but cannot be verified without a scene comparison; exact pixels-per-world-unit remains unset.
- Face remains an implied expression from natural knots rather than a skull. Crown is detailed and dense; reduced-scale screen readability still requires composition testing.

## Artwork choices, not fixed canon
- Two main trunks branch low.
- Two lateral attack branches: screen-left and screen-right. Each has woody terminal subdivisions, not hands.
- Five clearly visible primary ground-root runs: left outer, left front, center front, right front, right outer. Prompt requested six but output has five unambiguous primary runs; do not invent a hidden sixth or regard this as a canonical count. Preserve the five visible runs in future frames.
- Four broad crown masses can be used for animation segmentation. Internal support bough topology is partially occluded by foliage and must be explicitly designed during rigging, not inferred as verified four independent branches.

## Proposed articulation (not implemented)
- Root anchor proposed at approximately (639, 1070) on the 1254 square source; normalized (0.510, 0.853). This is body/root base, not lowest curled root tip. Confirm with battle floor placement.
- Trunk low split approx (680, 750); left attack base (520, 680), right attack base (855, 760). These are approximate visual control points, not extracted bones.
- Separate five root runs, two attack branches, two trunk masses and four canopy masses while preserving connections. Paint occluded areas with image generation before independent transforms; do not stretch the flattened image and claim a complete rig.
- Fine-root anticipation and branch wind-up need separate poses/VFX. Calm resolution retracts branches and stills roots; no felling or explosion.

## Files and limitations
- B_R01_B_ANCIENT_TREE_base_v1.png is a byte-preserved generated RGBA source/export. No retouch or thresholding applied. Built-in image generator, prompt_v1.txt.
- Original generated source remains original-generation-output:exec-7ba8913a-d30b-4fb2-a3e9-d78934a06405.png.
- Real transparency is present. Alpha has low-value fringe pixels at full-image bounds; visible bounds at alpha >=16 are (25,25)-(1246,1229). Crown's right margin is only 8 px, so a padded working canvas is required before deformation. Do not treat alpha>0 bounding box as clean silhouette.
- Interior alpha is predominantly 250–251, not fully opaque. Preserve original alpha; evaluate on actual light/dark background and decide an explicit export policy before final engine delivery.
- Future animation and device tests are outstanding. This is not a spritesheet or layered PSD.

# R01 independent source-art QA

2026-10-08 UTC. Source-art rendering only, not game integration or iPhone testing. The user accepted the current art/motion baseline at 17:11 UTC; remaining R01 art production need not be blocked on subjective shoulder refinement.

## Completed evidence
- `portrait_composite_390x694.png`: earlier clean-plate/front composite; Library `libfile_835e2d7d003081919d6d1158a38d551d`.
- `boar_alpha_white_390x694.png`, gray and black variants: original straight alpha rendered through Transparent/Emission material, no alpha cutoff or source-pixel edits. No visible brown halo or substantial fringe at the tested display size. Hidden RGB exposed by a raw viewer is not visible artwork.
- `four_layer_neutral_390x694.png` and four `four_layer_offset_*` PNGs: far_v01, back_trees_v01, playfield_v02, foreground_v02, independently composited. Canonical small cottage roof remains partly visible above canopy; mountains, amber light, wooden bridge, stream, moon/vine stone, clear dry floor and lower vegetation all read. No empty holes or conspicuous broken joins were seen in these five rendered positions at 390×694.
- `witch_R01_four_layer_QA.blend`: editable isolated Blender scene with packed original textures. `render_layer_qa.py` reproduces it. No existing game changed.

## Test settings and interpretation
CPU Cycles, 8 samples, Closest texture filtering, original straight alpha, Standard/None look for new four-layer renders. Earlier diagnostic scene used Standard/Medium High Contrast; it is an edge/compositing check, not neutral color proof.

All background sources941×1671. The 390×694 review canvas introduces minor aspect rounding and is a test viewport, not a final specification. Full-canvas alignment is used; only far plane has1% overscan. Stationary floor; far offsets±2x/±1y, trees±4x/±2y, front±8x/±4y source pixels. Neutral and all four corner extrema were inspected. Continuous movement, subpixel shimmer and larger envelopes remain untested.

Boarv2 source1536×1024; substantial alpha≥128 bbox(266,117)-(1300,903). Visible test width120points; height91.22points. Foot baseline340points from bottom. This gives readable separated tusks and four feet. Cyan rectangles reserve approximate party occupancy only; they do not prove approved-character proportions, witch-waist scale, pixel-density compatibility or HUD/telegraph clearance. No approved character sprite was extracted or altered.

Separate scene ellipse supplies a neutral22% opacity contact-shadow test below the boar; not painted into any texture. Shadow shape/placement is provisional. Source image pixels were never modified or thresholded.

## Stage assessment
Static source-art direction and actual-alpha independent-layer feasibility are supported. Current boar motion is user-accepted; independent foreleg motion and editable source are documented by the rig worker. Its behind-body layering conceals the shoulder cap but hides much of the upper leg; production anatomy/ground-contact/weight transfer remain refinements, not a reason to reverse the user's current acceptance.

Remaining production checks: approved-character scale/density comparison, full HUD/telegraph/effects readability, continuous parallax, atlas padding/filter/pivots, canonical head/tusk tilt and recovery, complete animation states, game import and actual iPhone performance. No full G2, complete enemy animation set, or device pass is claimed.

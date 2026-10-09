# E_R01_01 苔角いのしし: two-plane animation feasibility

Status: Independent foreleg animation demonstrated. Production art feasibility gate FAILED for a seamless shoulder join. This is an editable motion test, not a completed enemy animation set.

## What is in the test
- Five seconds, 120 frames at 24 fps. All numbers are test values, not approved production specifications.
- Frames 1–24: planted idle (no unsupported full-body breathing warp).
- 25–42 and 43–60: two foreleg reach/back/return motions about a shoulder pivot.
- 61–80: straight root translation along X, with a brief anticipation. This is a root-motion demonstration, not a running gait.
- 81–99: restrained foreleg settle; 100–120: hold at charge endpoint. Not a loop.
- Canonical sideways tusk tilt and recovery head shake are NOT demonstrated: no independently separated head exists. The head, tusks, torso and other legs remain one rigid plate.

## Inspection findings
1. At rest and both scrape extrema, the foreground leg's upper black outline and rounded cap remain visible over the shoulder. The shape looks pasted on rather than continuously articulated. The existing pixels are left intact; hiding or warping this seam would conceal the asset issue.
2. No missing shoulder hole opens within the tested -7° to +5° arc because the body plate provides overlapping coverage. No duplicate near-front hoof is visible: the supplied body plate has that leg removed, retaining the other three legs.
3. Rigid swing has a useful readable forward/back silhouette, but is not anatomically complete. The approximate hoof landmark moves about 38px forward/11px upward at -7°, and 28px backward/5px downward at +5°, then returns exactly. A real ground-contact scrape needs knee/ankle articulation or a purpose-drawn foot-contact pose. This test does not claim locked floor contact.
4. Small source semi-transparent fringes remain. Original RGBA is used without thresholding, cleanup or repainting. The neutral gray stage exposes these rather than concealing them on a busy forest background.
5. Only one leg is articulated. Idle four-foot probing, weight transfer, hit/recovery head animation, full attack gait and defeat are unimplemented. No game integration or device-performance claim.

## Rig / reproduction
Open E_R01_01_cutout_feasibility.blend in Blender 4.3.2. Textures are packed. CTRL_root_straight_charge moves both plates; CTRL_near_foreleg_shoulder_900_540 moves only the foreground foreleg. Both use editable keyframes and timeline markers. No source texture pixels are changed. Orthographic camera includes the full original 1536×1024 registration canvas, with review labels outside it.

Run `blender -b -t 4 --python build_rig.py` to rebuild and render PNG frames with the bundled byte-identical textures. Add `-- --test` for one extreme frame. PNGs are rendered by Blender. Encode without changing source art: `ffmpeg -framerate 24 -i frames/review_%04d.png -c:v libx264 -crf 20 -pix_fmt yuv420p -movflags +faststart E_R01_01_cutout_review.mp4`.

Cycles CPU, four samples, modest 768×576 output is chosen for portable, fast review. Eevee was attempted but failed graphics-context creation in this cloud environment. Rendering noise/antialiasing is review quality, not a final pixel-perfect export.

## Next asset requirement
Re-author the detachable shoulder overlap as a clean joint with a hidden/protected upper cap and sufficient body underpainting. Add separate head/tusks and articulated or alternate lower-leg/hoof poses before claiming the canonical telegraph and recovery. No such painting or extraction was performed here.

## Non-destructive layer-order comparison
A second scene and clip, E_R01_01_cutout_behind_body.blend / E_R01_01_cutout_review_behind.mp4, place the same moving foreleg 0.03 units behind the body rather than in front. This naturally occludes the cap outline, with no image change. Idle and both extreme poses were rendered and inspected. No shoulder gap appears and the foot still moves, but most upper-leg anatomy is hidden by the reconstructed chest/belly. The result reads as a short lower leg emerging under the belly. It is the cleaner visual arrangement for a rough timing prototype, not a clean production solution. Both versions are retained for an honest comparison. Rebuild this variant with `blender -b -t 4 --python build_rig.py -- --behind`.

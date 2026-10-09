# R01 eight-base-asset independent QA

2026-10-08 UTC. Scope: R01 only. Current artwork preserved; no source PNG pixel editing. This is a review of two background systems and six enemy/boss base images, not complete game-ready animation or full G2 acceptance.

## Deliverable
- Review-only board: `R01_eight_base_assets_review.png`, Library `libfile_c3c109cd3f6c8191999ae8679dc591fd`.
- Actual-alpha field test: `four_normal_enemies_in_field_390x694.png`.
- Arena-only composite: `boss_arena_three_layers_390x694.png`.
- Independent boss over arena: `ancient_tree_in_arena_390x694.png`.
- Reproduction: `render_R01_set_qa.py`, `R01_eight_assets_QA.blend`, `ancient_tree_arena_QA.blend`, `remaining_set_render_settings.json`, `all_actor_metrics.json`.

The board is a QA layout, never a replacement for the independent assets. Saved scenes pack source textures. No existing game code changed and no Mac/iPhone save or validation is implied.

## Rendering evidence
Blender CPU Cycles8samples, Standard/None view, Closest filtering, original straight alpha mixed between Transparent and Emission. No thresholding, cleanup, recoloring or painted composites. Background layers are separate planes; sprites are separate planes. No visible surrounding glow, conspicuous white/black halo, or background rectangle was seen around the six actors at tested sizes. Source-viewer RGB beneath alpha0 is not visible rendered artwork.

Field viewport390×694: normal boar120points bbox width; spider72; leaf105; resin78. These are provisional display tests. Review board uses independently chosen thumbnail sizes and is explicitly not world-scale evidence. Ancient tree is305points wide over the390point arena, with root-bottom at260points from bottom. A house/approved-character scale comparison has not been supplied.

## Canonical visual findings
- BG_R01_FIELD: prior four-layer QA remains applicable; wooden bridge, stream, moon/vine stone, distant cottage roof and dry floor remain readable.
- BG_R01_BOSS: backforest + terrain/stone + foreground compose into a natural, darker forest and broad dry floor with a moon/vine monument. No baked boss, blue crystal, temple, fortress, HUD or text. Static joins look coherent. Parallax/overscan for this separate arena remains untested.
- E_R01_01: four hooves, two separated rising moss tusks, brown coat, no root crown. Existing accepted motion baseline unchanged.
- E_R01_02 v2 (preferred): compact brown spider with short clustered appendages, pale yellow abdominal light and white silk wrapping now lower on the abdomen; face palps are shorter than v1. Eight fully traceable leg chains cannot be certified from this occluded single pose; that topology should be locked when producing motion/directions. No extra leg is asserted from an ambiguous mouth appendage.
- E_R01_03: two large separate outward-sweeping sickle leaves with a small insect body. Silhouette remains distinct in the field test. Four walking feet are clearly visible; further connections are occluded, so complete topology awaits movement/direction work.
- E_R01_04: near-spherical amber/translucent-looking shell, no flames. Six visible appendage endpoints are consistent with six legs; far-side two connections are partly concealed, so full chain connectivity remains unverified rather than declaring wrong anatomy.
- B_R01_A: four hooves, two prominent tusks, large face/forelegs and low roots crossing forehead toward back of head. Clearly distinct from the uncrowned normal boar.
- B_R01_B: broad green crown, low divided trunk, small white branch nodes, roots and lateral branches. No giant blue crystal, architecture, pedestal or gore. Single-plane base shape is preserved; root/branch articulation remains separate work.

## Practical findings to carry forward
1. Central ancient-tree placement cleanly renders but occludes much of the monument. If the monument must remain readable during combat, adjust the independent actor/stone positions or composition at integration. This is not a request to repaint accepted source art.
2. Source margins need care before animation/atlasing: ancient-tree substantial-alpha right margin9px; miniboss top16px/bottom19px; leaf top36px/right40px. Static artwork is intact; large deformation/automatic trim must not assume generous padding.
3. Against the warm busy field, the small brown spider and amber resin have less local contrast than the white-tusk boar. Both remain identifiable here, but actual HP/telegraphs/effects and contact shadows need a gameplay readability pass.
4. The eight-base-art set is present and suitable as the current production baseline. It does not establish all attacks/states, approved character density/waist scale, canonical giant-tree versus house scale, full motion limb topology, collision, atlas behavior or device performance.

Respect the user's acceptance of the current boar motion. Do not reinstate subjective shoulder refinements as a blocker to producing the remaining R01 assets. Future technical verification stays explicitly separate from this art baseline.

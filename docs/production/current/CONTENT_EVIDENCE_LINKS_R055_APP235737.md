# R055 evidence links — additive R052 supplement

R055 keeps the R054 manual app target (235737, executable SHA `f2a16851…`) and the R054 matrix unchanged: 248 rows, with 242 `PARTIAL`, 1 `NOT_PRODUCED`, and 5 `INCOMPLETE`. The 13 inherited evidence-link rows are retained; this revision appends R052 evidence to `ui_surface / home` and adds rows for `party_character / C_APPRENTICE` (sprite alias `LUNA`) and `ui_surface / furniture`. This is evidence-only and does not represent formal adoption.

## R052 scope and build identity

The furniture interaction/restart assertion is `WitchUITests/testFurniturePlacementAndUse`, 1/1 passed in 16.353 seconds. The Xcode-produced simulator executable SHA is `3b1048a46ec0a5d109dca4e7b0b911866c329e2c145ae0d6f8fe66c2eefedc3e`; it is distinct from the manual app executable in the ledger target (`f2a16851b41ee24c5f8efc255ee4d2d5ffa7c7a0fb13648f4e002714242a0a6b`). The raw test run remains `RECOVERY_PENDING`: Xcode changed the container UUID. A separate reconciliation restored four fixed diagnostic files and verified all 641 prior JSON files and the new QA save unchanged; the reason for the UUID change remains unknown.

The separate read-only capture did not install the app or rerun the test. It recorded a 15.301667-second video with 909 decoded frames and 48 visual samples at 4 fps from seconds 2–14; PTS reversals were zero. The capture showed LUNA at the desk and four party members in the 14-second home screenshot. Source-frame/logical-index sync is unproven, so this is bounded visual sampling, not full motion acceptance.

`C_APPRENTICE` is the catalog actor ID; `LUNA` is the sprite/display alias. The test and sampled home scene support this mapping, while technical QA remains separate from Human approval.

## Rows

### ui_surface / home

**Proven:** Prior R045 frozen103source XcodeDebug:3sizes,5controls,4partyvisible,3saveexact,81fixedrestored,552nonfixedunchanged

**Limits:** 10screen technical acceptance; no action taps/VoiceOver/physical device/Human adoption

### party_character / C_WITCH

**Proven:** 5staffx2costumes,9frames3wrap+idle,1354/1354OCR

**Limits:** Historical app221236; modest motion naturalnessPARTIAL;2videosPTSreverse

### gear_type / EQ_W_01

**Proven:** Eachstaff standard/travel9walkframes3wrap,no grossdetach/duplicate shaft in reviewed native100samples

**Limits:** Historical app221236;naturalness andfinalartPARTIAL

### gear_type / EQ_W_G1

**Proven:** Eachstaff standard/travel9walkframes3wrap,no grossdetach/duplicate shaft in reviewed native100samples

**Limits:** Historical app221236;naturalness andfinalartPARTIAL

### gear_type / EQ_W_G2

**Proven:** Eachstaff standard/travel9walkframes3wrap,no grossdetach/duplicate shaft in reviewed native100samples

**Limits:** Historical app221236;naturalness andfinalartPARTIAL

### gear_type / EQ_W_P1

**Proven:** Eachstaff standard/travel9walkframes3wrap,no grossdetach/duplicate shaft in reviewed native100samples

**Limits:** Historical app221236;naturalness andfinalartPARTIAL

### gear_type / EQ_W_P2

**Proven:** Eachstaff standard/travel9walkframes3wrap,no grossdetach/duplicate shaft in reviewed native100samples

**Limits:** Historical app221236;naturalness andfinalartPARTIAL

### appearance_candidate / ERNA_TRAVEL

**Proven:** All5staff dedicated9framewalk3wrap+idle observed

**Limits:** Candidateappearance notapprovedsaleproduct

### party_character / C_FAMILIAR

**Proven:** SyntheticDASH2 exacttarget34/34videojoin,anticipate/direct/execute

**Limits:** Historical app222455;recover/idle preempted bynextcast;ordinaryR03617/18 unchanged

### ui_surface / workshop

**Proven:** R037 frozen source no explicit staticcopytruncation found

**Limits:** Viewport clipping andweak intersects helper leave wholetext readability unverified;R048pending

### challenge / CH_R02_03

**Proven:** ExactchallengeID in after-acquisition Core 6loadouts x3seeds supplement

**Limits:** HistoricalCore derived-save trial; no native orhumanfun proof;notall15challenges

### challenge / CH_R03_03

**Proven:** ExactchallengeID in after-acquisition Core 6loadouts x3seeds supplement

**Limits:** HistoricalCore derived-save trial; no native orhumanfun proof;notall15challenges

### challenge / CH_R05_02

**Proven:** ExactchallengeID in after-acquisition Core 6loadouts x3seeds supplement

**Limits:** HistoricalCore derived-save trial; no native orhumanfun proof;notall15challenges

### party_character / C_APPRENTICE

**Proven:** R052 Xcode XCTest checks the home-scene label for LUNA reading at the desk and checks furniture remains placed after restart; separate read-only capture visually samples the same LUNA home reading scene.

**Limits:** Catalog entity ID is C_APPRENTICE (sprite/display alias LUNA). No exact source-frame/logical-index sync; sampled video is not full animation-quality or Human acceptance. Xcode test executable differs from manual R055 target.

### ui_surface / furniture

**Proven:** R052 testFurniturePlacementAndUse passed 1/1 and checked in-use furniture state plus placement retained after app restart; Xcode test executable identity is recorded separately from manual target.

**Limits:** Raw test run remains RECOVERY_PENDING after container UUID changed. Separate reconciliation restored four fixed diagnostics and verified 637/641 prior JSON files plus the new QA save unchanged. Cause of UUID change is unknown. No broader furniture catalog, physical-device, or Human adoption claim.

R055 is an evidence-link supplement only. The matrix file and readiness counts were not edited.

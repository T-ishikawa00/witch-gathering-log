# R371 controlled challenge-mechanic candidate

Status: source-only, uncompiled, unrun. Formal adoption: false.

The suite has 15 challenge entries. Fourteen run deterministic Core probes over the pinned R368 catalog scenarios; CH_R02_02 verifies the exact already-passed R359 membrane receipt and deliberately does not simulate it again. New probes use canonical party IDs with controlled maxHP=100,000, attack=10, defense=0. This keeps encounter cycles observable but does not represent ordinary equipment, progression, reward, victory balance, player experience, or formal adoption.

Each new case writes its full bounded `CombatResult` as one unique JSON file under `WITCH_R371_EVIDENCE_ROOT`. The tests check authored event relationships using action roots, chronology, target and hit counts, and independently replay party/enemy HP from the event ledger and reconcile to `CombatResult`. Evidence output is exclusive-create and no save is written. The R359 external receipt is checked by exact SHA and test identifier.

Inputs are pinned to the R368 isolated Core package manifest (68 staged files), its Package.swift and relevant simulator/domain/model sources, plus R367 coverage/failure records and the R359 source/pass receipt.

No compile/test was run. CH_R03_02 checks the phase-two AoE cycle after the retained revision-155 ordinary trace did not observe a post-shift tell. The mechanism-only fixture may reveal timeline or assertion assumptions; it cannot replace that ordinary-play evidence.

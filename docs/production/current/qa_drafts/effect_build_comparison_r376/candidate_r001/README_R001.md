# R376: one earned direct-versus-poison build comparison

This is a source-only, unexecuted candidate. It reuses the archived R368 free/no-ad 30-virtual-day snapshot and its exact App/runtime identity. The snapshot contains two unassigned Witch weapon instances at Q0, enhancement 0, refinement rank I, and 0 invested dust: `EQ_W_01` (`BC499DA8-3B80-5536-BAFB-5143888B392C`) and `EQ_W_P1` (`6CA40746-2A06-4374-A92D-F321927D48BE`). Both have catalog attack bonus +3. The direct control has no active effects; P1 has `POISON_STACK` and `POISON_STACK_CAP_2`.

The one XCTest runs six no-reward previews: those two owned-in-save weapon choices on `CH_R02_01`, seeds 37601–37603, with every other equipped slot held to the same snapshot map. It records full event traces, ticks, win/loss, party/enemy HP, event counts, quality, investment, and latent-slot payloads. It expects poison events only in the P1 arm. The source save and run report are SHA-checked before and after; the in-memory repository snapshot must remain exactly unchanged.

This answers one narrow question: does an equal catalog-stat poison weapon produce observable poison mechanics and a different combat outcome profile from the direct weapon on the authored DoT/heal challenge? The natural latent-slot rolls differ between these two real inventory instances. Their impact is recorded, so this is a practical build comparison, not a pure causal estimate of the weapon effect. It is also a test overlay preview from a simulated 30-day cohort, not ordinary human-play, optimization, balance, paid value, or formal approval.

## Existing comparison coverage and remaining gaps

R346 already produced 27 paired outcomes (three loadout pairings across three challenges and three seeds), but its deterministic candidate selector chose by investment/quality and did not isolate effect families. R376 adds one focused poison comparison. It does not compare barrier, counter, heal, chase, or other latent-role builds; those remain unverified as comparative value. If R376 is useful, the next bounded comparison should use a naturally owned equal-quality/no-investment pair for one of those effects and a challenge that can trigger it, while preserving per-item latent data and stopping if no suitable pair exists.

No compile, XCTest, Simulator action, save write, grant, purchase, or ad completion was performed for R376.

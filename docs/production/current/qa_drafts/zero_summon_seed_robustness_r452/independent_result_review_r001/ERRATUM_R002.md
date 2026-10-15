# R452 result-review erratum

This additive correction resolves the one-ID discrepancy noted in `REVIEW_R001`. The natural `EQ_FEET_02` UUID `036d0113-4efe-54af-8b7d-de645b956f58` is present in each day-30 inventory and natural-origin set. After the day-30 checkpoint, each action journal records the explicit command `dismantle_actual_natural_duplicate_036d0113-4efe-54af-8b7d-de645b956f58`, with a +1 refine-dust delta. The final gear join is exactly the day-30 gear set minus this UUID (1,445 → 1,444) in both seeds. The final save SHA differs from the day-30 cold-reopen save SHA, as expected after the transaction.

The origin join is therefore exact after accounting for the recorded dismantle; the earlier discrepancy was a review omission, not a data-integrity failure. The original report remains unchanged.

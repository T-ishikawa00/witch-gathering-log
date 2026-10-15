# Provenance note

During the R002 corrections, the R001 test source path was edited in place before the corrected bytes were copied to candidate_r002. The existing R001 manifest pin does not match the current R001 file bytes, and the original R001 byte payload was not retained in this folder. Therefore R001 is not represented as byte-exact preserved. Candidate R002 is the authoritative corrected test source; the earlier R001 assertions and any eventual execution state must not be inferred from the current R001 path.

R002 preservation note

During the authorized R003 correction, edits were initially made in candidate_r002 before its frozen status was recognized. To preserve the prior revision, candidate_r003/reconstruction/candidate_r001 was copied from R001 and SOURCE_PATCH_R002.diff was applied there. The resulting bytes for all source/test files were checked against MANIFEST_R002.json and copied back to candidate_r002; each recorded SHA matched. R002 README, patch, and manifest were not changed. The temporary R003 working copies of the correction are the R003 candidate files.

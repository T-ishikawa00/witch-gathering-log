# Erratum R001 — source path

My earlier status message incorrectly said the native source files had disappeared. That was a workdir mistake: commands without an explicit `workdir` inspected `/Users/PUBLIC_USER/Projects/idle-loot-rpg`, not the assigned worktree `/Users/PUBLIC_USER/.codex/worktrees/witch-03to05-r1/idle-loot-rpg`. The specified worktree's `native/build/source_R093_compile_r002` was present and was used for this review. There is no evidence that cleanup removed the R093 source snapshot; I retract that claim.

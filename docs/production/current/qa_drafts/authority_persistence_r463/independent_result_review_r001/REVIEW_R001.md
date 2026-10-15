# R463 durable-store result review

**Disposition:** scoped PASS for the marked local rehearsal store and the tested R461/Core regressions. This does not establish a production purchase path or hardware power-loss durability. Read-only review of saved results and output files; no tests, builds, or app/device operations were run here.

## Evidence verified

- R002 input manifest is `root_execution_r002/INPUTS.json` (SHA-256 `f3ee31cba9f7d2ddc5a0edc10d01ca0c5a9490de13cd18f3c750c3862e2d8027`). It pins the integrated R463 store source to SHA-256 `611c33072323ea6ec33c38813826d32d1b220c932af8430e8f3ee36c381d7f24`, the Root R003 test source to `e1e2038a8b8468bc2e61e76b95ec2800dfcb090c3bd597d873a03edd1dfb8af6`, plus the protocol and regression inputs. The result records all input files unchanged.
- `root_execution_r002/RESULT.json` (SHA-256 `c3b898ebe3fe121643159c0c4c05f144290748d7eb345aa42e06c717ce919f2e`) and its log (`4696bfd1138512a08d78ebecd109c613d476ae4c867a5323afa94e65cc066bcd`) agree: 45 methods, 45 passed, 0 failed, 0 skipped, 19.215 seconds, 241,270,784 allocated build bytes. Suite split is 12 R461 protocol, 8 R463 file-store, 7 R453 importer, 1 R454 transaction identity, and 17 save-recovery tests. This is a method count, not 45 independent requirements.
- The earlier R001 execution remains a retained failure: 44 methods, 43 passed, 1 assertion failed on error wording. R002’s test-only repair and cumulative-cap case pass in the later run; the initial failure is not rewritten as a pass.
- `PROCESS_RESULT.json` (SHA-256 `b8f4db463aeada0831ad20e1b1f362628e932ef3c89ff8db2141ea20f0f466c8`) reports seven independent executable processes: pending request write and cold read, two competing observation CAS writers with exactly one winner, winner readback, refund/debt write, and a stale success rejected after process restart. Saved output contents corroborate a single pending operation and revision-10 refunded state with debt 2. The final pending/observation/lock files are mode `0600`, single-link, under the explicitly marked rehearsal directory.
- `ROOT_INTEGRATION_R001.json` records the exact integrated source/test hashes and the same 45/45 result. The 256-record cumulative account limit is explicitly retained as a nonproduction rehearsal bound; there is no eviction or production retention lifecycle.

## Limits and remaining gates

The process test demonstrates independent-process persistence/CAS under the tested schedule. It does not kill a process between individual write/rename/fsync steps, simulate hardware power loss, exercise app wiring, authenticate an Apple transaction, contact a production service, or grant gameplay currency/items. Production purchase routes remain disabled. Keep R463 classified as isolated persistence QA, not commerce or release acceptance.

## Pins

- Swift result: `docs/production/current/qa_drafts/authority_persistence_r463/root_execution_r002/RESULT.json` — `c3b898ebe3fe121643159c0c4c05f144290748d7eb345aa42e06c717ce919f2e`.
- Process result: `docs/production/current/qa_drafts/authority_persistence_r463/root_execution_r002/PROCESS_RESULT.json` — `b8f4db463aeada0831ad20e1b1f362628e932ef3c89ff8db2141ea20f0f466c8`.
- Integration receipt: `docs/production/current/qa_drafts/authority_persistence_r463/ROOT_INTEGRATION_R001.json` — `f3cec5b6cfe08b6bd5cf7e4d7d8955fde9f5803c17fe8c206cc5461a7ef806ab`.
- Final observation output: mode `0600`, one link, SHA-256 `bfb8a966d92f6e766ae69409b05b9f6677c46c5fae1f65cac8099bceaf7ac0cc`.
- Final pending-operation output: mode `0600`, one link, SHA-256 `269abd876be5141fd3d30ca005bef2db17f999277e56b83e50420ff51d8fa5fb`.

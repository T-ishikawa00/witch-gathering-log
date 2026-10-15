#!/usr/bin/env python3
"""Validate an existing R239 saved-combat lifecycle sidecar; never launches or writes to the app."""
import argparse
import json
import sys
from pathlib import Path


def fail(message: str, code: int = 2) -> int:
    print(json.dumps({"status": "FAIL_OR_NOT_OBSERVED", "reason": message}, sort_keys=True))
    return code


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace", type=Path)
    parser.add_argument("--expect", choices=("deferred-hit-complete", "lethal-cancel"), required=True)
    args = parser.parse_args()
    try:
        payload = json.loads(args.trace.read_text(encoding="utf-8"))
    except Exception as exc:
        return fail(f"trace_read_error:{type(exc).__name__}")
    if not isinstance(payload, dict) or payload.get("schema") != "r214-replay-trace-r239-v1":
        return fail("unexpected_schema")
    replay_id = payload.get("replayID")
    rows = payload.get("rows")
    if not isinstance(replay_id, str) or not isinstance(rows, list) or payload.get("rowCount") != len(rows) or not rows or len(rows) > 16:
        return fail("invalid_replay_envelope")
    if not all(isinstance(row, dict) and row.get("replayID") == replay_id for row in rows):
        return fail("row_replay_identity_mismatch")
    def first(kind: str):
        return next((i for i, row in enumerate(rows) if row.get("kind") == kind), None)
    start = first("execute_started")
    deferred = first("hit_visual_deferred")
    if start is None or deferred is None or not start < deferred:
        return fail("execute_or_deferred_hit_not_observed")
    start_row, deferred_row = rows[start], rows[deferred]
    identity = (start_row.get("actorID"), start_row.get("rootActionID"), start_row.get("sceneGeneration"), start_row.get("eventSequence"))
    if not identity[0] or not identity[1] or not isinstance(identity[2], int) or not isinstance(identity[3], int):
        return fail("execute_identity_incomplete")
    if (deferred_row.get("actorID"), deferred_row.get("executeRootActionID"), deferred_row.get("sceneGeneration"), deferred_row.get("executeEventSequence")) != identity:
        return fail("deferred_hit_not_joined_to_execute")
    hit_sequence = deferred_row.get("eventSequence")
    if not isinstance(hit_sequence, int):
        return fail("deferred_hit_sequence_missing")
    if args.expect == "deferred-hit-complete":
        execute_done = next((i for i in range(deferred + 1, len(rows)) if rows[i].get("kind") == "execute_completed" and rows[i].get("eventSequence") == identity[3] and rows[i].get("rootActionID") == identity[1]), None)
        hit_started = next((i for i in range((execute_done or 0) + 1, len(rows)) if rows[i].get("kind") == "hit_visual_started_after_execute" and rows[i].get("executeEventSequence") == identity[3] and hit_sequence in rows[i].get("deferredHitEventSequences", [])), None) if execute_done is not None else None
        hit_done = next((i for i in range((hit_started or 0) + 1, len(rows)) if rows[i].get("kind") == "hit_visual_completed" and rows[i].get("executeEventSequence") == identity[3] and hit_sequence in rows[i].get("deferredHitEventSequences", [])), None) if hit_started is not None else None
        if execute_done is None or hit_started is None or hit_done is None:
            return fail("ordered_completion_chain_not_observed")
        print(json.dumps({"status":"PASS_SCOPED_TRACE","mode":args.expect,"replayID":replay_id,"actorID":identity[0],"rootActionID":identity[1],"executeEventSequence":identity[3],"hitEventSequence":hit_sequence,"rowIndices":{"executeStarted":start,"hitDeferred":deferred,"executeCompleted":execute_done,"hitStarted":hit_started,"hitCompleted":hit_done}},sort_keys=True))
        return 0
    cancel = next((i for i, row in enumerate(rows) if row.get("kind") == "hit_visual_cancelled" and row.get("executeEventSequence") == identity[3] and row.get("executeRootActionID") == identity[1] and row.get("reason") == "lethal_resolve" and (row.get("eventSequence") == hit_sequence or hit_sequence in row.get("coalescedHitEventSequences", []))), None)
    if cancel is None:
        return fail("lethal_resolve_cancellation_not_observed")
    if any(row.get("kind") == "hit_visual_started_after_execute" and row.get("executeEventSequence") == identity[3] and hit_sequence in row.get("deferredHitEventSequences", []) for row in rows[cancel+1:]):
        return fail("deferred_hit_started_after_lethal_cancel")
    print(json.dumps({"status":"PASS_SCOPED_TRACE","mode":args.expect,"replayID":replay_id,"actorID":identity[0],"rootActionID":identity[1],"executeEventSequence":identity[3],"hitEventSequence":hit_sequence,"cancelRowIndex":cancel},sort_keys=True))
    return 0

if __name__ == "__main__":
    sys.exit(main())

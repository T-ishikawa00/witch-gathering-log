#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <simulator-udid> <bundle-id> [stable-qa-save-key]" >&2
  exit 2
fi
udid="$1"
bundle_id="$2"
qa_key="${3:-audio-probe-r001}"
qa_key="$(printf '%s' "$qa_key" | tr -cd '[:alnum:]_-' | cut -c1-64)"
if [[ -z "$qa_key" ]]; then
  echo "QA key must contain at least one ASCII letter, digit, '_' or '-'" >&2
  exit 2
fi
out_dir="${TMPDIR:-/tmp}/witch-audio-qa-${udid}"
mkdir -p "$out_dir"
stdout_file="$out_dir/stdout.log"
stderr_file="$out_dir/stderr.log"
diag_file="$out_dir/diagnostics.log"
: > "$stdout_file"
: > "$stderr_file"
: > "$diag_file"

xcrun simctl launch --terminate-running-process --stdout="$stdout_file" --stderr="$stderr_file" \
  "$udid" "$bundle_id" --qa-isolated "--qa-save-key=$qa_key" \
  --qa-audio-diagnostics --qa-audio-probe

for _ in $(seq 1 40); do
  xcrun simctl spawn "$udid" log show --last 1m --style compact --predicate 'process == "WitchGathering" AND eventMessage CONTAINS "WITCH_AUDIO_QA"' > "$diag_file" 2>/dev/null || true
  if rg -q 'WITCH_AUDIO_QA .*"qaProbePassed":true' "$diag_file"; then
    echo "PASS: audio QA probe completed. Logs: $out_dir"
    exit 0
  fi
  if rg -q 'WITCH_AUDIO_QA .*"qaProbePassed":false' "$diag_file"; then
    echo "FAIL: audio QA assertion failed. Logs: $out_dir" >&2
    cat "$diag_file" "$stdout_file" "$stderr_file" >&2
    exit 1
  fi
  sleep 0.5
done

echo "BLOCKED: no completed WITCH_AUDIO_QA probe found. Confirm app startup calls runQASmokeProbeIfRequested() and inspect $out_dir" >&2
cat "$diag_file" "$stdout_file" "$stderr_file" >&2
exit 3

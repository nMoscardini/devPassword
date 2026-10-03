#!/bin/bash
# devPassword smoke test (devDesign principle 8): build everything, run every test,
# including the end-to-end run on a 1,000-record synthetic vault. Synthetic data only.
# The last line of logs/smoke-latest.log is always SMOKE PASSED or SMOKE FAILED.
cd "$(dirname "$0")/.."
mkdir -p logs
LOG=logs/smoke-latest.log
{
  echo "== $(date '+%Y-%m-%d %H:%M:%S') smoke"
  sw_vers 2>/dev/null || true
  swift --version 2>&1 | head -1
} > "$LOG"
status=0
echo "== build" | tee -a "$LOG"
swift build >> "$LOG" 2>&1 || status=1
if [ $status -eq 0 ]; then
  echo "== test" | tee -a "$LOG"
  swift test >> "$LOG" 2>&1 || status=1
fi
grep -E "error:|failed \(|Executed .* tests" "$LOG" | tail -15
if [ $status -eq 0 ]; then
  echo "SMOKE PASSED" | tee -a "$LOG"
else
  echo "SMOKE FAILED - see $LOG" | tee -a "$LOG"
  exit 1
fi

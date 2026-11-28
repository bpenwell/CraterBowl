# Shared waits for the multi-process smoke scripts (net_test.sh, mm_test.sh). Source it.
# A loaded machine (load average 20-60 on WSL) can take many times longer to boot Godot than an
# idle one, so never wait for process startup with a fixed sleep or a fixed-count poll (#283):
# poll until a generous deadline, stop early when the process being waited on has exited, and on
# failure say what never happened and show the tail of the logs.

# Seconds to wait for one startup step (host listening, invite code printed, match started).
# Also the extra headroom added to each process's `timeout` cap, which is only a hang guard.
WAIT_SECS="${WAIT_SECS:-90}"
WAITED=0

# wait_for SECS "PIDS" CMD...: run CMD every 0.1 s until it succeeds (return 0), SECS pass, or
# any process in PIDS (space-separated, may be empty) has exited (return 1). Sets WAITED (s).
wait_for() {
  local start=$SECONDS end=$((SECONDS + $1)) pids=$2 p
  shift 2
  while :; do
    "$@" && { WAITED=$((SECONDS - start)); return 0; }
    for p in $pids; do
      kill -0 "$p" 2>/dev/null || { WAITED=$((SECONDS - start)); "$@"; return; }
    done
    [ "$SECONDS" -ge "$end" ] && { WAITED=$((SECONDS - start)); return 1; }
    sleep 0.1
  done
}

# log_has REGEX FILE...: some FILE has a line matching the extended regex.
log_has() { grep -qE -- "$1" "${@:2}" 2>/dev/null; }

# show_logs FILE...: the last LOG_TAIL (default 20) lines of each log, for a failure message.
show_logs() {
  local f
  for f in "$@"; do
    echo "--- last ${LOG_TAIL:-20} lines of $f"
    tail -n "${LOG_TAIL:-20}" "$f" 2>/dev/null
  done
}

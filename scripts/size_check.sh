#!/usr/bin/env bash
# File-size ratchet for src/**/*.gd (see scripts/size_budget.txt). No Godot needed.
# New files over MAX_LINES fail. Budgeted files that grow past their budget only warn for now,
# so in-flight PRs keep passing; set SIZE_STRICT=1 to make that a failure too.
set -uo pipefail
cd "$(dirname "$0")/.."
MAX_LINES="${MAX_LINES:-500}"
BUDGET="${SIZE_BUDGET:-scripts/size_budget.txt}"
fail=0
while IFS= read -r f; do
	n=$(wc -l < "$f" | tr -d ' ')
	b=$(awk -v f="$f" '$1 == f { print $2 }' "$BUDGET")
	if [ -n "$b" ]; then
		if [ "$n" -gt "$b" ]; then
			if [ "${SIZE_STRICT:-0}" = "1" ]; then
				echo "SIZE FAIL: $f is $n lines, budget $b"; fail=1
			else
				echo "SIZE WARN: $f is $n lines, budget $b. Put new behavior in its own file (AGENTS.md \"Where new code goes\")"
			fi
		fi
	elif [ "$n" -gt "$MAX_LINES" ]; then
		echo "SIZE FAIL: $f is $n lines (max $MAX_LINES). Split it by responsibility (AGENTS.md \"Where new code goes\")"; fail=1
	fi
done < <(find src -name '*.gd' | sort)
[ $fail -eq 0 ] && echo "SIZE PASS"
exit $fail

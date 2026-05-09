#!/bin/bash
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { ((PASS++)); echo -e "  ${GREEN}PASS${NC}: $1"; }
fail() { ((FAIL++)); echo -e "  ${RED}FAIL${NC}: $1"; }
header() { echo -e "\n${CYAN}$1${NC}"; }

run_check() {
    local name="$1"
    local cmd="$2"
    local err_file
    err_file=$(mktemp)

    bash -lc "$cmd" >/dev/null 2>"$err_file"
    local exit_code=$?
    local err_text
    err_text=$(sed -n '1,3p' "$err_file")
    rm -f "$err_file"

    if [ "$exit_code" -eq 0 ]; then
        pass "$name succeeded"
    else
        fail "$name failed (exit=$exit_code)"
        if [ -n "$err_text" ]; then
            echo "    $err_text"
        fi
    fi
}

header "WSL Interop Test"

if command -v powershell.exe >/dev/null 2>&1; then
    pass "powershell.exe is in PATH"
else
    fail "powershell.exe is not in PATH"
fi

if command -v cmd.exe >/dev/null 2>&1; then
    pass "cmd.exe is in PATH"
else
    fail "cmd.exe is not in PATH"
fi

run_check "powershell.exe -c \"exit\"" 'powershell.exe -c "exit"'
run_check "cmd.exe /c exit 0" 'cmd.exe /c exit 0'
run_check "cmd.exe /c ver" 'cmd.exe /c ver'

header "Summary"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -eq 0 ]; then
    exit 0
fi

exit 1

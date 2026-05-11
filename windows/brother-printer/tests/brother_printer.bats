#!/usr/bin/env bats
# brother_printer.bats - Brother DCP-T820DW Win11 spooler 修復 regression check
#
# 對應 .claude/skills/brother-printer.md「成功條件」中可自動驗證的部分。
# 執行：bats windows/brother-printer/tests/brother_printer.bats

DOTFILES="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
HEALTHCHECK="$DOTFILES/windows/brother-printer/healthcheck.ps1"

@test "T-BP1: healthcheck.ps1 存在" {
    [ -f "$HEALTHCHECK" ]
}

@test "T-BP2: Spooler 自動重啟 + 無重複 Brother 項目（regression）" {
    command -v powershell.exe >/dev/null 2>&1 || skip "powershell.exe 不存在（非 WSL 環境）"

    local script_win
    script_win=$(wslpath -w "$HEALTHCHECK")

    run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$script_win"

    echo "$output"
    [ "$status" -eq 0 ]
}

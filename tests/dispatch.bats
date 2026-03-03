#!/usr/bin/env bats
# dispatch.bats - T-D1, T-D2: PROJECT 計算

setup() {
    load test_helper
    common_setup
}

teardown() {
    common_teardown
}

@test "T-D1: 非 git 目錄 → PROJECT = basename of PWD" {
    local result
    result=$(cd /tmp && {
        PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)"
        PROJECT="$(basename "${PROJECT:-$PWD}")"
        echo "$PROJECT"
    })
    [ "$result" = "tmp" ]
}

@test "T-D2: git repo 內 → PROJECT = repo name" {
    local result
    result=$(cd "$SCRIPT_DIR/.." && {
        PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)"
        PROJECT="$(basename "${PROJECT:-$PWD}")"
        echo "$PROJECT"
    })
    [ "$result" = "dotfiles" ]
}

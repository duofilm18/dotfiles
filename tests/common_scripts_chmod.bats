#!/usr/bin/env bats
# common_scripts_chmod.bats - regression for ansible/roles/common "Make shell
# scripts executable". The bare `chmod *.sh *.py` glob exits non-zero (and fails
# the play) when scripts/ has no .py file; the find-based task must not.

@test "find-based chmod exits 0 and chmods .sh even when no .py exists" {
  tmp="$(mktemp -d)"
  printf '#!/bin/sh\n' > "$tmp/a.sh"
  run find "$tmp" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod u+x {} +
  [ "$status" -eq 0 ]
  [ -x "$tmp/a.sh" ]
  rm -rf "$tmp"
}

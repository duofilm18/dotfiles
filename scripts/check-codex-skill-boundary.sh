#!/bin/bash
# check-codex-skill-boundary.sh - 驗證 ~/.codex/skills 只包含指向 .claude/skills 的 shim

set -euo pipefail

CODEX_SKILLS_DIR="${CODEX_HOME:-$HOME/.codex}/skills"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/dotfiles/.claude/skills}"
MARKER="Canonical source:"

[ -d "$CODEX_SKILLS_DIR" ] || exit 0

failures=0

while IFS= read -r skill_file; do
    canonical=$(sed -n "s|^$MARKER[[:space:]]*||p" "$skill_file" | head -1)

    if [ -z "$canonical" ]; then
        echo "Missing canonical source marker: $skill_file" >&2
        failures=1
        continue
    fi

    case "$canonical" in
        "$CLAUDE_SKILLS_DIR"/*) ;;
        *)
            echo "Canonical source outside .claude/skills: $skill_file -> $canonical" >&2
            failures=1
            continue
            ;;
    esac

    if [ ! -f "$canonical" ]; then
        echo "Canonical source missing: $skill_file -> $canonical" >&2
        failures=1
        continue
    fi

    if ! grep -Fq "Do not maintain content in ~/.codex/skills." "$skill_file"; then
        echo "Missing no-maintenance warning: $skill_file" >&2
        failures=1
    fi
done < <(find "$CODEX_SKILLS_DIR" -mindepth 2 -maxdepth 2 -name 'SKILL.md' -type f | sort)

exit "$failures"

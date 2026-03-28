# CODEX.md

本 repo 的唯一正式協作規範是 [`CLAUDE.md`](./CLAUDE.md)。

開始任何分析、修改、除錯、建立 skill 前，先讀 [`CLAUDE.md`](./CLAUDE.md)。
若本檔與 [`CLAUDE.md`](./CLAUDE.md) 有任何差異，以 [`CLAUDE.md`](./CLAUDE.md) 為準。

## Skills

- `~/.codex` 的 config、auth、sessions、logs、state 照常留在 Codex
- 正式 skill 內容只維護在 [`/home/duofilm/dotfiles/.claude/skills`](/home/duofilm/dotfiles/.claude/skills)
- [`/home/duofilm/.codex/skills`](/home/duofilm/.codex/skills) 只允許作為 Codex 相容 shim，不得維護正式內容
- 若 `.codex/skills` 與 `.claude/skills` 不一致，以 `.claude/skills` 為準

## Boundary

- 不要在 `~/.codex/skills` 建立第二份正式 workflow、長篇規範或獨立 skill 真相
- 若 Codex 需要相容入口，只能建立指向 `.claude/skills` 的 shim
- 任何 skill 邊界規則，以 [`CLAUDE.md`](./CLAUDE.md) 與 repo 內 guard tests 為準

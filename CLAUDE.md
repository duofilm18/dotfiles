# Dotfiles - Claude AI 協作規範

## 專案說明

這是個人開發環境配置，用於快速設置 WSL + Docker 開發環境。

詳細使用說明請見 [README.md](./README.md)

## 可用 Skills

| Skill | 用途 |
|-------|------|
| [add-hook](.claude/skills/add-hook.md) | 新增 Claude Code Hook |

## 規則

1. **修改前確認** - 修改設定檔前先說明內容，等用戶確認
2. **更新文件** - 新增檔案要更新 README.md
3. **記得推送** - 改完要 `git push`，不要只 commit
4. **模板分離** - 機器特定設定用 `.example` 模板 + `.gitignore`

## 目錄結構

```
dotfiles/
├── .claude/skills/   # Claude AI 技能
├── docker/           # Docker 配置
├── scripts/          # 安裝腳本
├── shared/           # 共用配置 (vim, tmux)
├── wsl/              # WSL 專用配置
└── windows/          # Windows 配置
```

## 常用指令

```bash
# 安裝環境
~/dotfiles/scripts/install.sh

# 安裝 Docker
~/dotfiles/scripts/install-docker.sh

# 設定 Claude Hooks
~/dotfiles/scripts/setup-claude-hooks.sh

# 安全審查
~/dotfiles/scripts/safe-check.sh "要審查的指令"
```

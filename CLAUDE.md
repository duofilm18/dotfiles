# Dotfiles - Claude AI 協作規範

## 專案說明

這是個人開發環境配置，用於快速設置 WSL 開發環境。

詳細使用說明請見 [README.md](./README.md)

## 可用 Skills

| Skill | 用途 |
|-------|------|
| [add-hook](.claude/skills/add-hook.md) | 新增 Claude Code Hook |
| [tailscale-route-conflict](.claude/skills/tailscale-route-conflict.md) | Tailscale 路由衝突診斷與修復 |
| [wsl-lan-connectivity](.claude/skills/wsl-lan-connectivity.md) | WSL2 無法連線本地區網的排查 |

## 規則

1. **修改前確認** - 修改設定檔前先說明內容，等用戶確認
2. **更新文件** - 新增檔案要更新 README.md
3. **記得推送** - 改完要 `git push`，不要只 commit
4. **模板分離** - 機器特定設定用 `.example` 模板 + `.gitignore`

## 目錄結構

```
dotfiles/
├── .claude/skills/   # Claude AI 技能
├── ansible/          # Ansible 自動化部署
│   ├── roles/        # common, wsl, rpi_*, tinkerboard
│   ├── site.yml      # 主 playbook
│   └── rpi5b.yml     # RPi5B playbook
├── scripts/          # Shell 安裝腳本（備援）
├── shared/           # 共用配置 (vim, tmux)
└── wsl/              # WSL 專用配置 + Claude hooks
```

## 常用指令

```bash
# Ansible 部署（推薦）
cd ~/dotfiles/ansible && ansible-playbook site.yml
ansible-playbook rpi5b.yml --tags mqtt

# Shell 備援
~/dotfiles/scripts/install.sh
~/dotfiles/scripts/setup-rpi5b.sh

# 設定 Claude Hooks
~/dotfiles/scripts/setup-claude-hooks.sh

# 安全審查
~/dotfiles/scripts/safe-check.sh "要審查的指令"
```

---

## ⚠️ Tailscale 連線限制

| 類型 | 範例 | 狀態 |
|------|------|------|
| Tailscale IP | `http://100.105.101.50:8080` | ❌ 不可用 |
| Magic DNS | `http://rpi5b.tail77f91d.ts.net:8080` | ❌ 不可用 |

**正確方式**：使用 subnet routing 透過 `http://192.168.88.10:<port>`

詳細說明：[tailscale-route-conflict.md](.claude/skills/tailscale-route-conflict.md#⚠️-tailscale-連線限制重要)

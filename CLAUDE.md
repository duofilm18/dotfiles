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
# SSH 連線 RPi5B
ssh root@192.168.88.10

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

## 環境備註

- **Docker 只跑在 RPi5B 上**，WSL 不跑 Docker，所以 WSL2 mirrored networking mode 不會有衝突
- WSL2 已設定 `networkingMode=mirrored`，可直連區網 `192.168.88.x`
- **⚠️ WSL 的 Tailscale 絕不要 `--accept-routes=true`**——會建立 fwmark policy route 黑洞，導致區網連線全斷。詳見 [wsl-lan-connectivity.md](.claude/skills/wsl-lan-connectivity.md)

## WSL → RPi5B 連線方式

WSL 透過 **mirrored networking 直連 LAN**，不經過 Tailscale：

```bash
# 正確：直接用 LAN IP
ssh root@192.168.88.10
curl http://192.168.88.10:8080
```

| 方式 | 範例 | 狀態 | 說明 |
|------|------|------|------|
| LAN IP | `192.168.88.10` | ✅ 正確 | mirrored networking 直連 |
| Tailscale IP | `100.103.230.107` | ❌ 不通 | WSL 未開 accept-routes，預期行為 |
| Magic DNS | `rpi5b.tail77f91d.ts.net` | ❌ 不通 | 同上 |

**如果 WSL 突然連不到 RPi5B**，最常見原因是 Tailscale `accept-routes` 被意外開啟。排查步驟見 [wsl-lan-connectivity.md](.claude/skills/wsl-lan-connectivity.md)

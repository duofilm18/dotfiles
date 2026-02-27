# Dotfiles - Claude AI 協作規範

## 專案說明

這是個人開發環境配置，用於快速設置 WSL 開發環境。

詳細使用說明請見 [README.md](./README.md)

## 可用 Skills

| Skill | 用途 |
|-------|------|
| [add-hook](.claude/skills/add-hook.md) | Claude Code Hook 與 dispatch.sh 事件分發 |
| [tailscale-route-conflict](.claude/skills/tailscale-route-conflict.md) | Tailscale 路由衝突診斷與修復 |
| [wsl-lan-connectivity](.claude/skills/wsl-lan-connectivity.md) | WSL2 無法連線本地區網的排查 |
| [pihole-tplink](.claude/skills/pihole-tplink.md) | Pi-hole + TP-Link 路由器廣告攔截設定與排查 |
| [architecture-health](.claude/skills/architecture-health.md) | 系統層級架構健康原則（裝置邊界、語意介面、硬體歸屬） |
| [background-script](.claude/skills/background-script.md) | 背景常駐腳本的進程組管理規範 |
| [unidirectional-state](.claude/skills/unidirectional-state.md) | 單向資料流與被動顯示器架構規範 |
| [ime-mqtt-contract](.claude/skills/ime-mqtt-contract.md) | IME 檔案介面契約（格式、路徑） |
| [streamdeck](.claude/skills/streamdeck.md) | Stream Deck 硬體規格、按鍵佈局與操作 |
| [skill-creator](.claude/skills/skill-creator.md) | Skill 撰寫規範（基於 Anthropic 官方） |
| [testing](.claude/skills/testing.md) | Bats 測試慣例與 LED E2E 流程 |
| [deploy-paths](.claude/skills/deploy-paths.md) | Windows 部署路徑契約（禁止硬寫路徑） |
| [font-subset](.claude/skills/font-subset.md) | Noto Sans TC 字型 subset 流程 |
| [lighthouse](.claude/skills/lighthouse.md) | Lighthouse 效能測試（WSL 限制與替代方案） |
| [deploy-guard](.claude/skills/deploy-guard.md) | RPi5B 部署安全防護（Stop hook 自動檢測未部署改動） |
| [ansible-conventions](.claude/skills/ansible-conventions.md) | Ansible 撰寫規範（venv、變數、權限） |
| [mqtt-wiring](.claude/skills/mqtt-wiring.md) | MQTT topic 接線契約與登記表 |
| [shared-contract](.claude/skills/shared-contract.md) | 跨腳本共用契約（lib 抽取、guard test、禁止複製） |
| [rpi5b-services](.claude/skills/rpi5b-services.md) | RPi5B 服務介面、手機推播、API 約束 |

## 規則

1. **修改前確認** - 修改設定檔前先說明內容，等用戶確認
2. **更新文件** - 新增檔案要更新 README.md
3. **記得推送** - 改完要 `git push`，不要只 commit
4. **模板分離** - 機器特定設定用 `.example` 模板 + `.gitignore`
5. **安裝/設定功能 → Ansible** - 新增系統套件、設定檔、服務等安裝邏輯，一律加進 `ansible/roles/` 對應的 role，不碰 `scripts/install.sh`（它只是 bootstrap）
6. **禁止直接 SSH 改 RPi** - 所有 RPi 變更必須透過 Ansible role，不准 SSH 進去手動裝套件或改設定（否則下次 playbook 會覆蓋或遺漏）
7. **Ansible 撰寫規範** - 詳見 [ansible-conventions](.claude/skills/ansible-conventions.md)
8. **MQTT 接線登記** - 新增/修改 MQTT topic 必須更新 [mqtt-wiring](.claude/skills/mqtt-wiring.md) 登記表
9. **跨腳本共用契約** - 新建腳本若用到已存在的 payload 格式 / config / 常數，必須 source `scripts/lib/` 共用 lib，禁止複製貼上。詳見 [shared-contract](.claude/skills/shared-contract.md)

## 目錄結構

```
dotfiles/
├── .claude/skills/   # Claude AI 技能
├── ansible/          # Ansible 自動化部署
│   ├── roles/        # common, wsl, rpi_*, tinkerboard
│   ├── site.yml      # 主 playbook
│   └── rpi5b.yml     # RPi5B playbook
├── scripts/          # Shell 腳本（install.sh 為 bootstrap）
├── shared/           # 共用配置 (vim, tmux)
├── tests/            # Bats 測試
└── wsl/              # WSL 專用配置 + Claude hooks
```

## 常用指令

```bash
# SSH 連線 RPi5B
ssh root@192.168.88.10

# Ansible 部署（推薦）
cd ~/dotfiles/ansible && ansible-playbook site.yml
ansible-playbook rpi5b.yml --tags mqtt

# Bootstrap（安裝 Ansible + 跑 playbook）
~/dotfiles/scripts/install.sh
~/dotfiles/scripts/setup-rpi5b.sh

# 設定 Claude Hooks
~/dotfiles/scripts/setup-claude-hooks.sh

```

---

## 環境備註

- **Pi-hole 跑在 RPi5B Docker 上**（`192.168.88.10:53`），TP-Link 路由器 DHCP 的主要 DNS 指向它，次要 DNS **必須留空**。設定與排查詳見 [pihole-tplink.md](.claude/skills/pihole-tplink.md)
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

## 背景腳本撰寫規範

常駐背景腳本**必須用進程組管理生命週期**（`kill -- -PID` + `trap 'kill 0' EXIT`），否則 tmux reload 後子進程變孤兒互打。詳見 [background-script](.claude/skills/background-script.md)。

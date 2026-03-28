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
| [wsl-win11-files](.claude/skills/wsl-win11-files.md) | WSL 讀取 Windows / Win11 / OneDrive 檔案契約 |
| [brother-printer](.claude/skills/brother-printer.md) | Brother 印表機固定修復流程（先查 Windows Spooler，不走即興 CUPS 排查） |
| [internal-link-optimizer](.claude/skills/internal-link-optimizer.md) | SEO 內部連結調整、錨文字分配、目標頁對齊 |
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
| [deploy-integrity](.claude/skills/deploy-integrity.md) | 部署完整性免疫系統（pre-commit + Stop hook + marker 三層防護） |
| [rpi-ssh-setup](.claude/skills/rpi-ssh-setup.md) | RPi SSH 設定（Windows/WSL 雙 key、host key 清理） |
| [removal-checklist](.claude/skills/removal-checklist.md) | 移除元件時的殘留引用掃描清單 |
| [topic-architecture-planner](.claude/skills/topic-architecture-planner.md) | SEO 主題架構、hub/supporting pages、collection page 規劃 |

## 規則

1. **不維護平行規範** - `CLAUDE.md` 是唯一正式規範；若存在 `CODEX.md`，只允許作為 redirect stub 指向 `CLAUDE.md`，不得維護第二套內容
2. **CLAUDE.md 是唯一入口** - Claude 與 Codex 一律以 `CLAUDE.md` 為唯一專案規範入口
3. **先讀 CLAUDE.md 再動手** - 進入 repo 後，任何實作、排查、修改前，先讀 `CLAUDE.md`
4. **已有流程就照跑** - 若 `CLAUDE.md` 或 `.claude/skills/` 已定義流程，必須先依該流程執行，不得另建排查樹
1. **修改前確認** - 修改設定檔前先說明內容，等用戶確認
2. **更新文件** - 新增檔案要更新 README.md
3. **記得推送** - 改完要 `git push`，不要只 commit
4. **模板分離** - 機器特定設定用 `.example` 模板 + `.gitignore`
5. **安裝/設定功能 → Ansible** - 新增系統套件、設定檔、服務等安裝邏輯，一律加進 `ansible/roles/` 對應的 role，不碰 `scripts/install.sh`（它只是 bootstrap）
6. **禁止直接 SSH 改 RPi** - 所有 RPi 變更必須透過 Ansible role，不准 SSH 進去手動裝套件或改設定（否則下次 playbook 會覆蓋或遺漏）
7. **Ansible 撰寫規範** - 詳見 [ansible-conventions](.claude/skills/ansible-conventions.md)
8. **MQTT 接線登記** - 新增/修改 MQTT topic 必須更新 [mqtt-wiring](.claude/skills/mqtt-wiring.md) 登記表
9. **跨腳本共用契約** - 新建腳本若用到已存在的 payload 格式 / config / 常數，必須 source `scripts/lib/` 共用 lib，禁止複製貼上。詳見 [shared-contract](.claude/skills/shared-contract.md)
10. **背景腳本進程組管理** - 新建常駐背景腳本必須用 `scripts/lib/pidfile.sh` 管理生命週期，禁止自行寫 PID boilerplate。詳見 [background-script](.claude/skills/background-script.md)
11. **單向資料流** - 設計多端狀態同步（MQTT、Stream Deck、LED）時，必須遵循 Source → Publisher → Consumer 單向流，Consumer 不可寫回 Source。詳見 [unidirectional-state](.claude/skills/unidirectional-state.md)
12. **架構健康** - 新增跨裝置元件時，必須確認硬體邏輯歸屬正確（顯示優先權由顯示端決定、語意介面不含硬體細節）。詳見 [architecture-health](.claude/skills/architecture-health.md)
13. **寫完要測試** - 修改功能 code 後必須補/更新對應測試（Bats 或 pytest），測試全過才 commit。詳見 [testing](.claude/skills/testing.md)
14. **Windows 路徑契約** - 碰到 Windows 部署路徑時禁止硬寫，必須用變數或 registry 查詢。詳見 [deploy-paths](.claude/skills/deploy-paths.md)
15. **IME 介面契約** - 修改 IME 相關邏輯（IME_Indicator、ime-mqtt-publisher、tmux status bar）時，必須確認 writer/reader 格式一致（只允許 `zh`/`en`）。詳見 [ime-mqtt-contract](.claude/skills/ime-mqtt-contract.md)
16. **部署完整性抗體** - 新增 Ansible 管理的 systemd service 時，必須在 `tests/deploy_integrity.bats` 加對應的 DI-* 測試（腳本存在、template 存在、task 引用、handler 存在）。詳見 [deploy-integrity](.claude/skills/deploy-integrity.md)
17. **移除元件必掃殘留** - 砍掉腳本、服務、hook 或任何跨檔案元件時，必須跑 [removal-checklist](.claude/skills/removal-checklist.md) 掃描清單，同一個 commit 清乾淨
18. **Codex / Claude 邊界** - Codex 本體設定、登入、sessions、logs 仍留在 `~/.codex/`；只有正式 skill 內容移到 `.claude/skills/`。`~/.codex/skills/` 只允許存在 shim，必須標明 `Canonical source: <repo>/.claude/skills/<name>.md`，且明示 `Do not maintain content in ~/.codex/skills.`，不得在 `.codex/skills` 寫第二份正式內容

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

## Codex Skill 邊界

- Codex 本體資料（config、auth、sessions、logs、state）留在 `~/.codex/`
- 正式內容：[`/home/duofilm/dotfiles/.claude/skills`](/home/duofilm/dotfiles/.claude/skills)
- 相容入口：[`/home/duofilm/.codex/skills`](/home/duofilm/.codex/skills)
- `~/.codex/skills/*/SKILL.md` 只能是 shim，不得承載正式 workflow、長篇規範或第二份真相
- guard script：`scripts/check-codex-skill-boundary.sh`
- guard test：`bats tests/deploy_integrity.bats --filter "DI-14"`

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

- **Pi-hole 原生安裝在 RPi5B 上**（`192.168.88.10:53`，systemd pihole-FTL），TP-Link 路由器 DHCP 的主要 DNS 指向它，次要 DNS **必須留空**。設定與排查詳見 [pihole-tplink.md](.claude/skills/pihole-tplink.md)
- **Docker 只跑在 RPi5B 上**（uptime-kuma + ntfy），WSL 不跑 Docker，所以 WSL2 mirrored networking mode 不會有衝突
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

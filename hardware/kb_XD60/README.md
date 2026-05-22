# XD60 鍵盤專案

公司電腦的 XD60 機械鍵盤，跑客製 QMK 韌體。**動工前先讀同資料夾的 [CLAUDE.md](./CLAUDE.md)。**

## 硬體規格

| 項目 | 值 |
|------|-----|
| 型號 | XD60 二代(rev2)/ QMK `xiudi/xd60/rev2` |
| MCU | ATmega32u4(28KB) |
| USB（正常模式）| VID `0x7844` / PID `0x6060`（VIA / 裝置管理員看到的）|
| USB（DFU bootloader）| `0x03EB:0x2FF4`（`atmel-dfu`,進 bootloader 燒錄時）|
| RGB 燈條 | 6× WS2812(背面),資料腳 `F6` |
| 背光 | 單色,腳位 `F5` |

## 實體配列(QMK `LAYOUT_all`)

| 項目 | 選擇 |
|------|------|
| 退格鍵 | 不分裂 |
| 回車 | ANSI 2.25u |
| 左 Shift | 2u |
| 右 Shift 區 | `/` + F5 + ↑ + Fn |
| 空格行 | 6.25u + 方向鍵(← ↓ →) |

實體 **64 鍵**,每行(上→下)14 / 14 / 13 / 14 / 9。`LAYOUT_all` 是 67 位超集,
多的 3 個分裂變體位置填 `KC_NO`。

## 資產配置

```
hardware/kb_XD60/
├── CLAUDE.md                  ← 開工提示;動到此資料夾自動載入
├── xd60_qmk_keymap.json       ← 編譯用 keymap(由 .layout 同步產生,出廠預設)
├── xd60_via_definition.json   ← VIA 定義檔,載入 VIA App 用(很少變)
├── xd60_via_keymap.layout     ← VIA 鍵位的真實來源(VIA Export),其餘由它同步
├── xd60_custom/               ← 客製 keymap 原始碼,symlink 進 qmk_firmware
│   ├── keymap.c               ← 4 層 keymap(標準 QMK + VIA,無客製魔改)
│   └── rules.mk               ← VIA + LTO
├── tests/check_keymap_sync.py ← 守門:keymap.c 必須與 JSON 逐鍵一致
└── tools/sync_from_via.py     ← VIA → repo + 編譯,一鍵同步(不需 AI)
```

## 建置環境(一次性)

```bash
cd ~/dotfiles/ansible && ansible-playbook wsl.yml --tags qmk
```

裝 AVR toolchain + `qmk` CLI + clone `qmk_firmware`,並把 `xd60_custom/` symlink 進
`qmk_firmware/keyboards/xiudi/xd60/keymaps/`。

## 編譯 → 燒錄

```bash
qmk compile -kb xiudi/xd60/rev2 -km xd60_custom
```

1. `.hex` 給 Windows
2. 鍵盤進 bootloader(按住左上角鍵 + 插 USB)
3. Windows 用 QMK Toolbox 燒錄(atmel-dfu;首次需 Zadig 綁 WinUSB 驅動)

> 日常**改鍵位用 VIA**,即時生效、不必重編譯。只有改層數 / 編譯預設才需重編譯。
> 想把 VIA 的設定同步回 repo 當基礎,用 `tools/sync_from_via.py`(見下節)。

## Keymap(4 層)

| 層 | 進入 | 內容 |
|----|------|------|
| L0 Base | 預設層 | HHKB 風格打字層 |
| L1 Fn | 按住 `MO(1)`(右下) | F1~F12、滑鼠、媒體、方向 |
| L2 數字 | 按住 `MO(2)`(空格左) | 數字鍵盤、Home/End/PgUp/PgDn、RGB/背光、音量 |
| L3 方向 | L2 上按 `MO(3)` | 方向鍵等 |

- 鍵位以 VIA 即時編輯;`keymap.c` 的 `keymaps[]` 是出廠預設,已同步成目前 VIA 的設定。
- 底燈是**標準 QMK rgblight**(xd60 出廠內建全部動畫),用 Layer 2 的 RGB 鍵手動控制,
  沒有客製魔改。

## VIA 即時鍵位編輯

韌體已開 `VIA_ENABLE`,鍵位改在 VIA App 即時生效。

1. 開 [usevia.app](https://usevia.app)(Chrome/Edge)
2. ⚙ Settings → 開啟 **Show Design tab**
3. **Design** 分頁 → 載入 `xd60_via_definition.json`
4. **Configure** 分頁 → 接上鍵盤自動辨識 → 拖拉改鍵

VIA 顯示 67 鍵超集,實機 64 鍵,3 個無鍵帽的位置略過即可。

### 備份 / 還原

VIA 鍵位存在鍵盤 EEPROM。`xd60_via_keymap.layout` 是匯出備份(防重燒清 EEPROM)。
還原:VIA App → **Load Saved Layout** → 選此檔。

## 把 VIA 設定同步回 repo（`tools/sync_from_via.py`）

日常改鍵位只在 VIA、不用碰 repo。但偶爾想把 VIA 現況存成「出廠預設基礎」
(這樣重燒韌體也是你的設定),用這支腳本一次做完,**不需要 AI**:

```bash
# 1. VIA App → Save Current Layout，匯出 .layout 到 OneDrive 的 XD60_VIA/
# 2. 跑：
python3 ~/dotfiles/hardware/kb_XD60/tools/sync_from_via.py
```

它會:讀最新的 `.layout` → 更新 `keymap.c` + `xd60_qmk_keymap.json` +
`xd60_via_keymap.layout` → 跑 sync check → 編譯 → 把 `.hex` 複製到桌面。
之後自己 `git commit` 即可。

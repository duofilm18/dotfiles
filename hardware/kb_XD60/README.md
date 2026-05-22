# XD60 鍵盤專案

公司電腦的 XD60 機械鍵盤，跑客製 QMK 韌體。**動工前先讀同資料夾的 [CLAUDE.md](./CLAUDE.md)。**

## 硬體規格

| 項目 | 值 |
|------|-----|
| 型號 | XD60 二代(rev2)/ QMK `xiudi/xd60/rev2` |
| MCU | ATmega32u4(28KB) |
| USB | VID `0xFEED` / PID `0x6060` |
| Bootloader | `atmel-dfu` |
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
├── xd60_qmk_keymap.json       ← 編譯預設 keymap(真實來源)
├── xd60_via_definition.json   ← VIA 定義檔,載入 VIA App 用
├── xd60_via_keymap.layout     ← VIA 實際鍵位備份,重灌時 Import 回去
├── xd60_custom/               ← 客製 keymap 原始碼,symlink 進 qmk_firmware
│   ├── keymap.c               ← 4 層 + rgblight_layers + VIA
│   ├── config.h               ← RGBLIGHT_LAYERS / 色序覆寫
│   └── rules.mk               ← MOUSEKEY/EXTRAKEY/RGBLIGHT/BACKLIGHT/VIA/LTO
└── tests/check_keymap_sync.py ← 守門:keymap.c 必須與 JSON 逐鍵一致
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

> 日常**改鍵位用 VIA**,不必重編譯。只有改底燈顏色 / 層數才需重編譯 ——
> 順序:改 `xd60_qmk_keymap.json` → 同步 `keymap.c` → 跑 `check_keymap_sync.py` → 編譯。

## Keymap(4 層)

| 層 | 進入 | 內容 | 底燈色 |
|----|------|------|--------|
| L0 Base | 預設層 | HHKB 風格打字層 | 無色(關) |
| L1 Fn | 按住 `MO(1)`(右下) | F1~F12、滑鼠、媒體、方向 | 紅 |
| L2 數字 | 按住 `MO(2)`(空格左) | 數字鍵盤、底燈/背光、音量 | 綠 |
| L3 預備 | VIA 指定 | 待 VIA 填 | 藍 |

- 鍵位以 VIA 即時編輯;`keymap.c` 的 `keymaps[]` 只是出廠預設值。
- 底燈逐層顏色固定編譯在 `keymap.c`(`rgblight_layers`),VIA 改不了 —— 要改顏色須重編譯。

## VIA 即時鍵位編輯

韌體已開 `VIA_ENABLE`,鍵位改在 VIA App 即時生效。

1. 開 [usevia.app](https://usevia.app)(Chrome/Edge)
2. ⚙ Settings → 開啟 **Show Design tab**
3. **Design** 分頁 → 載入 `xd60_via_definition.json`
4. **Configure** 分頁 → 接上鍵盤自動辨識 → 拖拉改鍵

VIA 顯示 67 鍵超集,實機 64 鍵,3 個無鍵帽的位置略過即可。

### 備份 / 還原

VIA 鍵位存在鍵盤 EEPROM。`xd60_via_keymap.layout` 是匯出備份(防重燒清 EEPROM)。
還原:VIA App → **Load Saved Layout** → 選此檔。之後在 VIA 又改了鍵位,記得重匯出覆蓋。

## 待辦

- [ ] Layer 1/2 截圖轉錄,實機核對;Layer 3 待 VIA 填鍵位
- [ ] WS2812 色序:`config.h` 已備好覆寫(預設關),選紅變綠才取消註解重編譯

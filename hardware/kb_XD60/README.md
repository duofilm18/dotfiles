# XD60 鍵盤專案

公司電腦的 XD60 機械鍵盤 — 從 YDKB 韌體遷移到 QMK 的紀錄與資產。

## 硬體規格

| 項目 | 值 |
|------|-----|
| 型號 | **XD60 二代(rev2)** |
| MCU | ATmega32u4(28KB 應用程式空間) |
| USB | VID `0xFEED` / PID `0x6060` |
| Bootloader | `atmel-dfu` |
| RGB 燈條 | **6× WS2812 定址式**(背面貼片),資料腳 **F6** |
| 背光 | 單色背光,腳位 **F5** |

型號是用 WSL 查 Windows USB 裝置(`HID\VID_FEED&PID_6060`)+ 比對 QMK `xiudi/xd60/rev2` 定義確認的。

## 實體配列(QMK 用 `LAYOUT_all`)

| 項目 | 選擇 |
|------|------|
| 退格鍵 | 不分裂 |
| 回車 | 普通回車(ANSI 2.25u) |
| 左 Shift | 2u |
| Z 行字母 | 左移 0.25u |
| 右 Shift | 1u+1u+1u(`/` + F5 + ↑ + Fn) |
| 空格行 | 6.25u + 方向鍵(← ↓ →) |

## 問題與解法

- **現況**:鍵盤跑 **YDKB 韌體**(`GH60 BT_RGB Mod`,作者 YANG,基於 TMK),用 [ydkb.io](https://ydkb.io) 配置。
- **問題**:YDKB 的 `GH60_ABC` profile 對 LED 設定不符 → RGB 顏色亂跳,且 profile 在別人網站上改不了。
- **解法**:改用 **QMK**(TMK 的開源後繼者)。XD60 二代已內建支援 `keyboards/xiudi/xd60/rev2`,且其 RGB 定義已正確(6× WS2812 / F6)→ 換過去即修好亂跳。

## 編譯路線(主線:本地客製編譯)

走客製編譯,才能做 Configurator 做不到的事(逐層底燈換色、WS2812 色序)。
keymap 原始碼版控在本 repo,WSL 只負責編譯出 `.hex`,**燒錄仍在 Windows**
(WSL2 無原生 USB)。

### 資產配置

```
hardware/kb_XD60/
├── xd60_qmk_keymap.json          ← 唯一真實來源(QMK 官方定義 + 實機截圖)
├── xd60_custom/                  ← 客製 keymap 原始碼,symlink 進 qmk_firmware
│   ├── keymap.c                  ← 3 層 + rgblight_layers 逐層換色
│   ├── config.h                  ← RGBLIGHT_LAYERS / WS2812 色序(備援)
│   └── rules.mk                  ← MOUSEKEY / EXTRAKEY / RGBLIGHT / BACKLIGHT
└── tests/check_keymap_sync.py    ← 守門:keymap.c 必須與 JSON 逐鍵一致
```

### 建置環境(Ansible,一次性)

```bash
cd ~/dotfiles/ansible && ansible-playbook wsl.yml --tags qmk
```

`wsl` role 的 `qmk` tag 會裝 AVR toolchain(`gcc-avr` / `avr-libc` /
`binutils-avr`)、用 pipx 裝 `qmk` CLI、shallow clone `qmk_firmware`,
並把 `xd60_custom/` symlink 進 `qmk_firmware/keyboards/xiudi/xd60/rev2/keymaps/`。

### 編譯 → 燒錄

```bash
# WSL:編譯出 .hex
qmk compile -kb xiudi/xd60/rev2 -km xd60_custom
# 備援(不靠 qmk CLI):cd ~/qmk_firmware && make xiudi/xd60/rev2:xd60_custom
```

1. 把產出的 `.hex` 給 Windows 端
2. 鍵盤進 bootloader(按住左上角鍵 + 插 USB)
3. Windows 用 QMK Toolbox 燒錄(atmel-dfu)

改 keymap 的順序:**先改 `xd60_qmk_keymap.json`** → 同步 `xd60_custom/keymap.c`
→ 跑 `python3 hardware/kb_XD60/tests/check_keymap_sync.py` 確認一致 → 編譯。

## 備援:QMK Configurator(零安裝)

不想裝編譯環境時的快速路線,但**做不到逐層換色 / 色序客製**:

1. 開 [config.qmk.fm](https://config.qmk.fm)
2. `Import QMK Keymap` → 選 [`xd60_qmk_keymap.json`](./xd60_qmk_keymap.json)
3. 自動帶出 `xiudi/xd60/rev2` + `LAYOUT_all` + 3 層
4. 切 Layer 1 / 2 對照截圖微調 → 綠色 `COMPILE` → `FIRMWARE` 下載 `.hex`
5. 進 bootloader(按住鍵盤左上角鍵 + 插 USB)→ 用 QMK Toolbox 燒錄

## Keymap(3 層,見 `xd60_qmk_keymap.json` / `xd60_custom/keymap.c`)

- **Layer 0 — Base**:HHKB 風格。`Fn = MO(1)` 在右下、`MO(2)` 在空格左邊。
  - 此層由 `gh60 (3).hex` 解碼 + 截圖核對,**精準**。
- **Layer 1 — Fn**(按住 MO(1)):F1~F12、滑鼠鍵、媒體、方向/翻頁。
- **Layer 2 — RGB/數字**(按住 MO(2)):RGB 控制鍵(`RGB_TOG/MOD/HUI/SAI/VAI`)、背光、數字鍵盤、音量。
  - Layer 1/2 由 YDKB 截圖轉錄,**需在 Configurator 核對**。
- **底燈逐層換色**:`keymap.c` 用 `rgblight_layers` —— L_FN 全段紅、L_RGB 全段藍,放開模式鍵自動復原。

## 原始 YDKB 韌體

- 備份檔:`OneDrive\電腦軟體\XD60鍵盤\gh60 (3).hex`(萬一要回退)
- 韌體內 keymap 資料表:binary offset `0x148` 起,5 列 × 14 欄,每層 70 bytes

## 外部 review 核對紀錄

### 2026-05-20:DeepSeek 產的 `info.json` / `keymap.c` — ❌ 不採用

核對後**全部捨棄**,原因:

- **`info.json` 的 `matrix_pins` 是捏造的**。真實 QMK `xiudi/xd60/rev2`:
  cols(14)= `F0 F1 E6 C7 C6 B6 D4 B1 B7 B5 B4 D7 D6 B3`,rows(5)= `D0 D1 D2 D3 D5`。
  DeepSeek 寫成 15 cols / 6 rows,錯 → 用了矩陣對不上,鍵盤打不出字。
- 走 QMK Configurator 網頁版**不需要自備 info.json**,官方定義已內建。
- **`keymap.c` 是本地編譯路線用的**,跟網頁 Configurator(吃 JSON)工作流不符。
- keymap.c 內容也錯:Esc/Tab 顛倒、Base 層沒放 `MO(1)/MO(2)`(進不了其他層)、
  右 Shift 區誤植為 `< >`(實際是 F5 / ↑ / Fn)、`LAYOUT_all` 只給 65 鍵(實際 67,編譯報錯)。

**結論:keymap 一律以本資料夾的 `xd60_qmk_keymap.json` 為準**
(依據:真實抓下來的 QMK 官方定義 + 實機 3 張 layer 截圖)。
外部 AI 若無實機截圖與真實 repo,會幻覺出錯誤硬體定義,勿直接採用。

## 已知問題 / 待辦

- [x] 「逐層自動換色」—— `keymap.c` 已用 `rgblight_layers` 實作(L_FN 紅 / L_RGB 藍)
- [ ] Layer 1 / 2 是截圖轉錄,燒錄前在實機核對
- [ ] WS2812 色序:`config.h` 已備好覆寫(預設不啟用)。燒錄後若選紅變綠,
      取消 `WS2812_BYTE_ORDER` 那行註解重編譯
- [ ] 首次跑 `ansible-playbook wsl.yml --tags qmk` 建置編譯環境(尚未部署)

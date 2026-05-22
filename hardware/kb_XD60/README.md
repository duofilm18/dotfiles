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
├── CLAUDE.md                     ← 開工提示(必踩的坑);動到此資料夾自動載入
├── xd60_qmk_keymap.json          ← 編譯預設 keymap(QMK 官方定義 + 實機截圖)
├── xd60_via_definition.json      ← VIA 定義檔(由 QMK LAYOUT_all 轉),載入 VIA App 用
├── xd60_via_keymap.layout        ← VIA 實際鍵位備份(VIA Export),重灌時 Import 回去
├── xd60_custom/                  ← 客製 keymap 原始碼,symlink 進 qmk_firmware
│   ├── keymap.c                  ← 4 層 + rgblight_layers 逐層換色 + VIA
│   ├── config.h                  ← RGBLIGHT_LAYERS / 色序覆寫(備援)
│   └── rules.mk                  ← MOUSEKEY / EXTRAKEY / RGBLIGHT / BACKLIGHT / VIA / LTO
└── tests/check_keymap_sync.py    ← 守門:keymap.c 必須與 JSON 逐鍵一致
```

### 建置環境(Ansible,一次性)

```bash
cd ~/dotfiles/ansible && ansible-playbook wsl.yml --tags qmk
```

`wsl` role 的 `qmk` tag 會裝 AVR toolchain(`gcc-avr` / `avr-libc` /
`binutils-avr`)、用 pipx 裝 `qmk` CLI、shallow clone `qmk_firmware`,
並把 `xd60_custom/` symlink 進 `qmk_firmware/keyboards/xiudi/xd60/keymaps/`
(keymaps 在 `xd60/` 層、rev2/rev3 共用;QMK 解析 keymap 會往父目錄找)。

### 編譯 → 燒錄

```bash
# WSL:編譯出 .hex
qmk compile -kb xiudi/xd60/rev2 -km xd60_custom
# 備援(不靠 qmk CLI):cd ~/qmk_firmware && make xiudi/xd60/rev2:xd60_custom
```

1. 把產出的 `.hex` 給 Windows 端
2. 鍵盤進 bootloader(按住左上角鍵 + 插 USB)
3. Windows 用 QMK Toolbox 燒錄(atmel-dfu)

日常**改鍵位用 VIA**(見下節),不必重編譯。需要重編譯的情況:改底燈顏色、
改層數、改編譯預設值。此時順序:**先改 `xd60_qmk_keymap.json`** → 同步
`xd60_custom/keymap.c` → 跑 `python3 hardware/kb_XD60/tests/check_keymap_sync.py`
確認一致 → 編譯。

## 備援:QMK Configurator(零安裝)

不想裝編譯環境時的快速路線,但**做不到逐層換色 / 色序客製**:

1. 開 [config.qmk.fm](https://config.qmk.fm)
2. `Import QMK Keymap` → 選 [`xd60_qmk_keymap.json`](./xd60_qmk_keymap.json)
3. 自動帶出 `xiudi/xd60/rev2` + `LAYOUT_all` + 4 層
4. 對照截圖微調 → 綠色 `COMPILE` → `FIRMWARE` 下載 `.hex`
5. 進 bootloader(按住鍵盤左上角鍵 + 插 USB)→ 用 QMK Toolbox 燒錄

## Keymap(4 層,見 `xd60_custom/keymap.c`)

鍵位之後改在 **VIA App**(見下節);`keymap.c` 的 `keymaps[]` 只是燒進去的預設值。
逐層底燈顏色則固定編譯在 `keymap.c`,VIA 改不了。

| 層 | 進入方式 | 內容 | 底燈色 |
|----|---------|------|--------|
| Layer 0 — Base | 預設層 | HHKB 風格打字層 | 無色(關) |
| Layer 1 — Fn | 按住 `MO(1)`(右下) | F1~F12、滑鼠、媒體、方向/翻頁 | 紅 |
| Layer 2 — 數字/RGB | 按住 `MO(2)`(空格左) | 數字鍵盤、底燈/背光控制、音量 | 綠 |
| Layer 3 — 預備層 | 尚無按鍵(待 VIA 指定) | 空白,內容待 VIA 填 | 藍 |

- Layer 0 由 `gh60 (3).hex` 解碼 + 截圖核對,**精準**;實體 64 鍵(14+14+13+14+9)已實機數過核對。
- Layer 1/2 由 YDKB 截圖轉錄,**需在實機核對**。
- keycode 採 **現行 QMK 命名**:底燈 `UG_*`(舊 `RGB_*` 已廢)、滑鼠 `MS_*`(舊 `KC_MS_*/KC_BTN*/KC_WH_*` 已廢)。改鍵時以實際 qmk_firmware 的 `quantum/keycodes.h` 為準。
- 底燈逐層換色用 `rgblight_layers` + `RGBLIGHT_LAYERS_OVERRIDE_RGB_OFF`(Base 關燈時顏色層仍亮)。

## VIA 即時鍵位編輯

韌體已開 `VIA_ENABLE` —— 鍵位改在 VIA App 即時生效,**不用重編譯重刷**。

1. 開 [usevia.app](https://usevia.app)(Chrome/Edge)
2. 右上 ⚙ Settings → 開啟 **Show Design tab**
3. **Design** 分頁 → 載入 [`xd60_via_definition.json`](./xd60_via_definition.json)
4. 回 **Configure** 分頁 → 接上鍵盤即自動辨識 → 拖拉改鍵

- 定義檔由 QMK 官方 `LAYOUT_all` 幾何資料轉出,矩陣保證正確,**非手寫臆測**。
- 顯示的是 67 鍵分裂超集;實機只有 64 鍵,3 個分裂變體位置無實體鍵帽(`KC_NO`),VIA 裡略過即可。
- 底燈顏色不歸 VIA 管,要改顏色仍須改 `keymap.c` 重編譯。

### VIA 鍵位備份 / 還原

`xd60_via_keymap.layout` 是 VIA 實際鍵位的備份(VIA App 的 **Save Current Layout** 匯出)。

- VIA 改的鍵位存在鍵盤 EEPROM,平常不會掉;此檔是「重燒韌體可能清 EEPROM」時的保險。
- **還原**:VIA App → **Load Saved Layout** → 選此檔。
- ⚠️ 此檔是某時點的快照;之後在 VIA 又改了鍵位,記得重新匯出覆蓋此檔。
- 注意:`keymap.c` 的編譯預設值**未**跟著此檔同步(刻意),兩者用途不同 ——
  `keymap.c` = 燒進去的出廠預設,`.layout` = VIA 之後的實際改動。

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

- [x] 逐層自動換色 —— `keymap.c` 用 `rgblight_layers`(L0 無 / L1 紅 / L2 綠 / L3 藍)
- [x] VIA 即時鍵位編輯 —— `VIA_ENABLE`,定義檔 `xd60_via_definition.json`
- [x] 編譯環境 —— `ansible-playbook wsl.yml --tags qmk` 已部署,實機編譯/燒錄已驗證
- [x] 實體配列 —— 64 鍵(每行 14/14/13/14/9)已實機數過,對上 `LAYOUT_all` 的 67−3 `KC_NO`
- [ ] Layer 1/2 截圖轉錄,在實機核對;Layer 3 預備層待 VIA 填鍵位
- [ ] WS2812 色序:`config.h` 已備好覆寫(預設不啟用),選紅變綠才取消註解重編譯

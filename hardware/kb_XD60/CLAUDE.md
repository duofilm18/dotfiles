# XD60 鍵盤 — 開工提示

**動手前先讀 [README.md](./README.md)** —— 完整規格、編譯/燒錄/VIA 流程都在那。
本檔只列「一定會踩、不先講就會浪費時間」的雷。

## 5 個必踩的坑

1. **keycode 改名** —— 新版 QMK 已廢舊名（`RGB_*`→`UG_*`、`KC_MS_*/KC_BTN*/KC_WH_*`
   →`MS_*`、`KC_GESC`→`QK_GESC`、`KC_NLCK`→`KC_NUM`…），用舊名直接編譯失敗。
   VIA 匯出的 `.layout` 也是舊名 —— `tools/sync_from_via.py` 的 `CONV` 表會自動轉，
   照腳本走就好。**只有手寫 `keymap.c` 才要自己注意**，以實機
   `~/qmk_firmware/quantum/keycodes.h` 為準，別憑記憶。
2. **keymap 路徑** —— xiudi/xd60 的 keymaps 在 `keyboards/xiudi/xd60/keymaps/`
   （`xd60/` 層，rev2/rev3 共用），**不是** `xd60/rev2/keymaps/`。
3. **Windows 燒錄要驅動** —— DFU 裝置（`0x03EB:0x2FF4`）需 WinUSB 驅動，用 **Zadig**
   綁一次；沒綁的話 QMK Toolbox 顯示 `NO DRIVER`、dfu-programmer 報 `no device present`，
   看似 `Flash complete` 其實一個 byte 都沒寫。
4. **WSL 只編譯、不燒錄** —— WSL2 無原生 USB。WSL 出 `.hex`，燒錄在 Windows
   用 QMK Toolbox（atmel-dfu）。
5. **重燒韌體可能清空 VIA 設定** —— 韌體改動較大時 QMK 會重置 EEPROM，VIA 改的鍵位
   會掉回 `keymap.c` 出廠預設。重燒後若鍵位不對 → VIA App `Load Saved Layout` 載
   `xd60_via_keymap.layout` 還原。

## 常用指令

```bash
# VIA 改完鍵位後，同步回 repo + 編譯出 .hex（一鍵，平常用這個，不需 AI）
python3 hardware/kb_XD60/tools/sync_from_via.py

qmk compile -kb xiudi/xd60/rev2 -km xd60_custom        # 單獨編譯
python3 hardware/kb_XD60/tests/check_keymap_sync.py    # keymap.c ↔ JSON 同步守門
```

## 規矩

- **日常鍵位改 VIA**，即時生效、不必重編譯;`keymap.c` 只是燒進去的出廠預設。
- **要把 VIA 設定同步回 repo 當基礎** —— 跑 `tools/sync_from_via.py`,別手改
  `keymap.c` / `xd60_qmk_keymap.json`(手改容易和 VIA 不一致;keymap.c 由腳本產生)。
- 底燈是**標準 QMK rgblight**(無客製魔改),用 Layer 2 的 RGB 鍵控制。
- 外部 AI 無實機截圖會幻覺出錯誤硬體定義,勿直接採用。

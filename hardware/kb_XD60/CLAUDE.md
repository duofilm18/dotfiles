# XD60 鍵盤 — 開工提示

**動手前先讀 [README.md](./README.md)** —— 完整規格、編譯/燒錄/VIA 流程都在那。
本檔只列「一定會踩、不先講就會浪費時間」的雷。

## 4 個必踩的坑

1. **keycode 改名** —— 新版 QMK 已廢舊名，用錯直接編譯失敗：
   - 底燈：`RGB_*` → `UG_*`（`RGB_TOG`→`UG_TOGG`、`RGB_MOD`→`UG_NEXT`、
     `RGB_HUI`→`UG_HUEU`、`RGB_SAI`→`UG_SATU`、`RGB_VAI`→`UG_VALU`、`RGB_VAD`→`UG_VALD`）
   - 滑鼠：`KC_MS_*/KC_BTN*/KC_WH_*` → `MS_*`（`KC_MS_U`→`MS_UP`、`KC_BTN1`→`MS_BTN1`、
     `KC_WH_D`→`MS_WHLD` …）
   - 改鍵時以實機 `~/qmk_firmware/quantum/keycodes.h` 為準，別憑記憶。
2. **keymap 路徑** —— xiudi/xd60 的 keymaps 在 `keyboards/xiudi/xd60/keymaps/`
   （`xd60/` 層，rev2/rev3 共用），**不是** `xd60/rev2/keymaps/`。
3. **Windows 燒錄要驅動** —— DFU 裝置（`03EB:2FF4`）需 WinUSB 驅動，用 **Zadig** 綁一次；
   沒綁的話 QMK Toolbox 會顯示 `NO DRIVER`、dfu-programmer 報 `no device present`，
   看似 `Flash complete` 其實一個 byte 都沒寫。
4. **WSL 只編譯、不燒錄** —— WSL2 無原生 USB。WSL 出 `.hex`，燒錄在 Windows
   用 QMK Toolbox（atmel-dfu）。

## 常用指令

```bash
qmk compile -kb xiudi/xd60/rev2 -km xd60_custom        # 編譯（symlink 已就位）
python3 hardware/kb_XD60/tests/check_keymap_sync.py    # keymap.c ↔ JSON 同步守門
```

## 規矩

- **`xd60_qmk_keymap.json` 是 keymap 的真實來源** —— 改鍵先改它、再同步 `keymap.c`、
  跑 sync check。外部 AI 無實機截圖會幻覺出錯誤硬體定義，勿直接採用。
- **底燈顏色只能改 `keymap.c` 重編譯**，VIA / QMK Configurator 都做不到。
- **日常鍵位改 VIA**，不必重編譯；`keymap.c` 的 `keymaps[]` 只是燒進去的出廠預設。

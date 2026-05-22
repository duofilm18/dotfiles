# XD60 rev2 客製 keymap — build features
# xiudi/xd60/rev2 在 keyboard 層已開部分功能，此處明列本 keymap 實際用到的，
# 避免日後 keyboard 預設變動時 keymap 默默壞掉。

MOUSEKEY_ENABLE = yes    # Layer 1 滑鼠鍵：MS_UP/DOWN/LEFT/RGHT, MS_BTN*, MS_WHL*
EXTRAKEY_ENABLE = yes    # 媒體 / 音量鍵：KC_MPLY, KC_VOLU, KC_VOLD, KC_MUTE
RGBLIGHT_ENABLE = yes    # 6× WS2812 底燈 + rgblight_layers 逐層換色
BACKLIGHT_ENABLE = yes   # Layer 2 單色背光控制：BL_TOGG, BL_STEP（腳位 F5）
VIA_ENABLE = yes         # VIA 即時鍵位編輯（鍵位改在 VIA App，不用重刷）
LTO_ENABLE = yes         # link-time 最佳化，壓縮韌體體積（ATmega32u4 只有 28KB）

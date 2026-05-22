// XD60 rev2 客製 keymap — 客製編譯路線
//
// 唯一真實來源：../xd60_qmk_keymap.json
//   （真實抓下來的 QMK 官方 xiudi/xd60/rev2 定義 + 實機 3 層截圖核對）
// 本檔三層 keymap 由該 JSON 機械轉換而來，token 與 JSON 一一對應。
// 同步守門：tests/check_keymap_sync.py（keymap.c 與 JSON 任一不一致即 fail）。
//
// 客製編譯才能做、Configurator 做不到的兩件事都在這檔：
//   1. rgblight_layers — 逐層底燈換色（L_FN 紅 / L_RGB 藍）
//   2. WS2812 色序 — 見 config.h（預設不啟用，僅備援）

#include QMK_KEYBOARD_H

enum xd60_layers {
    L_BASE = 0,  // HHKB 風格基礎層
    L_FN,        // MO(1)：F 區、滑鼠、媒體、方向/翻頁
    L_RGB,       // MO(2)：RGB/背光控制、數字鍵盤、音量
};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    // ── Layer 0：Base（由 gh60 (3).hex 解碼 + 截圖核對，精準）──
    [L_BASE] = LAYOUT_all(
        KC_TAB,  KC_1,    KC_2,    KC_3,    KC_4,    KC_5,    KC_6,    KC_7,    KC_8,    KC_9,    KC_0,    KC_MINS, KC_EQL,  KC_BSLS, KC_NO,
        KC_ESC,  KC_Q,    KC_W,    KC_E,    KC_R,    KC_T,    KC_Y,    KC_U,    KC_I,    KC_O,    KC_P,    KC_LBRC, KC_RBRC, KC_BSPC,
        KC_LCTL, KC_A,    KC_S,    KC_D,    KC_F,    KC_G,    KC_H,    KC_J,    KC_K,    KC_L,    KC_SCLN, KC_QUOT, KC_NO,   KC_ENT,
        KC_LSFT, KC_NO,   KC_Z,    KC_X,    KC_C,    KC_V,    KC_B,    KC_N,    KC_M,    KC_COMM, KC_DOT,  KC_SLSH, KC_F5,   KC_UP,   MO(1),
        MO(2),   KC_LGUI, KC_LALT, KC_SPC,  KC_BSPC, KC_BSPC, KC_LEFT, KC_DOWN, KC_RGHT
    ),

    // ── Layer 1：Fn（按住 MO(1)）— 由 YDKB 截圖轉錄，燒前在實機核對 ──
    [L_FN] = LAYOUT_all(
        KC_TRNS, KC_F1,   KC_F2,   KC_F3,   KC_F4,   KC_F5,   KC_F6,   KC_F7,   KC_F8,   KC_F9,   KC_F10,  KC_F11,  KC_F12,  KC_TRNS, KC_NO,
        KC_TRNS, MS_BTN1, MS_UP,   MS_BTN2, MS_WHLU, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_MPLY, KC_UP,   KC_PSCR, KC_DEL,
        KC_TRNS, MS_LEFT, MS_DOWN, MS_RGHT, MS_WHLD, KC_TRNS, KC_TRNS, KC_TRNS, KC_HOME, KC_PGUP, KC_LEFT, KC_RGHT, KC_NO,   KC_TRNS,
        KC_TRNS, KC_NO,   MS_BTN1, MS_BTN2, MS_BTN3, KC_TRNS, KC_TRNS, KC_TRNS, KC_END,  KC_PGDN, KC_DOWN, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS,
        KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS
    ),

    // ── Layer 2：RGB/數字（按住 MO(2)）— 由 YDKB 截圖轉錄，燒前在實機核對 ──
    [L_RGB] = LAYOUT_all(
        KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_INS,  KC_NUM,  KC_TRNS, KC_LPRN, KC_RPRN, KC_UNDS, KC_TRNS, KC_TRNS, KC_NO,
        KC_CAPS, UG_TOGG, UG_NEXT, UG_HUEU, UG_SATU, UG_VALU, KC_ESC,  KC_P7,   KC_P8,   KC_P9,   KC_PPLS, KC_PMNS, KC_PAST, KC_TRNS,
        KC_TRNS, UG_VALD, UG_VALU, KC_TRNS, BL_TOGG, BL_STEP, KC_PENT, KC_P4,   KC_P5,   KC_P6,   KC_SCLN, KC_PPLS, KC_NO,   KC_TRNS,
        KC_TRNS, KC_VOLD, KC_VOLU, KC_MUTE, KC_TRNS, KC_TRNS, KC_PDOT, KC_P1,   KC_P2,   KC_P3,   KC_PSLS, KC_PENT, KC_TRNS, KC_TRNS, KC_TRNS,
        KC_TRNS, KC_TRNS, KC_TRNS, KC_P0,   KC_PDOT, KC_PENT, KC_PENT, KC_TRNS, KC_TRNS
    ),
};

// ── rgblight_layers：逐層底燈換色 ───────────────────────────────
// QMK Configurator 做不到（待辦第 3 項），客製編譯才有。
// 6 顆 WS2812 全段上色：L_FN 全紅、L_RGB 全藍，放開模式鍵自動復原。

// 新版 QMK 把 RGBLED_NUM 改名 RGBLIGHT_LED_COUNT，相容兩種命名。
#ifndef RGBLED_NUM
#    define RGBLED_NUM RGBLIGHT_LED_COUNT
#endif

const rgblight_segment_t PROGMEM xd60_fn_lighting[] = RGBLIGHT_LAYER_SEGMENTS(
    {0, RGBLED_NUM, HSV_RED}
);
const rgblight_segment_t PROGMEM xd60_rgb_lighting[] = RGBLIGHT_LAYER_SEGMENTS(
    {0, RGBLED_NUM, HSV_BLUE}
);
const rgblight_segment_t* const PROGMEM xd60_rgb_layers[] = RGBLIGHT_LAYERS_LIST(
    xd60_fn_lighting,   // index 0 → L_FN
    xd60_rgb_lighting   // index 1 → L_RGB
);

void keyboard_post_init_user(void) {
    rgblight_layers = xd60_rgb_layers;
}

layer_state_t layer_state_set_user(layer_state_t state) {
    rgblight_set_layer_state(0, layer_state_cmp(state, L_FN));
    rgblight_set_layer_state(1, layer_state_cmp(state, L_RGB));
    return state;
}

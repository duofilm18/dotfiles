// XD60 rev2 客製 keymap — QMK + VIA + 逐層底燈換色
//
// 唯一真實來源：../xd60_qmk_keymap.json（由 VIA 匯出 xd60_via_keymap.layout 同步）
// 同步守門：tests/check_keymap_sync.py（keymap.c 與 JSON 任一不一致即 fail）。
// 本檔由 tools/sync_from_via.py 整檔產生 —— keymaps[] 別手改（改 VIA 後重跑腳本）;
// 下半 rgblight_layers 是固定區塊，要改底燈顏色改腳本模板的 HSV_*。
//
// 逐層底燈：L_BASE 黑(關) / L_FN 紅 / L_NUM 綠 / L_L3 藍。

#include QMK_KEYBOARD_H

enum xd60_layers {
    L_BASE = 0,  // 打字基礎層 —— 底燈黑
    L_FN,        // MO(1)：F 區、滑鼠、媒體、方向 —— 紅
    L_NUM,       // MO(2)：數字鍵盤、RGB/背光控制、音量 —— 綠
    L_L3,        // MO(3)：方向鍵等 —— 藍
};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [L_BASE] = LAYOUT_all(
        KC_TAB,  KC_1,    KC_2,    KC_3,    KC_4,    KC_5,    KC_6,    KC_7,    KC_8,    KC_9,    KC_0,    KC_MINS, KC_EQL,  KC_BSLS, KC_NO,
        QK_GESC, KC_Q,    KC_W,    KC_E,    KC_R,    KC_T,    KC_Y,    KC_U,    KC_I,    KC_O,    KC_P,    KC_LBRC, KC_RBRC, KC_BSPC,
        KC_LCTL, KC_A,    KC_S,    KC_D,    KC_F,    KC_G,    KC_H,    KC_J,    KC_K,    KC_L,    KC_SCLN, KC_QUOT, KC_NO,   KC_ENT,
        KC_LSFT, KC_NO,   KC_Z,    KC_X,    KC_C,    KC_V,    KC_B,    KC_N,    KC_M,    KC_COMM, KC_DOT,  KC_SLSH, KC_F5,   KC_UP,   MO(1),
        MO(2),   KC_LGUI, KC_LALT, KC_SPC,  KC_BSPC, KC_BSPC, KC_LEFT, KC_DOWN, KC_RGHT
    ),
    [L_FN] = LAYOUT_all(
        KC_TRNS, KC_F1,   KC_F2,   KC_F3,   KC_F4,   KC_F5,   KC_F6,   KC_F7,   KC_F8,   KC_F9,   KC_F10,  KC_F11,  KC_F12,  KC_TRNS, KC_NO,
        KC_TRNS, MS_BTN1, MS_UP,   MS_BTN2, MS_WHLU, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_MPLY, KC_UP,   KC_PSCR, KC_DEL,
        KC_TRNS, MS_LEFT, MS_DOWN, MS_RGHT, MS_WHLD, KC_TRNS, KC_TRNS, KC_TRNS, KC_HOME, KC_PGUP, KC_LEFT, KC_RGHT, KC_NO,   KC_TRNS,
        KC_TRNS, KC_NO,   MS_BTN1, MS_BTN2, MS_BTN3, KC_TRNS, KC_TRNS, KC_TRNS, KC_END,  KC_PGDN, KC_DOWN, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS,
        KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS
    ),
    [L_NUM] = LAYOUT_all(
        KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_INS,  KC_NUM,  KC_TRNS, S(KC_9), S(KC_0), S(KC_MINS), KC_TRNS, KC_TRNS, KC_NO,
        KC_CAPS, UG_TOGG, UG_NEXT, UG_HUEU, UG_SATU, UG_VALU, KC_PGUP, KC_P7,   KC_P8,   KC_P9,   KC_PEQL, KC_PMNS, KC_PAST, KC_TRNS,
        KC_TRNS, UG_SPDU, UG_VALU, RGB_MODE_GRADIENT, RGB_MODE_SWIRL, BL_STEP, KC_HOME, KC_P4,   KC_P5,   KC_P6,   KC_END,  KC_PPLS, KC_NO,   KC_TRNS,
        KC_TRNS, KC_VOLD, KC_VOLD, KC_VOLU, KC_MUTE, KC_TRNS, KC_TRNS, KC_PGDN, KC_P1,   KC_P2,   KC_P3,   KC_PSLS, KC_TRNS, KC_TRNS, KC_TRNS,
        KC_TRNS, KC_ENT,  MO(3),   KC_P0,   KC_PDOT, KC_PENT, KC_TRNS, KC_TRNS, KC_TRNS
    ),
    [L_L3] = LAYOUT_all(
        KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS,
        KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS,
        KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_LEFT, KC_DOWN, KC_UP,   KC_RGHT, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS,
        KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS,
        KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS
    ),
};

// ── 逐層底燈換色（rgblight_layers）────────────────────────────────
// 底燈 6× WS2812。基礎層靜態黑(視覺上=關)，按住 MO(1/2/3) 疊上紅/綠/藍，
// 放開自動復原。rgblight 全程保持 enabled —— 顏色層才會 render（不用
// rgblight_disable，那條路之前沒亮過）。
#ifndef RGBLED_NUM
#    define RGBLED_NUM RGBLIGHT_LED_COUNT
#endif

const rgblight_segment_t PROGMEM xd60_fn_layer[]  = RGBLIGHT_LAYER_SEGMENTS({0, RGBLED_NUM, HSV_RED});
const rgblight_segment_t PROGMEM xd60_num_layer[] = RGBLIGHT_LAYER_SEGMENTS({0, RGBLED_NUM, HSV_GREEN});
const rgblight_segment_t PROGMEM xd60_l3_layer[]  = RGBLIGHT_LAYER_SEGMENTS({0, RGBLED_NUM, HSV_BLUE});
const rgblight_segment_t* const PROGMEM xd60_rgb_layers[] = RGBLIGHT_LAYERS_LIST(
    xd60_fn_layer,    // index 0 → L_FN   紅
    xd60_num_layer,   // index 1 → L_NUM  綠
    xd60_l3_layer     // index 2 → L_L3   藍
);

void keyboard_post_init_user(void) {
    rgblight_layers = xd60_rgb_layers;
    rgblight_mode_noeeprom(RGBLIGHT_MODE_STATIC_LIGHT);
    rgblight_sethsv_noeeprom(HSV_BLACK);   // 基礎層底燈關(靜態黑)
}

layer_state_t layer_state_set_user(layer_state_t state) {
    rgblight_set_layer_state(0, layer_state_cmp(state, L_FN));
    rgblight_set_layer_state(1, layer_state_cmp(state, L_NUM));
    rgblight_set_layer_state(2, layer_state_cmp(state, L_L3));
    return state;
}

#pragma once

// 逐層底燈換色（rgblight_layers）— 客製編譯路線才有，Configurator 做不到。
// keymap.c 用 RGBLIGHT_LAYER_SEGMENTS / rgblight_set_layer_state 即依賴此旗標。
#define RGBLIGHT_LAYERS

// WS2812 色序 ── 預設「不要」啟用下行 ──
//
// xiudi/xd60/rev2 的官方定義已是正確色序（見 ../README.md「外部 review 核對紀錄」），
// 故預設沿用 QMK 內建設定，不在此覆寫。
//
// 僅當實機燒錄後顏色對不上（例：RGB_HUI 調成紅卻亮綠 = G/R 對調）時，
// 才取消下行註解改成對應色序，重編譯：
//   #define WS2812_BYTE_ORDER WS2812_BYTE_ORDER_RGB

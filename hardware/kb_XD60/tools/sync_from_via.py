#!/usr/bin/env python3
"""sync_from_via.py — 把 VIA 匯出的 .layout 同步回 repo 並編譯出 .hex。

這支腳本把「VIA 設定 → repo 出廠預設 → 韌體」整條流程自動化，**不需要 AI**：
  1. 讀最新的 VIA .layout（VIA App → Save Current Layout 匯出的檔）
  2. keycode 轉成現行 QMK 名、矩陣序轉成 LAYOUT_all 序
  3. 更新 xd60_qmk_keymap.json + xd60_custom/keymap.c + xd60_via_keymap.layout
  4. 跑 check_keymap_sync.py
  5. qmk 編譯，.hex 複製到 Windows 桌面
之後自己 `git commit` 即可。

用法：
  python3 sync_from_via.py [path/to/file.layout]
不給路徑時，自動抓 OneDrive XD60_VIA/ 裡 mtime 最新的 .layout。

注意：keymap.c 由本腳本「整檔重新產生」—— 上半 keymaps[] 是 VIA 來的鍵位，
下半的 rgblight_layers（逐層底燈換色）是固定區塊。要改底燈顏色 → 改本腳本
KEYMAP_C 模板裡的 HSV_*;別直接手改 keymap.c（會被下次同步覆蓋）。
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

KB = Path(__file__).resolve().parents[1]                         # hardware/kb_XD60
QMK_HOME = Path.home() / "qmk_firmware"
QMK_INFO = QMK_HOME / "keyboards/xiudi/xd60/info.json"
QMK_BIN = Path.home() / ".local/bin/qmk"
QMK_HEX = QMK_HOME / "xiudi_xd60_rev2_xd60_custom.hex"
VIA_DIR = Path("/mnt/c/Users/duofilm/OneDrive - hepei/電腦軟體/XD60鍵盤/XD60_VIA")
DESKTOP = Path("/mnt/c/Users/duofilm/Desktop")

# VIA 舊 keycode 名 → 現行 QMK 名（否則 keymap.c 編不過）
CONV = {
    "KC_MS_BTN1": "MS_BTN1", "KC_MS_BTN2": "MS_BTN2", "KC_MS_BTN3": "MS_BTN3",
    "KC_MS_BTN4": "MS_BTN4", "KC_MS_BTN5": "MS_BTN5",
    "KC_MS_UP": "MS_UP", "KC_MS_DOWN": "MS_DOWN",
    "KC_MS_LEFT": "MS_LEFT", "KC_MS_RIGHT": "MS_RGHT",
    "KC_MS_WH_UP": "MS_WHLU", "KC_MS_WH_DOWN": "MS_WHLD",
    "KC_MS_WH_LEFT": "MS_WHLL", "KC_MS_WH_RIGHT": "MS_WHLR",
    # 更舊的裸名（VIA 通常匯出 KC_MS_* 形式，這幾個是保險，與坑表宣稱一致）
    "KC_MS_U": "MS_UP", "KC_MS_D": "MS_DOWN", "KC_MS_L": "MS_LEFT", "KC_MS_R": "MS_RGHT",
    "KC_BTN1": "MS_BTN1", "KC_BTN2": "MS_BTN2", "KC_BTN3": "MS_BTN3",
    "KC_BTN4": "MS_BTN4", "KC_BTN5": "MS_BTN5",
    "KC_WH_U": "MS_WHLU", "KC_WH_D": "MS_WHLD", "KC_WH_L": "MS_WHLL", "KC_WH_R": "MS_WHLR",
    "KC_NLCK": "KC_NUM", "KC_GESC": "QK_GESC",
    "RGB_TOG": "UG_TOGG", "RGB_MOD": "UG_NEXT", "RGB_RMOD": "UG_PREV",
    "RGB_HUI": "UG_HUEU", "RGB_HUD": "UG_HUED",
    "RGB_SAI": "UG_SATU", "RGB_SAD": "UG_SATD",
    "RGB_VAI": "UG_VALU", "RGB_VAD": "UG_VALD",
    "RGB_SPI": "UG_SPDU", "RGB_SPD": "UG_SPDD",
    "RGB_M_P": "RGB_MODE_PLAIN", "RGB_M_B": "RGB_MODE_BREATHE",
    "RGB_M_R": "RGB_MODE_RAINBOW", "RGB_M_SW": "RGB_MODE_SWIRL",
    "RGB_M_SN": "RGB_MODE_SNAKE", "RGB_M_K": "RGB_MODE_KNIGHT",
    "RGB_M_X": "RGB_MODE_XMAS", "RGB_M_G": "RGB_MODE_GRADIENT",
    "RGB_M_T": "RGB_MODE_RGBTEST", "RGB_M_TW": "RGB_MODE_TWINKLE",
}

KEYMAP_C = '''// XD60 rev2 客製 keymap — QMK + VIA + 逐層底燈換色
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
{L0}
    ),
    [L_FN] = LAYOUT_all(
{L1}
    ),
    [L_NUM] = LAYOUT_all(
{L2}
    ),
    [L_L3] = LAYOUT_all(
{L3}
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
'''

ROW_LENS = [15, 14, 14, 15, 9]


def die(msg):
    sys.exit(f"✗ {msg}")


def find_layout(arg):
    if arg:
        p = Path(arg)
        return p if p.is_file() else die(f"找不到檔案：{p}")
    if not VIA_DIR.is_dir():
        die(f"找不到 VIA 匯出資料夾：{VIA_DIR}")
    cands = sorted(VIA_DIR.glob("*.layout"), key=lambda p: p.stat().st_mtime)
    if not cands:
        die(f"{VIA_DIR} 裡沒有 .layout 檔（先在 VIA 按 Save Current Layout）")
    return cands[-1]


def fmt_layer(layer):
    lines, i = [], 0
    for rl in ROW_LENS:
        row = layer[i:i + rl]
        i += rl
        cells = [t if (i >= 67 and n == len(row) - 1) else t + ","
                 for n, t in enumerate(row)]
        lines.append("        " + " ".join(c.ljust(8) for c in cells).rstrip())
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description="同步 VIA .layout 回 repo 並編譯")
    ap.add_argument("layout", nargs="?", help="VIA .layout 路徑（省略則抓最新的）")
    ap.add_argument("--no-compile", action="store_true", help="只同步，不編譯")
    args = ap.parse_args()

    layout_path = find_layout(args.layout)
    print(f"• 來源 .layout：{layout_path}")

    if not QMK_INFO.is_file():
        die(f"找不到 {QMK_INFO} —— 先跑 ansible-playbook wsl.yml --tags qmk")

    # LAYOUT_all 矩陣順序
    la = json.load(open(QMK_INFO))["layouts"]["LAYOUT_all"]["layout"]
    mat_order = [(k["matrix"][0], k["matrix"][1]) for k in la]
    if len(mat_order) != 67:
        die(f"LAYOUT_all 應為 67 鍵，實際 {len(mat_order)}")

    # VIA .layout（4 層 × 70，矩陣 row-major）
    via = json.load(open(layout_path))["layers"]
    if len(via) != 4 or any(len(l) != 70 for l in via):
        die(f".layout 應為 4 層 × 70，實際 {[len(l) for l in via]}")

    layers = [[CONV.get(vl[r * 14 + c], vl[r * 14 + c]) for (r, c) in mat_order]
              for vl in via]

    # 更新 xd60_qmk_keymap.json
    jp = KB / "xd60_qmk_keymap.json"
    j = json.load(open(jp))
    j["notes"] = "XD60 rev2 - synced from VIA. 4 layers. Standard QMK + VIA."
    j["layers"] = layers
    json.dump(j, open(jp, "w"), indent=2, ensure_ascii=False)
    open(jp, "a").write("\n")
    print(f"• 已更新 {jp.name}")

    # 更新 keymap.c
    out = KEYMAP_C
    for n in range(4):
        out = out.replace("{L%d}" % n, fmt_layer(layers[n]))
    (KB / "xd60_custom" / "keymap.c").write_text(out)
    print("• 已更新 xd60_custom/keymap.c")

    # 更新 repo 內的 .layout 備份
    backup = KB / "xd60_via_keymap.layout"
    if Path(layout_path).resolve() != backup.resolve():
        shutil.copy(layout_path, backup)
        print(f"• 已更新 {backup.name}")

    # sync check
    r = subprocess.run([sys.executable, str(KB / "tests/check_keymap_sync.py")])
    if r.returncode != 0:
        die("sync check 失敗")

    if args.no_compile:
        print("✓ 同步完成（--no-compile，未編譯）")
        return

    # 編譯
    if not QMK_BIN.is_file():
        die(f"找不到 {QMK_BIN}")
    print("• 編譯中…")
    r = subprocess.run([str(QMK_BIN), "compile", "-kb", "xiudi/xd60/rev2",
                        "-km", "xd60_custom"], cwd=QMK_HOME)
    if r.returncode != 0 or not QMK_HEX.is_file():
        die("編譯失敗")

    # 複製 .hex 到桌面
    if DESKTOP.is_dir():
        shutil.copy(QMK_HEX, DESKTOP / "xd60_custom.hex")
        print(f"• .hex 已複製到桌面：{DESKTOP / 'xd60_custom.hex'}")
    else:
        print(f"• .hex 在 {QMK_HEX}（找不到桌面資料夾）")

    print("✓ 全部完成。檢查無誤後 git commit;要更新韌體再用 QMK Toolbox 燒桌面的 .hex。")


if __name__ == "__main__":
    main()

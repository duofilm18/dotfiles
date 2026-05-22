#!/usr/bin/env python3
"""XD60 keymap 同步守門 — regression check。

驗證 xd60_custom/keymap.c 的三層 LAYOUT_all 與唯一真實來源
xd60_qmk_keymap.json 逐鍵一致。任一不符即非零退出。

為什麼要這個檢查（見 ../README.md「外部 review 核對紀錄」）：
keymap 的真實來源是「QMK 官方定義 + 實機 3 層截圖」，外部 AI 無實機時會
幻覺出錯誤硬體定義。客製編譯路線多了一份手寫 keymap.c，這支腳本確保它
不會悄悄偏離 JSON。改 keymap 時：先改 JSON，再同步 keymap.c，跑此檢查。

用法：  python3 hardware/kb_XD60/tests/check_keymap_sync.py
"""

import json
import re
import sys
from pathlib import Path

KB_DIR = Path(__file__).resolve().parent.parent
JSON_PATH = KB_DIR / "xd60_qmk_keymap.json"
KEYMAP_C = KB_DIR / "xd60_custom" / "keymap.c"
KEYS_PER_LAYER = 67
LAYER_COUNT = 4


def strip_comments(src: str) -> str:
    """移除 C 的 // 行註解與 /* */ 區塊註解。"""
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.DOTALL)
    src = re.sub(r"//[^\n]*", "", src)
    return src


def extract_layout_blocks(src: str) -> list[str]:
    """抓出每個 LAYOUT_all( ... ) 的括號平衡內容。"""
    blocks, marker, i = [], "LAYOUT_all(", 0
    while (idx := src.find(marker, i)) != -1:
        start = idx + len(marker)
        depth, j = 1, start
        while depth > 0:
            if src[j] == "(":
                depth += 1
            elif src[j] == ")":
                depth -= 1
            j += 1
        blocks.append(src[start : j - 1])
        i = j
    return blocks


def tokenize(body: str) -> list[str]:
    """以深度 0 的逗號切 token；MO(1) 這類含括號的 token 不會被切開。"""
    tokens, depth, cur = [], 0, ""
    for c in body:
        if c == "(":
            depth += 1
            cur += c
        elif c == ")":
            depth -= 1
            cur += c
        elif c == "," and depth == 0:
            tokens.append(cur)
            cur = ""
        else:
            cur += c
    if cur.strip():
        tokens.append(cur)
    return ["".join(t.split()) for t in tokens]  # 去掉所有空白


def main() -> int:
    if not JSON_PATH.exists() or not KEYMAP_C.exists():
        print(f"FAIL: 找不到 {JSON_PATH} 或 {KEYMAP_C}", file=sys.stderr)
        return 1

    json_layers = json.loads(JSON_PATH.read_text())["layers"]
    json_layers = [["".join(k.split()) for k in layer] for layer in json_layers]

    blocks = extract_layout_blocks(strip_comments(KEYMAP_C.read_text()))
    c_layers = [tokenize(b) for b in blocks]

    errors = []
    if len(c_layers) != LAYER_COUNT:
        errors.append(f"keymap.c 有 {len(c_layers)} 個 LAYOUT_all，應為 {LAYER_COUNT}")
    if len(json_layers) != LAYER_COUNT:
        errors.append(f"JSON 有 {len(json_layers)} 層，應為 {LAYER_COUNT}")

    for n in range(min(len(c_layers), len(json_layers))):
        cl, jl = c_layers[n], json_layers[n]
        if len(cl) != KEYS_PER_LAYER:
            errors.append(f"Layer {n}: keymap.c 有 {len(cl)} 鍵，應為 {KEYS_PER_LAYER}")
        if len(jl) != KEYS_PER_LAYER:
            errors.append(f"Layer {n}: JSON 有 {len(jl)} 鍵，應為 {KEYS_PER_LAYER}")
        for pos, (c, j) in enumerate(zip(cl, jl)):
            if c != j:
                errors.append(f"Layer {n} 第 {pos} 鍵不符：keymap.c={c!r} JSON={j!r}")

    if errors:
        print("FAIL: keymap.c 與 xd60_qmk_keymap.json 不同步", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    print(f"OK: keymap.c 與 JSON 同步（{LAYER_COUNT} 層 × {KEYS_PER_LAYER} 鍵）")
    return 0


if __name__ == "__main__":
    sys.exit(main())

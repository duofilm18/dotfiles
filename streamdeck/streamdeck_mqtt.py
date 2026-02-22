#!/usr/bin/env python3
"""Stream Deck MQTT Monitor - 顯示 Claude Code hook 狀態

訂閱 RPi5B 的 MQTT broker，將多個 Claude Code instance 的狀態
顯示在 Stream Deck 不同按鍵上。自動依專案資料夾名稱分配按鍵。

需在 Windows 上執行（Stream Deck USB 接在 Windows）。
"""

import json
import os
import sys
from pathlib import Path

# hidapi.dll 搜尋：優先從腳本同目錄載入
_script_dir = str(Path(__file__).parent)
if sys.platform == "win32":
    os.add_dll_directory(_script_dir)

import paho.mqtt.client as mqtt
from PIL import Image, ImageDraw, ImageFont
from StreamDeck.DeviceManager import DeviceManager
from StreamDeck.ImageHelpers import PILHelper

# --- 設定 ---

CONFIG_PATH = Path(__file__).parent / "config.json"
with open(CONFIG_PATH, encoding="utf-8") as f:
    config = json.load(f)

# --- 狀態顯示對照表 ---
# bg: 按鍵背景色, fg: 文字色
# 顏色對齊 wsl/led-effects.json，completed 用綠色替代黑色（按鍵上黑色=關閉）

STATE_DISPLAY = {
    "idle":      {"label": "IDLE",    "bg": (255, 13,  0),   "fg": (255, 255, 255)},
    "running":   {"label": "RUNNING", "bg": (0,   0,   255), "fg": (255, 255, 255)},
    "waiting":   {"label": "WAITING", "bg": (255, 255, 0),   "fg": (0,   0,   0)},
    "completed": {"label": "DONE",    "bg": (0,   180, 0),   "fg": (255, 255, 255)},
    "error":     {"label": "ERROR",   "bg": (255, 0,   0),   "fg": (255, 255, 255)},
    "off":       {"label": "OFF",     "bg": (30,  30,  30),  "fg": (128, 128, 128)},
}
UNKNOWN_DISPLAY = {"label": "?", "bg": (50, 50, 50), "fg": (200, 200, 200)}

# --- 全域變數 ---

_deck = None
_button_start = 0       # 起始按鍵 index
_max_projects = 8       # 最多顯示幾個專案
_projects = {}          # project_name → button_index
_next_button = 0        # 下一個可用的按鍵 index


def _load_font(size):
    """載入字型，Windows 用 arial.ttf，找不到就用預設。"""
    try:
        return ImageFont.truetype("arial.ttf", size)
    except IOError:
        return ImageFont.load_default()


def render_button(deck, key_index, project_name, state_info):
    """產生按鍵圖片並推送到 Stream Deck。"""
    image = PILHelper.create_key_image(deck)
    draw = ImageDraw.Draw(image)
    w, h = image.size

    # 背景
    draw.rectangle([(0, 0), (w, h)], fill=state_info["bg"])

    # 上方：專案名稱（截斷顯示）
    font_small = _load_font(11)
    label = project_name[:10]
    draw.text((w // 2, h // 4), label, font=font_small,
              fill=state_info["fg"], anchor="mm")

    # 中央：狀態
    font_large = _load_font(18)
    draw.text((w // 2, h // 2 + 5), state_info["label"], font=font_large,
              fill=state_info["fg"], anchor="mm")

    native = PILHelper.to_native_key_format(deck, image)
    deck.set_key_image(key_index, native)


def _get_button_for_project(project_name):
    """取得專案對應的按鍵 index，新專案自動分配下一個。"""
    global _next_button

    if project_name in _projects:
        return _projects[project_name]

    if _next_button >= _max_projects:
        return None  # 按鍵已滿

    idx = _button_start + _next_button
    _projects[project_name] = idx
    _next_button += 1
    print(f"  Key {idx} → {project_name}")
    return idx


# --- MQTT callbacks ---

def on_connect(client, userdata, flags, rc):
    # 訂閱 claude/led/# 接收所有專案的狀態
    client.subscribe("claude/led/+")
    print(f"MQTT connected (rc={rc}), subscribed to claude/led/+")


def on_message(client, userdata, msg):
    try:
        data = json.loads(msg.payload.decode())
    except (json.JSONDecodeError, UnicodeDecodeError):
        return

    # 從 topic 取得專案名稱: claude/led/{project}
    parts = msg.topic.split("/")
    if len(parts) != 3:
        return
    project_name = parts[2]

    state = data.get("state", "").lower()
    state_info = STATE_DISPLAY.get(state, UNKNOWN_DISPLAY)

    button_idx = _get_button_for_project(project_name)
    if button_idx is None:
        return

    if _deck and _deck.is_open():
        with _deck:
            render_button(_deck, button_idx, project_name, state_info)


# --- 主程式 ---

def main():
    global _deck, _button_start, _max_projects

    # Stream Deck 初始化
    decks = DeviceManager().enumerate()
    if not decks:
        print("No Stream Deck found. Check:")
        print("  1. hidapi.dll is in PATH")
        print("  2. Official Stream Deck software is closed")
        print("  3. Device is connected via USB")
        return

    _deck = decks[0]
    _deck.open()
    _deck.set_brightness(config.get("deck_brightness", 30))
    _button_start = config.get("claude_button_index", 0)
    _max_projects = config.get("max_projects", 8)

    print(f"Stream Deck: {_deck.deck_type()} ({_deck.key_count()} keys)")
    print(f"Claude buttons: Key {_button_start} ~ {_button_start + _max_projects - 1}")

    # MQTT 連線
    broker = config.get("mqtt_broker", "192.168.88.10")
    port = config.get("mqtt_port", 1883)

    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(broker, port, 60)

    print(f"Connecting to MQTT {broker}:{port}...")

    try:
        client.loop_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        _deck.reset()
        _deck.close()


if __name__ == "__main__":
    main()

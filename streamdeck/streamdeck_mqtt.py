#!/usr/bin/env python3
"""Stream Deck MQTT Monitor - 顯示 Claude Code hook 狀態

訂閱 RPi5B 的 MQTT broker，將 claude/led 狀態顯示在 Stream Deck 按鍵上。
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
_button_index = 0


def _load_font(size):
    """載入字型，Windows 用 arial.ttf，找不到就用預設。"""
    try:
        return ImageFont.truetype("arial.ttf", size)
    except IOError:
        return ImageFont.load_default()


def render_button(deck, key_index, state_info):
    """產生按鍵圖片並推送到 Stream Deck。"""
    image = PILHelper.create_key_image(deck)
    draw = ImageDraw.Draw(image)
    w, h = image.size

    # 背景
    draw.rectangle([(0, 0), (w, h)], fill=state_info["bg"])

    # 上方標題
    font_small = _load_font(11)
    draw.text((w // 2, h // 4), "CLAUDE", font=font_small,
              fill=state_info["fg"], anchor="mm")

    # 中央狀態
    font_large = _load_font(18)
    draw.text((w // 2, h // 2 + 5), state_info["label"], font=font_large,
              fill=state_info["fg"], anchor="mm")

    native = PILHelper.to_native_key_format(deck, image)
    deck.set_key_image(key_index, native)


# --- MQTT callbacks ---

def on_connect(client, userdata, flags, rc):
    topic = config.get("mqtt_topic", "claude/led")
    client.subscribe(topic)
    print(f"MQTT connected (rc={rc}), subscribed to {topic}")


def on_message(client, userdata, msg):
    try:
        data = json.loads(msg.payload.decode())
    except (json.JSONDecodeError, UnicodeDecodeError):
        return

    state = data.get("state", "").lower()
    state_info = STATE_DISPLAY.get(state, UNKNOWN_DISPLAY)

    if _deck and _deck.is_open():
        with _deck:
            render_button(_deck, _button_index, state_info)


# --- 主程式 ---

def main():
    global _deck, _button_index

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
    _button_index = config.get("claude_button_index", 0)

    print(f"Stream Deck: {_deck.deck_type()} ({_deck.key_count()} keys)")

    # 初始按鍵：等待 MQTT 訊息
    with _deck:
        render_button(_deck, _button_index, UNKNOWN_DISPLAY)

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

#!/usr/bin/env python3
"""Stream Deck MQTT Monitor - 顯示 Claude Code hook 狀態

訂閱 RPi5B 的 MQTT broker，將多個 Claude Code instance 的狀態
顯示在 Stream Deck 不同按鍵上。自動依專案資料夾名稱分配按鍵。

需在 Windows 上執行（Stream Deck USB 接在 Windows）。
"""

import json
import os
import subprocess
import sys
import threading
import time
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

# 閃爍時的交替顯示（白底）
BLINK_DISPLAY = {
    "idle":    {"label": "IDLE",    "bg": (255, 255, 255), "fg": (255, 13,  0)},
    "waiting": {"label": "WAITING", "bg": (255, 255, 255), "fg": (200, 180, 0)},
}

# --- 全域變數 ---

_deck = None
_button_start = 0       # 起始按鍵 index
_max_projects = 8       # 最多顯示幾個專案
_projects = {}          # project_name → button_index
_project_states = {}    # project_name → state string
_next_button = 0        # 下一個可用的按鍵 index
_free_buttons = []      # 已釋放的 slot，可被新專案重用
_blink_on = False       # 閃爍切換旗標


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
    title_size = config.get("font_size_title", 11)
    font_small = _load_font(title_size)
    label = project_name[:10]
    draw.text((w // 2, h // 4), label, font=font_small,
              fill=state_info["fg"], anchor="mm")

    # 中央：狀態
    state_size = config.get("font_size_state", 18)
    font_large = _load_font(state_size)
    draw.text((w // 2, h // 2 + 5), state_info["label"], font=font_large,
              fill=state_info["fg"], anchor="mm")

    native = PILHelper.to_native_key_format(deck, image)
    deck.set_key_image(key_index, native)


def _get_button_for_project(project_name):
    """取得專案對應的按鍵 index，新專案自動分配下一個（優先重用已釋放 slot）。"""
    global _next_button

    if project_name in _projects:
        return _projects[project_name]

    # 優先使用已釋放的 slot
    if _free_buttons:
        idx = _free_buttons.pop(0)
        _projects[project_name] = idx
        print(f"  Key {idx} → {project_name} (reused)")
        return idx

    if _next_button >= _max_projects:
        return None  # 按鍵已滿

    idx = _button_start + _next_button
    _projects[project_name] = idx
    _next_button += 1
    print(f"  Key {idx} → {project_name}")
    return idx


def _remove_project(project_name):
    """移除專案：清除按鍵畫面、釋放 slot 供新專案重用。"""
    if project_name not in _projects:
        return

    button_idx = _projects.pop(project_name)
    _project_states.pop(project_name, None)
    _free_buttons.append(button_idx)

    # 清除按鍵畫面（顯示為關閉狀態）
    if _deck and _deck.is_open():
        try:
            with _deck:
                render_button(_deck, button_idx, "", STATE_DISPLAY["off"])
        except Exception:
            pass

    print(f"  Key {button_idx} ← {project_name} (removed)")


# --- 按鍵回調 ---

def _reverse_lookup(button_idx):
    """從按鍵 index 反查專案名稱。"""
    for name, idx in _projects.items():
        if idx == button_idx:
            return name
    return None


def on_key_press(deck, key, state):
    """按下按鍵時切換到對應的 tmux session 並拉起 Windows Terminal。"""
    if not state:  # key release, ignore
        return

    project = _reverse_lookup(key)
    if not project:
        return

    try:
        # 1. 找到 @project 匹配的 tmux window 並切換
        #    Claude Code 跑在同一 session 的不同 window，用 @project 標記
        cmd = (
            f"idx=$(tmux list-windows -F '#{{window_index}} #{{@project}}'"
            f" | grep ' {project}$' | head -1 | cut -d' ' -f1)"
            f" && [ -n \"$idx\" ] && tmux select-window -t :$idx"
        )
        subprocess.Popen(
            ["wsl.exe", "bash", "-c", cmd],
            creationflags=0x08000000 if sys.platform == "win32" else 0,
        )
        # 2. 把 Windows Terminal 拉到前景
        subprocess.Popen(
            ["powershell.exe", "-WindowStyle", "Hidden", "-Command",
             "(New-Object -ComObject WScript.Shell).AppActivate('Terminal')"],
            creationflags=0x08000000 if sys.platform == "win32" else 0,
        )
        print(f"  Switching to tmux window: {project}")
    except Exception as e:
        print(f"  Switch failed: {e}")


# --- 閃爍 timer ---

def blink_loop():
    """每秒切換 idle/waiting 按鍵的顯示（狀態色 ↔ 白色）。"""
    global _blink_on
    while True:
        time.sleep(1)
        _blink_on = not _blink_on
        if not (_deck and _deck.is_open()):
            continue
        for project_name, button_idx in list(_projects.items()):
            state = _project_states.get(project_name, "")
            if state not in BLINK_DISPLAY:
                continue
            if _blink_on:
                info = BLINK_DISPLAY[state]
            else:
                info = STATE_DISPLAY[state]
            try:
                with _deck:
                    render_button(_deck, button_idx, project_name, info)
            except Exception:
                break  # deck 斷線，等 reconnect


# --- MQTT callbacks ---

def on_connect(client, userdata, flags, rc):
    # 訂閱 claude/led/# 接收所有專案的狀態
    client.subscribe("claude/led/+")
    print(f"MQTT connected (rc={rc}), subscribed to claude/led/+")


def on_message(client, userdata, msg):
    # 從 topic 取得專案名稱: claude/led/{project}
    parts = msg.topic.split("/")
    if len(parts) != 3:
        return
    project_name = parts[2]

    # 空 payload = 專案已關閉，清除按鍵
    if not msg.payload:
        _remove_project(project_name)
        return

    try:
        data = json.loads(msg.payload.decode())
    except (json.JSONDecodeError, UnicodeDecodeError):
        return

    state = data.get("state", "").lower()
    _project_states[project_name] = state
    state_info = STATE_DISPLAY.get(state, UNKNOWN_DISPLAY)

    button_idx = _get_button_for_project(project_name)
    if button_idx is None:
        return

    if _deck and _deck.is_open():
        try:
            with _deck:
                render_button(_deck, button_idx, project_name, state_info)
        except Exception:
            pass  # deck 斷線，等 reconnect


# --- Stream Deck 連線管理 ---

def open_deck():
    """開啟 Stream Deck，找不到回傳 None。"""
    global _deck
    try:
        decks = DeviceManager().enumerate()
        if not decks:
            return None
        _deck = decks[0]
        _deck.open()
        _deck.set_brightness(config.get("deck_brightness", 30))
        _deck.set_key_callback(on_key_press)
        print(f"Stream Deck: {_deck.deck_type()} ({_deck.key_count()} keys)")
        return _deck
    except Exception as e:
        print(f"  Deck open failed: {e}")
        return None


def rerender_all():
    """重連後重新繪製所有已知按鍵。"""
    if not (_deck and _deck.is_open()):
        return
    for project_name, button_idx in list(_projects.items()):
        state = _project_states.get(project_name, "")
        state_info = STATE_DISPLAY.get(state, UNKNOWN_DISPLAY)
        try:
            with _deck:
                render_button(_deck, button_idx, project_name, state_info)
        except Exception:
            break


def reconnect_loop():
    """背景 thread：偵測 USB 斷線，自動重連 + 重繪。"""
    while True:
        time.sleep(3)
        if _deck is None:
            continue
        try:
            if _deck.is_open():
                continue
        except Exception:
            pass
        # deck 斷線，嘗試重連
        print("Stream Deck disconnected, reconnecting...")
        while True:
            if open_deck():
                print("Stream Deck reconnected!")
                rerender_all()
                break
            time.sleep(3)


# --- 主程式 ---

def main():
    global _button_start, _max_projects

    _button_start = config.get("claude_button_index", 0)
    _max_projects = config.get("max_projects", 8)

    # Stream Deck 初始化（等到接上為止）
    print("Waiting for Stream Deck...")
    while not open_deck():
        time.sleep(3)
    print(f"Claude buttons: Key {_button_start} ~ {_button_start + _max_projects - 1}")

    # 背景 threads
    threading.Thread(target=blink_loop, daemon=True).start()
    threading.Thread(target=reconnect_loop, daemon=True).start()

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
        if _deck:
            try:
                _deck.reset()
                _deck.close()
            except Exception:
                pass


if __name__ == "__main__":
    main()

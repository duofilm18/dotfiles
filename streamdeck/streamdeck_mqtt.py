#!/usr/bin/env python3
"""Stream Deck MQTT Monitor - 顯示 Claude Code hook 狀態

訂閱 RPi5B 的 MQTT broker，將多個 Claude Code instance 的狀態
顯示在 Stream Deck 不同按鍵上。自動依專案資料夾名稱分配按鍵。

支援 Windows（USB 直連）和 WSL（usbipd 轉發）。
"""

import json
import logging
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

log = logging.getLogger(__name__)

# hidapi.dll 搜尋：優先從腳本同目錄載入（僅 Windows）
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

_state_lock = threading.Lock()
_deck = None
_button_start = 0       # 起始按鍵 index
_max_projects = 8       # 最多顯示幾個專案
_projects = {}          # project_name → button_index
_project_states = {}    # project_name → state string
_next_button = 0        # 下一個可用的按鍵 index
_free_buttons = []      # 已釋放的 slot，可被新專案重用
_blink_on = False       # 閃爍切換旗標
_date_button_index = -1 # 日期按鍵 index（-1 = 停用）
_last_date = ""         # 上次渲染的日期，用於偵測跨日
_rebuilding = False     # Rebuild Phase：MQTT 重連時先收集 cache，最後 batch render
_rebuild_timer = None   # Rebuild 完成的 debounce timer

DATE_DISPLAY = {"label": "", "bg": (40, 40, 40), "fg": (255, 255, 255)}

_IS_WSL = sys.platform != "win32"
_CREATE_NO_WINDOW = 0x08000000 if sys.platform == "win32" else 0


def _load_font(size, bold=False):
    """載入字型，跨平台支援。"""
    if sys.platform == "win32":
        name = "arialbd.ttf" if bold else "arial.ttf"
    else:
        name = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold \
            else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    try:
        return ImageFont.truetype(name, size)
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
    title_size = config.get("font_size_title", 16)
    font_small = _load_font(title_size)
    label = project_name[:10]
    draw.text((w // 2, h // 4), label, font=font_small,
              fill=state_info["fg"], anchor="mm")

    # 中央：狀態（粗體）
    state_size = config.get("font_size_state", 18)
    font_large = _load_font(state_size, bold=True)
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
    _next_button += 1
    # 跳過日期按鍵
    if idx == _date_button_index:
        if _next_button >= _max_projects:
            return None
        idx = _button_start + _next_button
        _next_button += 1

    _projects[project_name] = idx
    print(f"  Key {idx} → {project_name}")
    return idx


def render_date_button():
    """渲染日期按鍵，顯示 YYYYMMDD（上下兩行）。"""
    global _last_date
    with _state_lock:
        deck_ref = _deck
    if _date_button_index < 0 or not (deck_ref and deck_ref.is_open()):
        return
    today = time.strftime("%Y%m%d")
    _last_date = today
    try:
        image = PILHelper.create_key_image(deck_ref)
        draw = ImageDraw.Draw(image)
        w, h = image.size
        draw.rectangle([(0, 0), (w, h)], fill=DATE_DISPLAY["bg"])
        font = _load_font(config.get("font_size_date", 32), bold=True)
        # YYYY 上方、MMDD 下方
        draw.text((w // 2, h // 3), today[:4], font=font,
                  fill=DATE_DISPLAY["fg"], anchor="mm")
        draw.text((w // 2, h * 2 // 3), today[4:], font=font,
                  fill=DATE_DISPLAY["fg"], anchor="mm")
        native = PILHelper.to_native_key_format(deck_ref, image)
        with deck_ref:
            deck_ref.set_key_image(_date_button_index, native)
    except Exception:
        log.debug("render_date_button failed", exc_info=True)


def _remove_project(project_name):
    """移除專案：清除按鍵畫面、釋放 slot 供新專案重用。"""
    with _state_lock:
        if project_name not in _projects:
            return
        button_idx = _projects.pop(project_name)
        _project_states.pop(project_name, None)
        _free_buttons.append(button_idx)
        rebuilding = _rebuilding
        deck_ref = _deck

    # Rebuild 中不碰硬體，等 batch render 統一處理
    if not rebuilding and deck_ref and deck_ref.is_open():
        try:
            with deck_ref:
                render_button(deck_ref, button_idx, "", STATE_DISPLAY["off"])
        except Exception:
            log.debug("_remove_project render failed", exc_info=True)

    print(f"  Key {button_idx} ← {project_name} (removed)")


# --- 按鍵回調 ---

def _reverse_lookup(button_idx):
    """從按鍵 index 反查專案名稱。"""
    with _state_lock:
        for name, idx in _projects.items():
            if idx == button_idx:
                return name
    return None


def _run_powershell(command):
    """呼叫 powershell.exe（Windows 直接呼叫，WSL 透過 interop）。"""
    subprocess.Popen(
        ["powershell.exe", "-WindowStyle", "Hidden", "-Command", command],
        creationflags=_CREATE_NO_WINDOW,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def on_key_press(deck, key, state):
    """按下按鍵時切換到對應的 tmux session 並拉起 Windows Terminal。"""
    if not state:  # key release, ignore
        return

    if key == _date_button_index:
        # 按下日期按鍵 → 輸入今天日期 YYYYMMDD
        today = time.strftime("%Y%m%d")
        _run_powershell(
            f"Set-Clipboard -Value '{today}'; "
            "Add-Type -AssemblyName System.Windows.Forms; "
            "[System.Windows.Forms.SendKeys]::SendWait('^v')"
        )
        print(f"  Date typed: {today}")
        return

    project = _reverse_lookup(key)
    if not project:
        return

    try:
        # 1. 切換 tmux window
        cmd = (
            f"idx=$(tmux list-windows -F '#{{window_index}} #{{@project}}'"
            f" | grep ' {project}$' | head -1 | cut -d' ' -f1)"
            f" && [ -n \"$idx\" ] && tmux select-window -t :$idx"
        )
        if _IS_WSL:
            subprocess.Popen(["bash", "-c", cmd],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            subprocess.Popen(["wsl.exe", "bash", "-c", cmd],
                             creationflags=_CREATE_NO_WINDOW)

        # 2. 把 Windows Terminal 拉到前景
        _run_powershell(
            "(New-Object -ComObject WScript.Shell).AppActivate('Terminal')"
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
        with _state_lock:
            if _rebuilding:
                continue
            snapshot = list(_projects.items())
            states = dict(_project_states)
            deck_ref = _deck
        if not (deck_ref and deck_ref.is_open()):
            continue
        # 跨日更新日期按鍵
        if _date_button_index >= 0 and time.strftime("%Y%m%d") != _last_date:
            render_date_button()
        for project_name, button_idx in snapshot:
            state = states.get(project_name, "")
            if state not in BLINK_DISPLAY:
                continue
            if _blink_on:
                info = BLINK_DISPLAY[state]
            else:
                info = STATE_DISPLAY[state]
            try:
                with deck_ref:
                    render_button(deck_ref, button_idx, project_name, info)
            except Exception:
                log.debug("blink_loop render failed", exc_info=True)
                break  # deck 斷線，等 reconnect


# --- MQTT callbacks ---

def _finish_rebuild():
    """Rebuild Phase 完成：從 cache 一次性 batch render 所有按鍵。"""
    global _rebuilding
    with _state_lock:
        _rebuilding = False
        snapshot = list(_projects.items())
        states = dict(_project_states)
        deck_ref = _deck
    if deck_ref and deck_ref.is_open():
        _clear_all_buttons(deck_ref)
        render_date_button()
        _rerender_from_snapshot(deck_ref, snapshot, states)
    print(f"  Rebuild complete: {len(snapshot)} projects")


def on_connect(client, userdata, flags, rc, properties=None):
    # Retained Snapshot Rebuild：reconnect = cold start
    # 清空 cache，訂閱後收集 retained 訊息，debounce 後 batch render
    global _next_button, _rebuilding, _rebuild_timer
    with _state_lock:
        _rebuilding = True
        if _rebuild_timer:
            _rebuild_timer.cancel()
        _projects.clear()
        _project_states.clear()
        _free_buttons.clear()
        _next_button = 0
        # Fallback：若 broker 無 retained 訊息，1 秒後仍完成 rebuild
        _rebuild_timer = threading.Timer(1.0, _finish_rebuild)
        _rebuild_timer.start()
    client.subscribe("claude/led/+")
    print(f"MQTT connected (rc={rc}), rebuilding...")


def on_message(client, userdata, msg):
    global _rebuild_timer
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

    with _state_lock:
        _project_states[project_name] = state
        button_idx = _get_button_for_project(project_name)
        if button_idx is None:
            return
        rebuilding = _rebuilding
        if rebuilding:
            # Rebuild Phase：只更新 cache，debounce 後 batch render
            if _rebuild_timer:
                _rebuild_timer.cancel()
            _rebuild_timer = threading.Timer(0.3, _finish_rebuild)
            _rebuild_timer.start()
            return
        deck_ref = _deck

    # 正常運作：逐訊息即時 render（lock 外）
    state_info = STATE_DISPLAY.get(state, UNKNOWN_DISPLAY)
    if deck_ref and deck_ref.is_open():
        try:
            with deck_ref:
                render_button(deck_ref, button_idx, project_name, state_info)
        except Exception:
            log.debug("on_message render failed", exc_info=True)


# --- Stream Deck 連線管理 ---

def _clear_all_buttons(deck):
    """清空所有按鍵畫面（純被動顯示器：啟動 = 空白）。"""
    off = STATE_DISPLAY["off"]
    for key in range(deck.key_count()):
        try:
            render_button(deck, key, "", off)
        except Exception:
            break


def open_deck(reset_state=True):
    """開啟 Stream Deck，找不到回傳 None。

    reset_state=True: 首次啟動，清空內部狀態等 MQTT retained 重建。
    reset_state=False: USB 重連，保留內部狀態只重設硬體。
    """
    global _deck, _next_button
    try:
        decks = DeviceManager().enumerate()
        if not decks:
            return None
        new_deck = decks[0]
        new_deck.open()
        new_deck.set_brightness(config.get("deck_brightness", 30))
        new_deck.set_key_callback(on_key_press)
        _clear_all_buttons(new_deck)
        with _state_lock:
            _deck = new_deck
            if reset_state:
                _projects.clear()
                _project_states.clear()
                _free_buttons.clear()
                _next_button = 0
        render_date_button()
        print(f"Stream Deck: {new_deck.deck_type()} ({new_deck.key_count()} keys)")
        return new_deck
    except Exception as e:
        print(f"  Deck open failed: {e}")
        return None


def _rerender_from_snapshot(deck_ref, snapshot, states):
    """用 snapshot 重繪所有按鍵（lock 外呼叫，不阻塞 USB I/O）。"""
    for project_name, button_idx in snapshot:
        state = states.get(project_name, "")
        state_info = STATE_DISPLAY.get(state, UNKNOWN_DISPLAY)
        try:
            with deck_ref:
                render_button(deck_ref, button_idx, project_name, state_info)
        except Exception:
            log.debug("_rerender_from_snapshot failed", exc_info=True)
            break


def rerender_all():
    """重連後重新繪製所有已知按鍵。"""
    with _state_lock:
        snapshot = list(_projects.items())
        states = dict(_project_states)
        deck_ref = _deck
    if not (deck_ref and deck_ref.is_open()):
        return
    render_date_button()
    _rerender_from_snapshot(deck_ref, snapshot, states)


def reconnect_loop():
    """背景 thread：偵測 USB 斷線，自動重連 + 重繪。"""
    while True:
        time.sleep(3)
        with _state_lock:
            deck_ref = _deck
        if deck_ref is None:
            continue
        try:
            if deck_ref.is_open():
                continue
        except Exception:
            pass
        # deck 斷線，嘗試重連
        print("Stream Deck disconnected, reconnecting...")
        while True:
            if open_deck(reset_state=False):
                print("Stream Deck reconnected!")
                rerender_all()
                break
            time.sleep(3)


# --- Singleton：啟動時砍掉舊進程 ---

_PID_FILE = Path(__file__).parent / "streamdeck_mqtt.pid"


def _kill_stale_instances():
    """讀 PID file，砍掉舊進程，寫入自己的 PID。"""
    if _PID_FILE.exists():
        try:
            old_pid = int(_PID_FILE.read_text().strip())
            if old_pid != os.getpid():
                os.kill(old_pid, signal.SIGTERM)
                print(f"  Killed stale process (PID {old_pid})")
                time.sleep(1)  # 等舊進程釋放 USB
        except (ValueError, ProcessLookupError, PermissionError):
            pass  # PID 無效或進程已不存在
    _PID_FILE.write_text(str(os.getpid()))


# --- 主程式 ---

def main():
    global _button_start, _max_projects

    _kill_stale_instances()

    _button_start = config.get("claude_button_index", 0)
    _max_projects = config.get("max_projects", 8)
    global _date_button_index
    _date_button_index = config.get("date_button_index", -1)

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

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
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
                log.debug("Deck cleanup failed", exc_info=True)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""MQTT LED Service - gpiozero 版

使用 gpiozero RGBLED 控制 GPIO，內建平滑轉場、自動執行緒管理。
手刻 PWM 迴圈全部移除，改用 gpiozero 內建 blink/pulse。

Topics:
    claude/led     - RGB LED 控制 {domain, state, project}
                     Consumer 查本地 led-effects.json 映射表翻譯成硬體指令
                     pattern: blink, solid, pulse, rainbow
    claude/buzzer  - 蜂鳴器控制 {frequency, duration}
    claude/melody  - 旋律播放 {name: "zelda_secret"}

Watchdog:
    透過 sd_notify 通知 systemd watchdog，防止服務卡住。
"""

import json
import os
import socket
import threading
import time
from pathlib import Path

import lgpio
from gpiozero import RGBLED
from gpiozero.pins.lgpio import LGPIOFactory
import paho.mqtt.client as mqtt

from melodies import MELODIES

# 載入設定
config_path = Path(__file__).parent / "config.json"
with open(config_path) as f:
    config = json.load(f)

# 載入 LED 效果映射表（domain-keyed）
_effects_path = Path(__file__).parent / "led-effects.json"
with open(_effects_path) as f:
    _effects = json.load(f)

gpio = config["gpio"]
COMMON_ANODE = config.get("common_anode", True)
GPIO_CHIP = config.get("gpio_chip", 0)

# RGB LED（gpiozero 處理 PWM、執行緒、共陽極反轉）
# 明確指定 chip，避免 gpiozero 自動偵測 RPi5 時用錯 chip 編號（Armbian 用 0，RPi OS 用 4）
_factory = LGPIOFactory(chip=GPIO_CHIP)
led = RGBLED(
    red=gpio["red"],
    green=gpio["green"],
    blue=gpio["blue"],
    active_high=not COMMON_ANODE,
    pin_factory=_factory,
)

# 蜂鳴器（lgpio 直接控制，不受頻率範圍限制）
# 啟動時設為輸入模式（高阻抗），避免底噪；播放時才切輸出
_h = lgpio.gpiochip_open(GPIO_CHIP)
_buzzer_pin = gpio["buzzer"]
lgpio.gpio_claim_input(_h, _buzzer_pin)

# rainbow / solid timer 的取消機制
_cancel = threading.Event()
_off_timer = None
_melody_cancel = threading.Event()  # 旋律中斷機制
_last_led_payload = ""  # LED 去重：相同 payload 不重複執行

# ── domain 優先權（IME 2 秒中斷）──
_IME_INTERRUPT_SECS = 2.0
_last_domain_state = {}   # {domain: {state, project}}
_ime_timer = None
_ime_active = False

_RAINBOW_COLORS = [
    (1, 0, 0),  # 紅
    (1, 1, 0),  # 黃
    (0, 1, 0),  # 綠
    (0, 1, 1),  # 青
    (0, 0, 1),  # 藍
    (1, 0, 1),  # 紫
    (1, 1, 1),  # 白
]


# ─── systemd watchdog ──────────────────────────────────

def _sd_notify(state: str):
    """Send notification to systemd (sd_notify protocol)."""
    addr = os.environ.get("NOTIFY_SOCKET")
    if not addr:
        return
    if addr.startswith("@"):
        addr = "\0" + addr[1:]
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        sock.sendto(state.encode(), addr)
        sock.close()
    except OSError:
        pass


def _watchdog_loop():
    """Periodically ping systemd watchdog."""
    while True:
        _sd_notify("WATCHDOG=1")
        time.sleep(25)  # WatchdogSec=60, ping every 25s


# ─── LED effects ───────────────────────────────────────

def _stop_custom():
    """停止自訂效果（rainbow / solid timer）"""
    global _off_timer
    _cancel.set()
    if _off_timer:
        _off_timer.cancel()
        _off_timer = None


def _run_rainbow(times, interval):
    """彩虹：七色輪流，結束後自動關燈"""
    _cancel.clear()
    for _ in range(times):
        for color in _RAINBOW_COLORS:
            if _cancel.is_set():
                return
            led.color = color
            if _cancel.wait(timeout=interval):
                return
    led.off()


def _run_effect(r, g, b, pattern, times, duration, interval):
    """根據 pattern 執行燈效，gpiozero 自動處理轉場"""
    _stop_custom()

    if pattern == "solid":
        led.color = (r, g, b)
        if duration > 0:
            global _off_timer
            _off_timer = threading.Timer(duration, led.off)
            _off_timer.start()

    elif pattern == "blink":
        led.blink(
            on_time=interval,
            off_time=interval,
            on_color=(r, g, b),
            off_color=(0, 0, 0),
            n=times if times < 999 else None,
            background=True,
        )

    elif pattern == "pulse":
        half = interval / 2.0 if interval > 0 else 1.0
        led.pulse(
            fade_in_time=half,
            fade_out_time=half,
            on_color=(r, g, b),
            off_color=(0, 0, 0),
            n=times if times < 999 else None,
            background=True,
        )

    elif pattern == "rainbow":
        threading.Thread(
            target=_run_rainbow,
            args=(times, interval),
            daemon=True,
        ).start()


def _beep(frequency, duration_ms):
    """蜂鳴器：播放時切輸出模式，結束後切回輸入模式（高阻抗）消除底噪"""
    try:
        lgpio.gpio_claim_output(_h, _buzzer_pin, 0)
        lgpio.tx_pwm(_h, _buzzer_pin, frequency, 50)
        time.sleep(duration_ms / 1000.0)
    finally:
        lgpio.tx_pwm(_h, _buzzer_pin, 0, 0)
        lgpio.gpio_write(_h, _buzzer_pin, 0)
        lgpio.gpio_claim_input(_h, _buzzer_pin)


def _play_melody(notes):
    """播放旋律：依序播放 [(freq, duration_ms), ...] 音符序列"""
    _melody_cancel.clear()
    try:
        lgpio.gpio_claim_output(_h, _buzzer_pin, 0)
        for freq, dur in notes:
            if _melody_cancel.is_set():
                break
            if freq == 0:  # REST
                lgpio.tx_pwm(_h, _buzzer_pin, 0, 0)
            else:
                lgpio.tx_pwm(_h, _buzzer_pin, freq, 50)
            if _melody_cancel.wait(timeout=dur / 1000.0):
                break
    finally:
        lgpio.tx_pwm(_h, _buzzer_pin, 0, 0)
        lgpio.gpio_write(_h, _buzzer_pin, 0)
        lgpio.gpio_claim_input(_h, _buzzer_pin)


# ─── effect lookup ────────────────────────────────────

def _lookup_effect(domain, state):
    """查映射表，回傳硬體指令 dict 或 None。"""
    domain_map = _effects.get(domain)
    if domain_map and isinstance(domain_map, dict):
        return domain_map.get(state)
    return None


# ─── domain priority helpers ──────────────────────────

def _display_effect(domain, state, project):
    """查映射表 + 執行燈效。回傳 effect dict 或 None。"""
    effect = _lookup_effect(domain, state)
    if not effect:
        return None
    r = effect.get("r", 0) / 255.0
    g = effect.get("g", 0) / 255.0
    b = effect.get("b", 0) / 255.0
    pattern = effect.get("pattern", "solid")
    times = effect.get("times", 1)
    duration = effect.get("duration", 5)
    interval = effect.get("interval", 0.3)
    _run_effect(r, g, b, pattern, times, duration, interval)
    return effect


def _cancel_ime_timer():
    """取消 IME 計時器。"""
    global _ime_timer
    if _ime_timer:
        _ime_timer.cancel()
        _ime_timer = None


def _ime_timeout():
    """IME timer 到期，回復 Claude 顯示。"""
    global _ime_active
    _ime_active = False
    _ime_timer_ref = None  # timer 已到期，不需 cancel
    claude = _last_domain_state.get("claude")
    if claude:
        _display_effect("claude", claude["state"], claude["project"])


# ─── MQTT callbacks ───────────────────────────────────

def on_connect(client, userdata, flags, rc):
    global _last_led_payload, _ime_active, _last_domain_state
    _last_led_payload = ""  # 重連後清除，讓 retained 訊息正常執行
    _ime_active = False
    _last_domain_state = {}
    _cancel_ime_timer()
    print(f"Connected to MQTT broker (rc={rc})")
    client.subscribe("claude/led")
    client.subscribe("claude/buzzer")
    client.subscribe("claude/melody")


def on_message(client, userdata, msg):
    try:
        data = json.loads(msg.payload.decode())
    except json.JSONDecodeError:
        return

    if msg.topic == "claude/led":
        global _last_led_payload, _ime_active, _ime_timer
        raw = msg.payload.decode()
        if raw == _last_led_payload:
            return  # 同樣的指令不重複執行（retained 重送等）
        _last_led_payload = raw

        # 語意 payload：用 domain+state 查映射表翻譯成硬體指令
        # domain="raw" 為 debug 直通模式，直接用 payload 的 r/g/b
        domain = data.get("domain", "")
        state = data.get("state", "")
        project = data.get("project", "")

        if domain == "raw":
            effect = data
            r = effect.get("r", 0) / 255.0
            g = effect.get("g", 0) / 255.0
            b = effect.get("b", 0) / 255.0
            pattern = effect.get("pattern", "solid")
            times = effect.get("times", 1)
            duration = effect.get("duration", 5)
            interval = effect.get("interval", 0.3)
            _run_effect(r, g, b, pattern, times, duration, interval)
        elif domain == "ime":
            # IME 訊息：立即顯示 + 啟動 2s timer
            _last_domain_state["ime"] = {"state": state, "project": project}
            effect = _display_effect(domain, state, project)
            if not effect:
                return
            _cancel_ime_timer()
            _ime_active = True
            _ime_timer = threading.Timer(_IME_INTERRUPT_SECS, _ime_timeout)
            _ime_timer.daemon = True
            _ime_timer.start()
        elif _ime_active:
            # Claude 訊息在 IME 中斷期間：存但不顯示
            _last_domain_state["claude"] = {"state": state, "project": project}
            effect = _lookup_effect(domain, state)
            if not effect:
                return
            # suppressed ACK
            client.publish("claude/led/ack", json.dumps({
                "domain": domain, "state": state, "project": project,
                "r": effect.get("r", 0), "g": effect.get("g", 0), "b": effect.get("b", 0),
                "pattern": effect.get("pattern", "solid"),
                "is_lit": led.is_lit,
                "gpio": [0, 0, 0],
                "ts": int(time.time()),
                "suppressed": True,
            }))
            return
        else:
            # Claude 訊息正常：直接顯示
            _last_domain_state["claude"] = {"state": state, "project": project}
            effect = _display_effect(domain, state, project)
            if not effect:
                return

        # ACK：回報已接收並執行的燈效 + GPIO 實際輸出（供自動化測試端到端驗證）
        time.sleep(0.05)  # 等 gpiozero blink/pulse 啟動
        gpio_rgb = led.color  # gpiozero 回報的實際 GPIO 輸出 (0.0~1.0)
        client.publish("claude/led/ack", json.dumps({
            "domain": domain,
            "state": state,
            "project": project,
            "r": effect.get("r", 0),
            "g": effect.get("g", 0),
            "b": effect.get("b", 0),
            "pattern": effect.get("pattern", "solid"),
            "is_lit": led.is_lit,
            "gpio": [round(gpio_rgb[0], 3), round(gpio_rgb[1], 3), round(gpio_rgb[2], 3)],
            "ts": int(time.time()),
        }))

    elif msg.topic == "claude/buzzer":
        frequency = data.get("frequency", 1000)
        duration_ms = data.get("duration", 500)
        threading.Thread(
            target=_beep,
            args=(frequency, duration_ms),
            daemon=True,
        ).start()

    elif msg.topic == "claude/melody":
        name = data.get("name", "")
        notes = MELODIES.get(name)
        if notes:
            _melody_cancel.set()  # 中斷正在播放的旋律
            threading.Thread(
                target=_play_melody,
                args=(notes,),
                daemon=True,
            ).start()


if __name__ == "__main__":
    broker = config.get("mqtt_broker", "localhost")
    port = config.get("mqtt_port", 1883)

    anode_str = "共陽極" if COMMON_ANODE else "共陰極"
    print(f"MQTT LED Service starting (gpiozero)... ({anode_str})")
    print(f"Broker: {broker}:{port}")
    print(f"GPIO: R={gpio['red']}, G={gpio['green']}, B={gpio['blue']}, Buzzer={gpio['buzzer']}")
    print(f"Melodies: {', '.join(sorted(MELODIES.keys()))}")
    print("Subscribing: claude/led, claude/buzzer, claude/melody")

    # Start watchdog thread
    threading.Thread(target=_watchdog_loop, daemon=True).start()

    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(broker, port, 60)

    # Notify systemd we're ready
    _sd_notify("READY=1")

    client.loop_forever()

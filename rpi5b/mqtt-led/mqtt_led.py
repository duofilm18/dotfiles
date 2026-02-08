#!/usr/bin/env python3
"""MQTT LED Service - gpiozero 版

使用 gpiozero RGBLED 控制 GPIO，內建平滑轉場、自動執行緒管理。
手刻 PWM 迴圈全部移除，改用 gpiozero 內建 blink/pulse。

Topics:
    claude/led     - RGB LED 控制 {r, g, b, pattern, times, duration, interval}
                     pattern: blink, solid, pulse, rainbow
    claude/buzzer  - 蜂鳴器控制 {frequency, duration}
"""

import json
import threading
import time
from pathlib import Path

import lgpio
from gpiozero import RGBLED
import paho.mqtt.client as mqtt

# 載入設定
config_path = Path(__file__).parent / "config.json"
with open(config_path) as f:
    config = json.load(f)

gpio = config["gpio"]
COMMON_ANODE = config.get("common_anode", True)
GPIO_CHIP = config.get("gpio_chip", 4)

# RGB LED（gpiozero 處理 PWM、執行緒、共陽極反轉）
led = RGBLED(
    red=gpio["red"],
    green=gpio["green"],
    blue=gpio["blue"],
    active_high=not COMMON_ANODE,
)

# 蜂鳴器（lgpio 直接控制，不受頻率範圍限制）
_h = lgpio.gpiochip_open(GPIO_CHIP)
_buzzer_pin = gpio["buzzer"]
lgpio.gpio_claim_output(_h, _buzzer_pin, 0)

# rainbow / solid timer 的取消機制
_cancel = threading.Event()
_off_timer = None

_RAINBOW_COLORS = [
    (1, 0, 0),  # 紅
    (1, 1, 0),  # 黃
    (0, 1, 0),  # 綠
    (0, 1, 1),  # 青
    (0, 0, 1),  # 藍
    (1, 0, 1),  # 紫
    (1, 1, 1),  # 白
]


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
    """蜂鳴器"""
    try:
        lgpio.tx_pwm(_h, _buzzer_pin, frequency, 50)
        time.sleep(duration_ms / 1000.0)
    finally:
        lgpio.tx_pwm(_h, _buzzer_pin, 0, 0)
        lgpio.gpio_write(_h, _buzzer_pin, 0)


def on_connect(client, userdata, flags, rc):
    print(f"Connected to MQTT broker (rc={rc})")
    client.subscribe("claude/led")
    client.subscribe("claude/buzzer")


def on_message(client, userdata, msg):
    try:
        data = json.loads(msg.payload.decode())
    except json.JSONDecodeError:
        return

    if msg.topic == "claude/led":
        r = data.get("r", 0) / 255.0
        g = data.get("g", 0) / 255.0
        b = data.get("b", 0) / 255.0
        pattern = data.get("pattern", "solid")
        times = data.get("times", 1)
        duration = data.get("duration", 5)
        interval = data.get("interval", 0.3)
        _run_effect(r, g, b, pattern, times, duration, interval)

    elif msg.topic == "claude/buzzer":
        frequency = data.get("frequency", 1000)
        duration_ms = data.get("duration", 500)
        threading.Thread(
            target=_beep,
            args=(frequency, duration_ms),
            daemon=True,
        ).start()


if __name__ == "__main__":
    broker = config.get("mqtt_broker", "localhost")
    port = config.get("mqtt_port", 1883)

    anode_str = "共陽極" if COMMON_ANODE else "共陰極"
    print(f"MQTT LED Service starting (gpiozero)... ({anode_str})")
    print(f"Broker: {broker}:{port}")
    print(f"GPIO: R={gpio['red']}, G={gpio['green']}, B={gpio['blue']}, Buzzer={gpio['buzzer']}")
    print("Subscribing: claude/led, claude/buzzer")

    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(broker, port, 60)
    client.loop_forever()

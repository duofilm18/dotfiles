#!/usr/bin/env python3
"""MQTT LED Service - 訂閱 MQTT topic 控制 GPIO

Pure slave：收到什麼指令就執行什麼，不含業務邏輯。
所有燈效決策由 WSL (Master) 負責。

使用 lgpio 直接控制 GPIO（gpiozero RGBLED 在 lgpio 後端有相容問題）。

Topics:
    claude/led     - RGB LED 控制 {r, g, b, pattern, times, duration}
    claude/buzzer  - 蜂鳴器控制 {frequency, duration}
"""

import json
import threading
import time
from pathlib import Path

import lgpio
import paho.mqtt.client as mqtt

# 載入設定
config_path = Path(__file__).parent / "config.json"
with open(config_path) as f:
    config = json.load(f)

gpio = config["gpio"]
COMMON_ANODE = config.get("common_anode", True)
GPIO_CHIP = config.get("gpio_chip", 4)  # Pi5 = chip 4

# 開啟 GPIO
_h = lgpio.gpiochip_open(GPIO_CHIP)
_pins = {"red": gpio["red"], "green": gpio["green"], "blue": gpio["blue"]}
_buzzer_pin = gpio["buzzer"]

# 初始化：LED 全滅，蜂鳴器關
_OFF = 1 if COMMON_ANODE else 0
_ON = 0 if COMMON_ANODE else 1
for pin in _pins.values():
    lgpio.gpio_claim_output(_h, pin, _OFF)
lgpio.gpio_claim_output(_h, _buzzer_pin, 0)

# 用來取消正在執行的燈效
_cancel = threading.Event()


def _led_set(r, g, b):
    """設定 LED 顏色 (0.0~1.0)，gpio_write 開關"""
    for val, pin in [(r, _pins["red"]), (g, _pins["green"]), (b, _pins["blue"])]:
        if val > 0.5:
            lgpio.gpio_write(_h, pin, _ON)
        else:
            lgpio.gpio_write(_h, pin, _OFF)


def _led_off():
    """LED 全滅"""
    for pin in _pins.values():
        lgpio.gpio_write(_h, pin, _OFF)


def _run_effect(r, g, b, pattern, times, duration):
    """執行燈效，支援中途取消"""
    _cancel.clear()

    if pattern == "blink":
        for _ in range(times):
            if _cancel.is_set():
                break
            _led_set(r, g, b)
            if _cancel.wait(timeout=0.3):
                break
            _led_off()
            if _cancel.wait(timeout=0.3):
                break
    elif pattern == "solid":
        _led_set(r, g, b)
        _cancel.wait(timeout=duration)
    elif pattern == "pulse":
        for _ in range(times):
            if _cancel.is_set():
                break
            for i in range(0, 11):
                if _cancel.is_set():
                    break
                ratio = i / 10.0
                _led_set(r * ratio, g * ratio, b * ratio)
                time.sleep(0.05)
            for i in range(10, -1, -1):
                if _cancel.is_set():
                    break
                ratio = i / 10.0
                _led_set(r * ratio, g * ratio, b * ratio)
                time.sleep(0.05)

    _led_off()


def _beep(frequency, duration_ms):
    """響蜂鳴器"""
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

        _cancel.set()
        threading.Thread(
            target=_run_effect,
            args=(r, g, b, pattern, times, duration),
            daemon=True,
        ).start()

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
    print(f"MQTT LED Service starting... ({anode_str}, chip={GPIO_CHIP})")
    print(f"Broker: {broker}:{port}")
    print(f"GPIO: R={gpio['red']}, G={gpio['green']}, B={gpio['blue']}, Buzzer={gpio['buzzer']}")
    print(f"Subscribing: claude/led, claude/buzzer")

    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(broker, port, 60)
    client.loop_forever()

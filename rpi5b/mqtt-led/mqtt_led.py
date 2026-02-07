#!/usr/bin/env python3
"""MQTT LED Service - 訂閱 MQTT topic 控制 GPIO

Pure slave：收到什麼指令就執行什麼，不含業務邏輯。
所有燈效決策由 WSL (Master) 負責。

Topics:
    claude/led     - RGB LED 控制 {r, g, b, pattern, times, duration}
    claude/buzzer  - 蜂鳴器控制 {frequency, duration}
"""

import json
import threading
import time
from pathlib import Path

import paho.mqtt.client as mqtt
from gpiozero import RGBLED, TonalBuzzer
from gpiozero.tones import Tone

# 載入設定
config_path = Path(__file__).parent / "config.json"
with open(config_path) as f:
    config = json.load(f)

gpio = config["gpio"]
led = RGBLED(red=gpio["red"], green=gpio["green"], blue=gpio["blue"])
buzzer = TonalBuzzer(gpio["buzzer"])

# 用來取消正在執行的燈效
_cancel = threading.Event()


def _run_effect(r, g, b, pattern, times, duration):
    """執行燈效，支援中途取消"""
    _cancel.clear()

    if pattern == "blink":
        for _ in range(times):
            if _cancel.is_set():
                break
            led.color = (r, g, b)
            if _cancel.wait(timeout=0.3):
                break
            led.off()
            if _cancel.wait(timeout=0.3):
                break
    elif pattern == "solid":
        led.color = (r, g, b)
        _cancel.wait(timeout=duration)
    elif pattern == "pulse":
        for _ in range(times):
            if _cancel.is_set():
                break
            for i in range(0, 11):
                if _cancel.is_set():
                    break
                ratio = i / 10.0
                led.color = (r * ratio, g * ratio, b * ratio)
                time.sleep(0.05)
            for i in range(10, -1, -1):
                if _cancel.is_set():
                    break
                ratio = i / 10.0
                led.color = (r * ratio, g * ratio, b * ratio)
                time.sleep(0.05)

    led.off()


def _beep(frequency, duration_ms):
    """響蜂鳴器"""
    try:
        buzzer.play(Tone(frequency))
        time.sleep(duration_ms / 1000.0)
    finally:
        buzzer.stop()


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

    print(f"MQTT LED Service starting...")
    print(f"Broker: {broker}:{port}")
    print(f"GPIO: R={gpio['red']}, G={gpio['green']}, B={gpio['blue']}, Buzzer={gpio['buzzer']}")
    print(f"Subscribing: claude/led, claude/buzzer")

    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(broker, port, 60)
    client.loop_forever()

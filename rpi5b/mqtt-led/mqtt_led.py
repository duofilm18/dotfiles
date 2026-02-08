#!/usr/bin/env python3
"""MQTT LED Service - 訂閱 MQTT topic 控制 GPIO

Pure slave：收到什麼指令就執行什麼，不含業務邏輯。
所有燈效決策由 WSL (Master) 負責。

使用 lgpio PWM 控制 GPIO，支援全彩漸變和平滑呼吸燈。

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

# PWM 設定
_PWM_FREQ = 1000  # 1kHz，LED 無閃爍感

# 初始化：LED 全滅（PWM duty=0），蜂鳴器關
for pin in _pins.values():
    lgpio.tx_pwm(_h, pin, _PWM_FREQ, 0)
lgpio.gpio_claim_output(_h, _buzzer_pin, 0)

# 用來取消正在執行的燈效
_cancel = threading.Event()


def _led_set(r, g, b):
    """設定 LED 顏色 (0.0~1.0)，PWM 控制亮度"""
    for val, pin in [(r, _pins["red"]), (g, _pins["green"]), (b, _pins["blue"])]:
        duty = val * 100.0  # 0.0~1.0 → 0~100%
        if COMMON_ANODE:
            duty = 100.0 - duty  # 共陽極：duty 反轉
        lgpio.tx_pwm(_h, pin, _PWM_FREQ, duty)


def _led_off():
    """LED 全滅"""
    off_duty = 100.0 if COMMON_ANODE else 0.0
    for pin in _pins.values():
        lgpio.tx_pwm(_h, pin, _PWM_FREQ, off_duty)


_RAINBOW_COLORS = [
    (1, 0, 0),  # 紅
    (1, 1, 0),  # 黃
    (0, 1, 0),  # 綠
    (0, 1, 1),  # 青
    (0, 0, 1),  # 藍
    (1, 0, 1),  # 紫
    (1, 1, 1),  # 白
]


def _run_effect(r, g, b, pattern, times, duration, interval=0.3):
    """執行燈效，支援中途取消"""
    _cancel.clear()

    if pattern == "blink":
        for _ in range(times):
            if _cancel.is_set():
                break
            _led_set(r, g, b)
            if _cancel.wait(timeout=interval):
                break
            _led_off()
            if _cancel.wait(timeout=interval):
                break
    elif pattern == "solid":
        _led_set(r, g, b)
        _cancel.wait(timeout=duration)
    elif pattern == "pulse":
        # interval 控制一次完整呼吸的秒數（漸亮 + 漸暗）
        # 50 步漸亮 + 50 步漸暗 = 100 步
        steps = 50
        step_delay = interval / (steps * 2) if interval > 0 else 0.02
        for _ in range(times):
            if _cancel.is_set():
                break
            for i in range(steps + 1):
                if _cancel.is_set():
                    break
                ratio = i / float(steps)
                _led_set(r * ratio, g * ratio, b * ratio)
                time.sleep(step_delay)
            for i in range(steps, -1, -1):
                if _cancel.is_set():
                    break
                ratio = i / float(steps)
                _led_set(r * ratio, g * ratio, b * ratio)
                time.sleep(step_delay)
    elif pattern == "rainbow":
        # 七色輪流閃，跑 times 輪後自動關燈
        for _ in range(times):
            for cr, cg, cb in _RAINBOW_COLORS:
                if _cancel.is_set():
                    break
                _led_set(cr, cg, cb)
                if _cancel.wait(timeout=interval):
                    break

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
        interval = data.get("interval", 0.3)

        _cancel.set()
        threading.Thread(
            target=_run_effect,
            args=(r, g, b, pattern, times, duration, interval),
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

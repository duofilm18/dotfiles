#!/usr/bin/env python3
"""MQTT ntfy Bridge - 訂閱 MQTT topic 轉發到 ntfy

Pure bridge：收到 MQTT 訊息，直接 POST 到 ntfy。
取代 Apprise，少一跳更快到達。

Topic:
    claude/notify - 通知訊息 {title, body}
"""

import json
from pathlib import Path

import paho.mqtt.client as mqtt
import requests

# 載入設定
config_path = Path(__file__).parent / "config.json"
with open(config_path) as f:
    config = json.load(f)


def _send_ntfy(url, topic, title, body):
    """POST 到 ntfy（使用 JSON API 支援 UTF-8 標題）"""
    try:
        resp = requests.post(
            f"{url}",
            json={"topic": topic, "title": title, "message": body},
            timeout=5,
        )
        print(f"Sent to {url} (status={resp.status_code})")
    except Exception as e:
        print(f"Failed to send to {url}: {e}")


def on_connect(client, userdata, flags, rc):
    print(f"Connected to MQTT broker (rc={rc})")
    client.subscribe("claude/notify")


def on_message(client, userdata, msg):
    try:
        data = json.loads(msg.payload.decode())
    except json.JSONDecodeError:
        return

    title = data.get("title", "")
    body = data.get("body", "")
    topic = config.get("ntfy_topic", "claude-notify")

    # 本地 ntfy
    ntfy_url = config.get("ntfy_url", "http://localhost:8080")
    _send_ntfy(ntfy_url, topic, title, body)

    # 雲端 ntfy（如果有設定）
    cloud_url = config.get("ntfy_cloud_url")
    if cloud_url:
        _send_ntfy(cloud_url, topic, title, body)


if __name__ == "__main__":
    broker = config.get("mqtt_broker", "localhost")
    port = config.get("mqtt_port", 1883)

    print(f"MQTT ntfy Bridge starting...")
    print(f"Broker: {broker}:{port}")
    print(f"ntfy: {config.get('ntfy_url', 'http://localhost:8080')}")
    print(f"Subscribing: claude/notify")

    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(broker, port, 60)
    client.loop_forever()

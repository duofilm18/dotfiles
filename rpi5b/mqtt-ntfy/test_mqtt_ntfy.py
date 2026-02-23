#!/usr/bin/env python3
"""test_mqtt_ntfy.py - MQTT ntfy Bridge 純邏輯測試

驗證：
  - MQTT payload 解析（正常/異常）
  - 單端點 / 雙端點發送
  - ntfy HTTP 失敗不 crash
  - on_connect 訂閱正確 topic

不碰真實 MQTT / ntfy，全 mock。

用法: cd rpi5b/mqtt-ntfy && python3 -m pytest test_mqtt_ntfy.py -v
"""

import json
import sys
from unittest.mock import MagicMock, patch, call

import pytest

# Mock 依賴
for _mod in ["paho", "paho.mqtt", "paho.mqtt.client", "requests"]:
    sys.modules[_mod] = MagicMock()

# Mock config
_mock_config = {
    "mqtt_broker": "localhost",
    "mqtt_port": 1883,
    "ntfy_url": "http://localhost:8080",
    "ntfy_cloud_url": "https://ntfy.sh",
    "ntfy_topic": "claude-notify-test",
}

with patch("builtins.open", MagicMock()):
    with patch("json.load", return_value=_mock_config):
        import mqtt_ntfy as mn

CLIENT = MagicMock()


def make_msg(payload_dict):
    """建立 mock MQTT message（topic 固定 claude/notify）。"""
    msg = MagicMock()
    msg.topic = "claude/notify"
    msg.payload = json.dumps(payload_dict).encode()
    return msg


def make_raw_msg(raw_bytes):
    """建立 raw payload 的 mock MQTT message。"""
    msg = MagicMock()
    msg.topic = "claude/notify"
    msg.payload = raw_bytes
    return msg


@pytest.fixture(autouse=True)
def reset():
    """每個測試前重置 mock。"""
    mn.requests = MagicMock()
    mn.config = dict(_mock_config)
    yield


# ═══════════════════════════════════════════════════════════
# Payload 解析
# ═══════════════════════════════════════════════════════════


class TestPayloadParsing:

    def test_malformed_json_ignored(self):
        """非 JSON payload → 不 crash、不發 ntfy。"""
        msg = make_raw_msg(b"not json")
        mn.on_message(CLIENT, None, msg)
        mn.requests.post.assert_not_called()

    def test_empty_fields_use_defaults(self):
        """title/body 缺少 → 用空字串。"""
        msg = make_msg({})
        with patch.object(mn, "_send_ntfy") as mock_send:
            mn.on_message(CLIENT, None, msg)
            # 至少呼叫一次（本地 ntfy）
            assert mock_send.called
            args = mock_send.call_args_list[0].args
            assert args[2] == ""  # title
            assert args[3] == ""  # body

    def test_title_body_passed_correctly(self):
        """title/body 正確傳遞。"""
        msg = make_msg({"title": "Test Title", "body": "Test Body"})
        with patch.object(mn, "_send_ntfy") as mock_send:
            mn.on_message(CLIENT, None, msg)
            args = mock_send.call_args_list[0].args
            assert args[2] == "Test Title"
            assert args[3] == "Test Body"


# ═══════════════════════════════════════════════════════════
# 雙端點發送
# ═══════════════════════════════════════════════════════════


class TestDualEndpoint:

    def test_sends_to_local_ntfy(self):
        """有 ntfy_url → 發到本地 ntfy。"""
        msg = make_msg({"title": "t", "body": "b"})
        with patch.object(mn, "_send_ntfy") as mock_send:
            mn.on_message(CLIENT, None, msg)
            urls = [c.args[0] for c in mock_send.call_args_list]
            assert "http://localhost:8080" in urls

    def test_sends_to_cloud_ntfy(self):
        """有 ntfy_cloud_url → 也發到雲端。"""
        msg = make_msg({"title": "t", "body": "b"})
        with patch.object(mn, "_send_ntfy") as mock_send:
            mn.on_message(CLIENT, None, msg)
            urls = [c.args[0] for c in mock_send.call_args_list]
            assert "https://ntfy.sh" in urls

    def test_no_cloud_url_skips_cloud(self):
        """ntfy_cloud_url 未設定 → 只發本地。"""
        mn.config = {**_mock_config, "ntfy_cloud_url": None}
        msg = make_msg({"title": "t", "body": "b"})
        with patch.object(mn, "_send_ntfy") as mock_send:
            mn.on_message(CLIENT, None, msg)
            assert mock_send.call_count == 1

    def test_both_endpoints_called(self):
        """本地 + 雲端 → _send_ntfy 呼叫 2 次。"""
        msg = make_msg({"title": "t", "body": "b"})
        with patch.object(mn, "_send_ntfy") as mock_send:
            mn.on_message(CLIENT, None, msg)
            assert mock_send.call_count == 2


# ═══════════════════════════════════════════════════════════
# _send_ntfy 函式
# ═══════════════════════════════════════════════════════════


class TestSendNtfy:

    def test_posts_json_with_topic_title_message(self):
        """_send_ntfy 用 JSON API POST。"""
        mn._send_ntfy("http://test:8080", "my-topic", "T", "B")
        mn.requests.post.assert_called_once()
        kwargs = mn.requests.post.call_args.kwargs
        assert kwargs["json"]["topic"] == "my-topic"
        assert kwargs["json"]["title"] == "T"
        assert kwargs["json"]["message"] == "B"
        assert kwargs["timeout"] == 5

    def test_http_error_no_crash(self):
        """requests.post 拋例外 → 不 crash。"""
        mn.requests.post.side_effect = Exception("connection refused")
        mn._send_ntfy("http://bad:8080", "t", "t", "b")  # should not raise

    def test_timeout_no_crash(self):
        """requests 超時 → 不 crash。"""
        mn.requests.post.side_effect = Exception("timeout")
        mn._send_ntfy("http://slow:8080", "t", "t", "b")  # should not raise


# ═══════════════════════════════════════════════════════════
# on_connect
# ═══════════════════════════════════════════════════════════


class TestOnConnect:

    def test_subscribes_claude_notify(self):
        """on_connect 訂閱 claude/notify。"""
        client = MagicMock()
        mn.on_connect(client, None, None, 0)
        client.subscribe.assert_called_once_with("claude/notify")

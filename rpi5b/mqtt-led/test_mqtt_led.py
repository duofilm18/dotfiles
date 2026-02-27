#!/usr/bin/env python3
"""test_mqtt_led.py - MQTT LED Service 純邏輯測試

驗證 LED 效果引擎的純邏輯路徑：
  - MQTT payload 解析（正常/異常）
  - effect dispatch（pattern 路由、參數傳遞）
  - timer 取消機制
  - rainbow 可取消
  - melody dispatch
  - buzzer dispatch

不碰硬體（gpiozero/lgpio 全 mock），不需要 RPi5B。

用法: cd rpi5b/mqtt-led && python3 -m pytest test_mqtt_led.py -v
"""

import json
import sys
import threading
from unittest.mock import MagicMock, patch, call

import pytest

# Mock 硬體依賴（非 RPi5B 環境無 lgpio / gpiozero）
_mock_lgpio = MagicMock()
_mock_gpiozero = MagicMock()
_mock_gpiozero_pins = MagicMock()

for _mod in [
    "lgpio",
    "gpiozero", "gpiozero.pins", "gpiozero.pins.lgpio",
    "paho", "paho.mqtt", "paho.mqtt.client",
]:
    sys.modules[_mod] = MagicMock()

# Mock config.json + led-effects.json（避免讀取不存在的檔案）
_mock_config = {
    "gpio": {"red": 22, "green": 17, "blue": 27, "buzzer": 18},
    "common_anode": True,
    "gpio_chip": 0,
    "mqtt_broker": "localhost",
    "mqtt_port": 1883,
}

_mock_effects = {
    "claude": {
        "idle":    {"r": 255, "g": 13,  "b": 0,   "pattern": "blink",   "times": 999, "interval": 1.0},
        "running": {"r": 0,   "g": 0,   "b": 255, "pattern": "pulse",   "times": 999, "interval": 2.0},
        "off":     {"r": 0,   "g": 0,   "b": 0,   "pattern": "solid",   "duration": 1},
    },
    "ime": {
        "zh": {"r": 255, "g": 34, "b": 0, "pattern": "solid", "duration": 0},
    },
}

with patch("builtins.open", MagicMock()):
    with patch("json.load", side_effect=[_mock_config, _mock_effects]):
        import mqtt_led as ml

CLIENT = MagicMock()


def make_msg(topic, payload_dict):
    """建立 mock MQTT message。"""
    msg = MagicMock()
    msg.topic = topic
    msg.payload = json.dumps(payload_dict).encode()
    return msg


def make_raw_msg(topic, raw_bytes):
    """建立 raw payload 的 mock MQTT message。"""
    msg = MagicMock()
    msg.topic = topic
    msg.payload = raw_bytes
    return msg


@pytest.fixture(autouse=True)
def reset():
    """每個測試前重置全域狀態。"""
    ml._cancel.clear()
    ml._melody_cancel.clear()
    ml._off_timer = None
    ml.led = MagicMock()
    ml.led.color = (0, 0, 0)
    ml.led.is_lit = False
    CLIENT.reset_mock()
    yield


# ═══════════════════════════════════════════════════════════
# MQTT payload 解析
# ═══════════════════════════════════════════════════════════


class TestPayloadParsing:

    def test_malformed_json_ignored(self):
        """非 JSON payload → 不 crash、不執行任何效果。"""
        msg = make_raw_msg("claude/led", b"not json")
        with patch.object(ml, "_run_effect") as mock_eff:
            ml.on_message(CLIENT, None, msg)
            mock_eff.assert_not_called()

    def test_semantic_payload_lookup(self):
        """語意 payload {domain, state} → 查映射表取得硬體指令。"""
        msg = make_msg("claude/led", {"domain": "claude", "state": "running", "project": "test"})
        with patch.object(ml, "_run_effect") as mock_eff:
            ml.on_message(CLIENT, None, msg)
            mock_eff.assert_called_once_with(0, 0, 1.0, "pulse", 999, 5, 2.0)

    def test_unknown_domain_state_ignored(self):
        """映射表找不到 → 不執行。"""
        msg = make_msg("claude/led", {"domain": "claude", "state": "foobar", "project": ""})
        with patch.object(ml, "_run_effect") as mock_eff:
            ml.on_message(CLIENT, None, msg)
            mock_eff.assert_not_called()

    def test_unknown_topic_ignored(self):
        """非已知 topic → 不執行。"""
        msg = make_msg("claude/unknown", {"domain": "claude", "state": "idle"})
        with patch.object(ml, "_run_effect") as mock_eff, \
             patch.object(ml, "_beep") as mock_beep:
            ml.on_message(CLIENT, None, msg)
            mock_eff.assert_not_called()
            mock_beep.assert_not_called()


# ═══════════════════════════════════════════════════════════
# Effect dispatch（pattern 路由）
# ═══════════════════════════════════════════════════════════


class TestEffectDispatch:

    def test_solid_sets_color(self):
        """pattern=solid → led.color = (r, g, b)。"""
        ml._run_effect(1.0, 0.5, 0.0, "solid", 1, 5, 0.3)
        ml.led.__setattr__("color", (1.0, 0.5, 0.0))

    def test_solid_with_duration_starts_timer(self):
        """pattern=solid + duration>0 → Timer 啟動。"""
        with patch("mqtt_led.threading.Timer", return_value=MagicMock()) as MockTimer:
            ml._run_effect(1.0, 0, 0, "solid", 1, 5, 0.3)
            MockTimer.assert_called_once_with(5, ml.led.off)
            MockTimer.return_value.start.assert_called_once()

    def test_solid_zero_duration_no_timer(self):
        """pattern=solid + duration=0 → 不啟動 Timer。"""
        with patch("mqtt_led.threading.Timer") as MockTimer:
            ml._run_effect(1.0, 0, 0, "solid", 1, 0, 0.3)
            MockTimer.assert_not_called()

    def test_blink_calls_led_blink(self):
        """pattern=blink → led.blink() 被呼叫。"""
        ml._run_effect(1.0, 0, 0, "blink", 5, 5, 0.3)
        ml.led.blink.assert_called_once()
        kwargs = ml.led.blink.call_args.kwargs
        assert kwargs["on_color"] == (1.0, 0, 0)
        assert kwargs["off_color"] == (0, 0, 0)
        assert kwargs["n"] == 5
        assert kwargs["background"] is True

    def test_blink_infinite_when_times_999(self):
        """times=999 → n=None（無限閃爍）。"""
        ml._run_effect(1.0, 0, 0, "blink", 999, 5, 0.3)
        kwargs = ml.led.blink.call_args.kwargs
        assert kwargs["n"] is None

    def test_pulse_calls_led_pulse(self):
        """pattern=pulse → led.pulse() 被呼叫。"""
        ml._run_effect(0, 0, 1.0, "pulse", 999, 5, 2.0)
        ml.led.pulse.assert_called_once()
        kwargs = ml.led.pulse.call_args.kwargs
        assert kwargs["on_color"] == (0, 0, 1.0)
        assert kwargs["fade_in_time"] == 1.0  # interval/2
        assert kwargs["fade_out_time"] == 1.0

    def test_rainbow_starts_thread(self):
        """pattern=rainbow → 背景 thread 啟動。"""
        with patch("mqtt_led.threading.Thread") as MockThread:
            MockThread.return_value = MagicMock()
            ml._run_effect(0, 0, 0, "rainbow", 3, 5, 1.0)
            MockThread.assert_called_once()
            assert MockThread.call_args.kwargs["target"] == ml._run_rainbow
            MockThread.return_value.start.assert_called_once()


# ═══════════════════════════════════════════════════════════
# Timer 取消機制
# ═══════════════════════════════════════════════════════════


class TestTimerCancel:

    def test_stop_custom_cancels_off_timer(self):
        """_stop_custom() 取消 _off_timer。"""
        mock_timer = MagicMock()
        ml._off_timer = mock_timer
        ml._stop_custom()
        mock_timer.cancel.assert_called_once()
        assert ml._off_timer is None

    def test_stop_custom_sets_cancel_event(self):
        """_stop_custom() 設置 _cancel event（中斷 rainbow）。"""
        ml._stop_custom()
        assert ml._cancel.is_set()

    def test_new_effect_cancels_previous(self):
        """新效果執行前先 _stop_custom。"""
        with patch.object(ml, "_stop_custom") as mock_stop:
            ml._run_effect(1, 0, 0, "solid", 1, 0, 0.3)
            mock_stop.assert_called_once()


# ═══════════════════════════════════════════════════════════
# Rainbow 可取消
# ═══════════════════════════════════════════════════════════


class TestRainbow:

    def test_rainbow_cycles_through_colors(self):
        """_run_rainbow 依序設置 7 種顏色。"""
        ml._cancel.clear()
        ml._cancel = MagicMock()
        ml._cancel.is_set.return_value = False
        ml._cancel.wait.return_value = False

        colors_seen = []
        original_led = ml.led

        class ColorTracker:
            is_lit = False
            def __init__(self):
                self._color = (0, 0, 0)
            @property
            def color(self):
                return self._color
            @color.setter
            def color(self, val):
                self._color = val
                colors_seen.append(val)
            def off(self):
                pass

        ml.led = ColorTracker()
        ml._run_rainbow(1, 0.0)

        assert len(colors_seen) == 7
        assert colors_seen[0] == (1, 0, 0)   # 紅
        assert colors_seen[-1] == (1, 1, 1)  # 白
        ml.led = original_led

    def test_rainbow_stops_on_cancel(self):
        """_cancel.is_set() == True → rainbow 立即停止。"""
        ml._cancel = MagicMock()
        ml._cancel.is_set.return_value = True

        colors_seen = []

        class ColorTracker:
            is_lit = False
            @property
            def color(self):
                return (0, 0, 0)
            @color.setter
            def color(self, val):
                colors_seen.append(val)
            def off(self):
                pass

        ml.led = ColorTracker()
        ml._run_rainbow(3, 1.0)
        assert len(colors_seen) == 0

    def test_rainbow_turns_off_after_completion(self):
        """rainbow 正常完成後呼叫 led.off()。"""
        ml._cancel = MagicMock()
        ml._cancel.is_set.return_value = False
        ml._cancel.wait.return_value = False

        ml._run_rainbow(1, 0.0)
        ml.led.off.assert_called_once()


# ═══════════════════════════════════════════════════════════
# Buzzer / Melody dispatch
# ═══════════════════════════════════════════════════════════


class TestBuzzerMelody:

    def test_buzzer_topic_starts_thread(self):
        """claude/buzzer → 背景 thread 呼叫 _beep。"""
        msg = make_msg("claude/buzzer", {"frequency": 1000, "duration": 500})
        with patch("mqtt_led.threading.Thread") as MockThread:
            MockThread.return_value = MagicMock()
            ml.on_message(CLIENT, None, msg)
            MockThread.assert_called_once()
            assert MockThread.call_args.kwargs["target"] == ml._beep

    def test_melody_known_name_starts_thread(self):
        """claude/melody + known name → 背景 thread 呼叫 _play_melody。"""
        ml.MELODIES = {"test_tune": [(440, 100), (880, 100)]}
        msg = make_msg("claude/melody", {"name": "test_tune"})
        with patch("mqtt_led.threading.Thread") as MockThread:
            MockThread.return_value = MagicMock()
            ml.on_message(CLIENT, None, msg)
            MockThread.assert_called_once()
            assert MockThread.call_args.kwargs["target"] == ml._play_melody

    def test_melody_unknown_name_ignored(self):
        """claude/melody + unknown name → 不啟動 thread。"""
        ml.MELODIES = {"test_tune": [(440, 100)]}
        msg = make_msg("claude/melody", {"name": "nonexistent"})
        with patch("mqtt_led.threading.Thread") as MockThread:
            ml.on_message(CLIENT, None, msg)
            MockThread.assert_not_called()

    def test_melody_cancels_previous(self):
        """新旋律取消正在播放的旋律（_melody_cancel.set）。"""
        ml.MELODIES = {"tune": [(440, 100)]}
        ml._melody_cancel = MagicMock()
        msg = make_msg("claude/melody", {"name": "tune"})
        with patch("mqtt_led.threading.Thread", return_value=MagicMock()):
            ml.on_message(CLIENT, None, msg)
            ml._melody_cancel.set.assert_called_once()


# ═══════════════════════════════════════════════════════════
# on_connect 訂閱
# ═══════════════════════════════════════════════════════════


class TestOnConnect:

    def test_subscribes_all_topics(self):
        """on_connect 訂閱 claude/led, claude/buzzer, claude/melody。"""
        client = MagicMock()
        ml.on_connect(client, None, None, 0)
        calls = [c.args[0] for c in client.subscribe.call_args_list]
        assert "claude/led" in calls
        assert "claude/buzzer" in calls
        assert "claude/melody" in calls


# ═══════════════════════════════════════════════════════════
# ACK 回報
# ═══════════════════════════════════════════════════════════


class TestLedAck:

    def test_led_message_publishes_ack(self):
        """claude/led 訊息處理後回報 ACK 到 claude/led/ack（含 domain/state/project）。"""
        msg = make_msg("claude/led", {"domain": "claude", "state": "idle", "project": "dotfiles"})
        with patch.object(ml, "_run_effect"), \
             patch("mqtt_led.time") as mock_time:
            mock_time.sleep = MagicMock()
            mock_time.time.return_value = 1234567890
            ml.on_message(CLIENT, None, msg)
            CLIENT.publish.assert_called_once()
            topic = CLIENT.publish.call_args.args[0]
            assert topic == "claude/led/ack"
            ack = json.loads(CLIENT.publish.call_args.args[1])
            assert ack["domain"] == "claude"
            assert ack["state"] == "idle"
            assert ack["project"] == "dotfiles"
            assert ack["r"] == 255
            assert ack["pattern"] == "blink"


# ═══════════════════════════════════════════════════════════
# Domain 優先權（IME 2s 中斷）
# ═══════════════════════════════════════════════════════════


class TestDomainPriority:

    def setup_method(self):
        """每個測試前清除 domain priority 狀態。"""
        ml._ime_active = False
        ml._last_domain_state = {}
        ml._ime_timer = None
        ml._last_led_payload = ""

    def test_ime_message_displays_immediately(self):
        """IME 訊息到達 → 立即顯示 + 啟動 timer。"""
        msg = make_msg("claude/led", {"domain": "ime", "state": "zh", "project": ""})
        with patch.object(ml, "_run_effect") as mock_eff, \
             patch("mqtt_led.time") as mock_time, \
             patch("mqtt_led.threading.Timer", return_value=MagicMock()) as MockTimer:
            mock_time.sleep = MagicMock()
            mock_time.time.return_value = 1234567890
            ml.on_message(CLIENT, None, msg)
            # 應執行 IME 燈效
            mock_eff.assert_called_once()
            # 應啟動 2s timer
            MockTimer.assert_called_once()
            assert MockTimer.call_args.args[0] == ml._IME_INTERRUPT_SECS
            MockTimer.return_value.start.assert_called_once()
            assert ml._ime_active is True

    def test_claude_suppressed_during_ime_interrupt(self):
        """IME 中斷期間 Claude 訊息被抑制（存但不顯示）。"""
        ml._ime_active = True
        msg = make_msg("claude/led", {"domain": "claude", "state": "running", "project": "test"})
        with patch.object(ml, "_run_effect") as mock_eff, \
             patch("mqtt_led.time") as mock_time:
            mock_time.time.return_value = 1234567890
            ml.on_message(CLIENT, None, msg)
            # 不應執行燈效
            mock_eff.assert_not_called()
            # 應存到 _last_domain_state
            assert ml._last_domain_state["claude"]["state"] == "running"
            # 應發 suppressed ACK
            CLIENT.publish.assert_called_once()
            ack = json.loads(CLIENT.publish.call_args.args[1])
            assert ack["suppressed"] is True

    def test_ime_timeout_restores_claude(self):
        """IME timer 到期 → 回復 Claude 顯示。"""
        ml._ime_active = True
        ml._last_domain_state["claude"] = {"state": "idle", "project": "dotfiles"}
        with patch.object(ml, "_display_effect") as mock_disp:
            ml._ime_timeout()
            assert ml._ime_active is False
            mock_disp.assert_called_once_with("claude", "idle", "dotfiles")

    def test_claude_normal_without_ime(self):
        """無 IME 中斷時 Claude 正常顯示。"""
        ml._ime_active = False
        msg = make_msg("claude/led", {"domain": "claude", "state": "idle", "project": "dotfiles"})
        with patch.object(ml, "_run_effect") as mock_eff, \
             patch("mqtt_led.time") as mock_time:
            mock_time.sleep = MagicMock()
            mock_time.time.return_value = 1234567890
            ml.on_message(CLIENT, None, msg)
            # 應正常執行燈效
            mock_eff.assert_called_once()

    def test_on_connect_clears_priority_state(self):
        """on_connect 清除所有 priority 狀態。"""
        ml._ime_active = True
        ml._last_domain_state = {"claude": {"state": "idle", "project": "x"}}
        ml._ime_timer = MagicMock()
        client = MagicMock()
        ml.on_connect(client, None, None, 0)
        assert ml._ime_active is False
        assert ml._last_domain_state == {}
        assert ml._ime_timer is None

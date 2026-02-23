#!/usr/bin/env python3
"""test_rebuild.py - Retained Snapshot Rebuild 測試

驗證 Stream Deck Consumer 的 Rebuild Phase：
  - MQTT retained → cache → batch render（無逐訊息閃爍）
  - reconnect 消除幽靈按鍵
  - 按鍵分配正確（無重複、跳過 date button）

用法: cd streamdeck && python -m pytest test_rebuild.py -v
"""

import json
import sys
from unittest.mock import MagicMock, patch

import pytest

# Mock 硬體依賴（WSL 無 StreamDeck USB / PIL）
for _mod in [
    "StreamDeck", "StreamDeck.DeviceManager", "StreamDeck.ImageHelpers",
    "PIL", "PIL.Image", "PIL.ImageDraw", "PIL.ImageFont",
    "paho", "paho.mqtt", "paho.mqtt.client",
]:
    sys.modules[_mod] = MagicMock()

import streamdeck_mqtt as sd

CLIENT = MagicMock()


def make_msg(topic, state="idle"):
    """建立 mock MQTT message。"""
    msg = MagicMock()
    msg.topic = topic
    if state is None:
        msg.payload = b""
    else:
        project = topic.split("/")[-1]
        msg.payload = json.dumps({"state": state, "project": project}).encode()
    return msg


@pytest.fixture(autouse=True)
def reset():
    """每個測試前重置全域狀態 + mock 硬體。"""
    sd._projects.clear()
    sd._project_states.clear()
    sd._free_buttons.clear()
    sd._next_button = 0
    sd._button_start = 0
    sd._max_projects = 8
    sd._date_button_index = 3
    sd._rebuilding = False
    sd._rebuild_timer = None
    # Mock deck
    sd._deck = MagicMock()
    sd._deck.is_open.return_value = True
    sd._deck.key_count.return_value = 32
    # Mock PIL（render_button 需要 image.size 可 unpack）
    img = MagicMock()
    img.size = (144, 144)
    sd.PILHelper.create_key_image.return_value = img
    # 停用真實 timer
    with patch("streamdeck_mqtt.threading.Timer", return_value=MagicMock()):
        yield


# ═══════════════════════════════════════════════════════════
# 核心：tmux 有 N 個專案 → Stream Deck 顯示 N 個不同按鍵
# ═══════════════════════════════════════════════════════════


class TestThreeProjectsThreeButtons:
    """使用者場景：tmux 有 dotfiles, landtw, duofilm → Stream Deck 顯示 3 個。"""

    def test_all_projects_present(self):
        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/dotfiles", "running"))
        sd.on_message(CLIENT, None, make_msg("claude/led/landtw", "idle"))
        sd.on_message(CLIENT, None, make_msg("claude/led/duofilm", "idle"))
        sd._finish_rebuild()

        assert set(sd._projects.keys()) == {"dotfiles", "landtw", "duofilm"}

    def test_no_duplicate_button_indices(self):
        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/dotfiles", "running"))
        sd.on_message(CLIENT, None, make_msg("claude/led/landtw", "idle"))
        sd.on_message(CLIENT, None, make_msg("claude/led/duofilm", "idle"))
        sd._finish_rebuild()

        indices = list(sd._projects.values())
        assert len(set(indices)) == 3, f"按鍵 index 重複: {sd._projects}"

    def test_states_match(self):
        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/dotfiles", "running"))
        sd.on_message(CLIENT, None, make_msg("claude/led/landtw", "idle"))
        sd.on_message(CLIENT, None, make_msg("claude/led/duofilm", "idle"))
        sd._finish_rebuild()

        assert sd._project_states["dotfiles"] == "running"
        assert sd._project_states["landtw"] == "idle"
        assert sd._project_states["duofilm"] == "idle"

    def test_batch_render_all_projects(self):
        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/dotfiles", "running"))
        sd.on_message(CLIENT, None, make_msg("claude/led/landtw", "idle"))
        sd.on_message(CLIENT, None, make_msg("claude/led/duofilm", "idle"))

        with patch.object(sd, "render_button") as mock_rb:
            sd._finish_rebuild()
            rendered = {c.args[2] for c in mock_rb.call_args_list if c.args[2]}
            assert rendered == {"dotfiles", "landtw", "duofilm"}


# ═══════════════════════════════════════════════════════════
# 幽靈消除：reconnect 後已消失的專案不殘留
# ═══════════════════════════════════════════════════════════


class TestGhostElimination:

    def test_reconnect_removes_disappeared_project(self):
        """專案 C 從 broker 消失 → reconnect 後 Stream Deck 不顯示。"""
        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/dotfiles", "running"))
        sd.on_message(CLIENT, None, make_msg("claude/led/landtw", "idle"))
        sd.on_message(CLIENT, None, make_msg("claude/led/ghost", "idle"))
        sd._finish_rebuild()
        assert "ghost" in sd._projects

        # Reconnect：ghost 已從 broker 刪除（retained 清空）
        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/dotfiles", "running"))
        sd.on_message(CLIENT, None, make_msg("claude/led/landtw", "idle"))
        sd._finish_rebuild()

        assert "ghost" not in sd._projects
        assert len(sd._projects) == 2

    def test_on_connect_clears_all_state(self):
        """on_connect 必須清空所有內部狀態。"""
        sd._projects["old"] = 5
        sd._project_states["old"] = "running"
        sd._free_buttons.append(7)
        sd._next_button = 3

        sd.on_connect(CLIENT, None, None, 0)

        assert len(sd._projects) == 0
        assert len(sd._project_states) == 0
        assert len(sd._free_buttons) == 0
        assert sd._next_button == 0
        assert sd._rebuilding is True


# ═══════════════════════════════════════════════════════════
# Rebuild Phase：rebuild 中不 render，結束後 batch render
# ═══════════════════════════════════════════════════════════


class TestRebuildPhase:

    def test_no_render_during_rebuild(self):
        sd.on_connect(CLIENT, None, None, 0)
        with patch.object(sd, "render_button") as mock_rb:
            sd.on_message(CLIENT, None, make_msg("claude/led/dotfiles", "running"))
            sd.on_message(CLIENT, None, make_msg("claude/led/landtw", "idle"))
            mock_rb.assert_not_called()

    def test_rebuilding_flag_lifecycle(self):
        sd.on_connect(CLIENT, None, None, 0)
        assert sd._rebuilding is True

        sd.on_message(CLIENT, None, make_msg("claude/led/dotfiles", "running"))
        assert sd._rebuilding is True  # 仍在 rebuild

        sd._finish_rebuild()
        assert sd._rebuilding is False

    def test_immediate_render_after_rebuild(self):
        sd.on_connect(CLIENT, None, None, 0)
        sd._finish_rebuild()
        assert sd._rebuilding is False

        with patch.object(sd, "render_button") as mock_rb:
            sd.on_message(CLIENT, None, make_msg("claude/led/newproject", "running"))
            assert mock_rb.called


# ═══════════════════════════════════════════════════════════
# 按鍵分配邏輯
# ═══════════════════════════════════════════════════════════


class TestButtonAllocation:

    def test_same_topic_no_duplicate(self):
        """同一 topic 重複收到 → 一個按鍵，狀態取最新。"""
        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/landtw", "idle"))
        sd.on_message(CLIENT, None, make_msg("claude/led/landtw", "running"))
        sd._finish_rebuild()

        assert len(sd._projects) == 1
        assert sd._project_states["landtw"] == "running"

    def test_skip_date_button_index(self):
        """按鍵分配跳過 date_button_index。"""
        sd._date_button_index = 1

        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/a", "idle"))
        sd.on_message(CLIENT, None, make_msg("claude/led/b", "idle"))
        sd.on_message(CLIENT, None, make_msg("claude/led/c", "idle"))
        sd._finish_rebuild()

        assert 1 not in sd._projects.values(), "date button index 不應被分配"

    def test_empty_payload_removes_project(self):
        """空 payload = 專案移除。"""
        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/dotfiles", "running"))
        sd.on_message(CLIENT, None, make_msg("claude/led/landtw", "idle"))
        sd._finish_rebuild()
        assert len(sd._projects) == 2

        # 正常模式收到空 payload
        sd.on_message(CLIENT, None, make_msg("claude/led/landtw", state=None))
        assert "landtw" not in sd._projects
        assert len(sd._projects) == 1

    def test_max_projects_limit(self):
        """超過 max_projects 上限不分配。"""
        sd._max_projects = 2

        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/a", "idle"))
        sd.on_message(CLIENT, None, make_msg("claude/led/b", "idle"))
        sd.on_message(CLIENT, None, make_msg("claude/led/c", "idle"))  # 超過上限
        sd._finish_rebuild()

        assert len(sd._projects) == 2
        assert "c" not in sd._projects

#!/usr/bin/env python3
"""test_rebuild.py - Retained Snapshot Rebuild 測試

驗證 Stream Deck Consumer 的 Rebuild Phase：
  - MQTT retained → cache → batch render（無逐訊息閃爍）
  - reconnect 消除幽靈按鍵
  - 按鍵分配正確（無重複、跳過 date button）
  - Thread Safety：多 thread 併發存取共用狀態

用法: cd streamdeck && python -m pytest test_rebuild.py -v
"""

import json
import sys
import threading
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


# ═══════════════════════════════════════════════════════════
# Button 回收：FIFO 順序、重用、跳過 date button
# ═══════════════════════════════════════════════════════════


class TestButtonRecycling:

    def _setup_three_projects(self):
        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/A", "idle"))
        sd.on_message(CLIENT, None, make_msg("claude/led/B", "idle"))
        sd.on_message(CLIENT, None, make_msg("claude/led/C", "idle"))
        sd._finish_rebuild()

    def test_removed_slot_reused_by_next_project(self):
        """A→0, B→1, C→2 → remove B → D gets slot 1。"""
        self._setup_three_projects()
        b_slot = sd._projects["B"]

        sd.on_message(CLIENT, None, make_msg("claude/led/B", state=None))
        sd.on_message(CLIENT, None, make_msg("claude/led/D", "running"))

        assert sd._projects["D"] == b_slot

    def test_free_buttons_fifo_order(self):
        """remove B then A → next gets B's slot (FIFO)。"""
        self._setup_three_projects()
        b_slot = sd._projects["B"]

        sd.on_message(CLIENT, None, make_msg("claude/led/B", state=None))
        sd.on_message(CLIENT, None, make_msg("claude/led/A", state=None))
        sd.on_message(CLIENT, None, make_msg("claude/led/D", "idle"))

        assert sd._projects["D"] == b_slot  # FIFO: B's slot first

    def test_recycle_skips_date_button(self):
        """date=1, A→0, B→2 → remove A → slot 0 reusable, date still skipped。"""
        sd._date_button_index = 1

        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/A", "idle"))
        sd.on_message(CLIENT, None, make_msg("claude/led/B", "idle"))
        sd._finish_rebuild()

        assert 1 not in sd._projects.values()  # date skipped
        a_slot = sd._projects["A"]

        sd.on_message(CLIENT, None, make_msg("claude/led/A", state=None))
        sd.on_message(CLIENT, None, make_msg("claude/led/C", "idle"))

        assert sd._projects["C"] == a_slot
        assert 1 not in sd._projects.values()


# ═══════════════════════════════════════════════════════════
# 正常模式 render：rebuild 後逐訊息即時更新
# ═══════════════════════════════════════════════════════════


class TestNormalModeRender:

    def test_new_message_renders_immediately(self):
        """finish_rebuild → on_message → render_button called。"""
        sd.on_connect(CLIENT, None, None, 0)
        sd._finish_rebuild()

        with patch.object(sd, "render_button") as mock_rb:
            sd.on_message(CLIENT, None, make_msg("claude/led/proj", "running"))
            assert mock_rb.called

    def test_state_update_uses_correct_display(self):
        """state='running' → STATE_DISPLAY['running'] 的 bg/fg。"""
        sd.on_connect(CLIENT, None, None, 0)
        sd._finish_rebuild()

        with patch.object(sd, "render_button") as mock_rb:
            sd.on_message(CLIENT, None, make_msg("claude/led/proj", "running"))
            state_info = mock_rb.call_args.args[3]
            assert state_info == sd.STATE_DISPLAY["running"]

    def test_unknown_state_uses_fallback(self):
        """state='foobar' → UNKNOWN_DISPLAY。"""
        sd.on_connect(CLIENT, None, None, 0)
        sd._finish_rebuild()

        msg = MagicMock()
        msg.topic = "claude/led/proj"
        msg.payload = json.dumps({"state": "foobar", "project": "proj"}).encode()

        with patch.object(sd, "render_button") as mock_rb:
            sd.on_message(CLIENT, None, msg)
            state_info = mock_rb.call_args.args[3]
            assert state_info == sd.UNKNOWN_DISPLAY


# ═══════════════════════════════════════════════════════════
# 錯誤 payload：不炸、靜默忽略
# ═══════════════════════════════════════════════════════════


class TestErrorResilience:

    def test_malformed_json_ignored(self):
        """payload = b'not json' → no crash, no state change。"""
        sd.on_connect(CLIENT, None, None, 0)
        sd._finish_rebuild()

        msg = MagicMock()
        msg.topic = "claude/led/proj"
        msg.payload = b"not json"

        sd.on_message(CLIENT, None, msg)
        assert "proj" not in sd._project_states

    def test_missing_state_field(self):
        """payload = b'{"project":"x"}' → state=''。"""
        sd.on_connect(CLIENT, None, None, 0)
        sd._finish_rebuild()

        msg = MagicMock()
        msg.topic = "claude/led/x"
        msg.payload = json.dumps({"project": "x"}).encode()

        sd.on_message(CLIENT, None, msg)
        assert sd._project_states["x"] == ""

    def test_invalid_topic_depth_ignored(self):
        """topic depth != 3 → ignored。"""
        sd.on_connect(CLIENT, None, None, 0)
        sd._finish_rebuild()

        for topic in ["claude/led", "claude/led/a/b"]:
            msg = MagicMock()
            msg.topic = topic
            msg.payload = json.dumps({"state": "idle"}).encode()
            sd.on_message(CLIENT, None, msg)

        assert len(sd._projects) == 0

    def test_remove_nonexistent_project_no_crash(self):
        """_remove_project('ghost') → no error。"""
        sd._remove_project("ghost")  # should not raise


# ═══════════════════════════════════════════════════════════
# 按鍵回調路由（mock subprocess）
# ═══════════════════════════════════════════════════════════


class TestOnKeyPress:

    def test_key_release_ignored(self):
        """on_key_press(deck, 0, False) → no action。"""
        with patch.object(sd, "_run_powershell") as mock_ps, \
             patch("streamdeck_mqtt.subprocess") as mock_sp:
            sd.on_key_press(sd._deck, 0, False)
            mock_ps.assert_not_called()
            mock_sp.Popen.assert_not_called()

    def test_date_button_triggers_paste(self):
        """按下 date button → _run_powershell called。"""
        sd._date_button_index = 3
        with patch.object(sd, "_run_powershell") as mock_ps:
            sd.on_key_press(sd._deck, 3, True)
            mock_ps.assert_called_once()

    def test_project_button_triggers_switch(self):
        """按下 project button → subprocess.Popen called。"""
        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/myproj", "idle"))
        sd._finish_rebuild()

        key_idx = sd._projects["myproj"]
        with patch("streamdeck_mqtt.subprocess.Popen") as mock_popen, \
             patch.object(sd, "_run_powershell"):
            sd.on_key_press(sd._deck, key_idx, True)
            assert mock_popen.called

    def test_unmapped_key_ignored(self):
        """按下未分配的 key → no subprocess call。"""
        with patch("streamdeck_mqtt.subprocess.Popen") as mock_popen, \
             patch.object(sd, "_run_powershell") as mock_ps:
            sd.on_key_press(sd._deck, 99, True)
            mock_popen.assert_not_called()
            mock_ps.assert_not_called()


# ═══════════════════════════════════════════════════════════
# 閃爍 display 表設定
# ═══════════════════════════════════════════════════════════


class TestBlinkDisplay:

    def test_idle_waiting_have_blink_display(self):
        """BLINK_DISPLAY 只含 idle 和 waiting。"""
        assert set(sd.BLINK_DISPLAY.keys()) == {"idle", "waiting"}

    def test_running_completed_not_in_blink(self):
        """running/completed/error 不在 BLINK_DISPLAY。"""
        for state in ("running", "completed", "error"):
            assert state not in sd.BLINK_DISPLAY


# ═══════════════════════════════════════════════════════════
# Timer debounce：rebuild 期間多則訊息重設 timer
# ═══════════════════════════════════════════════════════════


class TestTimerDebounce:

    def test_rapid_messages_reset_timer(self):
        """rebuild 中連續訊息 → timer.cancel 被呼叫。"""
        with patch("streamdeck_mqtt.threading.Timer", return_value=MagicMock()) as MockTimer:
            sd.on_connect(CLIENT, None, None, 0)
            first_timer = MockTimer.return_value

            sd.on_message(CLIENT, None, make_msg("claude/led/a", "idle"))
            assert first_timer.cancel.called

    def test_finish_rebuild_sets_flag_and_renders(self):
        """_finish_rebuild() → _rebuilding=False + rerender_all 被呼叫。"""
        sd._rebuilding = True
        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/a", "idle"))

        with patch.object(sd, "render_button"):
            sd._finish_rebuild()

        assert sd._rebuilding is False


# ═══════════════════════════════════════════════════════════
# Rerender / Clear all
# ═══════════════════════════════════════════════════════════


class TestRerenderAndClear:

    def test_rerender_all_renders_each_project(self):
        """3 projects → rerender_all → render_button called for each + date。"""
        sd.on_connect(CLIENT, None, None, 0)
        sd.on_message(CLIENT, None, make_msg("claude/led/a", "idle"))
        sd.on_message(CLIENT, None, make_msg("claude/led/b", "running"))
        sd.on_message(CLIENT, None, make_msg("claude/led/c", "waiting"))
        sd._finish_rebuild()

        with patch.object(sd, "render_button") as mock_rb, \
             patch.object(sd, "render_date_button"):
            sd.rerender_all()
            rendered = {c.args[2] for c in mock_rb.call_args_list}
            assert rendered == {"a", "b", "c"}

    def test_clear_all_buttons_renders_32_keys(self):
        """_clear_all_buttons → render_button called 32 times with 'off'。"""
        with patch.object(sd, "render_button") as mock_rb:
            sd._clear_all_buttons(sd._deck)
            assert mock_rb.call_count == 32
            for call in mock_rb.call_args_list:
                assert call.args[3] == sd.STATE_DISPLAY["off"]


# ═══════════════════════════════════════════════════════════
# Thread Safety：多 thread 併發存取共用狀態
# ═══════════════════════════════════════════════════════════


class TestThreadSafety:
    """驗證 _state_lock 保護共用狀態，防止 race condition crash。"""

    def test_finish_rebuild_and_on_connect_race(self):
        """Timer _finish_rebuild + on_connect 同時操作 state → 不 crash。"""
        barrier = threading.Barrier(2, timeout=5)
        errors = []

        def run_finish():
            try:
                barrier.wait()
                for _ in range(200):
                    sd._finish_rebuild()
            except Exception as e:
                errors.append(e)

        def run_connect():
            try:
                barrier.wait()
                for _ in range(200):
                    sd.on_connect(CLIENT, None, None, 0)
            except Exception as e:
                errors.append(e)

        with patch.object(sd, "render_button"), \
             patch.object(sd, "render_date_button"), \
             patch.object(sd, "_clear_all_buttons"):
            t1 = threading.Thread(target=run_finish)
            t2 = threading.Thread(target=run_connect)
            t1.start(); t2.start()
            t1.join(timeout=10); t2.join(timeout=10)

        assert not errors, f"Race condition crash: {errors}"

    def test_blink_iteration_during_clear(self):
        """blink_loop 讀 _projects 時 on_connect 清空 → 不 crash。"""
        errors = []

        # 填充狀態讓 blink 有東西迭代
        for i in range(10):
            sd._projects[f"proj{i}"] = i
            sd._project_states[f"proj{i}"] = "idle"

        barrier = threading.Barrier(2, timeout=5)

        def run_blink_iteration():
            try:
                barrier.wait()
                for _ in range(500):
                    # 模擬 blink_loop 核心迭代（不含 sleep/USB）
                    for name, idx in list(sd._projects.items()):
                        _ = sd._project_states.get(name, "")
            except Exception as e:
                errors.append(e)

        def run_clear():
            try:
                barrier.wait()
                for _ in range(500):
                    sd.on_connect(CLIENT, None, None, 0)
                    # 重新填充讓 blink 有東西讀
                    for i in range(10):
                        sd._projects[f"proj{i}"] = i
                        sd._project_states[f"proj{i}"] = "idle"
            except Exception as e:
                errors.append(e)

        with patch.object(sd, "render_button"), \
             patch.object(sd, "render_date_button"), \
             patch.object(sd, "_clear_all_buttons"):
            t1 = threading.Thread(target=run_blink_iteration)
            t2 = threading.Thread(target=run_clear)
            t1.start(); t2.start()
            t1.join(timeout=10); t2.join(timeout=10)

        assert not errors, f"Dict iteration crash: {errors}"

    def test_deck_swap_during_render(self):
        """_deck 被換掉時另一 thread 在 render → 不 crash。"""
        errors = []
        barrier = threading.Barrier(2, timeout=5)

        sd._projects["test"] = 0
        sd._project_states["test"] = "running"

        def run_render():
            try:
                barrier.wait()
                for _ in range(300):
                    sd.rerender_all()
            except Exception as e:
                errors.append(e)

        def run_swap():
            try:
                barrier.wait()
                for _ in range(300):
                    new_deck = MagicMock()
                    new_deck.is_open.return_value = True
                    new_deck.key_count.return_value = 32
                    sd._deck = new_deck
            except Exception as e:
                errors.append(e)

        with patch.object(sd, "render_button"), \
             patch.object(sd, "render_date_button"):
            t1 = threading.Thread(target=run_render)
            t2 = threading.Thread(target=run_swap)
            t1.start(); t2.start()
            t1.join(timeout=10); t2.join(timeout=10)

        assert not errors, f"Deck swap crash: {errors}"

    def test_state_lock_exists(self):
        """streamdeck_mqtt 必須有 _state_lock (threading.Lock)。"""
        assert hasattr(sd, "_state_lock"), "_state_lock not found"
        assert isinstance(sd._state_lock, type(threading.Lock()))

    def test_finish_rebuild_releases_lock(self):
        """_finish_rebuild 後 _state_lock 不能卡住（可立即 acquire）。"""
        with patch.object(sd, "render_button"), \
             patch.object(sd, "render_date_button"), \
             patch.object(sd, "_clear_all_buttons"):
            sd._rebuilding = True
            sd._finish_rebuild()

        acquired = sd._state_lock.acquire(timeout=1)
        assert acquired, "_state_lock stuck after _finish_rebuild"
        sd._state_lock.release()

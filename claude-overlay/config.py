# Claude Status Overlay - Configuration
#
# 顏色、大小、路徑、輪詢間隔（flat config，同 IME_Indicator 模式）

import os

# ============ State File Path ============
# WSL state files via UNC path
WSL_TMP_DIR = r"\\wsl$\Ubuntu\tmp"
STATE_FILE_PREFIX = "claude-led-state-"
ACTIVITY_FILE_PREFIX = "claude-activity-"

# ============ Polling ============
POLL_INTERVAL_MS = 1000  # 1 second

# ============ Blink ============
BLINK_INTERVAL_MS = 500  # 500ms toggle
BLINK_STATES = {"WAITING", "IDLE"}  # states that blink (match tmux blink behavior)

# ============ Stale Detection ============
STALE_TIMEOUT_SEC = 60  # activity file older than this → STALE

# ============ Window ============
WINDOW_ALPHA = 0.85  # 85% opacity
WINDOW_MIN_WIDTH = 220
WINDOW_PADDING = 8
ROW_HEIGHT = 24
FONT_FAMILY = "Segoe UI"
FONT_SIZE = 10
DOT_CHAR = "\u25cf"  # ●

# ============ Position Persistence ============
POSITION_FILE = os.path.join(
    os.environ.get("LOCALAPPDATA", ""),
    "claude-overlay",
    "position.json",
)

# ============ State Colors ============
STATE_COLORS = {
    "RUNNING":   "#3b82f6",  # blue
    "WAITING":   "#eab308",  # yellow
    "COMPLETED": "#22c55e",  # green
    "IDLE":      "#f97316",  # orange
    "STALE":     "#9ca3af",  # gray
}

# ============ Background ============
BG_COLOR = "#1e1e1e"
TEXT_COLOR = "#e5e5e5"
DIM_COLOR = "#555555"  # blink off state

# Sort priority (lower = higher in list)
STATE_SORT_ORDER = {
    "WAITING":   0,
    "RUNNING":   1,
    "IDLE":      2,
    "COMPLETED": 3,
    "STALE":     4,
}

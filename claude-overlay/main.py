# Claude Status Overlay - Entry Point
#
# Launch with pythonw.exe for windowless execution.
# Usage: pythonw.exe main.py

import ctypes

from overlay import StatusOverlay


if __name__ == "__main__":
    # DPI awareness (same pattern as IME_Indicator)
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except Exception:
        ctypes.windll.user32.SetProcessDPIAware()

    app = StatusOverlay()
    app.run()

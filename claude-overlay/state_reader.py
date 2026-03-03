# Claude Status Overlay - State Reader
#
# Scans \\wsl$\Ubuntu\tmp\claude-led-state-* and returns per-project status.

import glob
import os
import time

import config


def read_projects():
    """Return list of dicts: [{project, state, stale}, ...]
    sorted by STATE_SORT_ORDER then project name."""
    pattern = os.path.join(config.WSL_TMP_DIR, config.STATE_FILE_PREFIX + "*")
    results = []

    try:
        files = glob.glob(pattern)
    except OSError:
        return results

    now = time.time()

    for path in files:
        filename = os.path.basename(path)
        project = filename[len(config.STATE_FILE_PREFIX):]
        if not project:
            continue

        # Read state
        try:
            with open(path, "r") as f:
                state = f.read().strip().split("\n")[0].upper()
        except OSError:
            continue

        if state not in config.STATE_COLORS:
            state = "IDLE"

        # Check staleness via activity file
        activity_path = os.path.join(
            config.WSL_TMP_DIR,
            config.ACTIVITY_FILE_PREFIX + project,
        )
        stale = False
        try:
            with open(activity_path, "r") as f:
                last_activity = int(f.read().strip())
            if now - last_activity > config.STALE_TIMEOUT_SEC:
                stale = True
        except (OSError, ValueError):
            stale = True

        if stale and state not in ("COMPLETED", "IDLE"):
            state = "STALE"

        results.append({"project": project, "state": state})

    results.sort(key=lambda r: (
        config.STATE_SORT_ORDER.get(r["state"], 99),
        r["project"],
    ))

    return results

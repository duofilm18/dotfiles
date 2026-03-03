# Claude Status Overlay - Tkinter Window
#
# Draggable, semi-transparent, always-on-top overlay showing Claude project states.

import json
import os
import tkinter as tk

import config
from state_reader import read_projects


class StatusOverlay:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Claude Status")
        self.root.overrideredirect(True)  # no title bar
        self.root.attributes("-topmost", True)
        self.root.attributes("-alpha", config.WINDOW_ALPHA)
        self.root.configure(bg=config.BG_COLOR)

        # Drag state
        self._drag_x = 0
        self._drag_y = 0

        # Blink state
        self._blink_on = True
        self._blink_labels = []  # labels that need blinking

        # Content frame
        self.frame = tk.Frame(self.root, bg=config.BG_COLOR)
        self.frame.pack(fill=tk.BOTH, expand=True, padx=config.WINDOW_PADDING,
                        pady=config.WINDOW_PADDING)

        # Bind drag events on root
        self.root.bind("<ButtonPress-1>", self._on_drag_start)
        self.root.bind("<B1-Motion>", self._on_drag_motion)

        # Right-click menu
        self.menu = tk.Menu(self.root, tearoff=0)
        self.menu.add_command(label="Close", command=self.root.destroy)
        self.root.bind("<ButtonPress-3>", self._on_right_click)

        # Restore position
        self._restore_position()

        # Initial render + start polling
        self._update()
        self._blink()

    def _on_drag_start(self, event):
        self._drag_x = event.x
        self._drag_y = event.y

    def _on_drag_motion(self, event):
        x = self.root.winfo_x() + event.x - self._drag_x
        y = self.root.winfo_y() + event.y - self._drag_y
        self.root.geometry(f"+{x}+{y}")

    def _on_right_click(self, event):
        self.menu.tk_popup(event.x_root, event.y_root)

    def _restore_position(self):
        try:
            with open(config.POSITION_FILE, "r") as f:
                pos = json.load(f)
            self.root.geometry(f"+{pos['x']}+{pos['y']}")
        except (OSError, KeyError, json.JSONDecodeError):
            # Default: top-right area
            self.root.update_idletasks()
            screen_w = self.root.winfo_screenwidth()
            self.root.geometry(f"+{screen_w - 300}+50")

    def _save_position(self):
        x = self.root.winfo_x()
        y = self.root.winfo_y()
        try:
            os.makedirs(os.path.dirname(config.POSITION_FILE), exist_ok=True)
            with open(config.POSITION_FILE, "w") as f:
                json.dump({"x": x, "y": y}, f)
        except OSError:
            pass

    def _blink(self):
        """Toggle blink state for WAITING/IDLE labels."""
        self._blink_on = not self._blink_on
        for label, color in self._blink_labels:
            try:
                label.configure(fg=color if self._blink_on else config.DIM_COLOR)
            except tk.TclError:
                pass  # widget destroyed
        self.root.after(config.BLINK_INTERVAL_MS, self._blink)

    def _update(self):
        projects = read_projects()

        # Clear existing widgets
        for widget in self.frame.winfo_children():
            widget.destroy()
        self._blink_labels = []

        if not projects:
            label = tk.Label(
                self.frame,
                text="No active projects",
                font=(config.FONT_FAMILY, config.FONT_SIZE),
                fg=config.STATE_COLORS["STALE"],
                bg=config.BG_COLOR,
            )
            label.pack(anchor=tk.W)
            label.bind("<ButtonPress-1>", self._on_drag_start)
            label.bind("<B1-Motion>", self._on_drag_motion)
            label.bind("<ButtonPress-3>", self._on_right_click)
        else:
            for proj in projects:
                color = config.STATE_COLORS.get(proj["state"], config.STATE_COLORS["STALE"])
                text = f'{config.DOT_CHAR} {proj["project"]} \u2014 {proj["state"]}'
                label = tk.Label(
                    self.frame,
                    text=text,
                    font=(config.FONT_FAMILY, config.FONT_SIZE),
                    fg=color,
                    bg=config.BG_COLOR,
                    anchor=tk.W,
                )
                label.pack(fill=tk.X, anchor=tk.W)
                label.bind("<ButtonPress-1>", self._on_drag_start)
                label.bind("<B1-Motion>", self._on_drag_motion)
                label.bind("<ButtonPress-3>", self._on_right_click)

                # Register blinking labels
                if proj["state"] in config.BLINK_STATES:
                    self._blink_labels.append((label, color))

        # Resize window to fit content
        self.root.update_idletasks()
        req_w = max(self.frame.winfo_reqwidth() + config.WINDOW_PADDING * 2,
                    config.WINDOW_MIN_WIDTH)
        req_h = self.frame.winfo_reqheight() + config.WINDOW_PADDING * 2
        self.root.geometry(f"{req_w}x{req_h}")

        # Save position periodically
        self._save_position()

        # Schedule next update
        self.root.after(config.POLL_INTERVAL_MS, self._update)

    def run(self):
        self.root.mainloop()

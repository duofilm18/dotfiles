export interface StateDisplay {
  label: string;
  bg: [number, number, number];
  fg: [number, number, number];
}

/**
 * 狀態顯示對照表（對齊 Python streamdeck_mqtt.py）
 * bg: 按鍵背景色, fg: 文字色
 */
export const STATE_DISPLAY: Record<string, StateDisplay> = {
  idle:      { label: "IDLE",    bg: [255, 13,  0],   fg: [255, 255, 255] },
  running:   { label: "RUNNING", bg: [0,   0,   255], fg: [255, 255, 255] },
  waiting:   { label: "WAITING", bg: [255, 255, 0],   fg: [0,   0,   0]   },
  completed: { label: "DONE",    bg: [0,   180, 0],   fg: [255, 255, 255] },
  error:     { label: "ERROR",   bg: [255, 0,   0],   fg: [255, 255, 255] },
  off:       { label: "OFF",     bg: [30,  30,  30],  fg: [128, 128, 128] },
};

export const UNKNOWN_DISPLAY: StateDisplay = {
  label: "?",
  bg: [50, 50, 50],
  fg: [200, 200, 200],
};

export const DATE_DISPLAY: StateDisplay = {
  label: "",
  bg: [40, 40, 40],
  fg: [255, 255, 255],
};

export type GlobalSettings = {
  mqttBroker: string;
  mqttPort: number;
  [key: string]: string | number | boolean | null | undefined;
};

export const DEFAULT_SETTINGS: GlobalSettings = {
  mqttBroker: "192.168.88.10",
  mqttPort: 1883,
};

export interface StateDisplay {
  label: string;
  iconPath: string;  // 相對 sdPlugin 根目錄的靜態 SVG 路徑
}

/**
 * 狀態顯示對照表（對齊 rpi5b/mqtt-led/led-effects.json）
 *
 * 架構：靜態純色 SVG 背景 + setTitle 疊文字。
 * setImage 只在 state 變化時呼叫；專案名與 label 走 setTitle（極輕）。
 */
export const STATE_DISPLAY: Record<string, StateDisplay> = {
  idle:      { label: "IDLE",    iconPath: "imgs/states/idle" },
  running:   { label: "RUN",     iconPath: "imgs/states/running" },
  waiting:   { label: "WAIT",    iconPath: "imgs/states/waiting" },
  completed: { label: "DONE",    iconPath: "imgs/states/completed" },
  error:     { label: "ERR",     iconPath: "imgs/states/error" },
  off:       { label: "OFF",     iconPath: "imgs/states/off" },
};

export const UNKNOWN_DISPLAY: StateDisplay = {
  label: "?",
  iconPath: "imgs/states/off",
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
